$ErrorActionPreference = 'Stop'
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
$launcherEvidence = Join-Path $artifactRoot 'base-image-launcher.json'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

$result = [ordered]@{
    schema_version = 1
    phase = 'base-image-launcher'
    state = 'running'
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    elevated = $false
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $result.elevated = $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    $result | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $launcherEvidence -Encoding utf8

    & (Join-Path $PSScriptRoot 'New-TGDeskLabBaseImage.ps1') -Recreate
    $result.state = 'passed'
} catch {
    $result.state = 'failed'
    $result.error = $_.Exception.Message
    $result.script_stack = $_.ScriptStackTrace
    exit 1
} finally {
    $result.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    $result | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $launcherEvidence -Encoding utf8
}
