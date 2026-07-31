# Mapa de gaps — requisitos v1.1.0 vs. código atual

Auditoria por evidência (arquivo:linha), 2026-07-30. 48 itens de [REQUISITOS-V110.md](REQUISITOS-V110.md).

**Placar: 24 implementados · 18 parciais · 6 ausentes**

---

## ✅ Blocos prontos (não mexer)

| Bloco | Itens | Nota |
|---|---|---|
| **B — branding white-label** | B1–B6 | Flag por técnico só-admin, auto-habilitação bloqueada com 403, isolamento tech/cliente correto, volume Docker |
| **D — acesso remoto avançado** | D1–D3 | Módulo Rust `src/whiteboard/` próprio; atalhos; padrão desativado forçado no initState |
| **E — nomeação** | E1–E4 | Propagação device→tech→org atômica em uma tx |
| **F — cascata de suspensão** | F1–F2 | Propaga status + sessions + credenciais + presence + peer WireGuard |

---

## 🔴 Ausentes (6)

| Item | O que falta | Onde |
|---|---|---|
| **G4** | Dados técnicos/localização estruturados no chamado. Hoje é um `TextField` livre enviado como `description` | support_page.dart:210-237 |
| **G7** | Interface própria do freelancer. Não existe `freelancer_*.dart`; é if/else na tela do supervisor e `bootstrap_page.dart:112` devolve `HubHomePage` para qualquer técnico | flutter/lib/tgdesk/ |
| **G9** | Conectividade VPN do freelancer. `CreateFreelancer` não emite peer WireGuard nem vincula rede | support.go:289 / wg/hub.go |
| **H6** | Execução de teste/diagnóstico dentro do chamado. Flag `allow_analysis` existe, endpoint não | support_page.dart:164 |
| **I5** | Fullscreen real. `windowId=-1` → `fromWindowId(-1).setFullscreen()` é no-op | state_model.dart:11,104 |
| **I6** | Barra dupla. `DesktopTab` sem guarda de `embedded` + `RemoteToolbar` sobreposta | remote_tab_page.dart:140 |

**I5 e I6 têm raiz única:** a sessão roda embedded na janela principal.

---

## 🟡 Parciais (18) — por gravidade

### Bloqueiam a v1.0.0
| Item | Diagnóstico |
|---|---|
| **G6** | Escalonamento existe e é dinâmico (`available_at = now + rank*30s`, filtro lazy por query). Mas **não há scheduler**: oferta nunca expira, ticket trava em `offered` para sempre, sem re-despacho nem push |
| **C3** | **Enums divergentes**: servidor tem `accepted/in_progress/reopened`, Flutter tem `assigned/awaitingClient/completed`. `ticketStateFromServer` casa por nome → caem em `open`. Tela mostra estado errado |
| **C2** | 3 ações centrais são `onPressed: () {}` — Acesso temporário, Testes autorizados, Comprovações |
| **G10** | Schema cobre os 4 tipos de evidência; UI é diálogo estático com `onPressed: null`. Sem GPS, câmera, canvas de assinatura, PDF ou impressão |
| **G8** | Conflito: `0026` exige `supervisor_id IS NULL` para freelancer vs. `freelancer_profiles.supervisor_id NOT NULL`. **Em correção** |

### Qualidade do produto
| Item | Diagnóstico |
|---|---|
| **A2** | `badblocks` **explicitamente proibido** em `ui_contract.dart:129` (`forbiddenStorageTests`). GPU é `winsat d3d` sem métrica. `memory_integrity` testa só 128MB. Tudo Windows-only |
| **A3** | Grava só o resultado final; progresso é sobrescrito. Sem tabela de amostras |
| **A4** | Sem gráfico — consequência direta de A3, não há série temporal para plotar |
| **G5** | `haversine()` real, mas lat/lon vêm do body do dispatch e não de `ticket.location`; `quality_score` nunca é recalculado |
| **H1** | Role existe no banco e no authorizer; **nenhum handler cria ou autentica** cliente_avulso. Fluxo real é anônimo por `device_token` |
| **H5** | Permissão temporária só nasce se `standalone && virtual`; cliente normal em chamado virtual nunca ganha acesso. 4h hardcoded |
| **H3** | Rede "Pública isolada" com `cidr_virtual=NULL` — não é VPN |
| **C1** | "Abrir chamado" foi acrescentado ao relatório de hardware; orientação antiga apenas comentada, não substituída |
| **G3** | `ListDevices` não usa o Authorizer; hoje devolve vazio por acidente (freelancer não tem assignment) |
| **G1** | `devices.subnetwork_id` NULLABLE com `ON DELETE SET NULL` → permite device órfão de subrede |
| **I4** | Mecanismo de visibilidade correto; **org "tgdevs" não existe** em lugar nenhum, depende de vínculo manual |
| **I1** | `favicon_base64` chega no cliente e é descartado — ninguém escreve `%ProgramData%\TGDesk\branding\favicon.ico`, que `tray.rs:299` lê. Só bandeja, sem janela/exe |
| **I2** | Crop+resize+preview só para o favicon. Logo sem crop; preview 180×110 vs. render real 72×25 |

---

## Defeitos fora do checklist (achados na auditoria)

- `subnetworks.status` não participa de nenhuma cascata — status mente
- `SuspendNetwork` sem transação e com erro de query ignorado (admin.go:160); `SuspendSubnetwork` faz certo
- Anotação (D2) trafega piggyback no canal de **chat**, 1 msg por segmento, sem throttle
- D1 falha silenciosamente se o cliente não tiver `enable-block-input` + `sas_enabled` (sem feedback na UI)
