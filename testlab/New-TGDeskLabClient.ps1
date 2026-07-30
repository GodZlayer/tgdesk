[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('client', 'supervisor')]
    [string]$Role,
    [Parameter(Mandatory)]
    [string]$Version,
    [string]$ControlKeyPath = '',
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lab.config.json'
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This phase requires an elevated PowerShell process.'
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

Assert-Administrator
$configFullPath = [IO.Path]::GetFullPath($ConfigPath)
$config = Get-Content -LiteralPath $configFullPath -Raw | ConvertFrom-Json
$repoRoot = Split-Path -Parent $PSScriptRoot
$baseName = [string]$config.base_vm.name
$baseVhd = Join-Path (Join-Path ([string]$config.vm_root) $baseName) "$baseName.vhdx"
$installer = Join-Path $repoRoot "installers\output\tgdesk-installer-$Version.exe"
if (-not (Test-Path -LiteralPath $baseVhd -PathType Leaf)) { throw "Base VHD missing: $baseVhd" }
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Installer missing: $installer" }
if ($Role -ne 'client' -and -not (Test-Path -LiteralPath $ControlKeyPath -PathType Leaf)) {
    throw "Control key required for role $Role"
}

$vmName = "tgdesk-$Role-$($Version.Replace('.','-'))"
$vmPath = Join-Path ([string]$config.vm_root) $vmName
$vhdPath = Join-Path $vmPath "$vmName.vhdx"
$evidenceRoot = Join-Path $PSScriptRoot "artifacts\$vmName"
$evidencePath = Join-Path $evidenceRoot 'provision.json'
New-Item -ItemType Directory -Path $vmPath,$evidenceRoot -Force | Out-Null

$result = [ordered]@{
    schema_version = 1
    phase = 'provision-client'
    vm_name = $vmName
    role = $Role
    requested_version = $Version
    status = 'running'
    started_at = [DateTime]::UtcNow.ToString('o')
    measurements = [ordered]@{}
    failures = @()
}

try {
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        throw "VM already exists: $vmName"
    }
    New-VHD -Path $vhdPath -ParentPath $baseVhd -Differencing | Out-Null
    $switch = Get-VMSwitch -Name ([string]$config.switch_name) -ErrorAction Stop
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
        } | Select-Object -First 1
    if (-not $guestService) { throw "Guest Service Interface not found for $vmName" }
    $guestService | Enable-VMIntegrationService
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Start-VM -VM $vm | Out-Null

    Wait-Until -TimeoutSeconds 900 -Description 'PowerShell Direct ready' `
        -Probe {
            try {
                Invoke-Command -VMName $vmName -Credential (
                    [pscredential]::new(
                        'tgdesklab',
                        (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
                    )
                ) -ScriptBlock { [pscustomobject]@{ ready = $true; boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime } } -ErrorAction Stop
            } catch { [pscustomobject]@{ ready = $false; error = $_.Exception.Message } }
        } -Success { param($state) $state.ready } | Out-Null

    $guestRoot = 'C:\TGDeskLab'
    Invoke-Command -VMName $vmName -Credential (
        [pscredential]::new('tgdesklab',
            (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force))
    ) -ScriptBlock { New-Item -ItemType Directory -Path 'C:\TGDeskLab' -Force | Out-Null }
    Copy-VMFile -VMName $vmName -SourcePath $installer `
        -DestinationPath "$guestRoot\$(Split-Path -Leaf $installer)" `
        -FileSource Host -CreateFullPath -Force
    if ($Role -ne 'client') {
        Copy-VMFile -VMName $vmName -SourcePath $ControlKeyPath `
            -DestinationPath "$guestRoot\control.tgkey" `
            -FileSource Host -CreateFullPath -Force
    }

    $installResult = Invoke-Command -VMName $vmName -Credential (
        [pscredential]::new('tgdesklab',
            (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force))
    ) -ArgumentList $Version,$Role -ScriptBlock {
        param($RequestedVersion,$RequestedRole)
        $installer = "C:\TGDeskLab\tgdesk-installer-$RequestedVersion.exe"
        $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS'
        if ($RequestedRole -ne 'client') {
            $arguments += ' /CONTROLKEY="C:\TGDeskLab\control.tgkey"'
        }
        $command = "`"$installer`" $arguments /LOG=`"C:\TGDeskLab\install.log`""
        $process = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
            -Arguments @{ CommandLine = $command }
        [pscustomobject]@{
            exit_code = if ($process.ReturnValue -eq 0) { 0 } else { $process.ReturnValue }
            process_id = $process.ProcessId
        }
    }
    if ($installResult.exit_code -notin 0,3010) {
        throw "Installer returned $($installResult.exit_code)"
    }

    $state = Wait-Until -TimeoutSeconds 600 -Description 'TGDesk service and version ready' `
        -Probe {
            try {
                Invoke-Command -VMName $vmName -Credential (
                    [pscredential]::new('tgdesklab',
                        (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force))
                ) -ScriptBlock {
                    $service = Get-Service TGDesk -ErrorAction SilentlyContinue
                    $versionFile = 'C:\Program Files\TGDesk\version.txt'
                    [pscustomobject]@{
                        service = if ($service) { [string]$service.Status } else { 'Missing' }
                        version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { '' }
                        process_count = @(Get-Process tgdesk -ErrorAction SilentlyContinue).Count
                        status_file = Test-Path 'C:\ProgramData\TGDesk\state\status.json'
                    }
                }
            } catch { [pscustomobject]@{ service = 'Unavailable'; error = $_.Exception.Message } }
        } -Success {
            param($probe)
            $probe.service -eq 'Running' -and $probe.version -eq $Version
        }

    $result.status = 'passed'
    $result.measurements = [ordered]@{
        installer_sha256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        installer_exit_code = $installResult.exit_code
        final_state = $state
        vhd_path = $vhdPath
    }
} catch {
    $result.status = 'failed'
    $result.failures = @($_.Exception.Message)
    throw
} finally {
    $result.finished_at = [DateTime]::UtcNow.ToString('o')
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $evidencePath -Encoding utf8
}
