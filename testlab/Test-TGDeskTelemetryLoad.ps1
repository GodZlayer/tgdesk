param(
    [ValidateRange(2, 200)][int]$DeviceCount = 24,
    [ValidateRange(1, 10)][int]$RatePerDeviceHz = 1,
    [ValidateRange(5, 600)][int]$DurationSeconds = 12,
    [ValidateRange(90, 100)][double]$MinimumSuccessRatePct = 99,
    [ValidateRange(50, 10000)][double]$MaximumP95LatencyMs = 1500,
    [ValidateRange(64, 4096)][double]$MaximumMemoryMiB = 512,
    [ValidateRange(1, 800)][double]$MaximumCpuPct = 200
)
$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$apiContainer = (& docker compose -f $compose ps -q api-core).Trim()
if (-not $apiContainer) {
    throw 'O api-core isolado não está em execução.'
}
& (Join-Path $PSScriptRoot 'New-TGDeskLabAdminKey.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao preparar a autoridade Admin isolada.'
}

$artifactDirectory = Join-Path $PSScriptRoot 'artifacts'
$stdout = Join-Path $artifactDirectory 'telemetry-load.stdout.log'
$stderr = Join-Path $artifactDirectory 'telemetry-load.stderr.log'
$mount = "$($PSScriptRoot):/tests"
$arguments = @(
    'run', '--rm',
    '--network', "container:$apiContainer",
    '-e', "TGDESK_LOAD_DEVICES=$DeviceCount",
    '-e', "TGDESK_LOAD_RATE=$RatePerDeviceHz",
    '-e', "TGDESK_LOAD_DURATION=$DurationSeconds",
    '-v', $mount,
    'node:22-alpine',
    'node', '/tests/scripts/integration-telemetry-load.mjs'
)
$loadStartedAtUtc = (Get-Date).ToUniversalTime()
$process = Start-Process -FilePath 'docker.exe' -ArgumentList $arguments -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
$samples = @()
while (-not $process.HasExited) {
    $raw = & docker stats --no-stream --format '{{json .}}' $apiContainer 2>$null
    if ($LASTEXITCODE -eq 0 -and $raw) {
        $stat = $raw | ConvertFrom-Json
        $cpu = [double](($stat.CPUPerc -replace '%','').Trim())
        $memoryText = (($stat.MemUsage -split '/')[0]).Trim()
        $memoryMiB = if ($memoryText -match '^([\d.]+)GiB$') {
            [double]$Matches[1] * 1024
        } elseif ($memoryText -match '^([\d.]+)MiB$') {
            [double]$Matches[1]
        } elseif ($memoryText -match '^([\d.]+)KiB$') {
            [double]$Matches[1] / 1024
        } else { 0 }
        $samples += [pscustomobject]@{ cpu_pct = $cpu; memory_mib = $memoryMiB }
    }
    Start-Sleep -Milliseconds 500
    $process.Refresh()
}
$rawEvidencePath = Join-Path $artifactDirectory 'telemetry-load-raw.json'
if (-not (Test-Path $rawEvidencePath)) {
    throw 'Carga de telemetria não gerou evidência.'
}
$rawEvidence = Get-Content -Raw $rawEvidencePath | ConvertFrom-Json
$evidenceMeasuredAtUtc = [datetimeoffset]::Parse($rawEvidence.measured_at).UtcDateTime
if ($rawEvidence.state -ne 'passed' -or
    $evidenceMeasuredAtUtc -lt $loadStartedAtUtc.AddSeconds(-2)) {
    throw 'Carga de telemetria terminou sem evidência válida e atual.'
}
$maxCpu = [double](($samples | Measure-Object cpu_pct -Maximum).Maximum)
$maxMemory = [double](($samples | Measure-Object memory_mib -Maximum).Maximum)
$success = [double]$rawEvidence.metrics.success_rate_pct
$p95 = [double]$rawEvidence.metrics.latency_ms.p95
$passed = $rawEvidence.state -eq 'passed' -and
    $success -ge $MinimumSuccessRatePct -and
    $p95 -le $MaximumP95LatencyMs -and
    $maxMemory -le $MaximumMemoryMiB -and
    $maxCpu -le $MaximumCpuPct

$evidence = [ordered]@{
    schema_version = 1
    scenario = 'telemetry-load'
    state = if ($passed) { 'passed' } else { 'failed' }
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    assertions = @([ordered]@{
        id = 'stability.telemetry-load'
        state = if ($passed) { 'passed' } else { 'failed' }
        details = [ordered]@{
            device_count = $rawEvidence.metrics.device_count
            rate_per_device_hz = $rawEvidence.metrics.rate_per_device_hz
            duration_seconds = $rawEvidence.metrics.duration_seconds
            expected_messages = $rawEvidence.metrics.expected_messages
            succeeded = $rawEvidence.metrics.succeeded
            failed = $rawEvidence.metrics.failed
            success_rate_pct = [math]::Round($success, 3)
            latency_average_ms = [math]::Round([double]$rawEvidence.metrics.latency_ms.average, 3)
            latency_p95_ms = [math]::Round($p95, 3)
            latency_maximum_ms = [math]::Round([double]$rawEvidence.metrics.latency_ms.maximum, 3)
            api_cpu_peak_pct = [math]::Round($maxCpu, 3)
            api_memory_peak_mib = [math]::Round($maxMemory, 3)
            resource_samples = $samples.Count
            thresholds = [ordered]@{
                minimum_success_rate_pct = $MinimumSuccessRatePct
                maximum_p95_latency_ms = $MaximumP95LatencyMs
                maximum_api_memory_mib = $MaximumMemoryMiB
                maximum_api_cpu_pct = $MaximumCpuPct
            }
        }
    })
}
$output = Join-Path $artifactDirectory 'telemetry-load.json'
$evidence | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $output
$evidence | ConvertTo-Json -Depth 10
if (-not $passed) { exit 1 }
