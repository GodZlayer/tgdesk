[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'artifacts\keys\admin.tgdesk-key'),
    [int]$ExpiresInHours = 24
)

$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$adminID = [guid]::NewGuid().ToString()
$keyID = [guid]::NewGuid().ToString()
$secretBytes = [byte[]]::new(32)
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($secretBytes)
$rng.Dispose()
$secret = [Convert]::ToBase64String($secretBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$sha = [Security.Cryptography.SHA256]::Create()
$digestHex = ([BitConverter]::ToString(
    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret))) -replace '-', '').ToLowerInvariant()
$serverID = (([BitConverter]::ToString(
    $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('tgdesk-testlab-only'))) -replace '-', '').
    ToLowerInvariant().Substring(0, 16))
$sha.Dispose()

$sql = @"
BEGIN;
INSERT INTO technicians
  (id, username, password_hash, role, created_via_env, status)
VALUES
  ('$adminID', 'Administrador TestLab', '!key-only!', 'super_admin', false, 'ativo')
ON CONFLICT (username) DO UPDATE SET status='ativo'
RETURNING id;
INSERT INTO technician_enrollment_keys
  (id, technician_id, secret_hash, expires_at, created_by)
SELECT
  '$keyID', id, decode('$digestHex','hex'),
  now() + interval '$ExpiresInHours hours', id
FROM technicians WHERE username='Administrador TestLab';
COMMIT;
"@

$sql | docker compose -f $compose exec -T postgres `
    psql -v ON_ERROR_STOP=1 -U tgdesk_test -d tgdesk_test | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao criar a chave Admin no banco isolado.'
}

$payload = [ordered]@{
    format = 'tgdesk-control-key-v1'
    key_id = $keyID
    secret = $secret
    server_id = $serverID
}
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText(
    [IO.Path]::GetFullPath($OutputPath),
    ($payload | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false)
)

[ordered]@{
    state = 'passed'
    role = 'super_admin'
    key_path = [IO.Path]::GetFullPath($OutputPath)
    key_id = $keyID
    expires_in_hours = $ExpiresInHours
} | ConvertTo-Json
