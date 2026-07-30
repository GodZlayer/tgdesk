[CmdletBinding()]
param([string]$VMName = 'tgdesk-supervisor-0-3-48')
$ErrorActionPreference = 'Stop'
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
    Get-Process -Name 'tgdesk-installer-*' -ErrorAction SilentlyContinue |
        Stop-Process -Force
    Start-Sleep -Seconds 2
    Remove-Item 'C:\TGDeskLab\install.log' -Force -ErrorAction SilentlyContinue
}
[ordered]@{ state = 'passed'; vm_name = $VMName } | ConvertTo-Json
