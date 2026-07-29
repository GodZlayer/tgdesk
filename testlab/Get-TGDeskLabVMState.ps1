[CmdletBinding()]
param(
    [string]$VMName = 'tgdesk-win-base',
    [int]$GuestProbeTimeoutSeconds = 15,
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot 'artifacts\vm-state.json'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Get-TGDeskLabVMState.ps1 exige processo CLI elevado.'
}

$vm = Get-VM -Name $VMName -ErrorAction Stop
$services = @(Get-VMIntegrationService -VM $vm |
    Select-Object Name,Enabled,PrimaryStatusDescription,SecondaryStatusDescription,Id)
$guestProbe = [ordered]@{
    state = 'not-run'
}

if ($vm.State -eq 'Running') {
    $probeOutput = Join-Path (Split-Path -Parent $EvidencePath) 'vm-guest-probe.stdout.json'
    $probeError = Join-Path (Split-Path -Parent $EvidencePath) 'vm-guest-probe.stderr.log'
    $safeProbeOutput = $probeOutput.Replace("'", "''")
    $safeProbeError = $probeError.Replace("'", "''")
    $probeCode = @"
`$ErrorActionPreference = 'Stop'
try {
        `$credential = [pscredential]::new(
            'tgdesklab',
            (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
        )
        `$result = Invoke-Command -VMName '$VMName' -Credential `$credential -ScriptBlock {
            `$os = Get-CimInstance Win32_OperatingSystem
            [pscustomobject]@{
                computer_name = `$env:COMPUTERNAME
                caption = `$os.Caption
                version = `$os.Version
                build = `$os.BuildNumber
            }
        } -ErrorAction Stop
        `$result | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath '$safeProbeOutput' -Encoding utf8
        exit 0
} catch {
    [pscustomobject]@{ error = `$_.Exception.Message } | ConvertTo-Json |
        Set-Content -LiteralPath '$safeProbeError' -Encoding utf8
    exit 1
}
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probeCode))
    $process = Start-Process powershell.exe -PassThru -WindowStyle Hidden `
        -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded)
    $deadline = [DateTime]::UtcNow.AddSeconds($GuestProbeTimeoutSeconds)
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
    }
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
        $guestProbe = [ordered]@{
            state = 'timeout'
            timeout_seconds = $GuestProbeTimeoutSeconds
            process_id = $process.Id
        }
    } elseif ($process.ExitCode -eq 0) {
        try {
            $guestProbe = [ordered]@{
                state = 'passed'
                result = Get-Content $probeOutput -Raw | ConvertFrom-Json
            }
        } catch {
            $guestProbe = [ordered]@{
                state = 'failed'
                error = "Saída inválida do probe: $($_.Exception.Message)"
            }
        }
    } else {
        $guestProbe = [ordered]@{
            state = 'failed'
            exit_code = $process.ExitCode
            error = (Get-Content $probeError -Raw -ErrorAction SilentlyContinue)
        }
    }
}

$report = [ordered]@{
    schema_version = 1
    phase = 'vm-state'
    state = if ($guestProbe.state -eq 'passed') { 'passed' } else { 'degraded' }
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    vm = [ordered]@{
        name = $vm.Name
        state = $vm.State.ToString()
        status = $vm.Status
        uptime_seconds = [math]::Round($vm.Uptime.TotalSeconds)
        generation = $vm.Generation
        integration_services = $services
    }
    guest_probe = $guestProbe
}
$report | ConvertTo-Json -Depth 10 | Set-Content $EvidencePath -Encoding utf8
$report | ConvertTo-Json -Depth 8
if ($report.state -ne 'passed') { exit 2 }
