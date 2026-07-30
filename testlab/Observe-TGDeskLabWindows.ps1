[CmdletBinding()]
param([string]$EvidencePath = '')
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot `
        'artifacts\windows-e2e-observation.json'
}
& (Join-Path $scriptRoot 'Test-TGDeskWindowsE2E.ps1') `
    -ServiceRestartCycles 0 -EvidencePath $EvidencePath
exit $LASTEXITCODE
