[CmdletBinding()]
param(
    [ValidateSet('Up', 'Validate', 'Reset')]
    [string]$Action = 'Validate'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
$evidencePath = Join-Path $artifactRoot 'isolated-backend.json'
$productionVolumeNames = @(
    'server_tgdesk_pg_data',
    'server_tgdesk_hub_data',
    'server_tgdesk_hbbs_data',
    'server_tgdesk_hbbr_data',
    'server_tgdesk_branding_data'
)

New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    & docker compose -f $compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose falhou: $($Arguments -join ' ')"
    }
}

function Get-ContainerState {
    $raw = & docker compose -f $compose ps --format json
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível ler o estado do stack isolado.'
    }
    if (-not $raw) { return @() }
    return @($raw | ForEach-Object { $_ | ConvertFrom-Json })
}

function Wait-BackendState {
    while ($true) {
        $containers = @(Get-ContainerState)
        $api = $containers | Where-Object Service -eq 'api-core'
        $postgres = $containers | Where-Object Service -eq 'postgres'
        $redis = $containers | Where-Object Service -eq 'redis'

        $failed = $containers | Where-Object {
            $_.State -in @('exited', 'dead', 'removing') -or
            ($_.Health -and $_.Health -eq 'unhealthy')
        }
        if ($failed) {
            throw "Container falhou: $($failed.Service -join ', ')"
        }

        if ($api.State -eq 'running' -and
            $postgres.Health -eq 'healthy' -and
            $redis.Health -eq 'healthy') {
            try {
                $health = Invoke-RestMethod -Uri 'http://127.0.0.1:18090/healthz' -TimeoutSec 2
                if ($health.status -eq 'ok') {
                    return $containers
                }
            } catch {
                # O container ainda não publicou um estado HTTP verificável.
            }
        }
        Start-Sleep -Milliseconds 500
    }
}

try {
    if ($Action -eq 'Reset') {
        Invoke-Compose down --volumes --remove-orphans
    }

    if ($Action -in @('Up', 'Reset')) {
        Invoke-Compose up -d --build
    }

    $containers = @(Wait-BackendState)
    $volumes = @(& docker volume ls --format '{{.Name}}')
    $testVolumes = @($volumes | Where-Object { $_ -like 'tgdesk-testlab_*' })
    $productionVolumesPresent = @($productionVolumeNames | Where-Object { $_ -in $volumes })

    if ($testVolumes.Count -lt 5) {
        throw "Isolamento inválido: apenas $($testVolumes.Count) volumes de teste encontrados."
    }
    if ($productionVolumesPresent.Count -ne $productionVolumeNames.Count) {
        throw 'A validação detectou alteração ou ausência inesperada nos volumes de produção.'
    }

    $evidence = [ordered]@{
        schema_version = 1
        phase = 'isolated-backend'
        state = 'passed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        endpoint = 'http://127.0.0.1:18090'
        containers = @($containers | Select-Object Service, Name, State, Health)
        test_volumes = $testVolumes
        production_volumes_preserved = $productionVolumesPresent
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 8
} catch {
    $evidence = [ordered]@{
        schema_version = 1
        phase = 'isolated-backend'
        state = 'failed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        error = $_.Exception.Message
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -Path $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 8
    exit 1
}
