[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'lab.config.json'),
    [string]$EvidencePath,
    [switch]$Recreate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This phase requires an elevated PowerShell process.'
    }
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Wait-Until {
    param(
        [scriptblock]$Probe,
        [scriptblock]$Success,
        [int]$TimeoutSeconds,
        [string]$Description
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $last = $null
    do {
        $last = & $Probe
        if (& $Success $last) { return $last }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "State timeout: $Description. Last state: $($last | ConvertTo-Json -Compress -Depth 5)"
}

function Invoke-BoundedGuestProbe {
    param(
        [string]$VMName,
        [pscredential]$Credential,
        [int]$TimeoutSeconds = 20
    )
    $probeFile = Join-Path $env:TEMP "tgdesk-guest-probe-$([guid]::NewGuid().ToString('N')).json"
    $errorFile = "$probeFile.error"
    $credentialPassword = $Credential.GetNetworkCredential().Password.Replace("'", "''")
    $probeCode = @"
`$ErrorActionPreference = 'Stop'
try {
    `$credential = [pscredential]::new(
        '$($Credential.UserName.Replace("'", "''"))',
        (ConvertTo-SecureString '$credentialPassword' -AsPlainText -Force)
    )
    Invoke-Command -VMName '$($VMName.Replace("'", "''"))' -Credential `$credential -ScriptBlock {
        `$os = Get-CimInstance Win32_OperatingSystem
        [pscustomobject]@{
            ready = `$true
            caption = `$os.Caption
            version = `$os.Version
            build = `$os.BuildNumber
            computer_name = `$env:COMPUTERNAME
        }
    } -ErrorAction Stop | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath '$($probeFile.Replace("'", "''"))' -Encoding utf8
    exit 0
} catch {
    `$_.Exception.Message | Set-Content -LiteralPath '$($errorFile.Replace("'", "''"))' -Encoding utf8
    exit 1
}
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeCode))
    $process = Start-Process powershell.exe -PassThru -WindowStyle Hidden `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
    }
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
        return [pscustomobject]@{ ready = $false; error = "probe timeout after ${TimeoutSeconds}s" }
    }
    if ($process.ExitCode -eq 0 -and (Test-Path $probeFile)) {
        $state = Get-Content $probeFile -Raw | ConvertFrom-Json
        Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
        Remove-Item $errorFile -Force -ErrorAction SilentlyContinue
        return $state
    }
    $message = if (Test-Path $errorFile) { Get-Content $errorFile -Raw } else {
        "probe exited with code $($process.ExitCode)"
    }
    Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
    Remove-Item $errorFile -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{ ready = $false; error = $message.Trim() }
}

$evidencePath = if ($EvidencePath) {
    [IO.Path]::GetFullPath($EvidencePath)
} else {
    Join-Path $PSScriptRoot "artifacts\base-image-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')).json"
}
New-Item -ItemType Directory -Path (Split-Path -Parent $evidencePath) -Force | Out-Null

$result = [ordered]@{
    schema_version = 1
    phase = 'base-image'
    status = 'running'
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    measurements = [ordered]@{}
    failures = @()
}

$mountedIso = $null
$mountedVhd = $null
$isoPath = $null
$vhdPath = $null
try {
    Assert-Administrator
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $configDir = Split-Path -Parent ([IO.Path]::GetFullPath($ConfigPath))
    $isoPath = if ([IO.Path]::IsPathRooted([string]$config.base_vm.iso_path)) {
        [string]$config.base_vm.iso_path
    } else {
        [IO.Path]::GetFullPath((Join-Path $configDir ([string]$config.base_vm.iso_path)))
    }
    if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
        throw "Windows ISO not found: $isoPath"
    }

    $vmRoot = [string]$config.vm_root
    $vmName = [string]$config.base_vm.name
    $vmPath = Join-Path $vmRoot $vmName
    $vhdPath = Join-Path $vmPath "$vmName.vhdx"
    $resolvedRoot = [IO.Path]::GetFullPath($vmRoot).TrimEnd('\') + '\'
    $resolvedVMPath = [IO.Path]::GetFullPath($vmPath).TrimEnd('\') + '\'
    if (-not $resolvedVMPath.StartsWith(
        $resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "VM path escaped configured root: $resolvedVMPath"
    }
    if ($Recreate) {
        $existingVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($existingVM) {
            if ($existingVM.State -ne 'Off') {
                throw "Refusing to recreate running VM: $vmName ($($existingVM.State))"
            }
            Remove-VM -VM $existingVM -Force
        }
        if (Test-Path -LiteralPath $vmPath) {
            Remove-Item -LiteralPath $vmPath -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path $vmPath -Force | Out-Null

    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        throw "VM already exists: $vmName"
    }
    if (Test-Path -LiteralPath $vhdPath) {
        throw "VHD already exists: $vhdPath"
    }

    $mountedIso = Mount-DiskImage -ImagePath $isoPath -PassThru
    $isoDrive = ($mountedIso | Get-Volume | Where-Object DriveLetter | Select-Object -First 1).DriveLetter
    if (-not $isoDrive) { throw 'Mounted ISO has no drive letter' }
    $installWim = "$isoDrive`:\sources\install.wim"
    $installEsd = "$isoDrive`:\sources\install.esd"
    $imageFile = if (Test-Path -LiteralPath $installWim) { $installWim } elseif (
        Test-Path -LiteralPath $installEsd) { $installEsd } else {
        throw 'install.wim/install.esd not found in ISO'
    }
    $images = Get-WindowsImage -ImagePath $imageFile
    $selected = $images |
        Where-Object { $_.ImageName -match 'Enterprise.*Evaluation|Enterprise.*Avalia' } |
        Select-Object -First 1
    if (-not $selected) { $selected = $images | Select-Object -First 1 }

    $vhd = New-VHD -Path $vhdPath -Dynamic -SizeBytes ([int64]$config.base_vm.disk_size_gb * 1GB)
    $mountedVhd = Mount-VHD -Path $vhdPath -PassThru
    $disk = $mountedVhd | Get-Disk
    $disk | Initialize-Disk -PartitionStyle GPT
    # A FAT32 basic-data partition boots, but Windows specialize cannot discover it
    # as the system partition. Mark it explicitly as an EFI System Partition.
    $efi = New-Partition -DiskNumber $disk.Number -Size 260MB -AssignDriveLetter `
        -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Confirm:$false | Out-Null
    New-Partition -DiskNumber $disk.Number -Size 16MB `
        -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null
    $os = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'Windows' -Confirm:$false | Out-Null
    $osLetter = ($os | Get-Volume).DriveLetter
    $efiLetter = ($efi | Get-Volume).DriveLetter

    Invoke-Checked -FilePath dism.exe -ArgumentList @(
        '/Apply-Image',
        "/ImageFile:$imageFile",
        "/Index:$($selected.ImageIndex)",
        "/ApplyDir:$osLetter`:\"
    )
    Invoke-Checked -FilePath "$env:SystemRoot\System32\bcdboot.exe" -ArgumentList @(
        "$osLetter`:\Windows",
        '/s',
        "$efiLetter`:",
        '/f',
        'UEFI'
    )

    $panther = "$osLetter`:\Windows\Panther"
    New-Item -ItemType Directory -Path $panther -Force | Out-Null
    $unattendTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\unattend.xml') -Raw
    Set-Content -LiteralPath (Join-Path $panther 'unattend.xml') -Value $unattendTemplate -Encoding utf8

    Dismount-VHD -Path $vhdPath
    $mountedVhd = $null
    Dismount-DiskImage -ImagePath $isoPath
    $mountedIso = $null

    $switch = Get-VMSwitch -Name ([string]$config.switch_name) -ErrorAction SilentlyContinue
    if (-not $switch) {
        $switch = Get-VMSwitch | Where-Object SwitchType -eq 'External' | Select-Object -First 1
    }
    if (-not $switch) { throw "Hyper-V switch not found: $($config.switch_name)" }

    $vm = New-VM -Name $vmName -Generation 2 -VHDPath $vhdPath -Path $vmPath `
        -MemoryStartupBytes ([int64]$config.base_vm.memory_mb * 1MB) `
        -SwitchName $switch.Name
    Set-VMProcessor -VM $vm -Count ([int]$config.base_vm.cpu_count)
    Set-VM -VM $vm -AutomaticCheckpointsEnabled $false -AutomaticStartAction Nothing
    Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
    Enable-VMTPM -VM $vm
    $guestService = Get-VMIntegrationService -VMName $vmName |
        Where-Object {
            $_.Id.ToString() -match '6C09BB55-D683-4DA0-8931-C9BF705F6480$' -or
            $_.Name -match 'Guest Service Interface|Interface de Serviço de Convidado'
        } |
        Select-Object -First 1
    if (-not $guestService) {
        $available = Get-VMIntegrationService -VMName $vmName |
            Select-Object Name, Id
        throw "Guest Service Interface integration component not found. Available: $(
            $available | ConvertTo-Json -Compress)"
    }
    $guestService | Enable-VMIntegrationService
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows

    Start-VM -VM $vm | Out-Null
    $credential = [pscredential]::new(
        'tgdesklab',
        (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
    )
    $guest = Wait-Until -TimeoutSeconds 1200 -Description 'base Windows first boot' `
        -Probe {
            Invoke-BoundedGuestProbe -VMName $vmName -Credential $credential -TimeoutSeconds 20
        } -Success { param($state) $state.ready }
    # Stop-VM without -TurnOff requests a graceful guest shutdown.
    Stop-VM -Name $vmName
    Wait-Until -TimeoutSeconds 300 -Description 'base VM clean shutdown' `
        -Probe { (Get-VM -Name $vmName).State.ToString() } `
        -Success { param($state) $state -eq 'Off' } | Out-Null

    $result.status = 'passed'
    $result.measurements = [ordered]@{
        vm_name = $vmName
        vhd_path = $vhdPath
        image_name = $selected.ImageName
        image_index = $selected.ImageIndex
        switch_name = $switch.Name
        vhd_size_bytes = (Get-Item -LiteralPath $vhdPath).Length
        guest = $guest
        final_vm_state = (Get-VM -Name $vmName).State.ToString()
    }
} catch {
    $result.status = 'failed'
    $result.failures = @($_.Exception.Message)
    throw
} finally {
    if ($mountedVhd -and $vhdPath) { Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue }
    if ($mountedIso -and $isoPath) { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue }
    $result.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $evidencePath -Encoding utf8
}
