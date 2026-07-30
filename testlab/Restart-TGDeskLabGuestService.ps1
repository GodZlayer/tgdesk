[CmdletBinding()]
param([string]$VMName = 'tgdesk-supervisor-0-3-48')
$ErrorActionPreference = 'Stop'
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
    Restart-Service TGDesk -ErrorAction Stop
    (Get-Service TGDesk).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
}
[ordered]@{ state = 'passed'; vm_name = $VMName; service = 'Running' } | ConvertTo-Json
