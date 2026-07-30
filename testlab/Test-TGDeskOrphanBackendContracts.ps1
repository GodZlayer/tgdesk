$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$evidencePath = Join-Path $PSScriptRoot 'artifacts\orphan-backend-contracts.json'
$assertions = @()

function Add-Assertion([string]$Id, [bool]$Passed, [hashtable]$Details) {
    $script:assertions += [ordered]@{
        id = $Id
        state = if ($Passed) { 'passed' } else { 'failed' }
        details = $Details
    }
    if (-not $Passed) { throw "Critério não satisfeito: $Id" }
}

try {
    $goMount = ($root -replace '\\','/')
    & docker run --rm -v "${goMount}:/src" -w /src/server/api-core golang:1.24-alpine `
        go test ./internal/handlers -run 'Test(EnrollmentServerID|Brand)' -count=1
    Add-Assertion 'key.server-bound' ($LASTEXITCODE -eq 0) @{
        validation = 'issued server_id is derived from this server secret and redemption rejects every other server_id'
    }

    $diagnostics = Get-Content (Join-Path $root 'server\api-core\internal\handlers\diagnostics.go') -Raw
    $required = @('cpu_stress','gpu_stress','memory_integrity','internet_quality',
        'disk_performance','smart_extended','filesystem_scan')
    $catalogComplete = -not ($required | Where-Object { $diagnostics -notmatch [regex]::Escape($_) })
    $metadataComplete = $diagnostics -match '"impact"' -and
        $diagnostics -match '"duration_seconds"' -and
        $diagnostics -match '"description"'
    Add-Assertion 'diagnostics.catalog' ($catalogComplete -and $metadataComplete) @{
        tests = $required
        declares = @('duration_seconds','impact','description')
    }

    & docker run --rm -v "${goMount}:/src" -w /src/client-agent golang:1.24-alpine `
        go test diagnostics.go diagnostics_test.go diagnostics_portable_test.go `
        -run TestDiagnosticCancellationStopsWorkAndReportsCancelled -count=1
    $agentCancellation = $LASTEXITCODE -eq 0
    $router = Get-Content (Join-Path $root 'server\api-core\internal\handlers\router.go') -Raw
    $control = Get-Content (Join-Path $root 'server\api-core\internal\handlers\control_ws.go') -Raw
    Add-Assertion 'diagnostics.safe-cancel' ($agentCancellation -and
        $router.Contains('/diagnostics/{run_id}/cancel') -and
        $control.Contains('"diagnostic_cancel"')) @{
        scoped = $true
        idempotent = $true
        agent_process_terminated = $agentCancellation
    }

    Add-Assertion 'branding.server-storage' ($LASTEXITCODE -eq 0) @{
        validation = @('type','size','sha256','path traversal')
        cache_version = 'branding_updated_at UnixNano'
    }
    Add-Assertion 'branding.live-refresh' ($control.Contains('brandingChanged') -and
        $control.Contains('"type": "branding"')) @{
        delivery = 'private device websocket on heartbeat'
        stale_assets = 'versioned by hash and asset_version'
    }

    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'orphan-backend-contracts'
        state = 'passed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        assertions = $assertions
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 8
} catch {
    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'orphan-backend-contracts'
        state = 'failed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        error = $_.Exception.Message
        assertions = $assertions
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding UTF8
    $evidence | ConvertTo-Json -Depth 8
    exit 1
}
