$ErrorActionPreference = 'Stop'

# Comandos nativos (docker) escrevem PROGRESSO em stderr — "Image X Building",
# "Container Y Started". No Windows PowerShell 5.1, com ErrorActionPreference
# 'Stop', cada uma dessas linhas vira erro TERMINANTE mesmo com o docker
# retornando 0, e o deploy aborta no meio de uma publicação que estava dando
# certo. Foi o que reprovou a release 1.2.52.
#
# O critério de sucesso continua sendo o CÓDIGO DE SAÍDA, checado em cada passo
# abaixo — nada foi afrouxado. O que se elimina é o falso positivo.
$PSNativeCommandUseErrorActionPreference = $false

Push-Location $PSScriptRoot

try {
    $preferenciaAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    docker compose up -d --build --force-recreate api-core relay rendezvous
    if ($LASTEXITCODE -ne 0) {
        $ErrorActionPreference = $preferenciaAnterior
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

    $ErrorActionPreference = $preferenciaAnterior
    Write-Host 'TGDesk publicado: API, hbbs e hbbr operacionais.'
}
finally {
    Pop-Location
}
