[CmdletBinding()]
param(
    [string]$Source = '',
    [string]$InstallDir = 'C:\Program Files\TGDesk'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $PSScriptRoot 'stage-unified'
}
$Source = [IO.Path]::GetFullPath($Source)
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$stateDir = 'C:\ProgramData\TGDesk\updates'
$statePath = Join-Path $stateDir 'repair-v114-status.json'
$backupDir = Join-Path $stateDir ('repair-v114-backup-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

function Set-RepairState([string]$Phase, [bool]$Passed, [string]$Detail) {
    [IO.Directory]::CreateDirectory($stateDir) | Out-Null
    [ordered]@{
        measured_at = [DateTimeOffset]::UtcNow.ToString('o')
        phase = $Phase
        passed = $Passed
        detail = $Detail
        backup = $backupDir
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'O reparo precisa ser executado como Administrador.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Source 'tgdesk.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $Source 'tgdesk-updater.exe')) -or
        ((Get-Content -LiteralPath (Join-Path $Source 'version.txt') -Raw).Trim() -ne '1.1.6')) {
        throw 'Stage 1.1.6 incompleto ou inconsistente.'
    }

    Set-RepairState 'backup' $false 'Criando backup recuperavel da instalacao atual.'
    [IO.Directory]::CreateDirectory($backupDir) | Out-Null
    Copy-Item -Path (Join-Path $InstallDir '*') -Destination $backupDir -Recurse -Force

    Set-RepairState 'shutdown' $false 'Parando servico e processos TGDesk.'
    Stop-Service TGDesk -Force -ErrorAction SilentlyContinue
    Get-Process tgdesk -ErrorAction SilentlyContinue | Stop-Process -Force
    $deadline = (Get-Date).AddSeconds(20)
    while (@(Get-Process tgdesk -ErrorAction SilentlyContinue).Count -gt 0 -and
        (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
    }
    if (@(Get-Process tgdesk -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Um ou mais processos TGDesk nao encerraram.'
    }

    Set-RepairState 'copy' $false 'Instalando arquivos 1.1.6.'
    Copy-Item -Path (Join-Path $Source '*') -Destination $InstallDir -Recurse -Force
    $installedVersion = (Get-Content -LiteralPath (Join-Path $InstallDir 'version.txt') -Raw).Trim()
    if ($installedVersion -ne '1.1.6') {
        throw "Versao instalada divergente: $installedVersion"
    }

    Set-RepairState 'startup' $false 'Restaurando inicio automatico e servico.'
    New-Item -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -Force | Out-Null
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        -Name TGDesk -Value ('"' + (Join-Path $InstallDir 'tgdesk.exe') + '"')
    New-Item -Path 'HKCU:\SOFTWARE\TGDesk' -Force | Out-Null
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\TGDesk' -Name StartWithWindowsConfigured -Type DWord -Value 1
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\TGDesk' -Name StartWithWindows -Type DWord -Value 1
    Start-Service TGDesk
    $serviceDeadline = (Get-Date).AddSeconds(30)
    do {
        $service = Get-Service TGDesk -ErrorAction Stop
        if ($service.Status -eq 'Running') { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $serviceDeadline)
    if ($service.Status -ne 'Running') { throw 'O servico TGDesk nao iniciou.' }

    Set-RepairState 'launch' $false 'Abrindo a interface TGDesk.'
    Start-Process -FilePath (Join-Path $InstallDir 'tgdesk.exe') -WorkingDirectory $InstallDir
    Set-RepairState 'complete' $true 'TGDesk 1.1.6 reparado, servico ativo e interface iniciada.'
    exit 0
} catch {
    $failure = $_.Exception.Message
    try {
        Stop-Service TGDesk -Force -ErrorAction SilentlyContinue
        Get-Process tgdesk -ErrorAction SilentlyContinue | Stop-Process -Force
        if (Test-Path -LiteralPath $backupDir) {
            Copy-Item -Path (Join-Path $backupDir '*') -Destination $InstallDir -Recurse -Force
        }
        Start-Service TGDesk -ErrorAction SilentlyContinue
    } catch {
        $failure += '; rollback tambem falhou: ' + $_.Exception.Message
    }
    Set-RepairState 'failed' $false $failure
    exit 1
}
