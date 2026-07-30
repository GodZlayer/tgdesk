[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VMName,
    [Parameter(Mandatory)][string]$Version,
    [ValidateSet('client', 'supervisor')][string]$Role = 'client',
    [string]$EvidencePath = ''
)
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot "artifacts\$VMName\install-launch.json"
}
$credential = [pscredential]::new('tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force))
$launch = Invoke-Command -VMName $VMName -Credential $credential `
    -ArgumentList $Version,$Role -ScriptBlock {
        param($RequestedVersion,$RequestedRole)
        $installer = "C:\TGDeskLab\tgdesk-installer-$RequestedVersion.exe"
        $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS'
        if ($RequestedRole -ne 'client') {
            $arguments += ' /CONTROLKEY="C:\TGDeskLab\control.tgkey"'
        }
        $command = "`"$installer`" $arguments /LOG=`"C:\TGDeskLab\install.log`""
        Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
            -Arguments @{ CommandLine = $command }
    }
$result = [ordered]@{
    schema_version = 1
    phase = 'guest-install-launch'
    status = if ($launch.ReturnValue -eq 0) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    vm_name = $VMName
    process_id = $launch.ProcessId
    return_value = $launch.ReturnValue
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 6
if ($result.status -ne 'passed') { exit 1 }
