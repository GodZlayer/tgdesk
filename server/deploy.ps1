$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

try {
    docker compose up -d --build api-core
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao publicar o api-core.'
    }

    # relay/rendezvous compartilham o namespace de rede do api-core. Sempre que
    # ele é recriado, estes serviços também precisam ser recriados para não
    # permanecerem presos ao namespace antigo.
    docker compose up -d --force-recreate relay rendezvous
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao recriar hbbr/hbbs.'
    }

    $apiContainer = (docker compose ps -q api-core).Trim()
    if (-not $apiContainer) {
        throw 'Container api-core não encontrado.'
    }
    docker exec $apiContainer sh -c 'nc -z 10.70.0.1 21116 && nc -z 10.70.0.1 21117'
    if ($LASTEXITCODE -ne 0) {
        throw 'hbbs/hbbr não responderam dentro da VPN.'
    }

    Write-Host 'TGDesk publicado: API, hbbs e hbbr operacionais.'
}
finally {
    Pop-Location
}
