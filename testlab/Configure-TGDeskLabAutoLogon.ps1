[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    )
)
$ErrorActionPreference = 'Stop'
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
foreach ($name in $VMName) {
    try {
        Invoke-Command -VMName $name -Credential $credential `
            -ErrorAction Stop -ScriptBlock {
            $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            Set-ItemProperty $winlogon AutoAdminLogon '1'
            Set-ItemProperty $winlogon DefaultUserName 'tgdesklab'
            Set-ItemProperty $winlogon DefaultPassword 'TGDesk-Lab-Only-2026!'
            Set-ItemProperty $winlogon DefaultDomainName $env:COMPUTERNAME
            $run = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            New-Item $run -Force | Out-Null
            $command = '"C:\Program Files\TGDesk\tgdesk.exe"'
            Set-ItemProperty $run TGDesk $command
            Set-ItemProperty $run TGDeskLabDuplicateProbe $command
            foreach ($task in @('TGDeskLabUIProbeA','TGDeskLabUIProbeB')) {
                Unregister-ScheduledTask -TaskName $task -Confirm:$false `
                    -ErrorAction SilentlyContinue
            }
        }
    } catch {
        # PowerShell Direct is expected to disconnect as the guest reboots.
    }
}
[ordered]@{
    status = 'autologon-configured'
    vm_names = $VMName
} | ConvertTo-Json
