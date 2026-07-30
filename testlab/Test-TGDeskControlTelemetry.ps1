[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$apiContainer = (& docker compose -f $compose ps -q api-core).Trim()
if (-not $apiContainer) {
    throw 'O api-core isolado nao esta em execucao.'
}

& (Join-Path $PSScriptRoot 'New-TGDeskLabSupervisorKey.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao criar chave descartavel para controle e telemetria.'
}

$mount = "$($PSScriptRoot):/tests"
& docker run --rm --network "container:$apiContainer" `
    -v $mount node:22-alpine `
    node /tests/scripts/integration-control-telemetry.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$repo = Split-Path -Parent $PSScriptRoot
$goMount = "$($repo):/src"
& docker run --rm -v $goMount -w /src/server/api-core golang:1.24-alpine `
    go test ./internal/handlers -run 'Test(SustainedUsageLevels|HealthUsesAverageInsteadOfCurrentSample|StorageAndUnknownTemperatureHealth)$'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$evidencePath = Join-Path $PSScriptRoot 'artifacts\control-telemetry.json'
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
$evidence.assertions += @(
    [pscustomobject]@{
        id = 'telemetry.alert.server-average'
        state = 'passed'
        details = @{test = 'TestHealthUsesAverageInsteadOfCurrentSample'}
    },
    [pscustomobject]@{
        id = 'telemetry.thresholds.cpu'
        state = 'passed'
        details = @{test = 'TestSustainedUsageLevels'; thresholds = @(75, 85, 95)}
    },
    [pscustomobject]@{
        id = 'telemetry.temperature'
        state = 'passed'
        details = @{test = 'TestStorageAndUnknownTemperatureHealth'; missing_sensor = 'normal'}
    }
)
$evidence.measured_at = (Get-Date).ToUniversalTime().ToString('o')
$evidence | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $evidencePath -Encoding utf8
$evidence | ConvertTo-Json -Depth 12
