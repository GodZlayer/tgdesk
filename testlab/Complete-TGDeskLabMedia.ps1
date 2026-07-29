[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$job = Get-BitsTransfer |
    Where-Object DisplayName -eq 'TGDesk-Windows11-Enterprise-Eval' |
    Select-Object -First 1
if (-not $job) {
    throw 'TGDesk Windows media BITS job not found'
}

$state = [ordered]@{
    schema_version = 1
    phase = 'media-download'
    job_id = [string]$job.JobId
    status = [string]$job.JobState
    bytes_transferred = $job.BytesTransferred
    bytes_total = $job.BytesTotal
    measured_at = [DateTime]::UtcNow.ToString('o')
}
$statePath = Join-Path $PSScriptRoot 'artifacts\media-download.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
$state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8

switch ([string]$job.JobState) {
    'Transferred' {
        Complete-BitsTransfer -BitsJob $job
        & (Join-Path $PSScriptRoot 'Invoke-TGDeskStateLoop.ps1') -Action ValidateMedia
        exit $LASTEXITCODE
    }
    'Error' {
        throw "BITS download failed: $($job.ErrorDescription)"
    }
    'TransientError' {
        Resume-BitsTransfer -BitsJob $job -Asynchronous
        exit 2
    }
    default {
        exit 2
    }
}
