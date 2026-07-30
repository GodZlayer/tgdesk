[CmdletBinding()]
param(
    [ValidateSet('0.3.48', '0.4.0', '1.0.0', '1.1.0')]
    [string]$Version = '1.1.0',
    [switch]$AllowIncomplete
)

$ErrorActionPreference = 'Continue'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runStartedAt = (Get-Date).ToUniversalTime()
$runID = "tests-$Version-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))"
$artifactRoot = Join-Path $repo "testlab\artifacts\godzmind\$runID"
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$steps = @()

function Invoke-TestWorker {
    param([string]$Name, [string]$Script, [string[]]$Arguments = @())
    $started = Get-Date
    $log = Join-Path $artifactRoot "$Name.log"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments *>&1 |
        Set-Content -LiteralPath $log -Encoding utf8
    $code = $LASTEXITCODE
    $script:steps += [ordered]@{
        name = $Name
        state = if ($code -eq 0) { 'passed' } else { 'failed' }
        exit_code = $code
        duration_ms = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
        log = $log
    }
}

Invoke-TestWorker 'isolated-backend' `
    (Join-Path $repo 'testlab\Test-TGDeskIsolatedBackend.ps1') @('-Action','Validate')
Invoke-TestWorker 'control-key' `
    (Join-Path $repo 'testlab\Test-TGDeskControlKey.ps1')
Invoke-TestWorker 'orphan-backend-contracts' `
    (Join-Path $repo 'testlab\Test-TGDeskOrphanBackendContracts.ps1')
Invoke-TestWorker 'functional-contracts' `
    (Join-Path $repo 'testlab\Test-TGDeskFunctionalContracts.ps1')
Invoke-TestWorker 'installer-update-contracts' `
    (Join-Path $repo 'testlab\Test-TGDeskInstallerUpdate.ps1')
Invoke-TestWorker 'client-ui-contracts' `
    (Join-Path $repo 'testlab\Test-TGDeskClientUiContracts.ps1')
Invoke-TestWorker 'hierarchy' `
    (Join-Path $repo 'testlab\Test-TGDeskHierarchy.ps1')
Invoke-TestWorker 'deletion-identity' `
    (Join-Path $repo 'testlab\Test-TGDeskDeletionIdentity.ps1')
Invoke-TestWorker 'management-lifecycle' `
    (Join-Path $repo 'testlab\Test-TGDeskManagementLifecycle.ps1')
Invoke-TestWorker 'control-telemetry' `
    (Join-Path $repo 'testlab\Test-TGDeskControlTelemetry.ps1')
Invoke-TestWorker 'support-v110' `
    (Join-Path $repo 'testlab\Test-TGDeskSupportV110.ps1')
Invoke-TestWorker 'server-runtime' `
    (Join-Path $repo 'testlab\Test-TGDeskServerRuntime.ps1')
Invoke-TestWorker 'health' `
    (Join-Path $PSScriptRoot 'Get-TGDeskHealth.ps1')
Invoke-TestWorker 'version-gate' `
    (Join-Path $PSScriptRoot 'Invoke-TGDeskVersionGate.ps1') `
    $(if ($AllowIncomplete) {
        @('-Version',$Version,'-EvidenceSinceUtc',$runStartedAt.ToString('o'),'-NoFail')
    } else {
        @('-Version',$Version,'-EvidenceSinceUtc',$runStartedAt.ToString('o'))
    })

$gateArtifact = Join-Path $repo "testlab\artifacts\version-gate-$Version.json"
$gate = Get-Content $gateArtifact -Raw | ConvertFrom-Json
if ($gate.state -ne 'passed') {
    $steps[-1].state = 'blocked'
}
$failed = @($steps | Where-Object state -eq 'failed')
$blocked = @($steps | Where-Object state -eq 'blocked')
$state = if ($failed.Count) {
    'failed'
} elseif ($blocked.Count) {
    'incomplete'
} else {
    'passed'
}
$report = [ordered]@{
    schema_version = 1
    phase = 'godzmind-tests'
    run_id = $runID
    version = $Version
    state = $state
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    steps = $steps
}
$report | ConvertTo-Json -Depth 8 |
    Set-Content (Join-Path $artifactRoot 'tests.json') -Encoding utf8
$report | ConvertTo-Json -Depth 6
if ($failed.Count -or ($blocked.Count -and -not $AllowIncomplete)) { exit 1 }
