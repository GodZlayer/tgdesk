[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'acceptance.manifest.json'),
    [string]$ArtifactsPath = (Join-Path $PSScriptRoot 'artifacts'),
    [string]$EvidenceSinceUtc = '',
    [switch]$NoFail
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$criteria = @(
    foreach ($scenario in $manifest.scenarios) {
        foreach ($assertion in $scenario.assertions) {
            [pscustomobject]@{
                scenario = $scenario.id
                surface = $scenario.surface
                id = $assertion.id
                criterion = $assertion.criterion
            }
        }
    }
)

$observations = @{}
$invalidEvidence = @()
$evidenceSince = if ($EvidenceSinceUtc) {
    [DateTime]::Parse(
        $EvidenceSinceUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal
    ).ToUniversalTime()
} else { [DateTime]::MinValue }
if (Test-Path -LiteralPath $ArtifactsPath) {
    foreach ($file in Get-ChildItem -LiteralPath $ArtifactsPath -Recurse -File -Filter '*.json') {
        try {
            $document = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $measuredAt = if ($document.measured_at) {
                [DateTime]::Parse([string]$document.measured_at).ToUniversalTime()
            } else { [DateTime]::MinValue }
            if ($measuredAt -lt $evidenceSince) { continue }
            foreach ($assertion in @($document.assertions)) {
                if (-not $assertion.id -or -not $assertion.state) { continue }
                $current = $observations[[string]$assertion.id]
                if ($current -and $current.observed_at -gt $measuredAt) { continue }
                $observations[[string]$assertion.id] = [pscustomobject]@{
                    state = [string]$assertion.state
                    evidence = $file.FullName
                    measured_at = $document.measured_at
                    observed_at = $measuredAt
                    details = $assertion.details
                }
            }
        } catch {
            $invalidEvidence += [pscustomobject]@{
                path = $file.FullName
                error = $_.Exception.Message
            }
        }
    }
}

$results = @(
    foreach ($criterion in $criteria) {
        $observation = $observations[$criterion.id]
        [pscustomobject]@{
            scenario = $criterion.scenario
            surface = $criterion.surface
            id = $criterion.id
            criterion = $criterion.criterion
            state = if ($observation) { $observation.state } else { 'gap' }
            evidence = if ($observation) { $observation.evidence } else { $null }
            measured_at = if ($observation) { $observation.measured_at } else { $null }
        }
    }
)

$duplicateIDs = @(
    $criteria | Group-Object id | Where-Object Count -gt 1 | Select-Object -ExpandProperty Name
)
$unknownEvidenceIDs = @(
    $observations.Keys | Where-Object { $_ -notin $criteria.id }
)
$passed = @($results | Where-Object state -eq 'passed').Count
$failed = @($results | Where-Object state -eq 'failed').Count
$gaps = @($results | Where-Object state -eq 'gap').Count
$total = $results.Count
$coverage = if ($total) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }
$state = if ($duplicateIDs.Count -or $invalidEvidence.Count -or
    $unknownEvidenceIDs.Count -or $failed -or $gaps) { 'incomplete' } else { 'passed' }

$report = [ordered]@{
    schema_version = 1
    phase = 'acceptance-coverage'
    state = $state
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    summary = [ordered]@{
        scenarios = @($manifest.scenarios).Count
        criteria = $total
        passed = $passed
        failed = $failed
        gaps = $gaps
        coverage_percent = $coverage
    }
    duplicate_ids = $duplicateIDs
    unknown_evidence_ids = $unknownEvidenceIDs
    invalid_evidence = $invalidEvidence
    results = $results
}

$jsonPath = Join-Path $ArtifactsPath 'acceptance-coverage.json'
$markdownPath = Join-Path $ArtifactsPath 'acceptance-coverage.md'
New-Item -ItemType Directory -Path $ArtifactsPath -Force | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8

$lines = @(
    '# TGDesk - Cobertura de aceitação'
    ''
    "- Estado: **$state**"
    "- Cenários: $(@($manifest.scenarios).Count)"
    "- Critérios: $total"
    "- Aprovados: $passed"
    "- Falhos: $failed"
    "- Gaps sem evidência: $gaps"
    "- Cobertura: $coverage%"
    ''
    '| Estado | ID | Cenário | Critério |'
    '|---|---|---|---|'
)
foreach ($item in $results) {
    $lines += "| $($item.state) | ``$($item.id)`` | $($item.scenario) | $($item.criterion.Replace('|','/')) |"
}
$lines | Set-Content -LiteralPath $markdownPath -Encoding utf8

$report.summary | ConvertTo-Json
if ($state -ne 'passed' -and -not $NoFail) {
    exit 1
}
