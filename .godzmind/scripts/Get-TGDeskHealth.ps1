$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$artifactPath = Join-Path $repo 'testlab\artifacts\godzmind-health.json'

$docker = @(
    docker ps --format json | ForEach-Object { $_ | ConvertFrom-Json }
)
$launcherPath = Join-Path $repo 'testlab\artifacts\base-image-launcher.json'
$launcher = if (Test-Path $launcherPath) {
    Get-Content $launcherPath -Raw | ConvertFrom-Json
} else { $null }
$disk = Get-PSDrive -Name C
$tgdeskProcesses = @(
    Get-Process tgdesk -ErrorAction SilentlyContinue |
        Select-Object Id,SessionId,WorkingSet64,CPU,StartTime
)
$tgdeskServices = @(
    Get-Service -Name 'TGDesk*' -ErrorAction SilentlyContinue |
        Select-Object Name,Status,StartType
)
$report = [ordered]@{
    schema_version = 1
    phase = 'godzmind-health'
    state = 'passed'
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    host = [ordered]@{
        free_bytes_c = [int64]$disk.Free
        tgdesk_processes = $tgdeskProcesses
        tgdesk_services = $tgdeskServices
    }
    docker = [ordered]@{
        running_count = $docker.Count
        containers = @($docker | Select-Object Names,Image,State,Status,Ports)
    }
    hyperv_lab = [ordered]@{
        launcher = $launcher
        vm_worker_process_count = @(Get-Process vmwp -ErrorAction SilentlyContinue).Count
    }
}
$report | ConvertTo-Json -Depth 10 | Set-Content $artifactPath -Encoding utf8
$report | ConvertTo-Json -Depth 6
