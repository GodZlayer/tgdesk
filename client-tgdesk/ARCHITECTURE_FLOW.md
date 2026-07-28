# System Design — Host vs. Técnico no mesmo `tgdesk.exe`

## 1. Requisitos

**Funcional**
- Um único executável instalável serve os dois papéis (Seção 6/7 do plano de arquitetura).
- Sem login: máquina se comporta como Host — registra, pareia, sobe túnel WireGuard próprio, serve sessões RustDesk recebidas. Interface mínima.
- Com login de técnico: desbloqueia o Hub (árvore de dispositivos, suspensão/reativação, gestão de técnicos) na mesma janela de processo, **sem desligar** as capacidades de Host que já estivessem ativas na mesma máquina.
- Os dois papéis podem estar ativos **ao mesmo tempo, na mesma máquina física**, sem conflito de rede (ver Seção 4).

**Não-funcional**
- Nenhuma sessão de tela/relay/USB-IP trafega fora da VPN (decisão já tomada e implementada — Seção 8).
- Custo de banda de desenvolvimento: reaproveitar ao máximo o que já existe (núcleo RustDesk, `internal/wg` em Go) em vez de reescrever em outra linguagem.

**Restrições**
- Toolchain: Flutter/Dart + Rust (núcleo RustDesk) já compilados e funcionando; Go só para os agentes de rede (túnel WireGuard), por decisão já tomada nesta sessão de trabalho.
- Criar um adaptador WireGuard exige privilégio de Administrador no Windows (driver Wintun) — restrição do SO, não do design.

## 2. Desenho de alto nível

```
┌─────────────────────────────── tgdesk.exe (um processo) ───────────────────────────────┐
│                                                                                          │
│  ┌──────────────────────┐        desktop_multi_window         ┌─────────────────────┐  │
│  │   Janela Main         │ ───── (mesmo processo, nova   ───▶ │  Janela TgdeskHub    │  │
│  │   (núcleo RustDesk:   │        FlutterView, sem FFI)        │  (Dart puro, sem     │  │
│  │   captura de tela,    │ ◀──── botão "engrenagem admin" ──── │  FFI do RustDesk)    │  │
│  │   input, viewer)      │                                     │  Login/Devices/      │  │
│  └──────────┬────────────┘                                     │  Admin/Técnicos      │  │
│             │ sempre roda,                                     └──────────┬───────────┘  │
│             │ com ou sem login                                            │ login OK      │
│             ▼                                                             ▼               │
└─────────────────────────────────────────────────────────────────────────────────────────┘
              │ spawn (processo filho gerenciado pelo próprio tgdesk.exe)   │ spawn
              ▼                                                             ▼
   tgdesk-agent.exe host                                    tgdesk-agent.exe technician --token JWT
   (Go: registra device_id,                                 (Go: registra wg_pubkey do TÉCNICO,
    pareamento, heartbeat,                                   adaptador "tgdesk-tech0", IP 10.70.1.x)
    adaptador "tgdesk0",
    IP 10.70.2.x+)
              │                                                             │
              └──────────────────────────┬──────────────────────────────────┘
                                          ▼
                          api-core (plano de controle, sempre HTTP/WS
                          direto — não depende do túnel) + hub WireGuard
                          (plano de dados: hbbs/hbbr só respondem em 10.70.0.1)
```

## 3. Limites entre os dois papéis

| | Host (sem login) | Técnico (após login) |
|---|---|---|
| **Identidade de rede** | `devices` (device_id + device_token, nasce em `guest`) | `technicians` (technician_id + JWT) |
| **Adaptador WireGuard** | `tgdesk0`, pool `10.70.2.x+` (por Rede/Loja) | `tgdesk-tech0`, pool `10.70.1.x` (reservado p/ técnicos) |
| **Processo Go responsável** | `tgdesk-agent.exe host` | `tgdesk-agent.exe technician` |
| **UI exposta** | Mínima — só o necessário do RustDesk original (ID, notificação de sessão ativa) | Hub completo (janela `TgdeskHub`) |
| **Núcleo RustDesk** | Ativo desde o boot (é o próprio `tgdesk.exe`) — sempre pronto para servir uma sessão | Mesmo núcleo, mas o técnico o usa como *viewer* (ainda não conectado à árvore do Hub — ver pendência abaixo) |
| **Suspensão afeta** | `devices.state` + peer do hub (`wg_pubkey` do device) | `technicians.status` + peer do hub (`wg_pubkey` do technician) — **listas totalmente separadas**, suspender um não afeta o outro |

**Ponto-chave de design**: os dois papéis nunca competem pelo mesmo recurso porque cada um tem (a) sua própria linha na tabela certa (`devices` vs `technicians`), (b) seu próprio par de chaves WireGuard, (c) seu próprio nome de adaptador de rede, e (d) seu próprio pool de IP virtual. É isso que permite a mesma máquina física rodar os dois ao mesmo tempo — validado nesta sessão (Task #39: Host recebeu `10.70.6.8`, Técnico recebeu `10.70.1.2`, simultâneos, sem conflito).

## 4. Transições

1. **Boot do `tgdesk.exe`** → sempre lança `tgdesk-agent.exe host` em segundo plano (pendente: hoje isso ainda não está automatizado dentro do exe único, ver Seção 6).
2. **Usuário clica no ícone de admin** → abre janela `TgdeskHub` (mesmo processo) → tela de login.
3. **Login bem-sucedido** → Hub lança `tgdesk-agent.exe technician --token <jwt>` → adaptador `tgdesk-tech0` sobe (se admin) → árvore de dispositivos populada via `GET /api/v1/devices` + `WS /ws/presence`.
4. **Logout** → fecha a janela do Hub; o agente `technician` deveria ser encerrado também (pendência: hoje ele fica órfão rodando — precisa de um sinal de shutdown).
5. **Suspensão de um técnico** → `dropTechnicianHubPeer` derruba o peer no hub → a próxima tentativa de tráfego do `tgdesk-tech0` deixa de ser aceita, preservando o cadastro para posterior reativação.

## 5. Trade-offs explícitos

| Decisão | Ganho | Custo |
|---|---|---|
| WG em Go (processo filho) em vez de reescrever em Rust dentro do núcleo | Reaproveita código já testado (Fase 1/2 desta sessão); zero risco de regressão no núcleo RustDesk | Um processo filho a mais por papel ativo; requer que `tgdesk.exe` gerencie ciclo de vida (start/stop) desses processos — ainda não implementado |
| Hub como janela `desktop_multi_window` em vez de app Flutter separado | Um exe só de verdade, sem duplicar build; reaproveita infra que o próprio RustDesk já usa e testa | Janela do Hub não tem acesso direto ao FFI do RustDesk — abrir uma sessão a partir do Hub ainda exige lançar/coordenar com a janela `RemoteDesktop` existente (não implementado) |
| Pools de IP separados por papel (10.70.1.x técnico / 10.70.2.x+ redes) | Isolamento sem esforço extra de RBAC na camada de rede | Técnico assinado a múltiplas redes hoje só alcança o hub (10.70.0.1), não os devices diretamente — suficiente enquanto RustDesk usa relay (hbbr), insuficiente se algum dia quisermos P2P direto técnico↔host |

## 6. O que revisitar conforme o sistema cresce

1. ~~**Consolidação dos agentes Go**~~ — feito: `client-host` + `client-tunnel` viraram um binário só, `client-agent/tgdesk-agent.exe` (`host` padrão / `technician --token X`). Ainda pendente dentro disso: `tgdesk.exe` não inicia o `host` automaticamente nem encerra o `technician` no logout do Hub.
2. **Conectar Hub ↔ viewer**: o botão "conectar" na árvore de dispositivos ainda não abre uma janela `RemoteDesktop` de verdade usando o `rustdesk_id` do device.
3. **Múltiplas redes por técnico**: se um dia precisarmos de P2P direto (sem relay), o AllowedIPs do técnico precisa crescer de `10.70.0.1/32` para o CIDR de cada rede atribuída — hoje não é necessário porque tudo passa pelo hbbs/hbbr.
4. **Um técnico y um Host na mesma sessão de login do Windows**: não testamos dois USUÁRIOS do Windows diferentes na mesma máquina (só processos concorrentes do mesmo usuário) — se o Host rodar como serviço do Windows (LocalSystem) no futuro, o isolamento de `%APPDATA%` muda e precisa revisão.
