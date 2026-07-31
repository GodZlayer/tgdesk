# Memória de Projetos GodZmind

## Estrutura por projeto

### TGDesk

**Tipo**: plataforma Windows de suporte, monitoramento e acesso remoto
**Tecnologia**: Go, Flutter/Dart, Rust, PowerShell, Inno Setup, PostgreSQL, Redis, Docker e Hyper-V
**Stack de Testes**: Go test em container, integração HTTP/WebSocket/VPN em Docker isolado, Hyper-V com Windows 11, automação de UI e testes prolongados
**Repositório**: C:\Users\santo\Documents\TGDESK

**Características Críticas**:
- Um único produto TGDesk com serviço, VPN, telemetria, atualização modular e acesso remoto integrados.
- Admin real existe exclusivamente no computador original; laboratório cria somente clientes e supervisores.
- Dados operacionais em tempo real trafegam pelo canal WebSocket dentro da VPN.
- Hierarquia de gestão: organização, rede, sub-rede e dispositivo.
- Papéis previstos: Admin, supervisor, freelancer técnico e cliente avulso.
- Atualização modular não pode derrubar serviço ou VPN fora do contrato declarado.

**Critérios de Sucesso Padrão**:
- Funcionalidade: todos os cenários do manifest de aceitação possuem evidência real aprovada.
- Cobertura de Testes: 100% dos critérios de aceitação e todas as rotas críticas; cobertura de código medida sem regressão abaixo do baseline estabelecido.
- Integração: HTTP público apenas para bootstrap/recuperação; operação privada validada via VPN e WebSocket.
- Estabilidade: zero crash crítico, zero espera infinita e execução prolongada com reconexão e atualização.
- Windows: comportamento visual e de interação validado em VMs reais, inclusive fullscreen, DPI, UAC, bandeja e reinício.
- Segurança: chaves de instalação de uso único, Admin único e RBAC com Admin como superconjunto.

**Último GodZmind**:
- Data: 2026-07-29
- Objetivo: atingir 100% funcional e estável em todo o escopo acumulado até a versão 1.1.0
- Fases: metodologia e gates por versão em reconstrução; infraestrutura CLI em andamento
- Status: em progresso

**Código Crítico**:
- Path: server/api-core/internal/handlers/control_ws.go
- Estado: em evolução
- Path: installers/stage-unified
- Estado: versão 0.3.48 ainda não promovida por este GodZmind

## Histórico Global de GodZmind

| Data | Projeto | Objetivo | Fases | Status |
|------|---------|----------|-------|--------|
| 2026-07-30 | TGDesk | Catalogar arquitetura completa (estrutura, componentes, dependências, build, config) | 6 workers: structure-tree, dependencies-map, build-configs, components-identify, config-catalog, code-analysis | ✅ CUMPRIDO |
| 2026-07-30 | TGDesk | Configurar Admin Master via Enrollment Key System | 6 workers: verify-super-admin, create-super-admin, generate-enrollment-key, revoke-previous-admin, redeem-enrollment-key-retry, save-machine-credentials | ✅ CUMPRIDO |
| 2026-07-30 | TGDesk | Instalar v0.4.0 com Docker 100% funcional, Admin Master | 5 workers CLI (verify-docker, create-volumes, env-setup, health-check, admin-master-setup) | ✅ CUMPRIDO |
| 2026-07-29 | TGDesk | Cobrir todo o gap de verificação funcional e de estabilidade | Parse e infraestrutura inicial | em progresso |
| 2026-07-29 | TGDesk | Atingir 100% funcional e estável até a versão 1.1.0 | Contratos versionados e workers CLI | em progresso |

## Notas operacionais

- Não marcar versão como estável com base apenas em compilação.
- Não criar VM Admin; o Admin real permanece somente no computador original.
- Cada falha precisa produzir evidência com estado e causa antes da próxima correção.
