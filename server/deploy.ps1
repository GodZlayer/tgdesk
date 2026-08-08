$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

try {
    docker compose up -d --build --force-recreate api-core relay rendezvous
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao publicar api-core/hbbs/hbbr.'
    }

    # relay/rendezvous compartilham o namespace de rede do api-core. Sempre que
    # ele é recriado, estes serviços também precisam ser recriados para não
    # permanecerem presos ao namespace antigo.
    $apiContainer = (docker compose ps -q api-core).Trim()
    if (-not $apiContainer) {
        throw 'Container api-core não encontrado.'
    }
    $apiId = (docker inspect $apiContainer --format '{{.Id}}').Trim()
    foreach ($service in @('relay', 'rendezvous')) {
        $container = (docker compose ps -q $service).Trim()
        if (-not $container) {
            throw ("Container " + $service + " not found.")
        }
        $namespace = (docker inspect $container --format '{{.HostConfig.NetworkMode}}').Trim()
        if ($namespace -ne "container:$apiId") {
            throw ("Container " + $service + " is outside api-core namespace.")
        }
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
