[CmdletBinding()]
param(
    [ValidateSet('Fast', 'Full')]
    [string]$Scope = 'Fast'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runID = "build-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
$artifactRoot = Join-Path $repo "testlab\artifacts\godzmind\$runID"
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$steps = @()

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    $started = Get-Date
    $logPath = Join-Path $artifactRoot "$Name.log"
    $exitCode = 0
    $errorMessage = $null
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $output = & $Action 2>&1
        $ErrorActionPreference = $previousPreference
        $output | Set-Content -LiteralPath $logPath -Encoding utf8
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            $errorMessage = "Processo retornou Exit Code $exitCode"
        }
    } catch {
        $ErrorActionPreference = 'Stop'
        $exitCode = 1
        $errorMessage = $_.Exception.Message
        $_ | Out-String | Set-Content -LiteralPath $logPath -Encoding utf8
    }
    $script:steps += [ordered]@{
        name = $Name
        state = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        exit_code = $exitCode
        duration_ms = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
        log = $logPath
        error = $errorMessage
    }
}

Invoke-Step 'powershell-syntax' {
    $files = @(
        Get-ChildItem (Join-Path $repo '.godzmind\scripts') -File -Filter '*.ps1'
        Get-ChildItem (Join-Path $repo 'testlab') -File -Filter '*.ps1'
    )
    foreach ($file in $files) {
        [void][scriptblock]::Create((Get-Content $file.FullName -Raw))
    }
    "Parsed $($files.Count) PowerShell workers"
}

Invoke-Step 'json-contracts' {
    foreach ($path in @(
        'testlab\acceptance.manifest.json',
        'testlab\version-contracts.json',
        'testlab\lab.config.json'
    )) {
        Get-Content (Join-Path $repo $path) -Raw | ConvertFrom-Json | Out-Null
    }
    'JSON contracts parsed'
}

foreach ($module in @('server/api-core', 'client-agent', 'client-host',
        'client-tunnel', 'client-updater')) {
    $stepName = 'go-' + ($module -replace '[/\\]', '-')
    Invoke-Step $stepName {
        $dockerArgs = @('run', '--rm', '-v', "${repo}:/repo",
            '-w', "/repo/$module")
        if ($module -in @('client-agent', 'client-host', 'client-updater')) {
            $dockerArgs += @('-e', 'GOOS=windows', '-e', 'GOARCH=amd64',
                '-e', 'CGO_ENABLED=0')
        }
        $dockerArgs += @('golang:1.22-alpine', 'go', 'test')
        if ($module -in @('client-agent', 'client-host', 'client-updater')) {
            $dockerArgs += @('-exec', '/bin/true')
        }
        $dockerArgs += @('./...', '-count=1')
        & docker @dockerArgs
    }
}

Invoke-Step 'go-client-agent-versioning-tests' {
    & docker run --rm -v "${repo}:/repo" -w '/repo/client-agent' `
        golang:1.22-alpine go test ./internal/versioning -count=1
}

Invoke-Step 'flutter-analyze' {
    Push-Location (Join-Path $repo 'client-rustdesk-src\flutter')
    try {
        & C:\flutter\bin\flutter.bat pub get
        if ($LASTEXITCODE -eq 0) {
            & C:\flutter\bin\flutter.bat analyze --no-fatal-infos --no-fatal-warnings
        }
    } finally {
        Pop-Location
    }
}

if ($Scope -eq 'Full') {
    Invoke-Step 'rust-contracts' {
        Push-Location (Join-Path $repo 'client-rustdesk-src')
        try {
            # Valida lockfile e resolução sem exigir um VCPKG global. A
            # compilação nativa real ocorre logo abaixo pelo build Windows do
            # Flutter, que usa os artefatos e toolchain oficiais do produto.
            & cargo metadata --locked --no-deps --format-version 1
        } finally { Pop-Location }
    }
    Invoke-Step 'flutter-windows-release' {
        Push-Location (Join-Path $repo 'client-rustdesk-src\flutter')
        try { & C:\flutter\bin\flutter.bat build windows --release } finally { Pop-Location }
    }
    Invoke-Step 'installer-stage-sync' {
        $releaseDir = Join-Path $repo 'client-rustdesk-src\flutter\build\windows\x64\runner\Release'
        $stageDir = Join-Path $repo 'installers\stage-unified'
        if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'tgdesk.exe'))) {
            throw "Build Flutter sem tgdesk.exe: $releaseDir"
        }
        Copy-Item -Path (Join-Path $releaseDir '*') -Destination $stageDir -Recurse -Force
        $version = [regex]::Match(
            (Get-Content -LiteralPath (Join-Path $repo 'installers\tgdesk-installer.iss') -Raw),
            '#define MyAppVersion "([^"]+)"'
        ).Groups[1].Value
        if (-not $version) { throw 'Versão do instalador não encontrada' }
        Set-Content -LiteralPath (Join-Path $stageDir 'version.txt') -Value $version `
            -Encoding ascii -NoNewline
    }
    Invoke-Step 'installer-compile' {
        $iscc = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
            'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
            'C:\Program Files\Inno Setup 6\ISCC.exe'
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $iscc) { throw 'ISCC.exe não encontrado' }
        & $iscc (Join-Path $repo 'installers\tgdesk-installer.iss')
    }
    Invoke-Step 'installer-artifact-metadata' {
        $iss = Get-Content -LiteralPath (Join-Path $repo 'installers\tgdesk-installer.iss') -Raw
        $version = [regex]::Match($iss, '#define MyAppVersion "([^"]+)"').Groups[1].Value
        $installer = Join-Path $repo "installers\output\tgdesk-installer-$version.exe"
        if (-not (Test-Path -LiteralPath $installer)) { throw "Instalador ausente: $installer" }
        $stage = Join-Path $repo 'installers\stage-unified'
        $metadata = [ordered]@{
            schema_version = 1
            version = $version
            installer = [ordered]@{
                path = $installer
                size = (Get-Item -LiteralPath $installer).Length
                sha256 = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            stage_files = @(
                Get-ChildItem -LiteralPath $stage -File -Recurse | ForEach-Object {
                    [ordered]@{
                        path = $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
                        size = $_.Length
                        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    }
                } | Sort-Object path
            )
            generated_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $metadata | ConvertTo-Json -Depth 6 |
            Set-Content -LiteralPath (Join-Path $repo "installers\output\tgdesk-installer-$version.metadata.json") `
                -Encoding utf8
    }
}

$failed = @($steps | Where-Object state -eq 'failed')
$report = [ordered]@{
    schema_version = 1
    phase = 'godzmind-build'
    run_id = $runID
    scope = $Scope
    state = if ($failed.Count) { 'failed' } else { 'passed' }
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    steps = $steps
}
$reportPath = Join-Path $artifactRoot 'build.json'
$report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding utf8
$report | ConvertTo-Json -Depth 6
if ($failed.Count) { exit 1 }
