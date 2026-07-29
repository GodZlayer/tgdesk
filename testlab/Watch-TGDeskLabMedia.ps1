[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$statePath = Join-Path $PSScriptRoot 'artifacts\media-watch.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null

while ($true) {
    $job = Get-BitsTransfer |
        Where-Object DisplayName -eq 'TGDesk-Windows11-Enterprise-Eval' |
        Select-Object -First 1
    if (-not $job) { throw 'TGDesk media BITS job disappeared' }

    $state = [ordered]@{
        schema_version = 1
        phase = 'media-watch'
        job_id = [string]$job.JobId
        state = [string]$job.JobState
        bytes_transferred = $job.BytesTransferred
        bytes_total = $job.BytesTotal
        percent = if ($job.BytesTotal -gt 0) {
            [math]::Round(100 * $job.BytesTransferred / $job.BytesTotal, 2)
        } else { 0 }
        measured_at = [DateTime]::UtcNow.ToString('o')
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding utf8

    switch ([string]$job.JobState) {
        'Transferred' {
            Complete-BitsTransfer -BitsJob $job
            & (Join-Path $PSScriptRoot 'Invoke-TGDeskStateLoop.ps1') -Action ValidateMedia
            exit $LASTEXITCODE
        }
        'Error' { throw "BITS download failed: $($job.ErrorDescription)" }
        'Cancelled' { throw 'BITS download was cancelled' }
        'TransientError' { Resume-BitsTransfer -BitsJob $job -Asynchronous }
    }
    Start-Sleep -Seconds 5
}
