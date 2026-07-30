[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    ),
    [string]$EvidencePath = ''
)
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot `
        'artifacts\windows-e2e-logon-ui.json'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$targets = @()
foreach ($name in $VMName) {
    $observed = Invoke-Command -VMName $name -Credential $credential `
        -ScriptBlock {
        $explorers = @(Get-CimInstance Win32_Process `
            -Filter "Name='explorer.exe'" | Where-Object SessionId -gt 0)
        $sessionIds = @($explorers.SessionId | Select-Object -Unique)
        $all = @(Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'")
        $interactive = @($all | Where-Object {
            $_.SessionId -in $sessionIds
        })
        $uis = @($interactive | Where-Object {
            $_.CommandLine -notmatch '--(service|server|tray|tgdesk-|install|cm)'
        })
        $trays = @($interactive | Where-Object CommandLine -match '--tray')
        $services = @($all | Where-Object {
            $_.SessionId -eq 0 -and $_.CommandLine -match '--service'
        })
        Remove-ItemProperty `
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
            TGDeskLabDuplicateProbe -ErrorAction SilentlyContinue
        $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
        Set-ItemProperty $winlogon AutoAdminLogon '0'
        Remove-ItemProperty $winlogon DefaultPassword `
            -ErrorAction SilentlyContinue
        [ordered]@{
            session_ids = $sessionIds
            explorer_count = $explorers.Count
            ui_count = $uis.Count
            tray_count = $trays.Count
            service_count = $services.Count
            ui = @($uis | Select-Object `
                ProcessId,ParentProcessId,SessionId,CommandLine)
            tray = @($trays | Select-Object `
                ProcessId,ParentProcessId,SessionId,CommandLine)
        }
    }
    $targets += [ordered]@{ vm_name = $name; observed = $observed }
}
$passed = @($targets | Where-Object {
    $_.observed.session_ids.Count -ne 1 -or
    $_.observed.explorer_count -ne 1 -or
    $_.observed.ui_count -ne 1 -or
    $_.observed.tray_count -ne 1 -or
    $_.observed.service_count -ne 1
}).Count -eq 0
$result = [ordered]@{
    schema_version = 1
    phase = 'windows-logon-ui-lifecycle'
    status = if ($passed) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    mode = 'CLI-only process/session/command-line observation'
    assertions = @(
        [ordered]@{
            id = 'runtime.single-ui-process'
            state = if ($passed) { 'passed' } else { 'failed' }
            detail = 'Two Run entries at the same logon converge to one UI.'
        },
        [ordered]@{
            id = 'runtime.tray-start'
            state = if ($passed) { 'passed' } else { 'failed' }
            detail = 'Exactly one --tray process shares the interactive session.'
        }
    )
    targets = $targets
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force |
    Out-Null
$result | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 7
if (-not $passed) { exit 1 }
