param(
    [Parameter(Mandatory = $false)]
    [string]$Version = '1.1.1',
    [Parameter(Mandatory = $false)]
    [string]$Source = "$PSScriptRoot\stage-unified",
    [Parameter(Mandatory = $false)]
    [string]$ReleaseRoot = "$PSScriptRoot\..\server\releases\modules"
)

$ErrorActionPreference = 'Stop'
$sourcePath = [System.IO.Path]::GetFullPath($Source)
$versionRoot = [System.IO.Path]::GetFullPath((Join-Path $ReleaseRoot $Version))
$filesRoot = Join-Path $versionRoot 'files'

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Stage não encontrado: $sourcePath"
}
if (Test-Path -LiteralPath $versionRoot) {
    [System.IO.Directory]::Delete($versionRoot, $true)
}
[System.IO.Directory]::CreateDirectory($filesRoot) | Out-Null
Copy-Item -Path (Join-Path $sourcePath '*') -Destination $filesRoot -Recurse -Force
$updaterPayload = Join-Path $filesRoot 'tgdesk-updater.exe'
if (Test-Path -LiteralPath $updaterPayload) {
    Remove-Item -LiteralPath $updaterPayload -Force
}

$serviceFiles = @(
    'tgdesk.exe',
    'tgdesk_agent.dll',
    'librustdesk.dll'
)
$entries = foreach ($file in Get-ChildItem -LiteralPath $filesRoot -File -Recurse) {
    $relative = $file.FullName.Substring($filesRoot.Length).
        TrimStart('\').Replace('\', '/')
    [ordered]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).
            Hash.ToLowerInvariant()
        size = $file.Length
        scope = if ($serviceFiles -contains $relative) { 'service' } else { 'ui' }
    }
}

$manifest = [ordered]@{
    format_version = 1
    version = $Version
    generated_at = [DateTimeOffset]::UtcNow.ToString('o')
    processes = @('tgdesk.exe')
    services = @('TGDesk')
    restart_application = ''
    files = @($entries | Sort-Object path)
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText(
    (Join-Path $versionRoot 'manifest.json'),
    $manifestJson,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Release modular ${Version}: $($entries.Count) arquivos em $versionRoot"
