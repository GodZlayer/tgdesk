param(
    [string]$AdminLabel = 'Administrador',
    [string]$AdminKeyPath = '..\installers\output\TGDesk-Admin-0.3.8.tgdesk-key'
)

$ErrorActionPreference = 'Stop'
$adminId = [guid]::NewGuid().ToString()
$safeLabel = $AdminLabel.Replace("'", "''")
$sql = @"
BEGIN;
TRUNCATE TABLE sessions, telemetry_snapshots, alerts, devices,
  technician_assignments, technician_enrollment_keys,
  technician_machine_credentials, admin_actions RESTART IDENTITY CASCADE;
DELETE FROM technicians;
ALTER SEQUENCE technician_host_octet_seq RESTART WITH 2;
INSERT INTO technicians
  (id, username, password_hash, role, created_via_env, status)
VALUES
  ('$adminId', '$safeLabel', '!key-only!', 'super_admin', false, 'ativo');
COMMIT;
"@

docker compose --project-directory $PSScriptRoot exec -T postgres `
    psql -v ON_ERROR_STOP=1 -U tgdesk -d tgdesk -c $sql | Out-Null

$resolvedKeyPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $AdminKeyPath))
& (Join-Path $PSScriptRoot '..\installers\New-TGDeskAdminKey.ps1') `
    -OutputPath $resolvedKeyPath -ExpiresInHours 168

Write-Output "Controle TGDesk reiniciado."
Write-Output "Nova chave Admin: $resolvedKeyPath"
