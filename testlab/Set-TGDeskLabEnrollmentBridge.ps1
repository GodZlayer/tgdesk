[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VMName,
    [ValidateSet('Enable', 'Disable')][string]$Action = 'Enable',
    [string]$PublicApiAddress = '168.232.199.161',
    [int]$PublicApiPort = 8090,
    [int]$TestApiPort = 18090
)
$ErrorActionPreference = 'Stop'
$hostAddress = (Get-NetIPAddress -InterfaceAlias 'vEthernet (Default Switch)' `
    -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1).IPAddress
$credential = [pscredential]::new('tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force))

if ($Action -eq 'Enable') {
    & netsh interface portproxy delete v4tov4 listenaddress=$hostAddress listenport=$TestApiPort | Out-Null
    & netsh interface portproxy add v4tov4 listenaddress=$hostAddress listenport=$TestApiPort `
        connectaddress=127.0.0.1 connectport=$TestApiPort
    if ($LASTEXITCODE -ne 0) { throw 'Falha criando bridge no host.' }
    Remove-NetFirewallRule -DisplayName 'TGDeskLab Enrollment Bridge' -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'TGDeskLab Enrollment Bridge' -Direction Inbound `
        -Action Allow -Protocol TCP -LocalAddress $hostAddress -LocalPort $TestApiPort `
        -Profile Any | Out-Null
    Invoke-Command -VMName $VMName -Credential $credential `
        -ArgumentList $PublicApiAddress,$PublicApiPort,$hostAddress,$TestApiPort -ScriptBlock {
            param($PublicAddress,$PublicPort,$HostAddress,$TargetPort)
            $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if (-not $adapter) { throw 'Nenhum adaptador de rede ativo no guest.' }
            Get-NetIPAddress -IPAddress $PublicAddress -ErrorAction SilentlyContinue |
                Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled
            & ipconfig.exe /renew | Out-Null
            # Keep the DHCP NIC untouched: the public endpoint alias belongs to
            # the loopback interface and exists only during isolated enrollment.
            New-NetIPAddress -InterfaceIndex 1 -IPAddress $PublicAddress `
                -PrefixLength 32 -SkipAsSource $true | Out-Null
            & netsh interface portproxy delete v4tov4 listenaddress=$PublicAddress `
                listenport=$PublicPort | Out-Null
            & netsh interface portproxy add v4tov4 listenaddress=$PublicAddress `
                listenport=$PublicPort connectaddress=$HostAddress connectport=$TargetPort
            $health = Invoke-RestMethod "http://${PublicAddress}:$PublicPort/healthz" -TimeoutSec 10
            if ($health.status -ne 'ok') { throw "Health inesperado: $($health.status)" }
        }
} else {
    try {
        Invoke-Command -VMName $VMName -Credential $credential `
            -ArgumentList $PublicApiAddress,$PublicApiPort -ScriptBlock {
                param($PublicAddress,$PublicPort)
                & netsh interface portproxy delete v4tov4 listenaddress=$PublicAddress `
                    listenport=$PublicPort | Out-Null
                Get-NetIPAddress -IPAddress $PublicAddress -ErrorAction SilentlyContinue |
                    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
                $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
                if ($adapter) {
                    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled
                    & ipconfig.exe /renew | Out-Null
                }
            }
    } finally {
        & netsh interface portproxy delete v4tov4 listenaddress=$hostAddress `
            listenport=$TestApiPort | Out-Null
        Remove-NetFirewallRule -DisplayName 'TGDeskLab Enrollment Bridge' `
            -ErrorAction SilentlyContinue
    }
}
[ordered]@{
    state = 'passed'
    action = $Action
    vm_name = $VMName
    host_address = $hostAddress
} | ConvertTo-Json
