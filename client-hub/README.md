# TGDesk Hub — Interface Admin/Técnico

`tgdesk_hub.exe`: aplicativo Flutter **separado** do RustDesk (mesmo projeto/
toolchain, entrypoint próprio em `flutter/lib/tgdesk_main.dart`, sem depender
do núcleo Rust/FFI do RustDesk) que implementa a Seção 7 do plano de
arquitetura: login do técnico, árvore de dispositivos com presença em tempo
real, pareamento, kill-switch e gestão de técnicos.

## As duas versões do RustDesk dentro do TGDesk

O plano usa o núcleo do RustDesk em dois papéis bem separados:

| Build | Onde roda | Papel |
|---|---|---|
| `client-remote/rustdesk.exe` (+ `client-host/rustdesk.exe`, cópia idêntica) | Máquina do **Host** (cliente final), lançado pelo `tgdesk-host.exe` | Lado **servidor** da sessão — tela/input, sempre com notificação visual obrigatória |
| `client-hub/tgdesk_hub.exe` (este) | Máquina do **Técnico** | Lado **administrativo** — não é o visualizador RustDesk em si, é o Hub que decide *quem* o técnico pode acessar (RBAC) e *dispara* a sessão |

Hoje o botão "conectar" ainda **não está** ligado ao viewer do RustDesk dentro
do Hub — falta essa integração (rodar `rustdesk.exe <rustdesk_id>` a partir do
Hub, dentro da mesma janela ou como processo filho). Por enquanto, o técnico
vê o `rustdesk_id` do dispositivo na árvore e conecta manualmente com
`client-remote/rustdesk.exe <id>`. É o próximo passo natural.

## Túnel WireGuard próprio do Técnico

Como o hbbs/hbbr agora só respondem dentro da VPN (ver `server/README.md`), o
Hub precisa do seu próprio vínculo de rede — **independente** de qualquer
`tgdesk-host.exe` que esteja instalado na mesma máquina física. Por isso, após
o login, o Hub lança `tgdesk-tunnel.exe` (bundlado aqui, código-fonte em
`../client-tunnel/`) passando o JWT do técnico. Esse helper:

- Registra uma chave WireGuard **própria** do técnico (`POST /api/v1/technicians/wg-key`),
  alocada num pool de IP reservado (`10.70.1.x`) — distinto do pool das redes
  de cliente (`10.70.2.x` em diante).
- Sobe um adaptador de rede com nome próprio (`tgdesk-tech0`), diferente do
  adaptador do Host (`tgdesk0`) — os dois podem coexistir na mesma máquina
  Windows sem disputar o mesmo vínculo.
- Assim como o túnel do Host, a primeira vez exige o Hub rodando como
  Administrador (driver Wintun). Testado nesta sessão: registro da chave e
  alocação de IP funcionam via HTTP normalmente mesmo sem elevação; só a
  criação do adaptador em si exige admin.

Validado nesta sessão: rodando `tgdesk-host.exe` e `tgdesk-tunnel.exe` ao
mesmo tempo na mesma máquina, cada um recebeu IP virtual de pool diferente
(`10.70.6.x` vs `10.70.1.x`) sem nenhum conflito entre os dois processos.

## Telas implementadas

- **Login**: autentica contra `POST /api/v1/auth/login`, guarda o JWT em memória.
- **Dispositivos**: árvore Organização → Rede → Dispositivo, com bolinha de
  presença (verde=online, cinza=offline, azul=guest, vermelho=suspenso),
  atualizada em tempo real via `GET /ws/presence`. Botão flutuante para
  vincular um dispositivo por código de pareamento.
- **Admin** (só Super Admin): organizações/redes com kill-switch por rede ou
  organização inteira, criação de organização/rede, e aba de auditoria
  (`admin_actions`).
- **Técnicos** (só Super Admin): listar, criar técnico, atribuir
  organização/rede, kill-switch por técnico.

## Rodar

```bash
./tgdesk_hub.exe
```

Tela de login pede o endereço do servidor (padrão `http://127.0.0.1:8090`,
pode trocar em runtime) + usuário/senha.

## Recompilar

```bash
cd ../client-rustdesk-src/flutter
flutter build windows --release --target lib/tgdesk_main.dart
```

**Atenção**: o nome do `.exe` de saída é sempre `rustdesk.exe` (definido em
`windows/runner/main.cpp`, não pelo `--target`) — depois de compilar, copie
a pasta `build/windows/x64/runner/Release/` para cá e renomeie para
`tgdesk_hub.exe` **antes** de compilar o outro alvo (senão um build sobrescreve
o outro, os dois compartilham a mesma pasta `build/`).
