[CmdletBinding()]
param(
    [string]$OutputPath = '',
    [int]$ExpiresInHours = 24
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $scriptRoot 'artifacts\keys\supervisor.tgdesk-key'
}
$compose = Join-Path $scriptRoot 'docker-compose.test.yml'
$supervisorID = [guid]::NewGuid().ToString()
$keyID = [guid]::NewGuid().ToString()
$secretBytes = [byte[]]::new(32)
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($secretBytes) } finally { $rng.Dispose() }
$secret = [Convert]::ToBase64String($secretBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $digestHex = ([BitConverter]::ToString(
        $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret))) -replace '-', '').ToLowerInvariant()
    $serverID = (([BitConverter]::ToString(
        $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('tgdesk-testlab-only'))) -replace '-', '').
        ToLowerInvariant().Substring(0, 16))
} finally { $sha.Dispose() }

$sql = @"
BEGIN;
INSERT INTO technicians (id, username, password_hash, role, created_via_env, status)
VALUES ('$supervisorID', 'Supervisor VM $keyID', '!key-only!', 'tecnico', false, 'ativo');
INSERT INTO organizations(name, owner_technician_id)
VALUES ('Supervisor VM $keyID', '$supervisorID');
INSERT INTO technician_enrollment_keys
  (id, technician_id, secret_hash, expires_at, created_by)
SELECT '$keyID', '$supervisorID', decode('$digestHex','hex'),
       now() + interval '$ExpiresInHours hours', id
FROM technicians WHERE role='super_admin' ORDER BY created_at LIMIT 1;
COMMIT;
"@
$sql | docker compose -f $compose exec -T postgres `
    psql -v ON_ERROR_STOP=1 -U tgdesk_test -d tgdesk_test | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar chave Supervisor no banco isolado.' }

$payload = [ordered]@{
    format = 'tgdesk-control-key-v1'
    key_id = $keyID
    secret = $secret
    server_id = $serverID
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),
    ($payload | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
[ordered]@{
    state = 'passed'
    role = 'tecnico'
    key_path = [IO.Path]::GetFullPath($OutputPath)
    key_id = $keyID
} | ConvertTo-Json
