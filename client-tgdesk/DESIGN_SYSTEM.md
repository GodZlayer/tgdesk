# Design System — TGDesk Hub

## Design System Audit

### Summary
**Componentes revisados:** 4 telas (Login, Dispositivos, Admin, Técnicos) | **Issues encontrados:** 4 | **Score:** 45/100

O Hub foi construído rápido para provar o pipeline ponta-a-ponta (servidor → API → UI), sem nenhum token compartilhado — cada tela define suas próprias cores/estilos inline.

### Naming Consistency
| Issue | Componentes | Recomendação |
|---|---|---|
| Cor de presença duplicada | `_presenceColor` só existe em `devices_page.dart`, mas `technicians_page.dart` reimplementa a mesma ideia (`suspenso ? Colors.grey : Colors.red`) com lógica própria | Extrair `presenceColor(String)` para `theme.dart`, usar em ambas |
| Diálogo de confirmação de suspensão duplicado 2x | Admin e Técnicos | Um único `TgdeskConfirmDialog` parametrizado |
| Texto de erro duplicado 5x | Todas as páginas repetem `Text(_error!, style: TextStyle(color: Colors.red))` | Widget `TgdeskErrorText` |

### Token Coverage
| Categoria | Definido | Valores hardcoded encontrados |
|---|---|---|
| Cores | 0 | 13 instâncias de `Colors.red/green/grey/orange/blueGrey` |
| Espaçamento | 0 | `EdgeInsets.all(24)`, `SizedBox(height: 12)` etc. repetidos sem escala |
| Tipografia | 0 (usa `Theme.of(context).textTheme` corretamente na Login) | 1 instância de estilo inline fora do tema |

### Component Completeness
| Componente | Estados | Variantes | Docs | Score |
|---|---|---|---|---|
| Bolinha de presença | ✅ (4 estados) | ❌ (sem variante de tamanho) | ❌ | 4/10 |
| Botão de suspensão | ✅ (suspender/reativar) | ✅ (técnico/rede/organização/dispositivo) | ❌ | 6/10 |
| Diálogo de formulário (bind/criar técnico/criar rede) | ✅ | ❌ (3 implementações quase idênticas) | ❌ | 4/10 |

### Priority Actions
1. Criar `lib/tgdesk/theme.dart` com os tokens (feito nesta rodada — ver abaixo).
2. Extrair os 3 padrões duplicados (presença, confirmação de suspensão, texto de erro) para widgets compartilhados.
3. Documentar cada componente compartilhado à medida que for extraído (não deixar acumular).

---

## Tokens definidos (`lib/tgdesk/theme.dart`)

### Cores
| Token | Valor | Uso |
|---|---|---|
| `TgdeskColors.online` | `Colors.green` | Dispositivo ativo e com heartbeat recente |
| `TgdeskColors.offline` | `Colors.grey` | Dispositivo ativo mas sem heartbeat |
| `TgdeskColors.guest` | `Colors.blueGrey` | Dispositivo ainda não vinculado |
| `TgdeskColors.suspended` | `Colors.red` | Dispositivo/técnico/rede suspenso |
| `TgdeskColors.warning` | `Colors.orange` | Alerta ou ação de suspensão |
| `TgdeskColors.seed` | `Colors.indigo` | Semente do `ColorScheme` (Material 3) do app inteiro |

### Espaçamento
Escala de 4px (`TgdeskSpacing.xs/sm/md/lg/xl` = 4/8/12/16/24) — os diálogos hoje usam `12` e `24` ad-hoc, que já batem com `sm`*1.5 e `xl`; ao migrar, arredondar para a escala.

### Componentes compartilhados criados
- `TgdeskErrorText` — substitui as 5 repetições de texto de erro vermelho.
- `showTgdeskConfirmSuspendDialog` — confirmação compartilhada de suspensão.
- `presenceColor(String)` — função pura, movida para `theme.dart`.

## Do's e Don'ts
| ✅ Faça | ❌ Não faça |
|---|---|
| Usar `TgdeskColors.suspended` para qualquer estado "desligado/suspenso" | Escrever `Colors.red` direto numa tela nova |
| Adicionar um novo componente compartilhado quando o mesmo padrão aparecer 2x | Copiar/colar um `showDialog` inteiro de outra tela |
| Seguir a escala `TgdeskSpacing` | Usar números de espaçamento arbitrários (`13`, `17`...) |
