# Objetivo: Implementação v1.1.0 - Refatorações + Features

**ID**: obj-20260730-implementation-v110  
**Data**: 2026-07-30  
**Status**: Em execução  
**Escopo**: Refatorações estruturais + novas features (testes manuais depois)

## Objetivo Principal
Implementar v1.1.0 completo com refatorações críticas + 35 features em paralelo

## ⚠️ MODELO DE PAPÉIS — AUTORITATIVO (qualquer worker DEVE seguir)

Conjunto FINAL e EXATO de roles (5, nem mais nem menos):

| role | descrição |
|------|-----------|
| `super_admin` | o Admin. Gerente geral de tudo. Superconjunto de supervisor. |
| `supervisor` | admin da PRÓPRIA org + redes + subredes. **É o antigo `tecnico` renomeado.** |
| `cliente` | preso/vinculado a um supervisor. Sem uso operacional — só instalação/ser atendido. |
| `freelancer` | o "tech" novo. Atende chamados/serviços avulsos. Sem org e sem rede próprias. |
| `cliente_avulso` | não participa de rede nem de org. Só abre chamado. |

**`tecnico` NÃO EXISTE MAIS.** Ele virou `supervisor` (rename, não papel novo).
Ele NÃO é subordinado do supervisor.

Estrutura:
- Hierarquia base (cascata): `super_admin > supervisor > cliente`
- Avulsos, fora da hierarquia, respondem só ao super_admin: `freelancer`, `cliente_avulso`

Regra obrigatória do produto: **toda função de supervisor existe também para super_admin.**

Cascata de suspensão: suspender supervisor → org → redes → subredes → dispositivos.

## Fases de Implementação

### FASE 1 - CRÍTICO (Bloqueia tudo) [PARALELO - 3 workers]
**Objetivo**: Estrutura base para todas features futuras

| Worker | Status | Descrição | Blocker |
|--------|--------|-----------|---------|
| impl-db-schema-v110 | pending | DB Schema: estender papéis (Supervisor, Freelancer, Cliente), migrations 0026-0030 | SIM |
| impl-rbac-authorization | pending | RBAC Authorization: refatorar auth.go, middleware, centralizar permissões | SIM |
| impl-repository-layer | pending | Repository Layer: abstrair 89 queries inline, implementar DAO pattern | SIM |

### FASE 2 - Despacho [SERIAL após Fase 1]
| Worker | Status | Descrição |
|--------|--------|-----------|
| impl-dispatch-queue | pending | Job Queue Manager: despacho dinâmico, fila, rank (geoloc+quality) |

### FASE 2b - Features Paralelo [PARALELO após Fase 1]
| Worker | Status | Descrição |
|--------|--------|-----------|
| impl-photos-signature | pending | Fotos + Assinatura: backend + Flutter UI |
| impl-geolocation | pending | Geolocalização: device tracking + API |
| impl-print-export | pending | Impressão + Export: PDF, assinatura digital |

### FASE 3 - Cliente Avulso [SERIAL após Fase 2]
| Worker | Status | Descrição |
|--------|--------|-----------|
| impl-standalone-client | pending | Cliente Avulso: novo role, schema, API pública |
| impl-public-tickets | pending | Chamado Público: interface cliente avulso |

### FASE 4 - UI + Testes Manuais [SERIAL]
| Worker | Status | Descrição |
|--------|--------|-----------|
| impl-ui-refinement | pending | UI: fullscreen perfeito, design refinement |
| test-manual-coverage | pending | Testes manuais: usuario faz depois |

## Features por Versão

**v0.4.1** (3 features):
- Copy/paste integrado
- Desabilitar mouse/teclado
- Sistema de desenhar (caneta, borracha)

**v0.4.2** (8 features):
- Testes de dispositivo
- Branding para tech
- Logs visuais
- Testes remotos interativos

**v1.0.0** (8 features):
- Novo hierarquia + papéis
- Tech → Supervisor
- Tech Freelancer
- Fila dinâmica
- Geoloc + foto + assinatura

**v1.1.0** (6 features):
- Cliente avulso
- Chamado virtual/presencial
- Acesso temporal

**Fixes** (7 features):
- Favicon
- Crop/redimensionar
- Cascata suspensão
- Nomeação rules
- Fullscreen real

## Histórico
- [2026-07-30 ~14:30] Objetivo criado, Fase 1 (3 workers críticos) pronto para despacho
