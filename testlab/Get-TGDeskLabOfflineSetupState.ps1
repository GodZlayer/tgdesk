[CmdletBinding()]
param(
    [string]$VMName = 'tgdesk-win-base',
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot 'artifacts\vm-offline-setup-state.json'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Get-TGDeskLabOfflineSetupState.ps1 exige processo CLI elevado.'
}

$vm = Get-VM -Name $VMName -ErrorAction Stop
$disk = Get-VMHardDiskDrive -VM $vm | Select-Object -First 1
if (-not $disk) { throw "VHD nao encontrado para $VMName" }
$vhdPath = [IO.Path]::GetFullPath($disk.Path)
$allowedRoot = [IO.Path]::GetFullPath('C:\ProgramData\TGDeskLab\VMs').TrimEnd('\') + '\'
if (-not $vhdPath.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "VHD fora da raiz permitida: $vhdPath"
}
if ($vm.State -ne 'Off') {
    Stop-VM -VM $vm -TurnOff -Force
}

$mounted = $null
try {
    $mounted = Mount-VHD -Path $vhdPath -ReadOnly -PassThru
    $windowsVolume = $mounted | Get-Disk | Get-Partition | Get-Volume |
        Where-Object { $_.FileSystemLabel -eq 'Windows' } | Select-Object -First 1
    if (-not $windowsVolume.DriveLetter) { throw 'Volume Windows sem letra apos montagem.' }
    $root = "$($windowsVolume.DriveLetter):\"
    $logPaths = @(
        'Windows\Panther\setupact.log',
        'Windows\Panther\setuperr.log',
        'Windows\Panther\UnattendGC\setupact.log',
        'Windows\Panther\UnattendGC\setuperr.log'
    )
    $logs = foreach ($relative in $logPaths) {
        $path = Join-Path $root $relative
        $tail = if (Test-Path -LiteralPath $path) {
            @(Get-Content -LiteralPath $path -Tail 240 -ErrorAction SilentlyContinue |
                ForEach-Object { [string]$_ } |
                Where-Object {
                    $_ -match '(?i)error|fail|fatal|unattend|oobe|specialize|complete|success'
                })
        } else { @() }
        [ordered]@{
            relative_path = $relative
            exists = Test-Path -LiteralPath $path
            tail = $tail
        }
    }
    $setupHive = Join-Path $root 'Windows\System32\config\SYSTEM'
    $hiveName = "HKLM\TGDeskLabSystem-$PID"
    $setupState = [ordered]@{}
    & reg.exe load $hiveName $setupHive | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao carregar hive SYSTEM offline.' }
    try {
        $setupKey = "Registry::$hiveName\Setup"
        $statusKey = "$setupKey\Status\SysprepStatus"
        foreach ($name in @('CmdLine', 'OOBEInProgress', 'SetupPhase', 'SetupType', 'SystemSetupInProgress')) {
            $property = Get-ItemProperty -LiteralPath $setupKey -Name $name -ErrorAction SilentlyContinue
            if ($property) { $setupState[$name] = $property.$name }
        }
        foreach ($name in @('CleanupState', 'GeneralizationState')) {
            $property = Get-ItemProperty -LiteralPath $statusKey -Name $name -ErrorAction SilentlyContinue
            if ($property) { $setupState[$name] = $property.$name }
        }
    } finally {
        & reg.exe unload $hiveName | Out-Null
    }
    $report = [ordered]@{
        schema_version = 1
        phase = 'vm-offline-setup-state'
        state = 'passed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        vm_name = $VMName
        vhd_path = $vhdPath
        setup_state = $setupState
        logs = @($logs)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content $EvidencePath -Encoding utf8
    $report | ConvertTo-Json -Depth 6
} finally {
    if ($mounted) { Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue }
}
