# Acesso remoto (client/técnico em outra internet)

Por padrão o servidor só respondia em `127.0.0.1` (localhost) — por isso um
client em outra rede recebia *"conexão recusada"* e ficava preso em "aguardando
agente". Isto foi corrigido: o servidor agora escuta em `0.0.0.0` e os clients
apontam para o **IP público**. Mas duas coisas dependem da SUA infraestrutura:

## 1. Portas que precisam chegar até esta máquina

Seu IP público hoje: **168.232.199.161** (definido em `server/.env` → `HUB_PUBLIC_ADDR`).

| Porta | Protocolo | Para quê |
|---|---|---|
| **8090** | TCP | Plano de controle (login do técnico, registro/heartbeat do client, WebSocket de presença) |
| **41820** | UDP | Hub WireGuard (túnel de dados: tela remota, etc.) |

O relay RustDesk (hbbs/hbbr) **não** precisa de porta pública — ele só é
alcançado por dentro do túnel WireGuard (decisão de "VPN-only").

## 2. O que configurar

1. **Port-forward no roteador** → encaminhar `8090/TCP` e `41820/UDP` do IP
   público para o IP local desta máquina (a que roda o Docker).
2. **Firewall do Windows** → liberar entrada em `8090/TCP` e `41820/UDP`
   (o Docker Desktop costuma criar as regras, mas confirme). Exemplo (PowerShell admin):
   ```powershell
   New-NetFirewallRule -DisplayName "TGDesk control 8090" -Direction Inbound -Protocol TCP -LocalPort 8090 -Action Allow
   New-NetFirewallRule -DisplayName "TGDesk hub 41820"    -Direction Inbound -Protocol UDP -LocalPort 41820 -Action Allow
   ```
3. Confirme de fora: de outra rede, `http://168.232.199.161:8090/healthz` deve
   responder `{"status":"ok"}`.

## Se o IP público mudar

O IP está em dois lugares que precisam bater:
- `server/.env` → `HUB_PUBLIC_ADDR=<novo-ip>:41820` (e `docker compose up -d api-core`)
- Build dos clients → `--dart-define=TGDESK_SERVER=http://<novo-ip>:8090`

O técnico ainda pode digitar outro servidor no campo "Servidor" da tela de
login. O client (portátil/instalado) usa o endereço embutido no build.

## Alternativa sem IP público / port-forward

Se um dia não puder abrir portas, dá pra expor o controle (8090) por um túnel
(cloudflared/ngrok) — mas o hub WireGuard (41820/UDP) ainda precisa de um
endpoint UDP alcançável, então o túnel HTTP sozinho não cobre o plano de dados.
Nesse caso o mais simples continua sendo o IP público com as duas portas.
