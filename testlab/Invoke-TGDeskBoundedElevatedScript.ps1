[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ScriptArguments = @(),
    [int]$TimeoutSeconds = 180,
    [string]$EvidencePath = ''
)
$ErrorActionPreference = 'Stop'
if (-not $EvidencePath) {
    $EvidencePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) `
        'artifacts\bounded-worker.json'
}
$stdout = "$EvidencePath.stdout.log"
$stderr = "$EvidencePath.stderr.log"
$arguments = @(
    '--inline',
    'powershell.exe',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f (Resolve-Path $ScriptPath))
) + $ScriptArguments
$process = Start-Process sudo.exe -ArgumentList $arguments -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
} while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline)
$timedOut = -not $process.HasExited
if ($timedOut) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
}
$process.WaitForExit()
$process.Refresh()
$exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
$result = [ordered]@{
    schema_version = 1
    status = if ($timedOut) { 'timeout' } elseif (
        $exitCode -eq 0
    ) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    script = (Resolve-Path $ScriptPath).Path
    timeout_seconds = $TimeoutSeconds
    timed_out = $timedOut
    exit_code = $exitCode
    stdout = $stdout
    stderr = $stderr
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force |
    Out-Null
$result | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 5
if ($result.exit_code -ne 0) { exit $result.exit_code }
