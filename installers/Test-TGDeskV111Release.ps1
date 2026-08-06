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

# O core Rust nao e compilado pelo pipeline: o CMake do Flutter so COPIA
# target\release\libtgdeskcore.dll. Mudar src\ e rodar so o build publica um
# tgdesk.exe novo com o core antigo -- foi o que quase saiu na 1.1.51, com o C++
# registrando a classe de janela nova e o core procurando a velha.
# Ver BUILD-CORE.md.
$coreDll = Join-Path $root 'client-rustdesk-src\target\release\libtgdeskcore.dll'
$coreDllTime = if (Test-Path -LiteralPath $coreDll) {
    (Get-Item -LiteralPath $coreDll).LastWriteTimeUtc
} else { [datetime]::MinValue }
$lastRustCommit = (& git -C $root log -1 --format=%cI -- client-rustdesk-src/src | Out-String).Trim()
$rustCommitTime = if ($lastRustCommit) {
    ([datetimeoffset]$lastRustCommit).UtcDateTime
} else { [datetime]::MinValue }
Add-Check 'core.dll_newer_than_rust_sources' `
    ($coreDllTime -gt $rustCommitTime) `
    ("dll=$($coreDllTime.ToString('s')) rust=$($rustCommitTime.ToString('s'))")

# O agente publicado tem que ser mais novo que o codigo do agente, pela mesma
# razao do core: ate a 1.1.52 o pipeline so rodava 'go test' no client-agent e
# empacotava o tgdesk_agent.dll parado no stage. O de 3 de agosto nao mandava
# client_version no heartbeat, e sem isso o servidor nunca enfileira ninguem --
# a atualizacao automatica ficou quebrada sem nenhum erro aparecer.
$agentDll = Join-Path $root 'installers\stage-unified\tgdesk_agent.dll'
$agentDllTime = if (Test-Path -LiteralPath $agentDll) {
    (Get-Item -LiteralPath $agentDll).LastWriteTimeUtc
} else { [datetime]::MinValue }
$lastAgentCommit = (& git -C $root log -1 --format=%cI -- client-agent | Out-String).Trim()
$agentCommitTime = if ($lastAgentCommit) {
    ([datetimeoffset]$lastAgentCommit).UtcDateTime
} else { [datetime]::MinValue }
Add-Check 'agent.dll_newer_than_sources' `
    ($agentDllTime -gt $agentCommitTime) `
    ("dll=$($agentDllTime.ToString('s')) src=$($agentCommitTime.ToString('s'))")

# E o agente empacotado tem que de fato mandar a versao: e o unico dado que faz
# o servidor decidir quem atualiza.
$agentReportsVersion = $false
if (Test-Path -LiteralPath $agentDll) {
    $agentBytes = [IO.File]::ReadAllBytes($agentDll)
    $agentText = [Text.Encoding]::ASCII.GetString($agentBytes)
    $agentReportsVersion = $agentText.Contains('client_version')
}
Add-Check 'agent.reports_client_version' $agentReportsVersion ([string]$agentReportsVersion)

# O TGDesk atualiza sozinho -- e principio, nao recurso. Sao dois caminhos, e
# os dois tem que existir: a ordem do servidor (update_now), que serializa a
# fila e limita a banda, e a verificacao periodica do agente, que e o piso.
#
# Sem o piso a frota fica presa quando o agente empacotado nao entende a ordem.
# Foi o que aconteceu: o push entrou no codigo, o agente ficou parado numa
# versao anterior a ele, e ninguem atualizou mais sem nenhum erro aparecer.
$agentControl = Get-Content (Join-Path $root 'client-agent\cmd\agent\control.go') -Raw
Add-Check 'update.server_push_exists' `
    ($agentControl -match 'msg\.Type == "update_now"') 'update_now handled'
Add-Check 'update.agent_self_check_exists' `
    (($agentControl -match 'updateCheckTick\s*:=\s*time\.NewTicker') -and
     ($agentControl -match 'case <-updateCheckTick\.C:')) 'periodic self-check'

# E a verificacao precisa existir tambem no laco do HOST, que roda em qualquer
# estado do dispositivo. O laco do canal de controle so existe depois da
# vinculacao -- uma maquina recem-instalada fica em 'guest' ate um tecnico
# vincula-la, e sem isto ela congela na versao do instalador para sempre.
# Toda flag que o agente passa ao nucleo tem que estar na lista de excecoes do
# bloqueio de instancia unica. Sem isso, o processo do nucleo bate no mutex da
# UI e sai ANTES de imprimir a resposta -- mas so quando a janela do TGDesk
# esta aberta, entao o defeito e intermitente e parece outra coisa.
#
# Ja aconteceu duas vezes seguidas: --option deixava o acesso remoto sem
# configuracao, e --get-id deixava o ID vazio. Esta checagem le as flags do
# proprio codigo do agente em vez de depender de alguem lembrar de atualizar a
# lista.
$agentSources = Get-ChildItem (Join-Path $root 'client-agent') -Filter *.go -Recurse |
    ForEach-Object { Get-Content $_.FullName -Raw }
$coreFlags = [regex]::Matches(($agentSources -join "`n"),
    '(?:exePath|coreExe)\s*,\s*"(--[a-z-]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
# Le o main.cpp aqui em vez de reaproveitar $runnerMain: aquela variavel so e
# preenchida mais abaixo, e comparar contra ela vazia reprovava TODAS as flags
# — inclusive as que acabaram de ser adicionadas. Um teste que acusa erro onde
# nao ha e pior que teste nenhum: ensina a ignorar o resultado.
$whiteList = [regex]::Match(
    (Get-Content (Join-Path $root 'client-rustdesk-src\flutter\windows\runner\main.cpp') -Raw),
    'parameters_white_list\s*=\s*\{([\s\S]*?)\}').Groups[1].Value
$missingFlags = @($coreFlags | Where-Object { $whiteList -notmatch [regex]::Escape("`"$_`"") })
Add-Check 'core.cli_flags_bypass_ui_mutex' `
    ($missingFlags.Count -eq 0) `
    $(if ($missingFlags.Count) { "faltando: $($missingFlags -join ',')" }
      else { "todas as $($coreFlags.Count) na lista" })

$agentHost = Get-Content (Join-Path $root 'client-agent\cmd\agent\host.go') -Raw
Add-Check 'update.reaches_unbound_devices' `
    ($agentHost -match 'verificarAtualizacaoPeriodica\(\)') 'guest devices update too'

$releaseBuilder = Get-Content (Join-Path $root 'installers\New-TGDeskModuleRelease.ps1') -Raw
Add-Check 'updater.restarts_interactive_ui' `
    ($releaseBuilder -match "restart_application\s*=\s*'tgdesk\.exe'") 'tgdesk.exe'
$runnerMain = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\windows\runner\main.cpp') -Raw
Add-Check 'tray.bypasses_ui_mutex' `
    ($runnerMain -match 'parameters_white_list[\s\S]*?--tray') '--tray'
$traySource = Get-Content (Join-Path $root 'client-rustdesk-src\src\tray.rs') -Raw
$coreMainSource = Get-Content (Join-Path $root 'client-rustdesk-src\src\core_main.rs') -Raw
$windowsPlatformSource = Get-Content (Join-Path $root 'client-rustdesk-src\src\platform\windows.rs') -Raw

# A classe de janela nao pode voltar a ser a do template do Flutter.
# FindWindowW varre o sistema inteiro: com o nome padrao, qualquer outro app
# Flutter para Windows -- o cliente Cloudflare WARP entre eles -- casa na busca
# de instancia unica, e o TGDesk trazia (ou fechava) a janela alheia.
# As duas pontas se acham por este nome, entao as duas precisam bater.
$win32Window = Get-Content (Join-Path $root 'client-rustdesk-src\flutter\windows\runner\win32_window.cpp') -Raw
Add-Check 'window.class_is_own' `
    (($win32Window -match 'kWindowClassName\[\]\s*=\s*L"TGDESK_RUNNER_WIN32_WINDOW"') -and
     ($windowsPlatformSource -match 'FLUTTER_RUNNER_WIN32_WINDOW_CLASS[^\r\n]*=\s*"TGDESK_RUNNER_WIN32_WINDOW"')) `
    'TGDESK_RUNNER_WIN32_WINDOW'

# E a janela encontrada so vale depois que o processo dono dela prova ser o
# mesmo binario: classe propria reduz a colisao, nao a elimina.
Add-Check 'window.verifies_owning_process' `
    (($runnerMain -match 'FindOwnInstanceWindow') -and
     ($runnerMain -match 'QueryFullProcessImageNameW') -and
     ($runnerMain -notmatch '::FindWindowW\(getWindowClassName')) `
    'FindOwnInstanceWindow'
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
# A janela do atualizador segue o que a pessoa esta vendo: aparece com a janela
# do TGDesk aberta na frente (a atualizacao troca binarios e reinicia o
# servico -- sumir no meio disso deixa a pessoa no escuro), e nao aparece com o
# TGDesk minimizado na bandeja (quem minimizou esta fazendo outra coisa).
#
# Antes era sempre SW_HIDE, e o caso da janela aberta ficava sem resposta.
Add-Check 'updater.window_follows_main_window' `
    (($updateCore -match 'show := int32\(windows\.SW_HIDE\)') -and
     ($updateCore -match 'mainWindowIsOnScreen\(installDir\)') -and
     ($updateCore -match 'show = int32\(windows\.SW_SHOWNORMAL\)') -and
     ($updateCore -match 'ShellExecute\(0, verb, file, params, dir, show\)')) `
    'updater window shown only when the TGDesk window is on screen'

# E a janela conferida tem que ser a do TGDesk: FindWindowW varre o sistema
# inteiro, e decidir mostrar ou esconder pelo estado da janela de outro
# programa seria o mesmo descuido da classe de janela, so que mais silencioso.
Add-Check 'updater.verifies_owning_process' `
    (($updateCore -match 'QueryFullProcessImageName') -and
     ($updateCore -match 'tgdeskWindowClass\s*=\s*"TGDESK_RUNNER_WIN32_WINDOW"')) `
    'window ownership verified before reading its state'

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
Add-Check 'schema.migrations' ($migration -match '^54:0054_') $migration

$integrity = @(& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT check_name||':'||status FROM validate_schema_integrity() ORDER BY check_name")
Add-Check 'schema.integrity' ($integrity.Count -eq 6 -and @($integrity | Where-Object {$_ -notmatch ':PASS$'}).Count -eq 0) ($integrity -join ',')

$tables = (& docker compose -f $compose exec -T postgres psql -U tgdesk -d tgdesk -Atqc `
    "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('support_tickets','service_orders','dispatch_offers','supervisor_offers','ticket_ratings','temporary_ticket_permissions','onsite_evidence','diagnostic_samples','ticket_types','ticket_type_fields','pricing_rules','part_catalog','service_catalog','service_order_items','regions','technician_name_styles')" | Out-String).Trim()
Add-Check 'schema.product_tables' ($tables -eq '16') $tables

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
