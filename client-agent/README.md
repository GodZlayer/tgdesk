# tgdesk-agent.exe — agente único (Host + Técnico)

Consolida o que antes eram dois executáveis Go separados
(`client-host/tgdesk-host.exe` e `client-tunnel/tgdesk-tunnel.exe`) num só
binário. Cada papel continua com identidade de rede, adaptador e pool de IP
completamente independentes (ver `../client-tgdesk/ARCHITECTURE_FLOW.md`,
Seção 3) — só o arquivo `.exe` é compartilhado.

## Uso

```bash
tgdesk-agent.exe                       # papel Host (padrão)
tgdesk-agent.exe host                  # papel Host (explícito)
tgdesk-agent.exe technician --token X  # papel Técnico — chamado pelo Hub
```

## Arquivos

- `agent_main.go` — dispatcher (único `func main()`)
- `host.go` — papel Host: registro/pareamento/heartbeat/elevação sob demanda/túnel/RustDesk/telemetria (ex-`client-host/main.go`, `func main` renomeado para `runHost`)
- `technician.go` — papel Técnico: túnel WireGuard próprio do Hub (ex-`client-tunnel/main.go`, `func main` renomeado para `runTechnician`)
- `keys.go`, `netsh.go`, `status.go`, `telemetry.go`, `health_ext.go`, `elevate.go`, `install.go`, `remote_access.go` — compartilhados pelos dois papéis, sem duplicação
- `health_ext.go` — saúde estendida do hardware (SMART do disco, temperatura de CPU, GPU) via PowerShell/WMI + nvidia-smi, com janela escondida

## Como é distribuído (embutido, não solto)

O `.exe` **não** vai solto na pasta do cliente. Ele é embutido no `tgdesk.exe`
como asset Flutter (`flutter/assets/tgdesk-agent.bin` + `wintun.bin`) e
extraído em tempo de execução para `%LOCALAPPDATA%\TGDeskAgent`, de onde roda.
Isso é o que faz o cliente instalado não ter um `tgdesk-agent.exe` avulso.
Config (`tgdesk-agent.json`) e status (`tgdesk-status.json`) ficam nessa mesma
pasta — que a UI Dart lê via `agent_deploy.dart`. Pasta própria (não `tgdesk`)
de propósito: a versão portátil apaga `%LOCALAPPDATA%\tgdesk` num upgrade, e o
estado do agente não pode ir junto.

Ao reembutir o agente após recompilar, copie-o para os assets:

```bash
cp tgdesk-agent.exe ../client-rustdesk-src/flutter/assets/tgdesk-agent.bin
cp wintun.dll       ../client-rustdesk-src/flutter/assets/wintun.bin
```

## Recompilar

```bash
docker run --rm -v "<caminho>:/src" -w /src \
  -e GOOS=windows -e GOARCH=amd64 -e CGO_ENABLED=0 \
  golang:1.22-alpine sh -c "go mod tidy && go build -ldflags='-H=windowsgui' -o tgdesk-agent.exe ."
```

`-H=windowsgui` marca o binário como GUI subsystem em vez de console — sem
isso, toda vez que o tgdesk.exe lança o agente (host ou technician), o
Windows abre uma janela de console preta junto da UI bonita do Client/Hub.

`wintun.dll` precisa estar na mesma pasta (usado pelos dois papéis).
