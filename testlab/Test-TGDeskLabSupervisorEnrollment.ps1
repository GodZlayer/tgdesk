[CmdletBinding()]
param(
    [string]$VMName = 'tgdesk-supervisor-0-3-48',
    [string]$KeyPath = '',
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $KeyPath) {
    $KeyPath = Join-Path $scriptRoot 'artifacts\keys\supervisor.tgdesk-key'
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot "artifacts\$VMName\supervisor-enrollment.json"
}
$compose = Join-Path $scriptRoot 'docker-compose.test.yml'
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$key = Get-Content -LiteralPath $KeyPath -Raw | ConvertFrom-Json
$guest = Invoke-Command -VMName $VMName -Credential $credential -ScriptBlock {
    $statusPath = 'C:\ProgramData\TGDesk\state\status.json'
    $credentialPath = 'C:\ProgramData\TGDesk\identity\technician.dat'
    $refresh = $null
    if (Test-Path $credentialPath) {
        try {
            Add-Type -AssemblyName System.Security
            $encrypted = [IO.File]::ReadAllBytes($credentialPath)
            $plain = [Security.Cryptography.ProtectedData]::Unprotect(
                $encrypted, $null,
                [Security.Cryptography.DataProtectionScope]::LocalMachine)
            $auth = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
            $body = @{
                credential_id = $auth.credential_id
                secret = $auth.secret
                machine_id = $auth.machine_id
            } | ConvertTo-Json -Compress
            $response = Invoke-RestMethod `
                'http://168.232.199.161:8090/api/v1/auth/technician/refresh' `
                -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10
            $refresh = [ordered]@{
                valid = $true
                role = [string]$response.role
                username = [string]$response.username
                machine_id = [string]$response.machine_id
            }
        } catch {
            $refresh = [ordered]@{ valid = $false; error = $_.Exception.Message }
        }
    }
    [ordered]@{
        setup_running = [bool](Get-Process -Name 'tgdesk-installer-*' -ErrorAction SilentlyContinue)
        service = [string](Get-Service TGDesk -ErrorAction SilentlyContinue).Status
        version = if (Test-Path 'C:\Program Files\TGDesk\version.txt') {
            (Get-Content 'C:\Program Files\TGDesk\version.txt' -Raw).Trim()
        } else { '' }
        status = if (Test-Path $statusPath) {
            Get-Content $statusPath -Raw | ConvertFrom-Json
        } else { $null }
        credential_present = Test-Path $credentialPath
        control_identity = $refresh
        endpoint_health = $(try {
            (Invoke-RestMethod 'http://168.232.199.161:8090/healthz' -TimeoutSec 10).status
        } catch { "error: $($_.Exception.Message)" })
        install_log_tail = if (Test-Path 'C:\TGDeskLab\install.log') {
            @(Get-Content 'C:\TGDeskLab\install.log' -Tail 40 | ForEach-Object { [string]$_ })
        } else { @() }
        agent_log_tail = if (Test-Path 'C:\ProgramData\TGDesk\logs\agent.log') {
            @(Get-Content 'C:\ProgramData\TGDesk\logs\agent.log' -Tail 40 |
                ForEach-Object { [string]$_ })
        } else { @() }
        identity_files = @(Get-ChildItem 'C:\ProgramData\TGDesk\identity' -File `
            -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
}
$sql = "SELECT json_build_object('used', consumed_at IS NOT NULL, 'device_id', consumed_machine_id, 'technician_id', technician_id)::text FROM technician_enrollment_keys WHERE id='$($key.key_id)';"
$dbRaw = $sql | docker compose -f $compose exec -T postgres `
    psql -tA -v ON_ERROR_STOP=1 -U tgdesk_test -d tgdesk_test
if ($LASTEXITCODE -ne 0) { throw 'Falha consultando a chave no backend isolado.' }
$db = ($dbRaw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1) | ConvertFrom-Json
$replayStatus = 0
try {
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'http://127.0.0.1:18090/api/v1/auth/control-key/install' `
        -Method Post -ContentType 'application/json' `
        -Body (@{ key = $key; machine_id = [string]$db.device_id } |
            ConvertTo-Json -Depth 5 -Compress) -TimeoutSec 10 | Out-Null
    $replayStatus = 200
} catch {
    if ($_.Exception.Response) {
        $replayStatus = [int]$_.Exception.Response.StatusCode
    }
}
$roleObserved = (
    $guest.control_identity.valid -and
    $guest.control_identity.role -in @('tecnico','technician','supervisor','super_admin')
)
$passed = (
    -not $guest.setup_running -and
    $guest.service -eq 'Running' -and
    $guest.version -eq '0.3.48' -and
    $guest.endpoint_health -eq 'ok' -and
    $guest.credential_present -and
    [bool]$db.used -and
    [bool]$db.device_id -and
    $replayStatus -eq 409 -and
    $roleObserved
)
$result = [ordered]@{
    schema_version = 1
    phase = 'supervisor-isolated-enrollment'
    status = if ($passed) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    vm_name = $VMName
    backend_scope = 'tgdesk-testlab'
    key_id = $key.key_id
    key_used_once = [bool]$db.used
    key_device_id = [string]$db.device_id
    key_technician_id = [string]$db.technician_id
    replay_status = $replayStatus
    guest = $guest
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 10
if (-not $passed) { exit 1 }
