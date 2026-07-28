param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output\TGDesk-Admin.tgdesk-key'),
    [int]$ExpiresInHours = 168
)

$ErrorActionPreference = 'Stop'
$serverDir = Join-Path $PSScriptRoot '..\server'
$adminId = (docker compose --project-directory $serverDir exec -T postgres `
    psql -U tgdesk -d tgdesk -Atc `
    "select id from technicians where role='super_admin' and status='ativo' order by created_at limit 1;").Trim()
if (-not $adminId) { throw 'Nenhuma conta super_admin ativa foi encontrada.' }

$secretBytes = [byte[]]::new(32)
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($secretBytes)
$rng.Dispose()
$secret = [Convert]::ToBase64String($secretBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$sha256 = [Security.Cryptography.SHA256]::Create()
$digest = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($secret))
$digestHex = ([BitConverter]::ToString($digest) -replace '-', '').ToLowerInvariant()
$keyId = [guid]::NewGuid().ToString()

$jwtLine = Get-Content (Join-Path $serverDir '.env') |
    Where-Object { $_ -match '^JWT_SECRET=' } | Select-Object -First 1
$jwtSecret = $jwtLine.Substring('JWT_SECRET='.Length)
$serverDigest = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($jwtSecret))
$sha256.Dispose()
$serverId = (([BitConverter]::ToString($serverDigest) -replace '-', '').
    ToLowerInvariant().Substring(0, 16))

$sql = @"
update technician_enrollment_keys k
set consumed_at = now(), consumed_machine_id = 'revoked-by-new-admin-key'
from technicians t
where k.technician_id=t.id and t.role='super_admin' and k.consumed_at is null;
insert into technician_enrollment_keys
  (id, technician_id, secret_hash, expires_at, created_by)
values
  ('$keyId', '$adminId', decode('$digestHex','hex'),
   now() + interval '$ExpiresInHours hours', '$adminId');
"@
docker compose --project-directory $serverDir exec -T postgres `
    psql -v ON_ERROR_STOP=1 -U tgdesk -d tgdesk -c $sql | Out-Null

$payload = [ordered]@{
    format = 'tgdesk-control-key-v1'
    key_id = $keyId
    secret = $secret
    server_id = $serverId
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath) | Out-Null
[IO.File]::WriteAllText(
    $OutputPath, ($payload | ConvertTo-Json),
    [Text.UTF8Encoding]::new($false))
Write-Output (Resolve-Path $OutputPath)
