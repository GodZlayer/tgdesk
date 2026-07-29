$ErrorActionPreference = 'Stop'
$compose = Join-Path $PSScriptRoot 'docker-compose.test.yml'
$apiContainer = (& docker compose -f $compose ps -q api-core).Trim()
if (-not $apiContainer) { throw 'api-core isolado indisponível' }
& (Join-Path $PSScriptRoot 'New-TGDeskLabAdminKey.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar autoridade de teste' }
$mount = "$($PSScriptRoot):/tests"
& docker run --rm --network "container:$apiContainer" -v $mount `
    node:22-alpine node /tests/scripts/integration-deletion-identity.mjs
exit $LASTEXITCODE
