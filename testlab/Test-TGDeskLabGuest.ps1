[CmdletBinding()]
param(
    [string]$VMName = 'tgdesk-win-base',
    [string]$EvidencePath = '',
    [switch]$Shutdown
)

$ErrorActionPreference = 'Stop'
if (-not $EvidencePath) {
    $EvidencePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) `
        'artifacts\guest-probe.json'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$guest = Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
    $os = Get-CimInstance Win32_OperatingSystem
    [ordered]@{
        ready = $true
        caption = $os.Caption
        version = $os.Version
        build = $os.BuildNumber
        computer_name = $env:COMPUTERNAME
        tgdesk_service = [string](Get-Service TGDesk -ErrorAction SilentlyContinue).Status
        tgdesk_version = if (Test-Path 'C:\Program Files\TGDesk\version.txt') {
            (Get-Content 'C:\Program Files\TGDesk\version.txt' -Raw).Trim()
        } else { '' }
        lab_files = @(Get-ChildItem 'C:\TGDeskLab' -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name)
        install_log_tail = if (Test-Path 'C:\TGDeskLab\install.log') {
            @(Get-Content 'C:\TGDeskLab\install.log' -Tail 30 | ForEach-Object { [string]$_ })
        } else { @() }
        network = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object IPAddress -notlike '127.*' |
            Select-Object IPAddress,PrefixLength,InterfaceAlias)
        test_backend = [ordered]@{
            host_reachable = Test-NetConnection 172.18.80.1 -Port 18090 `
                -InformationLevel Quiet -WarningAction SilentlyContinue
            public_reachable = Test-NetConnection 168.232.199.161 -Port 8090 `
                -InformationLevel Quiet -WarningAction SilentlyContinue
        }
    }
}
if ($Shutdown) {
    Stop-VM -Name $VMName
    $deadline = [DateTime]::UtcNow.AddSeconds(300)
    do {
        $state = (Get-VM -Name $VMName).State.ToString()
        if ($state -eq 'Off') { break }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($state -ne 'Off') { throw "Timeout desligando ${VMName}: $state" }
}
$result = [ordered]@{
    schema_version = 1
    phase = 'guest-probe'
    status = 'passed'
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    vm_name = $VMName
    guest = $guest
    final_vm_state = (Get-VM -Name $VMName).State.ToString()
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 8
