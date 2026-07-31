# Objetivo: Remover TGDESKLAB e recompilar v0.4.1

**ID**: obj-20260730-remover-tgdesklab  
**Data**: 2026-07-30  
**Status**: Em execução  
**Autorização**: ✅ Confirmado pelo usuário

## Objetivo
1. Remover TGDESKLAB/testlab do código fonte completamente
2. Remover referências em workflows, docker, configs
3. Recompilar v0.4.1 (sem testlab)
4. Criar e executar script PowerShell de limpeza do Windows
5. Atualizar TGDesk via módulo de update nativo

## Workers (fases de execução)

| Worker | Status | Descrição |
|--------|--------|-----------|
| remove-testlab-source | pending | Deletar testlab/ e subdiretórios |
| remove-testlab-refs | pending | Remover refs em workflows, docker, .godzmind |
| rebuild-v0.4.1 | pending | Recompilar binários v0.4.1 sem testlab |
| create-cleanup-script | pending | Gerar PowerShell cleanup script |
| execute-windows-cleanup | pending | Executar limpeza no Windows |
| execute-modular-update | pending | Atualizar TGDesk via módulo nativo |

## Histórico
- [2026-07-30 ~12:50] Objetivo criado, 6 workers despachados em paralelo
