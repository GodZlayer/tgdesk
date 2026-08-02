[CmdletBinding()]
param(
    [string]$ComposeFile = '',
    [string]$ApiUrl = 'http://127.0.0.1:8090'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
if (-not $ComposeFile) {
    $ComposeFile = Join-Path $PSScriptRoot '..\server\docker-compose.yml'
}
$repairLog = Join-Path $env:ProgramData 'TGDesk\updates\admin-identity-repair.log'
[IO.Directory]::CreateDirectory((Split-Path -Parent $repairLog)) | Out-Null
'started' | Set-Content -LiteralPath $repairLog -Encoding UTF8
trap {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $repairLog)) | Out-Null
    $_.Exception.Message | Set-Content -LiteralPath $repairLog -Encoding UTF8
    exit 1
}

function Invoke-PsqlScalar([string]$Sql) {
    $value = & docker compose -f $ComposeFile exec -T postgres `
        psql -U tgdesk -d tgdesk -Atqc $Sql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar PostgreSQL.' }
    return ($value | Out-String).Trim()
}

function Invoke-Psql([string]$Sql) {
    $output = & docker compose -f $ComposeFile exec -T postgres `
        psql -U tgdesk -d tgdesk -v ON_ERROR_STOP=1 -Atqc $Sql 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('Falha ao alterar PostgreSQL: ' + (($output | Out-String).Trim()))
    }
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Execute este reparo como Administrador.'
}

$machineId = (Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid.Trim()
$technicianId = Invoke-PsqlScalar @"
SELECT id FROM technicians
WHERE role='super_admin' AND status='ativo'
ORDER BY created_at LIMIT 1
"@
if (-not $technicianId) { throw 'Nenhum super_admin ativo foi encontrado.' }

$previousCredential = Invoke-PsqlScalar @"
SELECT id FROM technician_machine_credentials
WHERE control_role='super_admin' AND status='ativo'
ORDER BY created_at LIMIT 1
"@

$raw = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($raw)
$rng.Dispose()
$secret = [Convert]::ToBase64String($raw).TrimEnd('=').Replace('+','-').Replace('/','_')
$sha = [Security.Cryptography.SHA256]::Create()
$secretHash = ([BitConverter]::ToString(
    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret)))).Replace('-', '')
$keyId = [Guid]::NewGuid().ToString()
$jwtSecret = (& docker compose -f $ComposeFile exec -T api-core printenv JWT_SECRET |
    Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $jwtSecret) { throw 'JWT_SECRET indisponivel.' }
$serverId = ([BitConverter]::ToString(
    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($jwtSecret)))).
    Replace('-', '').ToLowerInvariant().Substring(0, 16)
$sha.Dispose()
$jwtSecret = $null

Invoke-Psql @"
BEGIN;
UPDATE technician_machine_credentials
SET status='revogado'
WHERE control_role='super_admin' AND status='ativo';
INSERT INTO technician_enrollment_keys
    (id, technician_id, secret_hash, expires_at, created_by)
VALUES
    ('$keyId', '$technicianId', decode('$secretHash','hex'), now()+interval '15 minutes', '$technicianId');
COMMIT;
"@

try {
    $payload = @{
        key = @{
            format = 'tgdesk-control-key-v1'
            key_id = $keyId
            secret = $secret
            server_id = $serverId
        }
        machine_id = $machineId
    } | ConvertTo-Json -Depth 4 -Compress
    $redeemed = Invoke-RestMethod -Method Post `
        -Uri "$ApiUrl/api/v1/auth/technician/redeem" `
        -ContentType 'application/json' -Body $payload
    if ($redeemed.role -ne 'super_admin') { throw 'Tier retornado nao e super_admin.' }

    # A segunda tentativa precisa falhar com 409, comprovando consumo unico.
    $secondStatus = 0
    try {
        Invoke-WebRequest -UseBasicParsing -Method Post `
            -Uri "$ApiUrl/api/v1/auth/technician/redeem" `
            -ContentType 'application/json' -Body $payload | Out-Null
    } catch {
        $secondStatus = [int]$_.Exception.Response.StatusCode
    }
    if ($secondStatus -ne 409) { throw "Chave nao confirmou uso unico (HTTP $secondStatus)." }

    $credential = @{
        credential_id = [string]$redeemed.credential_id
        secret = [string]$redeemed.secret
        machine_id = [string]$redeemed.machine_id
    }
    $clear = [Text.Encoding]::UTF8.GetBytes(
        ($credential | ConvertTo-Json -Compress))
    $encrypted = [Security.Cryptography.ProtectedData]::Protect(
        $clear, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    $identityDir = Join-Path $env:ProgramData 'TGDesk\identity'
    [IO.Directory]::CreateDirectory($identityDir) | Out-Null
    $target = Join-Path $identityDir 'technician.dat'
    $temporary = "$target.new"
    [IO.File]::WriteAllBytes($temporary, $encrypted)
    Move-Item -LiteralPath $temporary -Destination $target -Force

    $refresh = Invoke-RestMethod -Method Post `
        -Uri "$ApiUrl/api/v1/auth/technician/refresh" `
        -ContentType 'application/json' `
        -Body ($credential | ConvertTo-Json -Compress)
    if ($refresh.role -ne 'super_admin') { throw 'Refresh nao confirmou super_admin.' }
} catch {
    $restore = if ($previousCredential) {
        "UPDATE technician_machine_credentials SET status='ativo' WHERE id='$previousCredential';"
    } else { '' }
    Invoke-Psql "BEGIN; DELETE FROM technician_enrollment_keys WHERE id='$keyId' AND consumed_at IS NULL; $restore COMMIT;"
    throw
} finally {
    $secret = $null
    $payload = $null
    $redeemed = $null
    $credential = $null
    $clear = $null
}

$active = Invoke-PsqlScalar @"
SELECT count(*) || ':' || min(control_role)
FROM technician_machine_credentials
WHERE status='ativo' AND machine_id='$machineId'
"@
if ($active -ne '1:super_admin') { throw "Estado final invalido: $active" }

[pscustomobject]@{
    repaired = $true
    role = 'super_admin'
    one_time_key_consumed = $true
    credential_file = (Join-Path $env:ProgramData 'TGDesk\identity\technician.dat')
} | ConvertTo-Json -Compress | Set-Content -LiteralPath $repairLog -Encoding UTF8
