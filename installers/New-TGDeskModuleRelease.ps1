param(
    [Parameter(Mandatory = $false)]
    [string]$Version = '1.1.11',
    [Parameter(Mandatory = $false)]
    [string]$Source = '',
    [Parameter(Mandatory = $false)]
    [string]$ReleaseRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $PSScriptRoot 'stage-unified'
}
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) {
    $ReleaseRoot = Join-Path $PSScriptRoot '..\server\releases\modules'
}
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
$previousUpdaterHash = ''
$previousRelease = @(Get-ChildItem -LiteralPath $ReleaseRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $Version -and $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1)
if ($previousRelease.Count -eq 1) {
    $previousManifestPath = Join-Path $previousRelease[0].FullName 'manifest.json'
    if (Test-Path -LiteralPath $previousManifestPath) {
        $previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
        $previousUpdater = @($previousManifest.files |
            Where-Object { $_.path -eq 'tgdesk-updater.exe' } |
            Select-Object -First 1)
        if ($previousUpdater.Count -eq 1) {
            $previousUpdaterHash = [string]$previousUpdater[0].sha256
        }
    }
}
$serviceFiles = @(
    'tgdesk.exe',
    'tgdesk_agent.dll',
    'librustdesk.dll'
)
$entries = foreach ($file in Get-ChildItem -LiteralPath $filesRoot -File -Recurse) {
    $relative = $file.FullName.Substring($filesRoot.Length).
        TrimStart('\').Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).
        Hash.ToLowerInvariant()
    # Um bootstrap idêntico ao da versão anterior não é um módulo da
    # atualização. Quando o hash mudar ele volta ao manifesto com scope
    # bootstrap e obriga o fluxo de instalador completo.
    if ($relative -eq 'tgdesk-updater.exe' -and
        $previousUpdaterHash -eq $hash) {
        continue
    }
    [ordered]@{
        path = $relative
        sha256 = $hash
        size = $file.Length
        scope = if ($relative -eq 'tgdesk-updater.exe') { 'bootstrap' }
            elseif ($serviceFiles -contains $relative) { 'service' }
            else { 'ui' }
    }
}

$manifest = [ordered]@{
    format_version = 1
    version = $Version
    generated_at = [DateTimeOffset]::UtcNow.ToString('o')
    processes = @('tgdesk.exe')
    services = @('TGDesk')
    # O servico roda na sessao 0 e nao pode restaurar a janela ou a bandeja
    # do usuario apos trocar os binarios. O updater, que nasceu na sessao
    # interativa, relanca explicitamente a interface ao concluir.
    restart_application = 'tgdesk.exe'
    files = @($entries | Sort-Object path)
}
$manifestJson = $manifest | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText(
    (Join-Path $versionRoot 'manifest.json'),
    $manifestJson,
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Release modular ${Version}: $($entries.Count) arquivos em $versionRoot"
