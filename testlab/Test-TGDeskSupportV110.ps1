$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$apiContainer = (& docker compose -f $compose ps -q api-core).Trim()
if (-not $apiContainer) { throw 'O api-core isolado não está em execução.' }

# A autoridade é sintética e descartável: cada execução revoga somente a
# credencial Admin do banco isolado para manter o worker repetível.
$prepareSql = @"
TRUNCATE support_tickets CASCADE;
DELETE FROM technicians WHERE role='freelancer';
DELETE FROM technicians WHERE username LIKE 'Supervisor %';
UPDATE technician_machine_credentials SET status='revogado'
WHERE technician_id IN (SELECT id FROM technicians WHERE username='Administrador TestLab');
"@
$prepareSql |
    docker compose -f $compose exec -T postgres psql -v ON_ERROR_STOP=1 -U tgdesk_test -d tgdesk_test | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar autoridade sintética isolada.' }

& (Join-Path $PSScriptRoot 'New-TGDeskLabAdminKey.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar chave Admin descartável.' }

$mount = "$($PSScriptRoot):/tests"
& docker run --rm --network "container:$apiContainer" -v $mount node:22-alpine `
    node /tests/scripts/integration-support-v110.mjs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
