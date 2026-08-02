param(
    [string]$ExpectedVersion = '1.1.1',
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

$health = $false
try { $health = (Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8090/healthz').StatusCode -eq 200 } catch {}
Add-Check 'docker.health' $health ([string]$health)

$migration = (& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT count(*)||':'||max(name) FROM schema_migrations" | Out-String).Trim()
Add-Check 'schema.migrations' ($migration -match '^33:0033_') $migration

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
