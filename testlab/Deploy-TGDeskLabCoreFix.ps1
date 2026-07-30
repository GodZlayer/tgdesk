[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    ),
    [string]$CorePath = '',
    [string]$AgentPath = ''
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $CorePath) {
    $CorePath = Join-Path $repo `
        'client-rustdesk-src\target\release\librustdesk.dll'
}
if (-not $AgentPath) {
    $AgentPath = Join-Path $repo 'client-agent\tgdesk_agent.dll'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$sourceHash = (Get-FileHash $CorePath -Algorithm SHA256).Hash
$agentHash = (Get-FileHash $AgentPath -Algorithm SHA256).Hash
$results = @()
foreach ($name in $VMName) {
    Invoke-Command -VMName $name -Credential $credential -ScriptBlock {
        Stop-Service TGDesk -Force -ErrorAction SilentlyContinue
        (Get-Service TGDesk).WaitForStatus(
            'Stopped', [TimeSpan]::FromSeconds(30))
        Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'" |
            Invoke-CimMethod -MethodName Terminate | Out-Null
    }
    Copy-VMFile -Name $name -SourcePath $CorePath `
        -DestinationPath 'C:\Program Files\TGDesk\librustdesk.dll' `
        -FileSource Host -Force
    Copy-VMFile -Name $name -SourcePath $AgentPath `
        -DestinationPath 'C:\Program Files\TGDesk\tgdesk_agent.dll' `
        -FileSource Host -Force
    $observed = Invoke-Command -VMName $name -Credential $credential `
        -ScriptBlock {
        Start-Service TGDesk
        (Get-Service TGDesk).WaitForStatus(
            'Running', [TimeSpan]::FromSeconds(30))
        [ordered]@{
            service = [string](Get-Service TGDesk).Status
            core_hash = (Get-FileHash `
                'C:\Program Files\TGDesk\librustdesk.dll' `
                -Algorithm SHA256).Hash
            agent_hash = (Get-FileHash `
                'C:\Program Files\TGDesk\tgdesk_agent.dll' `
                -Algorithm SHA256).Hash
        }
    }
    $results += [ordered]@{
        vm_name = $name
        service = $observed.service
        core_hash = $observed.core_hash
        hash_match = $observed.core_hash -eq $sourceHash
        agent_hash = $observed.agent_hash
        agent_hash_match = $observed.agent_hash -eq $agentHash
    }
}
$passed = @($results | Where-Object {
    $_.service -ne 'Running' -or
    -not $_.hash_match -or
    -not $_.agent_hash_match
}).Count -eq 0
$result = [ordered]@{
    schema_version = 1
    phase = 'deploy-core-fix'
    status = if ($passed) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    source_hash = $sourceHash
    agent_source_hash = $agentHash
    targets = $results
}
$evidence = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) `
    'artifacts\windows-e2e-core-deploy.json'
$result | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath $evidence -Encoding utf8
$result | ConvertTo-Json -Depth 6
if (-not $passed) { exit 1 }
