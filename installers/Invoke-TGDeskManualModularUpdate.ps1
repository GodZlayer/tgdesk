param(
    [Parameter(Mandatory = $true)] [string]$Staging,
    [Parameter(Mandatory = $true)] [string]$UpdaterSource,
    [string]$InstallDir = 'C:\Program Files\TGDesk',
    [string]$ResultPath = 'C:\ProgramData\TGDesk\updates\manual-update-result.json'
)

$ErrorActionPreference = 'Stop'

function Get-TGDeskState {
    param([string]$Phase)
    $service = Get-CimInstance Win32_Service -Filter "Name='TGDesk'" -ErrorAction SilentlyContinue
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'" -ErrorAction SilentlyContinue)
    $versionPath = Join-Path $InstallDir 'version.txt'
    $identityPath = 'C:\ProgramData\TGDesk\identity\device.json'
    [ordered]@{
        phase = $Phase
        measured_at = [DateTimeOffset]::UtcNow.ToString('o')
        version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { $null }
        service_state = if ($service) { $service.State } else { 'Missing' }
        service_pid = if ($service) { $service.ProcessId } else { 0 }
        process_ids = @($processes | ForEach-Object ProcessId)
        process_commands = @($processes | ForEach-Object CommandLine)
        session_ui_present = @($processes | Where-Object { $_.CommandLine -match '(?i)\s--server(?:\s|$)' }).Count -gt 0
        identity_sha256 = if (Test-Path -LiteralPath $identityPath) { (Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash } else { $null }
        tgdesk_sha256 = if (Test-Path -LiteralPath (Join-Path $InstallDir 'tgdesk.exe')) { (Get-FileHash -LiteralPath (Join-Path $InstallDir 'tgdesk.exe') -Algorithm SHA256).Hash } else { $null }
        agent_sha256 = if (Test-Path -LiteralPath (Join-Path $InstallDir 'tgdesk_agent.dll')) { (Get-FileHash -LiteralPath (Join-Path $InstallDir 'tgdesk_agent.dll') -Algorithm SHA256).Hash } else { $null }
        updater_sha256 = if (Test-Path -LiteralPath (Join-Path $InstallDir 'tgdesk-updater.exe')) { (Get-FileHash -LiteralPath (Join-Path $InstallDir 'tgdesk-updater.exe') -Algorithm SHA256).Hash } else { $null }
    }
}

$manifestPath = Join-Path $Staging 'manifest.json'
$filesRoot = Join-Path $Staging 'files'
if (-not (Test-Path -LiteralPath $manifestPath) -or -not (Test-Path -LiteralPath $filesRoot)) {
    throw 'Staging offline incompleto.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.format_version -ne 1 -or -not $manifest.version) {
    throw 'Manifesto offline incompatível.'
}
if (@($manifest.files | Where-Object path -eq 'tgdesk-updater.exe').Count -ne 0) {
    throw 'O updater não pode fazer parte do payload.'
}

$before = Get-TGDeskState -Phase 'before'
$installedUpdater = Join-Path $InstallDir 'tgdesk-updater.exe'
$updaterTemp = Join-Path $InstallDir 'tgdesk-updater.new.exe'
Copy-Item -LiteralPath $UpdaterSource -Destination $updaterTemp -Force
if ((Get-FileHash -LiteralPath $UpdaterSource -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $updaterTemp -Algorithm SHA256).Hash) {
    throw 'Falha ao preparar o updater imutável.'
}
Move-Item -LiteralPath $updaterTemp -Destination $installedUpdater -Force

$updaterStdout = 'C:\ProgramData\TGDesk\updates\updater-stdout.log'
$updaterStderr = 'C:\ProgramData\TGDesk\updates\updater-stderr.log'
& $installedUpdater -apply-staged -staging $Staging -install-dir $InstallDir -parent 0 `
    1> $updaterStdout 2> $updaterStderr
$updaterExitCode = $LASTEXITCODE

$after = Get-TGDeskState -Phase 'after'
$result = [ordered]@{
    target_version = $manifest.version
    updater_exit_code = $updaterExitCode
    updater_stdout = if (Test-Path -LiteralPath $updaterStdout) { Get-Content -LiteralPath $updaterStdout -Raw } else { $null }
    updater_stderr = if (Test-Path -LiteralPath $updaterStderr) { Get-Content -LiteralPath $updaterStderr -Raw } else { $null }
    before = $before
    after = $after
    identity_preserved = $before.identity_sha256 -eq $after.identity_sha256
}
$resultDir = Split-Path -Parent $ResultPath
New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ResultPath -Encoding UTF8

if ($updaterExitCode -ne 0) { throw "Updater terminou com código $updaterExitCode." }
if ($after.version -ne $manifest.version) { throw 'A versão instalada não corresponde ao manifesto.' }
if ($after.service_state -ne 'Running') { throw 'O serviço TGDesk não está em execução.' }
if (-not $after.session_ui_present) { throw 'A interface gerenciada pelo serviço não reiniciou.' }
if (-not $result.identity_preserved) { throw 'A identidade do dispositivo foi alterada.' }

$result | ConvertTo-Json -Depth 8
