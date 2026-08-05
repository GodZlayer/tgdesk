param(
    [string]$ExpectedVersion = '1.1.35',
    [switch]$RequireInstalledClient
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$compose = Join-Path $root 'server\docker-compose.yml'
$checks = New-Object Collections.Generic.List[object]

function Add-Check([string]$Name, [bool]$Passed, [string]$Actual) {
    $checks.Add([pscustomobject]@{ name=$Name; passed=$Passed; actual=$Actual })
}

$sourceVersion = (Get-Content (Join-Path $root 'client-rustdesk-src\flutter\version.txt') -Raw).Trim()
Add-Check 'source.version' ($sourceVersion -eq $ExpectedVersion) $sourceVersion

$releaseBuilder = Get-Content (Join-Path $root 'installers\New-TGDeskModuleRelease.ps1') -Raw
Add-Check 'updater.restarts_interactive_ui' `
    ($releaseBuilder -match "restart_application\s*=\s*'tgdesk\.exe'") 'tgdesk.exe'
$runnerMain = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\windows\runner\main.cpp') -Raw
Add-Check 'tray.bypasses_ui_mutex' `
    ($runnerMain -match 'parameters_white_list[\s\S]*?--tray') '--tray'
$traySource = Get-Content (Join-Path $root 'client-rustdesk-src\src\tray.rs') -Raw
$coreMainSource = Get-Content (Join-Path $root 'client-rustdesk-src\src\core_main.rs') -Raw
$windowsPlatformSource = Get-Content (Join-Path $root 'client-rustdesk-src\src\platform\windows.rs') -Raw
Add-Check 'tray.owns_blocking_event_loop' `
    (($traySource -match 'for attempt in 0\.\.max_retries[\s\S]*?make_tray\(\)') -and
     ($traySource -notmatch 'std::thread::spawn\(move \|\| \{[\s\S]{0,200}let max_retries')) `
    'blocking event loop'
Add-Check 'service.supervises_active_session_tray' `
    (($coreMainSource -match 'ensure_tray_in_active_session') -and
     ($windowsPlatformSource -match 'pub fn ensure_tray_in_active_session') -and
     ($windowsPlatformSource -match 'run_exe_in_session\(exe, vec!\["--tray"\]')) `
    'service to active session tray supervisor'
$updaterMain = Get-Content (Join-Path $root 'client-agent\cmd\updater\main.go') -Raw
$updaterUI = Get-Content (Join-Path $root 'client-agent\cmd\updater\ui_windows.go') -Raw
Add-Check 'updater.realtime_status_gui' `
    (($updaterMain -match 'runApplyStagedWithStatus') -and
     ($updaterUI -match 'ApplyStagedOfflineWithProgress') -and
     ($updaterUI -match 'msctls_progress32')) 'native status window'
$updateCore = Get-Content (Join-Path $root 'client-agent\internal\updatecore\updatecore.go') -Raw
Add-Check 'updater.runs_from_install_dir' `
    (($updateCore -match 'updaterExe := filepath\.Join\(installDir, "tgdesk-updater\.exe"\)') -and
     ($updateCore -notmatch 'copyFile\(installedUpdater, updaterExe\)')) `
    'no unsigned random-named copy — runs the installed exe directly, avoiding SmartScreen churn'
Add-Check 'updater.windows_replace_checks_remove' `
    (($updateCore -match 'removeErr = os\.Remove\(target\)') -and
     ($updateCore -match 'if removeErr != nil')) `
    'locked target is diagnosed before rename and rollback'
Add-Check 'updater.launches_gui_visible' `
    ($updateCore -match 'updaterExe[\s\S]{0,1800}ShellExecute\(0, verb, file, params, dir, windows\.SW_SHOWNORMAL\)') `
    'standalone updater is launched visible'

function Get-PEContract([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 256) { throw "PE invalido: $Path" }
    $pe = [BitConverter]::ToInt32($bytes, 0x3c)
    [pscustomobject]@{
        IsDll = (([BitConverter]::ToUInt16($bytes, $pe + 22) -band 0x2000) -ne 0)
        Subsystem = [BitConverter]::ToUInt16($bytes, $pe + 92)
        Text = [Text.Encoding]::ASCII.GetString($bytes)
    }
}
$agentPE = Get-PEContract (Join-Path $root 'installers\stage-unified\tgdesk_agent.dll')
$updaterPE = Get-PEContract (Join-Path $root 'installers\stage-unified\tgdesk-updater.exe')
Add-Check 'agent.valid_shared_dll_exports' `
    ($agentPE.IsDll -and $agentPE.Text.Contains('TGDeskAgentHost') -and
     $agentPE.Text.Contains('TGDeskAgentTechnicianService')) `
    'PE DLL with required host and VPN service exports'
Add-Check 'updater.windows_gui_subsystem' `
    ($updaterPE.Subsystem -eq 2) ([string]$updaterPE.Subsystem)

$health = $false
try { $health = (Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8090/healthz').StatusCode -eq 200 } catch {}
Add-Check 'docker.health' $health ([string]$health)

$migration = (& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT count(*)||':'||max(name) FROM schema_migrations" | Out-String).Trim()
Add-Check 'schema.migrations' ($migration -match '^49:0049_') $migration

$integrity = @(& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT check_name||':'||status FROM validate_schema_integrity() ORDER BY check_name")
Add-Check 'schema.integrity' ($integrity.Count -eq 6 -and @($integrity | Where-Object {$_ -notmatch ':PASS$'}).Count -eq 0) ($integrity -join ',')

$tables = (& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('support_tickets','service_orders','dispatch_offers','supervisor_offers','ticket_ratings','temporary_ticket_permissions','onsite_evidence','diagnostic_samples')" | Out-String).Trim()
Add-Check 'schema.product_tables' ($tables -eq '8') $tables

$containerVersion = (& docker compose -f $compose exec -T api-core printenv CLIENT_VERSION | Out-String).Trim()
Add-Check 'docker.version' ($containerVersion -eq $ExpectedVersion) $containerVersion

$routeStatus = 0
try {
    Invoke-WebRequest -UseBasicParsing -Method Post `
        'http://127.0.0.1:8090/api/v1/support/client/tickets' `
        -ContentType 'application/json' -Body '{}' | Out-Null
    $routeStatus = 200
} catch { $routeStatus = [int]$_.Exception.Response.StatusCode }
Add-Check 'api.client_ticket_route' ($routeStatus -eq 400) ([string]$routeStatus)

$catalogCount = (Select-String -Path (Join-Path $root 'server\api-core\internal\handlers\diagnostics.go') `
    -Pattern '\{"id":').Count
Add-Check 'diagnostics.catalog' ($catalogCount -ge 20) ([string]$catalogCount)
$diagnosticSource = Get-Content (Join-Path $root 'client-agent\cmd\agent\diagnostics.go') -Raw
$diagnosticUI = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\lib\tgdesk\diagnostics_dialog.dart') -Raw
$devicesUI = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\lib\tgdesk\devices_page.dart') -Raw
$deviceAuth = Get-Content (Join-Path $root 'server\api-core\internal\auth\authorizer.go') -Raw
Add-Check 'diagnostics.complete_suite' `
    (($diagnosticSource -match 'rootTest == "all_tests"') -and
     ($diagnosticSource -match 'storage_surface_read') -and
     ($diagnosticSource -notmatch 'WithTimeout\(ctx, 12\*time\.Minute\)')) `
    'all catalog tests plus cancellable read-only disk surface scan'
Add-Check 'diagnostics.no_duration_estimates' `
    ($diagnosticUI -notmatch "duration_seconds") 'no estimated duration in UI'
Add-Check 'diagnostics.grouped_live_results' `
    (($diagnosticSource -match 'GroupProgress') -and
     ($diagnosticSource -match 'CompletedTests') -and
     ($diagnosticUI -match 'Problemas indicados pela telemetria') -and
     ($diagnosticUI -match '_suiteResultVisual')) `
    'component groups, telemetry recommendations and per-test live details'
Add-Check 'devices.binding_action_is_inline' `
    (($devicesUI -match "child: Text\('Vincular dispositivo'\)") -and
     ($devicesUI -notmatch 'floatingActionButton:')) 'full-width top action'
Add-Check 'devices.management_umbrella' `
    (($devicesUI -match "d\['can_manage'\] == true") -and
     ($deviceAuth -match 'o\.owner_technician_id=\$1')) 'admin global, supervisor own organization'

$gaps = @(Get-ChildItem (Join-Path $root 'client-rustdesk-src\flutter\lib\tgdesk') -Filter *.dart |
    Select-String -Pattern 'GAP REMANESCENTE|TODO\(gap\)|ainda não é suportad')
Add-Check 'ui.no_declared_gaps' ($gaps.Count -eq 0) (($gaps | ForEach-Object {$_.Path+':'+$_.LineNumber}) -join ',')

$evidenceVolume = (& docker volume inspect server_tgdesk_evidence_data --format '{{.Name}}' 2>$null | Out-String).Trim()
Add-Check 'evidence.persistent_volume' ($evidenceVolume -eq 'server_tgdesk_evidence_data') $evidenceVolume

if ($RequireInstalledClient) {
    $installedVersion = if (Test-Path 'C:\Program Files\TGDesk\version.txt') {
        (Get-Content 'C:\Program Files\TGDesk\version.txt' -Raw).Trim()
    } else { 'missing' }
    Add-Check 'windows.installed_version' ($installedVersion -eq $ExpectedVersion) $installedVersion
    $service = (Get-Service TGDesk -ErrorAction SilentlyContinue).Status
    Add-Check 'windows.service' ($service -eq 'Running') ([string]$service)
    $window = @(Get-Process tgdesk -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowTitle -eq 'TGDesk' -and $_.Responding })
    Add-Check 'windows.ui_window' ($window.Count -eq 1) ([string]$window.Count)

    $adminRole = 'unavailable'
    $credentialPath = 'C:\ProgramData\TGDesk\identity\technician.dat'
    if (Test-Path -LiteralPath $credentialPath) {
        Add-Type -AssemblyName System.Security
        $clear = $null
        try {
            $encrypted = [IO.File]::ReadAllBytes($credentialPath)
            $clear = [Security.Cryptography.ProtectedData]::Unprotect(
                $encrypted, $null,
                [Security.Cryptography.DataProtectionScope]::LocalMachine)
            $credential = [Text.Encoding]::UTF8.GetString($clear) | ConvertFrom-Json
            $refresh = Invoke-RestMethod -Method Post `
                -Uri 'http://127.0.0.1:8090/api/v1/auth/technician/refresh' `
                -ContentType 'application/json' `
                -Body ($credential | ConvertTo-Json -Compress)
            $adminRole = [string]$refresh.role
        } catch {
            $adminRole = 'refresh_failed'
        } finally {
            if ($clear) { [Array]::Clear($clear, 0, $clear.Length) }
            $credential = $null
            $refresh = $null
        }
    }
    Add-Check 'windows.control_tier' ($adminRole -eq 'super_admin') $adminRole

    $deviceIdentityPath = 'C:\ProgramData\TGDesk\identity\device.json'
    $adminDeviceBinding = 'missing'
    if (Test-Path -LiteralPath $deviceIdentityPath) {
        $deviceID = [string]((Get-Content -LiteralPath $deviceIdentityPath -Raw |
            ConvertFrom-Json).device_id)
        if ($deviceID) {
            $adminDeviceBinding = (& docker compose -f $compose exec -T postgres `
                psql -U tgdesk -d tgdesk -Atqc `
                "SELECT d.state||':'||lower(o.name)||':'||(d.control_technician_id IS NOT NULL)::text FROM devices d JOIN networks n ON n.id=d.network_id JOIN organizations o ON o.id=n.organization_id WHERE d.id='$deviceID'" |
                Out-String).Trim()
        }
    }
    Add-Check 'windows.admin_device_binding' `
        ($adminDeviceBinding -eq 'ativo:tgdevs:true') $adminDeviceBinding
}

$failed = @($checks | Where-Object {-not $_.passed})
$result = [pscustomobject]@{
    measured_at = [DateTimeOffset]::UtcNow.ToString('o')
    version = $ExpectedVersion
    passed = $failed.Count -eq 0
    checks = $checks
}
$result | ConvertTo-Json -Depth 6
if ($failed.Count -ne 0) { exit 1 }
