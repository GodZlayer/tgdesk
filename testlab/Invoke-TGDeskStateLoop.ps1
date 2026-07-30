[CmdletBinding()]
param(
    [ValidateSet('Discover', 'ValidateBackend', 'ValidateMedia', 'ValidateVMPrerequisites', 'Run')]
    [string]$Action = 'Run',
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $ConfigPath) {
    $ConfigPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lab.config.json'
}

function Resolve-LabPath {
    param([string]$Base, [string]$Value)
    if ([IO.Path]::IsPathRooted($Value)) { return $Value }
    return [IO.Path]::GetFullPath((Join-Path $Base $Value))
}

function Write-Evidence {
    param(
        [string]$Phase,
        [string]$Status,
        [hashtable]$Measurements,
        [string[]]$Failures = @()
    )
    $evidence = [ordered]@{
        schema_version = 1
        run_id = $script:RunId
        phase = $Phase
        status = $Status
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        measurements = $Measurements
        failures = $Failures
    }
    $path = Join-Path $script:EvidenceRoot "$Phase.json"
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
    return $evidence
}

function Invoke-Discover {
    $vmms = Get-Service vmms -ErrorAction SilentlyContinue
    $vmcompute = Get-Service vmcompute -ErrorAction SilentlyContinue
    $getVM = Get-Command Get-VM -ErrorAction SilentlyContinue
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    $dockerType = if ($docker) {
        (& docker info --format '{{.OSType}}' 2>$null)
    } else { '' }
    $isoPath = Resolve-LabPath -Base $script:ConfigDir -Value ([string]$script:Config.base_vm.iso_path)
    $measurements = @{
        hyperv_module = [bool]$getVM
        vmms_status = if ($vmms) { [string]$vmms.Status } else { 'Missing' }
        vmcompute_status = if ($vmcompute) { [string]$vmcompute.Status } else { 'Missing' }
        docker_available = [bool]$docker
        docker_os_type = [string]$dockerType
        windows_iso = $isoPath
        windows_iso_exists = ($isoPath -ne '' -and (Test-Path -LiteralPath $isoPath -PathType Leaf))
    }
    $failures = @()
    if (-not $measurements.hyperv_module) { $failures += 'Hyper-V PowerShell module missing' }
    if ($measurements.vmms_status -ne 'Running') { $failures += 'Hyper-V VMMS is not running' }
    if (-not $measurements.docker_available) { $failures += 'Docker CLI missing' }
    $status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    Write-Evidence -Phase 'discover' -Status $status -Measurements $measurements -Failures $failures
}

function Invoke-ValidateBackend {
    $failures = @()
    $health = ''
    try {
        $health = (Invoke-RestMethod -Uri 'http://localhost:8090/healthz' -TimeoutSec 5).status
    } catch {
        $failures += "Health endpoint failed: $($_.Exception.Message)"
    }
    $compose = @()
    try {
        $compose = @(& docker compose --project-directory (Join-Path $PSScriptRoot '..\server') ps --format json |
            ForEach-Object { $_ | ConvertFrom-Json })
    } catch {
        $failures += "Compose inspection failed: $($_.Exception.Message)"
    }
    $unhealthy = @($compose | Where-Object { $_.State -ne 'running' })
    if ($health -ne [string]$script:Config.success_criteria.backend_health) {
        $failures += "Unexpected backend health: $health"
    }
    if ($unhealthy.Count -gt 0) {
        $failures += "Non-running containers: $($unhealthy.Service -join ', ')"
    }
    $measurements = @{
        health = $health
        containers = @($compose | ForEach-Object {
            @{ service = $_.Service; name = $_.Name; state = $_.State; health = $_.Health }
        })
    }
    $status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    Write-Evidence -Phase 'backend' -Status $status -Measurements $measurements -Failures $failures
}

function Invoke-ValidateMedia {
    $isoPath = Resolve-LabPath -Base $script:ConfigDir -Value ([string]$script:Config.base_vm.iso_path)
    $expected = ([string]$script:Config.base_vm.iso_sha256).ToUpperInvariant()
    $failures = @()
    $actual = ''
    if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
        $failures += 'Windows ISO has not been downloaded'
    } else {
        $actual = (Get-FileHash -LiteralPath $isoPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($actual -ne $expected) { $failures += 'Windows ISO SHA256 mismatch' }
    }
    $measurements = @{
        iso_path = $isoPath
        expected_sha256 = $expected
        actual_sha256 = $actual
        size_bytes = if (Test-Path -LiteralPath $isoPath) {
            (Get-Item -LiteralPath $isoPath).Length
        } else { 0 }
    }
    $status = if ($failures.Count -eq 0) { 'passed' } else { 'blocked' }
    Write-Evidence -Phase 'media' -Status $status -Measurements $measurements -Failures $failures
}

function Invoke-ValidateVMPrerequisites {
    $discoverPath = Join-Path $script:EvidenceRoot 'discover.json'
    if (-not (Test-Path -LiteralPath $discoverPath)) {
        throw 'discover.json is required before VM validation'
    }
    $discover = Get-Content -LiteralPath $discoverPath -Raw | ConvertFrom-Json
    $failures = @()
    if ($discover.status -ne 'passed') { $failures += 'Discovery phase did not pass' }
    if (-not $discover.measurements.windows_iso_exists) {
        $failures += 'Windows ISO has not been configured'
    }
    $measurements = @{
        hyperv_ready = (
            $discover.measurements.hyperv_module -and
            $discover.measurements.vmms_status -eq 'Running'
        )
        windows_iso_exists = [bool]$discover.measurements.windows_iso_exists
        windows_iso = [string]$discover.measurements.windows_iso
    }
    $status = if ($failures.Count -eq 0) { 'passed' } else { 'blocked' }
    Write-Evidence -Phase 'vm-prerequisites' -Status $status -Measurements $measurements -Failures $failures
}

$configFullPath = [IO.Path]::GetFullPath($ConfigPath)
if (-not (Test-Path -LiteralPath $configFullPath -PathType Leaf)) {
    throw "Lab config not found: $configFullPath"
}
$script:Config = Get-Content -LiteralPath $configFullPath -Raw | ConvertFrom-Json
$script:RunId = [guid]::NewGuid().ToString()
$script:ConfigDir = Split-Path -Parent $configFullPath
$artifactRoot = Resolve-LabPath -Base $script:ConfigDir -Value ([string]$script:Config.artifacts_root)
$script:EvidenceRoot = Join-Path $artifactRoot $script:RunId
New-Item -ItemType Directory -Path $script:EvidenceRoot -Force | Out-Null

$result = switch ($Action) {
    'Discover' { Invoke-Discover }
    'ValidateBackend' { Invoke-ValidateBackend }
    'ValidateMedia' { Invoke-ValidateMedia }
    'ValidateVMPrerequisites' {
        Invoke-Discover | Out-Null
        Invoke-ValidateVMPrerequisites
    }
    'Run' {
        $discover = Invoke-Discover
        if ($discover.status -ne 'passed') { $discover; break }
        $backend = Invoke-ValidateBackend
        if ($backend.status -ne 'passed') { $backend; break }
        $media = Invoke-ValidateMedia
        if ($media.status -ne 'passed') { $media; break }
        Invoke-ValidateVMPrerequisites
    }
}

$result | ConvertTo-Json -Depth 12
if ($result.status -eq 'failed') { exit 1 }
if ($result.status -eq 'blocked') { exit 2 }
