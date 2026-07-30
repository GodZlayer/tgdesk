$ErrorActionPreference = 'Stop'
$serverDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'server'
$evidencePath = Join-Path $PSScriptRoot 'artifacts\server-runtime.json'
$assertions = @()

function Add-Assertion {
    param([string]$ID, [bool]$Condition, [hashtable]$Details)
    if (-not $Condition) {
        throw "Assertion failed: $ID :: $($Details | ConvertTo-Json -Compress)"
    }
    $script:assertions += [ordered]@{
        id = $ID
        state = 'passed'
        details = $Details
    }
}

try {
    $containers = @(
        docker compose --project-directory $serverDir ps --format json |
            ForEach-Object { $_ | ConvertFrom-Json }
    )
    $api = $containers | Where-Object Service -eq 'api-core'
    $relay = $containers | Where-Object Service -eq 'relay'
    $rendezvous = $containers | Where-Object Service -eq 'rendezvous'
    if (-not $api -or -not $relay -or -not $rendezvous) {
        throw 'Stack de produção incompleto.'
    }

    $projectNames = @($containers | ForEach-Object Project | Select-Object -Unique)
    Add-Assertion 'server.compose-name' `
        ($projectNames.Count -eq 1 -and $projectNames[0] -eq 'server-tgdesk') `
        @{projects = $projectNames}

    $apiInspect = docker inspect $api.ID | ConvertFrom-Json
    $relayInspect = docker inspect $relay.ID | ConvertFrom-Json
    $rendezvousInspect = docker inspect $rendezvous.ID | ConvertFrom-Json
    $restartPolicies = @(
        $containers | ForEach-Object {
            $inspection = docker inspect $_.ID | ConvertFrom-Json
            [string]$inspection[0].HostConfig.RestartPolicy.Name
        }
    )
    Add-Assertion 'server.auto-restart' `
        (@($restartPolicies | Where-Object { $_ -ne 'unless-stopped' }).Count -eq 0) `
        @{restart_policies = $restartPolicies}

    $namedMounts = @(
        $apiInspect[0].Mounts + (docker inspect $relay.ID | ConvertFrom-Json)[0].Mounts +
        (docker inspect $rendezvous.ID | ConvertFrom-Json)[0].Mounts |
            Where-Object Type -eq 'volume' | ForEach-Object Name | Select-Object -Unique
    )
    $seedDisabled = ((docker inspect $api.ID | ConvertFrom-Json)[0].Config.Env -contains 'ENABLE_DEMO_SEED=false') -and
        ((docker inspect $api.ID | ConvertFrom-Json)[0].Config.Env -contains 'FORCE_RESEED=false')
    Add-Assertion 'server.volumes-persistent' `
        ($namedMounts.Count -ge 3 -and $seedDisabled) `
        @{named_volumes = $namedMounts; demo_seed_disabled = $seedDisabled}

    $expectedMode = "container:$($apiInspect[0].Id)"
    Add-Assertion 'server.relay-namespace' `
        ($relayInspect[0].HostConfig.NetworkMode -eq $expectedMode -and
         $rendezvousInspect[0].HostConfig.NetworkMode -eq $expectedMode) `
        @{
            expected = $expectedMode
            relay = [string]$relayInspect[0].HostConfig.NetworkMode
            rendezvous = [string]$rendezvousInspect[0].HostConfig.NetworkMode
        }

    $published = @(
        $api.Publishers | Where-Object PublishedPort -gt 0 |
            ForEach-Object { "$($_.PublishedPort)/$($_.Protocol)" }
    )
    $internal = @(
        docker exec $api.ID sh -lc "ss -lntup | grep -E ':(21116|21117)'"
    )
    Add-Assertion 'server.private-ports' `
        (($published -notcontains '21116/tcp') -and
         ($published -notcontains '21116/udp') -and
         ($published -notcontains '21117/tcp') -and
         (($internal -join "`n") -match ':21116') -and
         (($internal -join "`n") -match ':21117')) `
        @{published = $published; internal = $internal}

    $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8090/healthz' -TimeoutSec 3
    $migrationCount = docker compose --project-directory $serverDir exec -T postgres `
        psql -U tgdesk -d tgdesk -Atc 'select count(*) from schema_migrations;'
    Add-Assertion 'server.health-observable' `
        ($health.status -eq 'ok' -and [int]$migrationCount -gt 0) `
        @{health = $health.status; migration_count = [int]$migrationCount}

    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'server-deployment-and-recovery'
        state = 'passed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        assertions = $assertions
    }
    $evidence | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $evidencePath -Encoding utf8
    $evidence | ConvertTo-Json -Depth 10
} catch {
    $evidence = [ordered]@{
        schema_version = 1
        scenario = 'server-deployment-and-recovery'
        state = 'failed'
        measured_at = (Get-Date).ToUniversalTime().ToString('o')
        assertions = $assertions
        error = $_.Exception.Message
    }
    $evidence | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $evidencePath -Encoding utf8
    $evidence | ConvertTo-Json -Depth 10
    exit 1
}
