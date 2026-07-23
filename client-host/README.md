# tgdesk-host.exe — Cliente Host (Fase 1 + Fase 2)

Executável Windows real (compilado via cross-compile, sem precisar de Go
instalado no host) que implementa o fluxo da Seção 3.3 + Módulo A + Módulo B:

1. Registra o dispositivo no `api-core` (estado `guest`) e mostra o código de pareamento.
2. Faz heartbeat a cada 5s até um técnico vincular o dispositivo pelo Hub.
3. Ao ficar `ativo`: gera um par de chaves WireGuard real, envia a pública para
   `/api/v1/devices/wg-key`, recebe o IP virtual + config do hub, e sobe um
   túnel WireGuard de verdade (wireguard-go + Wintun) até o servidor.
4. Também ao ficar `ativo`: escreve a config do `rustdesk.exe` bundlado
   (`%APPDATA%\RustDesk\config\RustDesk2.toml`) apontando para o hbbs/hbbr do
   TGDesk (não a rede pública do RustDesk), inicia o `rustdesk.exe` como agente
   servidor, captura o ID gerado via `rustdesk.exe --get-id`, e reporta esse ID
   ao servidor (`POST /api/v1/devices/rustdesk-id`) — assim o `rustdesk_id`
   aparece amarrado ao `device_id` no `ListDevices` para o técnico.

`rustdesk.exe` + DLLs + `wintun.dll` precisam estar na mesma pasta deste
executável (copiados de `../client-remote/`) — já incluídos aqui.

## Rodar

```bash
# variável opcional; padrão é http://127.0.0.1:8090
set TGDESK_SERVER=http://127.0.0.1:8090
tgdesk-host.exe
```

Config persistida em `tgdesk-agent.json` ao lado do `.exe` (device_id, token,
chave privada — trate como segredo).

## Requisito: execução como Administrador

Criar o adaptador WireGuard (Wintun) exige privilégio de administrador na
**primeira vez** — é o Windows negando a instalação do driver de rede para um
processo não elevado (`ERROR_ACCESS_DENIED`), não um bug do TGDesk. Sem
elevação, o dispositivo registra, faz pareamento e recebe IP virtual
normalmente (validado nesta sessão) — só o túnel de dados em si não sobe.

Para completar o teste: clique com botão direito em `tgdesk-host.exe` →
"Executar como administrador".

`wintun.dll` (oficial, wintun.net, licença permissiva) precisa estar na mesma
pasta do `.exe` — já incluído aqui.

## Recompilar

```bash
docker run --rm -v "<caminho-desta-pasta>:/src" -w /src \
  -e GOOS=windows -e GOARCH=amd64 -e CGO_ENABLED=0 \
  golang:1.22-alpine sh -c "go mod tidy && go build -o tgdesk-host.exe ."
```
