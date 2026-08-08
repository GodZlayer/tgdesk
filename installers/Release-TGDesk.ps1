param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message"
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Invoke-Checked([scriptblock]$Command, [string]$FailureMessage) {
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Codigo: $LASTEXITCODE"
    }
}

function Set-TextFile([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Update-TextFile([string]$Path, [scriptblock]$Updater) {
    $current = [System.IO.File]::ReadAllText($Path)
    $updated = & $Updater $current
    Set-TextFile $Path $updated
}

function Resolve-InnoCompiler {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'Compilador Inno Setup 6 nao encontrado.'
}

function Resolve-ServerHost([string]$Root) {
    $serverHost = '127.0.0.1'
    $envPath = Join-Path $Root 'server\.env'
    if (-not (Test-Path -LiteralPath $envPath)) {
        return $serverHost
    }
    $hubLine = Get-Content -LiteralPath $envPath |
        Where-Object { $_ -match '^\s*HUB_PUBLIC_ADDR\s*=\s*(.+)$' } |
        Select-Object -First 1
    if (-not $hubLine) {
        return $serverHost
    }
    $value = ($hubLine -replace '^\s*HUB_PUBLIC_ADDR\s*=\s*', '').Trim()
    if ($value -match '^([^:]+):') {
        return $Matches[1]
    }
    if ($value) {
        return $value
    }
    return $serverHost
}

function New-ModuleRelease(
    [string]$Version,
    [string]$StageRoot,
    [string]$ReleaseRoot
) {
    $versionRoot = [System.IO.Path]::GetFullPath((Join-Path $ReleaseRoot $Version))
    $filesRoot = Join-Path $versionRoot 'files'
    if (Test-Path -LiteralPath $versionRoot) {
        [System.IO.Directory]::Delete($versionRoot, $true)
    }
    [System.IO.Directory]::CreateDirectory($filesRoot) | Out-Null
    Copy-Item -Path (Join-Path $StageRoot '*') -Destination $filesRoot -Recurse -Force

    $serviceFiles = @(
        'tgdesk.exe',
        'tgdesk_agent.dll',
        'libtgdeskcore.dll'
    )

    $entries = foreach ($file in Get-ChildItem -LiteralPath $filesRoot -File -Recurse) {
        $relative = $file.FullName.Substring($filesRoot.Length).TrimStart('\').Replace('\', '/')
        if ($relative -eq 'tgdesk-updater.exe') {
            continue
        }
        [ordered]@{
            path = $relative
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
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

    Set-TextFile (Join-Path $versionRoot 'manifest.json') (($manifest | ConvertTo-Json -Depth 8) + "`n")
    return @{
        Root = $versionRoot
        Manifest = Join-Path $versionRoot 'manifest.json'
        Files = $entries.Count
    }
}

$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterRoot = Join-Path $root 'client-rustdesk-src\flutter'
$agentRoot = Join-Path $root 'client-agent'
$serverRoot = Join-Path $root 'server\api-core'
$serverDeployRoot = Join-Path $root 'server'
$serverEnvPath = Join-Path $root 'server\.env'
$serverComposePath = Join-Path $root 'server\docker-compose.yml'
$stageRoot = Join-Path $PSScriptRoot 'stage-unified'
$releaseRoot = Join-Path $root 'server\releases\modules'
$installerScript = Join-Path $PSScriptRoot 'tgdesk-installer.iss'
$buildRoot = Join-Path $flutterRoot 'build\windows\x64\runner\Release'
$outputInstaller = Join-Path $PSScriptRoot "output\tgdesk-installer-$Version.exe"
$publishedInstaller = Join-Path $root 'server\releases\tgdesk-update.exe'
$publishedUpdater = Join-Path $root 'server\releases\tgdesk-updater.exe'
$metadataPath = Join-Path $PSScriptRoot "output\tgdesk-installer-$Version.metadata.json"

Write-Step 'Validando ferramentas'
Assert-Command git
Assert-Command go
Assert-Command flutter
$innoCompiler = Resolve-InnoCompiler

Write-Step "Aplicando versao $Version"
$buildNumber = (($Version -split '\.') -join '')
Set-TextFile (Join-Path $flutterRoot 'version.txt') $Version
Update-TextFile (Join-Path $flutterRoot 'pubspec.yaml') {
    param($text)
    $text -replace '(?m)^version:\s*\d+\.\d+\.\d+(\+\d+)?\s*$', "version: $Version+$buildNumber"
}
Set-TextFile (Join-Path $stageRoot 'version.txt') $Version
Update-TextFile $installerScript {
    param($text)
    $text = $text -replace '#define MyAppVersion "\d+\.\d+\.\d+"', "#define MyAppVersion `"$Version`""
    $text -replace 'OutputBaseFilename=tgdesk-installer-\d+\.\d+\.\d+', "OutputBaseFilename=tgdesk-installer-$Version"
}

Write-Step 'Executando gates de codigo'
Push-Location $agentRoot
try {
    Invoke-Checked { go test ./... } 'Falha nos testes do agente.'
} finally {
    Pop-Location
}
Push-Location $serverRoot
try {
    Invoke-Checked { go test ./internal/handlers } 'Falha nos testes do servidor.'
} finally {
    Pop-Location
}
Push-Location $flutterRoot
try {
    Invoke-Checked { flutter analyze --no-fatal-infos --no-fatal-warnings `
        lib/models/input_model.dart `
        lib/tgdesk/admin_page.dart `
        lib/tgdesk/api_client.dart `
        lib/tgdesk/branding_page.dart `
        lib/tgdesk/branding_window_icon.dart `
        lib/tgdesk/client_home_page.dart `
        lib/tgdesk/hub_home_page.dart `
        lib/tgdesk/support_page.dart } 'Falha no flutter analyze.'
} finally {
    Pop-Location
}

Write-Step 'Compilando DLL do agente embutido'
# O agente e carregado por tgdesk.exe como tgdesk_agent.dll. Rodar apenas
# `go test` valida o codigo, mas nao atualiza o binario que o CMake empacota;
# isso publicou versoes novas com o agente velho, que nao entendia update_now
# nem anunciava client_version. Compile antes do Flutter para que o install()
# em windows/CMakeLists.txt sempre leve a DLL desta arvore de fontes.
$agentDll = Join-Path $agentRoot 'tgdesk_agent.dll'
$agentHeader = Join-Path $agentRoot 'tgdesk_agent.h'
Push-Location $agentRoot
try {
    Invoke-Checked {
        go build -buildmode=c-shared -o $agentDll ./cmd/agent
    } 'Falha ao compilar tgdesk_agent.dll.'
} finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $agentDll) -or
    -not (Test-Path -LiteralPath $agentHeader)) {
    throw 'Compilacao nao gerou tgdesk_agent.dll e tgdesk_agent.h.'
}

Write-Step 'Compilando binario universal TGDesk'
Push-Location $flutterRoot
try {
    Invoke-Checked { flutter build windows --release } 'Falha no build Windows.'
} finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath (Join-Path $buildRoot 'tgdesk.exe'))) {
    throw 'Build Windows nao gerou tgdesk.exe.'
}

Write-Step 'Sincronizando stage-unified'
if (-not ([System.IO.Path]::GetFullPath($stageRoot).StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase))) {
    throw "Stage fora do workspace: $stageRoot"
}
robocopy $buildRoot $stageRoot /MIR /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -gt 7) {
    throw "Robocopy falhou com codigo $LASTEXITCODE."
}
Set-TextFile (Join-Path $stageRoot 'version.txt') $Version

$recoveryScript = Join-Path $PSScriptRoot 'tgdesk-recovery.ps1'
if (-not (Test-Path -LiteralPath $recoveryScript)) {
    throw 'Recuperador PowerShell do TGDesk nao encontrado.'
}
Copy-Item -LiteralPath $recoveryScript -Destination (Join-Path $stageRoot 'tgdesk-recovery.ps1') -Force

Write-Step 'Compilando updater standalone atual'
$stagedUpdater = Join-Path $stageRoot 'tgdesk-updater.exe'
Push-Location $agentRoot
try {
    Invoke-Checked {
        go build -ldflags '-H=windowsgui' -o $stagedUpdater ./cmd/updater
    } 'Falha ao compilar o updater standalone.'
} finally {
    Pop-Location
}
if (-not (Test-Path -LiteralPath $stagedUpdater)) {
    throw 'Compilacao nao gerou tgdesk-updater.exe.'
}

Write-Step 'Gerando release modular'
$module = New-ModuleRelease -Version $Version -StageRoot $stageRoot -ReleaseRoot $releaseRoot

Write-Step 'Compilando instalador'
$serverHost = Resolve-ServerHost $root
Write-Host "Host publico do servidor: $serverHost"
Invoke-Checked { & $innoCompiler "/DTGDeskServerHost=$serverHost" $installerScript } "Falha ao compilar instalador $Version."
if (-not (Test-Path -LiteralPath $outputInstaller)) {
    throw "Instalador nao encontrado: $outputInstaller"
}

Write-Step 'Publicando artefatos locais'
Copy-Item -LiteralPath $outputInstaller -Destination $publishedInstaller -Force
Copy-Item -LiteralPath $stagedUpdater -Destination $publishedUpdater -Force
$installerHash = (Get-FileHash -LiteralPath $outputInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
$publishedHash = (Get-FileHash -LiteralPath $publishedInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
if ($installerHash -ne $publishedHash) {
    throw 'Instalador publicado difere do instalador compilado.'
}
$updaterHash = (Get-FileHash -LiteralPath $stagedUpdater -Algorithm SHA256).Hash.ToLowerInvariant()
$publishedUpdaterHash = (Get-FileHash -LiteralPath $publishedUpdater -Algorithm SHA256).Hash.ToLowerInvariant()
if ($updaterHash -ne $publishedUpdaterHash) {
    throw 'Updater standalone publicado difere do updater compilado.'
}

$metadata = [ordered]@{
    schema_version = 1
    version = $Version
    build_number = [int]$buildNumber
    generated_at = [DateTimeOffset]::UtcNow.ToString('o')
    installer = [ordered]@{
        path = "installers/output/tgdesk-installer-$Version.exe"
        sha256 = $installerHash
        size = (Get-Item -LiteralPath $outputInstaller).Length
    }
    published_update = [ordered]@{
        path = 'server/releases/tgdesk-update.exe'
        sha256 = $publishedHash
        size = (Get-Item -LiteralPath $publishedInstaller).Length
    }
    standalone_updater = [ordered]@{
        path = 'server/releases/tgdesk-updater.exe'
        sha256 = $publishedUpdaterHash
        size = (Get-Item -LiteralPath $publishedUpdater).Length
    }
    module = [ordered]@{
        path = "server/releases/modules/$Version/manifest.json"
        files = $module.Files
        sha256 = (Get-FileHash -LiteralPath $module.Manifest -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    modified_files = @((git -C $root status --short) | ForEach-Object { $_.Trim() })
}
Set-TextFile $metadataPath (($metadata | ConvertTo-Json -Depth 8) + "`n")

Write-Step 'Liberando versao no servidor'
Update-TextFile $serverEnvPath {
    param($text)
    $text -replace '(?m)^CLIENT_VERSION=.*$', "CLIENT_VERSION=$Version"
}
Update-TextFile $serverComposePath {
    param($text)
    $text -replace '(?m)^(\s*CLIENT_VERSION:\s*)".*"', "`${1}`"$Version`""
}
Push-Location $serverDeployRoot
try {
    Invoke-Checked { & .\deploy.ps1 } 'Falha ao publicar servidor.'
} finally {
    Pop-Location
}

Write-Step 'Validando anuncio de update'
$manifestUrl = 'http://127.0.0.1:8090/api/v1/client/modules?version=0.0.0'
$manifestResponse = Invoke-RestMethod -Uri $manifestUrl -TimeoutSec 20
if ([string]$manifestResponse.version -ne $Version) {
    throw "Servidor anunciou versao $($manifestResponse.version), esperado $Version."
}

Write-Step 'Commitando release'
$status = git -C $root status --porcelain
if (-not $status) {
    throw 'Nao ha alteracoes para commitar apos a release.'
}
git -C $root add -A
$changedFiles = git -C $root diff --cached --name-only
$description = ($changedFiles | ForEach-Object { "- $_" }) -join "`n"
$commitMessage = "release: TGDesk $Version"
$commitBody = "Versao: $Version`nBuild: $buildNumber`n`nArquivos modificados:`n$description"
Invoke-Checked { git -C $root commit -m $commitMessage -m $commitBody } 'Falha ao criar commit.'

Write-Step 'Enviando para o remote'
$branch = (git -C $root branch --show-current).Trim()
if (-not $branch) {
    throw 'Branch atual nao identificado; push abortado.'
}
Invoke-Checked { git -C $root push origin $branch } 'Falha ao enviar push.'

Write-Step 'Release concluida'
Write-Host "Versao: $Version"
Write-Host "Build: $buildNumber"
Write-Host "Instalador: $outputInstaller"
Write-Host "SHA256: $installerHash"
Write-Host "Modulo: $($module.Manifest)"
