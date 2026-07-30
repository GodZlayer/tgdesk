[CmdletBinding()]
param(
    [ValidateSet('0.3.48', '0.4.0', '1.0.0', '1.1.0')]
    [string]$Version = '1.1.0',
    [string]$EvidenceSinceUtc = '',
    [switch]$NoFail
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$manifestPath = Join-Path $repo 'testlab\acceptance.manifest.json'
$contractsPath = Join-Path $repo 'testlab\version-contracts.json'
$coveragePath = Join-Path $repo 'testlab\artifacts\acceptance-coverage.json'
$artifactPath = Join-Path $repo "testlab\artifacts\version-gate-$Version.json"
$triagePath = Join-Path $repo "gaps-triagem-$Version.md"

# Critical gap IDs for 0.4.0
$criticalGapIds = @(
    'runtime.close-to-tray',
    'runtime.autostart-toggle',
    'ws.disconnect.truth',
    'update.push.button',
    'update.one-action.one-version'
)

$coverageArgs = @{NoFail = $true}
if ($EvidenceSinceUtc) { $coverageArgs.EvidenceSinceUtc = $EvidenceSinceUtc }
& (Join-Path $repo 'testlab\Get-TGDeskAcceptanceCoverage.ps1') @coverageArgs | Out-Null
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$contracts = Get-Content $contractsPath -Raw | ConvertFrom-Json
$coverage = Get-Content $coveragePath -Raw | ConvertFrom-Json

$targetIndex = -1
for ($i = 0; $i -lt $contracts.versions.Count; $i++) {
    if ($contracts.versions[$i].version -eq $Version) { $targetIndex = $i }
}
if ($targetIndex -lt 0) { throw "Contrato não encontrado: $Version" }

$requiredScenarios = @(
    for ($i = 0; $i -le $targetIndex; $i++) {
        @($contracts.versions[$i].includes)
    }
) | Select-Object -Unique
$knownScenarios = @($manifest.scenarios.id)
$unassigned = @($knownScenarios | Where-Object { $_ -notin @($contracts.versions.includes) })
$unknown = @($requiredScenarios | Where-Object { $_ -notin $knownScenarios })
if ($unassigned.Count -or $unknown.Count) {
    throw "Contrato inválido. Não atribuídos: $($unassigned -join ', '). Desconhecidos: $($unknown -join ', ')"
}

$required = @($coverage.results | Where-Object scenario -in $requiredScenarios)
$passed = @($required | Where-Object state -eq 'passed').Count
$failed = @($required | Where-Object state -eq 'failed').Count
$blocked = @($required | Where-Object state -eq 'blocked').Count

# Separate critical gaps from deferred gaps
$allGaps = @($required | Where-Object state -eq 'gap')
$criticalGaps = @($allGaps | Where-Object { $_.criterion -in $criticalGapIds }).Count
$deferredGaps = @($allGaps | Where-Object { $_.criterion -notin $criticalGapIds }).Count
$gaps = $allGaps.Count

# Gate state: blocked if failed, blocked, or critical gaps remain
$state = if ($failed -eq 0 -and $blocked -eq 0 -and $criticalGaps -eq 0) { 'passed' } else { 'blocked' }
$report = [ordered]@{
    schema_version = 1
    phase = 'version-gate'
    version = $Version
    state = $state
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    evidence_since_utc = $EvidenceSinceUtc
    required_scenarios = $requiredScenarios
    summary = [ordered]@{
        criteria = $required.Count
        passed = $passed
        failed = $failed
        blocked = $blocked
        gaps = $gaps
        gaps_critical = $criticalGaps
        gaps_deferred = $deferredGaps
        coverage_percent = if ($required.Count) {
            [math]::Round(($passed / $required.Count) * 100, 2)
        } else { 0 }
    }
    blocking_results = @(
        $required | Where-Object { $_.state -eq 'failed' -or $_.state -eq 'blocked' -or ($_.state -eq 'gap' -and $_.criterion -in $criticalGapIds) }
    )
}
$report | ConvertTo-Json -Depth 10 | Set-Content $artifactPath -Encoding utf8
$report.summary | ConvertTo-Json
if ($state -ne 'passed' -and -not $NoFail) { exit 1 }
