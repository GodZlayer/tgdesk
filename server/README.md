# TGDesk — Servidor Central

`docker-compose` com `api-core` (Go) + `postgres` + `redis` + `rendezvous`/`relay`
(hbbs/hbbr do RustDesk, compilados do zero em `rendezvous.Dockerfile`).

Implementado: Fase 0 (RBAC, estado `guest`, pareamento, suspensão/reativação +
auditoria), Fase 1 (wg-orchestrator com túnel WireGuard real via
wireguard-go — `internal/wg/`), e Fase 2 (rendezvous/relay próprios +
integração do `rustdesk_id` ao `device_id`).

**Plano de dados 100% dentro da VPN**: `rendezvous`/`relay` rodam com
`network_mode: "service:api-core"` — compartilham o network namespace onde
vive a interface WireGuard (`wg0`, `10.70.0.1`) e **não têm porta própria
publicada no host**. Só são alcançáveis por quem já está dentro do túnel
(estilo Hamachi: cada Rede é uma sub-rede virtual isolada; nenhum tráfego de
sessão remota ou USB/IP trafega fora da VPN). Isso significa que testar uma
sessão RustDesk de verdade exige o `tgdesk-host.exe` rodando com privilégio de
administrador (para o driver Wintun criar o adaptador) — sem isso, o
dispositivo pareia e aparece no Hub normalmente, mas o túnel de dados não sobe.

Ainda não implementado: USB/IP (Módulo C) e telemetria real (Módulo D) —
ambos devem, pelo mesmo princípio, trafegar exclusivamente dentro da VPN
quando forem construídos.

## Subir o servidor

```bash
cd server
cp .env.example .env   # ajuste JWT_SECRET, TECH_USERS, TECH_ASSIGN, SEED_ORGANIZATIONS
docker compose up -d --build
docker compose logs -f api-core
```

A API fica em `http://localhost:8090`. `postgres`/`redis` não são expostos
ao host, apenas à rede interna do compose.

## Fluxo de teste manual

```bash
# login
curl -s -X POST localhost:8090/api/v1/auth/login -d '{"username":"joao","password":"senhaForte123"}'

# registrar um device (estado guest, sem auth)
curl -s -X POST localhost:8090/api/v1/devices/register -d '{"hostname":"PC-01","mac":"AA:BB:CC:00:11:22"}'

# vincular (bind) usando o pairing_code retornado acima e um network_id existente
curl -s -X POST localhost:8090/api/v1/pairing/bind -H "Authorization: Bearer $TOKEN" \
  -d '{"pairing_code":"XXXXXX","network_id":"<uuid>"}'

# heartbeat do device já vinculado
curl -s -X POST localhost:8090/api/v1/devices/heartbeat -d '{"device_id":"<uuid>","device_token":"<token>"}'

# listar devices (RBAC-filtrado pelo token do técnico)
curl -s localhost:8090/api/v1/devices -H "Authorization: Bearer $TOKEN"

# suspender e reativar preservando o vínculo (somente super_admin)
curl -s -X POST localhost:8090/api/v1/admin/suspend/device/<uuid> -H "Authorization: Bearer $TOKEN"
curl -s -X POST localhost:8090/api/v1/admin/resume/device/<uuid> -H "Authorization: Bearer $TOKEN"
curl -s localhost:8090/api/v1/admin/audit -H "Authorization: Bearer $TOKEN"

# presença em tempo real (WebSocket)
websocat "ws://localhost:8090/ws/presence?token=$TOKEN"
```

## Endpoints

| Método | Rota | Auth |
|---|---|---|
| POST | `/api/v1/auth/login` | público |
| POST | `/api/v1/devices/register` | público (device nasce em `guest`) |
| POST | `/api/v1/devices/heartbeat` | device_token |
| GET | `/ws/presence` | JWT (query `?token=`) |
| POST | `/api/v1/pairing/bind` | técnico (RBAC) |
| GET | `/api/v1/devices` \| `/organizations` \| `/networks` | técnico (RBAC) |
| POST | `/api/v1/organizations` \| `/networks` \| `/technicians` \| `/technicians/assignments` | super_admin |
| POST | `/api/v1/admin/suspend/{technician,device,network,organization}/{id}` | super_admin |
| POST | `/api/v1/admin/resume/{technician,device,network,organization}/{id}` | super_admin |
| GET | `/api/v1/admin/audit` | super_admin |
| POST | `/api/v1/devices/wg-key` | device_token — recebe IP virtual + config do hub + rendezvous |
| POST | `/api/v1/devices/rustdesk-id` | device_token — amarra o ID do RustDesk ao device_id |

## Reiniciar do zero

```bash
docker compose down -v   # apaga o volume do Postgres — use com cuidado
```
