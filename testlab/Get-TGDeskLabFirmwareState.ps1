[CmdletBinding()]
param(
    [string]$VMName = 'tgdesk-win-base',
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot 'artifacts\vm-firmware-state.json'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Get-TGDeskLabFirmwareState.ps1 exige processo CLI elevado.'
}

$vm = Get-VM -Name $VMName
$firmware = Get-VMFirmware -VM $vm
$events = @(
    Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Hyper-V-Worker-Admin'
        StartTime = (Get-Date).AddHours(-2)
    } -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $vm.Id.Guid } |
        Select-Object -First 30 TimeCreated,Id,LevelDisplayName,Message
)
$report = [ordered]@{
    schema_version = 1
    phase = 'vm-firmware-state'
    state = 'passed'
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    vm = [ordered]@{
        id = $vm.Id
        state = $vm.State.ToString()
        status = $vm.Status
    }
    firmware = [ordered]@{
        secure_boot = $firmware.SecureBoot
        secure_boot_template = $firmware.SecureBootTemplate
        boot_order = @($firmware.BootOrder |
            Select-Object BootType,FirmwarePath,Device)
    }
    events = $events
}
$report | ConvertTo-Json -Depth 10 | Set-Content $EvidencePath -Encoding utf8
$report | ConvertTo-Json -Depth 8
