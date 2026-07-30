[CmdletBinding()]
param([string]$VMName = 'tgdesk-client-0-3-48')
$ErrorActionPreference = 'Stop'
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
    Stop-Service TGDesk -Force
    (Get-Service TGDesk).WaitForStatus(
        'Stopped', [TimeSpan]::FromSeconds(30))
    Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'" |
        Where-Object {
            $_.SessionId -eq 0 -and
            $_.CommandLine -match '--tgdesk-(host|technician-service)'
        } | Invoke-CimMethod -MethodName Terminate | Out-Null
    Remove-Item 'C:\ProgramData\TGDesk\identity\device.json',
        'C:\ProgramData\TGDesk\state\status.json' -Force `
        -ErrorAction SilentlyContinue
    Start-Service TGDesk
    (Get-Service TGDesk).WaitForStatus(
        'Running', [TimeSpan]::FromSeconds(30))
}
[ordered]@{
    status = 'passed'
    vm_name = $VMName
    reset_scope = 'isolated disposable client identity only'
} | ConvertTo-Json
