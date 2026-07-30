[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    )
)
$ErrorActionPreference = 'Stop'
$jobs = foreach ($name in $VMName) {
    Stop-VM -Name $name -TurnOff -Force -AsJob
}
$jobs | Wait-Job -Timeout 60 | Out-Null
$unfinished = @($jobs | Where-Object State -notin @('Completed','Failed'))
if ($unfinished.Count) {
    $unfinished | Stop-Job -ErrorAction SilentlyContinue
    throw "Timeout desligando: $($unfinished.Name -join ', ')"
}
$jobs | Receive-Job -ErrorAction Stop | Out-Null
foreach ($name in $VMName) {
    if ((Get-VM -Name $name).State -ne 'Off') {
        throw "$name não desligou."
    }
    Start-VM -Name $name
}
[ordered]@{
    status = 'passed'
    vm_names = $VMName
    states = @(Get-VM -Name $VMName | Select-Object Name,State)
} | ConvertTo-Json -Depth 5
