[CmdletBinding()]
param(
    [ValidateSet('BaseImage')]
    [string]$Phase = 'BaseImage'
)

$ErrorActionPreference = 'Stop'
$stateLoop = Join-Path $PSScriptRoot 'Invoke-TGDeskStateLoop.ps1'
& $stateLoop -Action ValidateMedia
if ($LASTEXITCODE -ne 0) {
    throw 'Validated Windows media is required before elevation'
}

$script = switch ($Phase) {
    'BaseImage' { Join-Path $PSScriptRoot 'Run-TGDeskLabBaseImageElevated.ps1' }
}
$arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$process = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru `
    -ArgumentList $arguments
if ($process.ExitCode -ne 0) {
    throw "Elevated phase $Phase failed with exit code $($process.ExitCode)"
}
