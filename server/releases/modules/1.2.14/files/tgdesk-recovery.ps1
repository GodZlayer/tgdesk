param(
    [string]$ApiBase = 'http://168.232.199.161:8090'
)

$ErrorActionPreference = 'Stop'
$installDir = 'C:\Program Files\TGDesk'
$dataDir = 'C:\ProgramData\TGDesk'
$versionFile = Join-Path $installDir 'version.txt'
if (-not (Test-Path -LiteralPath $versionFile)) { exit 0 }
$current = (Get-Content -LiteralPath $versionFile -Raw).Trim()

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Remote([string]$Uri, [string]$Path, [string]$Hash, [Int64]$Size) {
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Path
    if ((Get-Item -LiteralPath $Path).Length -ne $Size -or (Get-Sha256 $Path) -ne $Hash.ToLowerInvariant()) {
        throw "arquivo inválido: $Uri"
    }
}

# Este recuperador não depende dos dois EXEs: restaura o updater canônico,
# baixa o manifesto e deixa o próprio updater aplicar a transação.
$updaterInfo = Invoke-RestMethod -Uri "$ApiBase/api/v1/client/updater"
if (-not $updaterInfo.sha256 -or $updaterInfo.size -le 0) { throw 'metadados do updater inválidos' }
$staging = Join-Path $dataDir (Join-Path 'updates\recovery' ([Guid]::NewGuid().ToString()))
$files = Join-Path $staging 'files'
New-Item -ItemType Directory -Path $files -Force | Out-Null
$newUpdater = Join-Path $staging 'tgdesk-updater.next.exe'
Get-Remote "$ApiBase$($updaterInfo.url)" $newUpdater $updaterInfo.sha256 ([Int64]$updaterInfo.size)
$updater = Join-Path $installDir 'tgdesk-updater.exe'
$previous = Join-Path $staging 'tgdesk-updater.previous.exe'
if (Test-Path -LiteralPath $updater) { Move-Item -LiteralPath $updater -Destination $previous -Force }
try { Move-Item -LiteralPath $newUpdater -Destination $updater -Force } catch { if (Test-Path $previous) { Move-Item $previous $updater -Force }; throw }

$manifest = Invoke-RestMethod -Uri "$ApiBase/api/v1/client/modules?version=$([uri]::EscapeDataString($current))"
if (-not $manifest.version) { exit 0 }
$changed = @()
foreach ($item in @($manifest.files)) {
    if ($item.path -eq 'tgdesk-updater.exe' -or $item.path -match '(^|/|\\)\.\.($|/|\\)') { throw 'manifesto contém caminho inválido' }
    $target = Join-Path $installDir ($item.path -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $target) -or (Get-Sha256 $target) -ne $item.sha256.ToLowerInvariant()) {
        $download = Join-Path $files ($item.path -replace '/', '\\')
        New-Item -ItemType Directory -Path (Split-Path $download -Parent) -Force | Out-Null
        Get-Remote "$ApiBase/api/v1/client/modules/$($manifest.version)/$([uri]::EscapeDataString($item.path).Replace('%2F','/'))" $download $item.sha256 ([Int64]$item.size)
        $changed += $item
    }
}
if ($changed.Count -eq 0) { exit 0 }
$manifest.files = @($changed)
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $staging 'manifest.json') -Encoding UTF8
& $updater --apply-staged --staging $staging --install-dir $installDir --parent 0
exit $LASTEXITCODE
