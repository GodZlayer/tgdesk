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
        'artifacts\windows-e2e-interactive-ui.json'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$results = @()
foreach ($name in $VMName) {
    $observed = Invoke-Command -VMName $name -Credential $credential `
        -ScriptBlock {
        $explorer = @(Get-CimInstance Win32_Process `
            -Filter "Name='explorer.exe'" | Where-Object SessionId -gt 0)
        $sessionIds = @($explorer.SessionId | Select-Object -Unique)
        if ($sessionIds.Count -ne 1) {
            return [ordered]@{
                interactive_session = $false
                session_ids = $sessionIds
                ui_count = 0
                reason = 'Uma sessão Explorer interativa não foi observada.'
            }
        }
        $exe = 'C:\Program Files\TGDesk\tgdesk.exe'
        $taskCommand = '"' + $exe + '"'
        foreach ($taskName in @('TGDeskLabUIProbeA','TGDeskLabUIProbeB')) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null
            & schtasks.exe /Create /TN $taskName /SC ONCE `
                /ST ((Get-Date).AddMinutes(2).ToString('HH:mm')) `
                /TR $taskCommand /RU tgdesklab `
                /RP 'TGDesk-Lab-Only-2026!' /RL LIMITED /IT /F 2>&1 |
                Out-Null
            $createExitCode = $LASTEXITCODE
            $ErrorActionPreference = $previousPreference
            if ($createExitCode -ne 0) {
                throw "Falha criando tarefa $taskName"
            }
        }
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & schtasks.exe /Run /TN TGDeskLabUIProbeA 2>&1 | Out-Null
        $runAExitCode = $LASTEXITCODE
        & schtasks.exe /Run /TN TGDeskLabUIProbeB 2>&1 | Out-Null
        $runBExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($runAExitCode -ne 0 -or $runBExitCode -ne 0) {
            throw 'Falha iniciando tarefas concorrentes de UI.'
        }
        Start-Sleep -Seconds 12
        $processes = @(Get-CimInstance Win32_Process `
            -Filter "Name='tgdesk.exe'")
        $interactive = @($processes | Where-Object {
            $_.SessionId -eq $sessionIds[0]
        })
        $uis = @($interactive | Where-Object {
            $_.CommandLine -notmatch '--(service|server|tray|tgdesk-|install|cm)'
        })
        foreach ($taskName in @('TGDeskLabUIProbeA','TGDeskLabUIProbeB')) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & schtasks.exe /Delete /TN $taskName /F 2>&1 | Out-Null
            $ErrorActionPreference = $previousPreference
        }
        [ordered]@{
            interactive_session = $true
            session_ids = $sessionIds
            explorer_count = $explorer.Count
            ui_count = $uis.Count
            ui_processes = @($uis | Select-Object `
                ProcessId,ParentProcessId,SessionId,CommandLine)
            interactive_tgdesk_processes = @($interactive | Select-Object `
                ProcessId,ParentProcessId,SessionId,CommandLine)
        }
    }
    $results += [ordered]@{ vm_name = $name; observed = $observed }
}
$passed = @($results | Where-Object {
    -not $_.observed.interactive_session -or $_.observed.ui_count -ne 1
}).Count -eq 0
$result = [ordered]@{
    schema_version = 1
    phase = 'windows-interactive-ui-process'
    status = if ($passed) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    mode = 'CLI process/session observation only; no GUI control'
    assertions = @(
        [ordered]@{
            id = 'runtime.single-ui-process'
            state = if ($passed) { 'passed' } else { 'failed' }
            detail = 'Duas solicitações concorrentes por sessão resultam em exatamente uma UI.'
        },
        [ordered]@{
            id = 'runtime.tray-start'
            state = 'blocked'
            detail = 'Processos são observáveis por CLI; presença visual do ícone não é alegada.'
        }
    )
    targets = $results
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force |
    Out-Null
$result | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 7
if (-not $passed) { exit 1 }
