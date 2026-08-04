param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

$stageVersionPath = Join-Path $PSScriptRoot 'stage-unified\version.txt'
$stageVersion = (Get-Content -LiteralPath $stageVersionPath -Raw).Trim()
if ($stageVersion -ne $Version) {
    throw "Versao do stage ($stageVersion) difere da publicacao ($Version)."
}

$issPath = Join-Path $PSScriptRoot 'tgdesk-installer.iss'
$iss = Get-Content -LiteralPath $issPath -Raw
if ($iss -notmatch ('#define MyAppVersion "' + [regex]::Escape($Version) + '"') -or
    $iss -notmatch ('OutputBaseFilename=tgdesk-installer-' + [regex]::Escape($Version))) {
    throw "O instalador nao esta identificado como $Version."
}

& (Join-Path $PSScriptRoot 'New-TGDeskModuleRelease.ps1') -Version $Version

$compilerCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$compiler = $compilerCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $compiler) {
    throw 'Compilador Inno Setup 6 nao encontrado.'
}

# O instalador precisa validar a chave de controle contra o endereco publico
# do servidor, nao contra localhost (so funciona quando o instalador roda na
# propria maquina do servidor). Reaproveita o mesmo host de HUB_PUBLIC_ADDR
# do .env, ja usado para o hub WireGuard, como unica fonte de verdade.
$serverHost = '127.0.0.1'
$envPath = Join-Path $PSScriptRoot '..\server\.env'
if (Test-Path -LiteralPath $envPath) {
    $hubLine = Get-Content -LiteralPath $envPath |
        Where-Object { $_ -match '^\s*HUB_PUBLIC_ADDR\s*=\s*(.+)$' } |
        Select-Object -First 1
    if ($hubLine) {
        $value = ($hubLine -replace '^\s*HUB_PUBLIC_ADDR\s*=\s*', '').Trim()
        if ($value -match '^([^:]+):') {
            $serverHost = $Matches[1]
        } elseif ($value) {
            $serverHost = $value
        }
    }
}
Write-Host "Host do servidor para validacao de chave de controle: $serverHost"

& $compiler "/DTGDeskServerHost=$serverHost" $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao compilar o instalador $Version."
}

$installer = Join-Path $PSScriptRoot "output\tgdesk-installer-$Version.exe"
$published = Join-Path $PSScriptRoot '..\server\releases\tgdesk-update.exe'
Copy-Item -LiteralPath $installer -Destination $published -Force

$installerHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$publishedHash = (Get-FileHash -LiteralPath $published -Algorithm SHA256).Hash
if ($installerHash -ne $publishedHash) {
    throw 'O instalador publicado difere do instalador compilado.'
}

Write-Host "TGDesk $Version publicado localmente."
Write-Host "Instalador: $installer"
Write-Host "SHA256: $installerHash"
