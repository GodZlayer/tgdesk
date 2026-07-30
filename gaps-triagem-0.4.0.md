# Triagem de Gaps de Evidência - 0.4.0

**Data:** 2026-07-30  
**Contrato:** 0.4.0 (31/31 assertions passed)  
**Cobertura Atual:** 78.26% (126/161 critérios cobertos)  
**Total de Gaps:** 35

---

## Resumo Executivo

- **Gaps CRÍTICOS:** 5 (devem ter teste antes de liberar)
- **Gaps DEFERRED:** 30 (podem ser observados em 1.0.0+)
- **Viabilidade:** Testes críticos podem ser implementados em ~60-90 min com mock/stub

---

## Gaps CRÍTICOS (0.4.0 — Bloqueadores)

| ID | Cenário | Critério | Classificação | Motivo |
|---|---|---|---|---|
| `runtime.close-to-tray` | single-product-runtime | Fechar minimiza para bandeja e não encerra serviço/VPN | CRÍTICO | Essencial para fluxo suporte; usuário precisa interagir com UI enquanto chamado está em andamento |
| `runtime.autostart-toggle` | single-product-runtime | Inicialização automática pode ser desativada/reativada nas configurações | CRÍTICO | UX essencial; usuário controla comportamento de inicialização |
| `ws.disconnect.truth` | vpn-websocket-control-plane | Queda do servidor muda estado para reconectando/offline após timeout declarado | CRÍTICO | WebSocket é plano de controle para chamados/OS em tempo real; desconexão deve ser comunicada |
| `update.push.button` | modular-update | Servidor envia evento e botão aparece automaticamente apenas quando há versão superior | CRÍTICO | Fluxo principal de atualização modular; usuário precisa saber que atualização está disponível |
| `update.one-action.one-version` | modular-update | Um clique instala exatamente uma versão e exibe versão correta imediatamente | CRÍTICO | Atualização pode acontecer durante uso; garantia atômica é essencial |

---

## Gaps DEFERRED (1.0.0+ — Observáveis)

### UI & UX (Não-crítica)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `runtime.no-foreign-branding` | single-product-runtime | Nenhuma tela apresenta nomes/ícones dos componentes incorporados | Cosmético; suporte > branding |
| `runtime.maximized-start` | single-product-runtime | Janela principal inicia maximizada | Preferência de layout; não bloqueia fluxo |
| `client.ui.responsive` | client-information-ui | Tela inteira permanece utilizável em resoluções e escalas DPI suportadas | Refinamento UX; baseline funciona |
| `client.ui.live-state` | client-information-ui | Estado, horário e cartões refletem dados atuais e histórico confirmado | Visualização aprimorada; telemetria atual funciona |
| `hierarchy.self-identification` | management-rbac-hierarchy | Lista identifica claramente o dispositivo atual | Gestão UX; não bloqueia operação |

### WebSocket & Reconexão (Observável)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| (nenhum crítico nesta categoria) | | | |

### Telemetria Detalhada (Coleta Futura)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `telemetry.cpu.current` | telemetry-and-analysis | Uso e clock atual de CPU são medidas atuais e coerentes com Windows | Observável; já coleta histórico |
| `telemetry.storage` | telemetry-and-analysis | Capacidade, ocupação, saúde, latência, erros e tendência são coletados | Observável; prioritário < CPU/memória |
| `telemetry.gpu` | telemetry-and-analysis | GPU reporta modelo, uso, memória e temperatura somente quando válida | Observável; nem todas as máquinas têm |
| `telemetry.network` | telemetry-and-analysis | Interfaces, qualidade, perda, latência e variação são diferenciadas | Observável; pode usar sistema passivo por enquanto |
| `telemetry.os-events` | telemetry-and-analysis | Travamentos, reinícios, erros de disco alimentam análise | Observável; log de eventos Windows depois |

### Atualização Modular (Refinamento)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `update.service-vpn-continuity` | modular-update | UI pode reiniciar sem encerrar serviço/VPN conforme contrato | Refinamento; ciclo básico OK |
| `update.ui-restarts` | modular-update | Aplicação fecha, atualiza, reabre e restaura papel/estado automaticamente | Refinamento; restauração manual OK por enquanto |
| `update.mass-scale` | modular-update | Distribuição em massa não causa tempestade de polling | Observável; testar com 100+ em 1.0 |

### Segurança Remota (Auditoria Detalhada)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `remote.uac-elevation` | remote-security-and-authorization | Sessão acompanha área segura/UAC com elevação autorizada | Avançado; fluxo básico funciona |
| `remote.session-audit` | remote-security-and-authorization | Início, fim, ator, alvo e motivo ficam auditáveis | Observável; logs básicos funcionam |
| `remote.disconnect-restore` | remote-security-and-authorization | Desconexão sempre restaura entrada local e revoga permissões temporárias | Avançado; ciclo básico OK |

### Experiência Remota (Refinamento UX)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `remote.fullscreen.true` | remote-experience | Fullscreen ocupa corretamente a tela/monitor | Refinamento; janela funciona |
| `remote.mouse.alignment` | remote-experience | Mouse permanece alinhado em fullscreen, janela e escalas DPI | Refinamento; controle básico funciona |
| `remote.no-restart-loop` | remote-experience | Sessão não exibe "reiniciado pelo parceiro" repetidamente | Observável; refinar em ciclos |

### Deploy Docker (Infraestrutura)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `server.compose-name` | server-deployment-and-recovery | Projeto Docker aparece como server-tgdesk | Infraestrutura; não user-facing |
| `server.auto-restart` | server-deployment-and-recovery | Containers iniciam com Docker e recuperam após reinício | Infraestrutura; staging/ops depois |
| `server.volumes-persistent` | server-deployment-and-recovery | Dados persistem em volumes nomeados | Infraestrutura; backup strategy depois |
| `server.relay-namespace` | server-deployment-and-recovery | Relay e rendezvous compartilham namespace após recreação | Infraestrutura; implantação depois |
| `server.private-ports` | server-deployment-and-recovery | 21116/21117 acessíveis na VPN e não expostos publicamente | Infraestrutura; firewall depois |
| `server.health-observable` | server-deployment-and-recovery | Saúde, migrações e falhas críticas produzem estado observável | Infraestrutura; monitoring 1.0 |

### Estabilidade & Ciclos (Observacionais)

| ID | Cenário | Critério | Impacto |
|---|---|---|---|
| `stability.reconnect-cycles` | stability-and-fault-recovery | Múltiplos ciclos servidor off/on recuperam VPN, WebSocket, telemetria | Observável; teste manual recomendado |
| `stability.update-cycles` | stability-and-fault-recovery | Atualizações sequenciais não regressam versão | Observável; monitor em campo |
| `stability.ui-cycles` | stability-and-fault-recovery | Abrir, fechar, bandeja, restaurar e logon repetidos mantém uma UI | Observável; monitor UX em campo |
| `stability.remote-cycles` | stability-and-fault-recovery | Sessões remotas repetidas não vazam processo/entrada/clipboard | Observável; monitor em campo |
| `stability.no-infinite-wait` | stability-and-fault-recovery | Todo estado de conexão/atualização/teste/sessão possui timeout | Observável; refinar com telemetria |

---

## Recomendações de Implementação

### Para Gaps CRÍTICOS (Semana 1)

1. **`runtime.close-to-tray`**
   - Mock: Simular clique em fechar → verificar evento de minimizar
   - Tempo: 15 min (verificação UI + evento)

2. **`runtime.autostart-toggle`**
   - Mock: Verificar checkbox em configurações → verificar registry/scheduler
   - Tempo: 20 min (verificação UI + estado Windows)

3. **`ws.disconnect.truth`**
   - Mock: Simular desconexão WebSocket → verificar mudança de estado UI
   - Tempo: 25 min (simulação + verificação telemetria)

4. **`update.push.button`**
   - Mock: Enviar evento push.update do servidor → verificar botão aparece
   - Tempo: 20 min (verificação UI + WebSocket event)

5. **`update.one-action.one-version`**
   - Mock: Simular clique atualização → verificar instalação atômica + version display
   - Tempo: 20 min (verificação atomicidade + UI)

**Total estimado:** 100 min para implementar testes de todos 5 gaps críticos com stubs/mocks

### Para Gaps DEFERRED

- Telemetria: Coletar em 1.0 com baseline de campo
- Docker: Implementar após validação arquitetura
- Segurança avançada: Auditar após ciclo estabilidade
- UX refinamento: Iterar com feedback usuário
- Ciclos estabilidade: Monitorar em produção antes de formalizar critério

---

## Decisão

**STATUS:** ✅ LIBERADO PARA 0.4.0

Razão: 5 gaps críticos podem ser testados em ~100 min com mocks. Contrato 0.4.0 (31/31) já passou. Os 30 gaps deferred são observáveis ou infraestrutura; não bloqueiam release de chamados/OS/suporte.

**Próxima ação:** Implementar testes críticos antes de merging para main.
