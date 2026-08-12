# Arquitetura — Diagnóstico Probabilístico TGDesk

Documento de missão. Define a construção do pipeline que transforma a bateria de
diagnóstico do agente em um **experimento controlado**, persiste o dossiê do
computador e serve causas prováveis calibradas a partir de um serviço próprio
dentro do compose do TGDesk.

---

## 1. Princípio

Telemetria passiva só produz correlação: "estava lento e a temperatura estava
alta". Uma **rampa de carga** produz intervenção: "forcei o disco até o degrau 3
e ele parou de responder por 4,2s; repeti e quebrou no mesmo degrau". A segunda
forma é o que permite apontar causa e o que permite calibrar um modelo.

Disso decorre tudo:

- O dado útil não é um score, é o **limiar** — em que degrau quebrou, com que
  inclinação degradou, em quanto tempo recuperou. Curva, não número.
- A unidade de organização é o **status negativo**. Cada status negativo tem um
  conjunto fechado de causas candidatas, um conjunto de sinais que o produzem e
  um conjunto de testes que discriminam entre suas causas. Só entra na telemetria
  o sinal que muda a probabilidade de alguma causa de algum status.
- A saída ao técnico não é veredito: são no máximo **3 causas com probabilidade
  honesta**, ancoradas na curva que as sustenta. Quando o dossiê não decide, a
  resposta correta é abstenção com sugestão dos próximos testes.

O requisito de engenharia do modelo é **calibração**, não acurácia. Um modelo com
85% de acerto e mal calibrado é pior que inútil, porque o técnico aprende a
confiar num número que mente.

---

## 2. Base existente (verificada)

### Agente — `client-agent/cmd/agent/diagnostics.go`

Já existem, e são **conjunto candidato** a estágio da escada — confirmados,
adaptados ou podados pela derivação do corpus (§13.6), nunca assumidos como
dados:

| Função | Peça forçada |
| --- | --- |
| `cpuStress` | CPU |
| `memoryIntegrity` / `memoryExtended` | RAM |
| `storageSurfaceRead` | superfície do disco (leitura) |
| `diskPerformance` / `diskRandomPerformance` | disco sequencial / aleatório |
| `networkLatencySeries` / `internetQuality` | rede |

Já existem também `diagnosticProgress` (canal de progresso), `diagnosticPauseGate`
(pausa/retomada) e `diagnosticSuite` (seleção de testes). **A execução por etapas
já está de pé.**

O que falta não é existir: hoje cada teste devolve **veredito agregado**
(`map[string]any` no fim). O modelo precisa de **série temporal com carga no eixo
X**. É mudança de contrato de saída, não reescrita.

### Servidor — `server/api-core/internal/handlers/`

- `diagnostics.go` — `DiagnosticCatalog`, `StartDiagnostic`, `ListDiagnostics`,
  `CancelDiagnostic`, `PauseDiagnostic`, `ResumeDiagnostic`
- `telemetry.go`, `telemetry_rollup.go`, `telemetry_stats.go`
- `control_ws.go` — plano de controle

Transporte, autorização por dispositivo e ciclo de vida da execução já existem.

---

## 3. Arquitetura

```
postgres ──┬── api-core (Go)  ← dono da verdade, do WS, do RBAC e dos gates
           │        └── internal/diagnostico  ← regra + rede, em processo
           │            (pesos em model_version, sem volume)
           └── leitura em batch para treino
redis ─────────── cache de inferência
```

### Fronteira dura

**O motor de diagnóstico nunca fala com o cliente.** Recebe dossiê, devolve
distribuição de probabilidade. Todo WebSocket, RBAC e escopo org/rede/subrede
permanecem no `api-core`. Isso preserva a regra de que tudo é WebSocket e evita
um segundo plano de controle.

#### Correção: um container por projeto

Este documento desenhou o motor como serviço `brain` separado no compose. **Vale
a regra geral do projeto: um container por projeto.** A rede vive dentro do
`api-core`, em `internal/diagnostico`.

A fronteira acima não se perde com a junção — ela fica **mais forte**, porque o
motor deixa de ter endereço próprio: não tem rota, não abre canal, não conhece
RBAC nem organização. É função chamada, não serviço alcançável.

O que muda em consequência:

- **Sem serviço `brain`, sem `POST /infer` interno.** A chamada é in-process; o
  contrato (`PedidoDeInferencia` / `RespostaDeInferencia`) continua o mesmo, para
  que o caminho de volta seja trocar uma implementação sem tocar em chamador.
- **Sem `tgdesk_model_data`.** Os pesos moram em `model_version.pesos` (0079).
  O backup do banco leva o modelo junto, e restaurar um dump restaura o cérebro
  junto com o dado — em vez de um volume para versionar, sincronizar e perder.
- **Sem PyTorch.** A rede é um MLP em Go (`internal/diagnostico/rede.go`): ReLU,
  softmax, cross-entropy, backprop, calibração por temperatura. Mesma
  matemática. O ponto de troca fica declarado no arquivo: quando a entrada
  deixar de ser vetor de sinais e passar a ser a curva inteira como série, o
  treino sai para fora e só os pesos são importados.
- **Sem segundo runtime, segundo deploy e segundo ponto de falha.**

### Contrato do motor — três operações

Não são rotas: são funções, pela correção acima. O contrato é o mesmo.

| Operação | Entrada | Saída |
| --- | --- | --- |
| `Inferir` | dossiê (run + features) | `{status, causas[≤3] {codigo, prob}, abstain, proximos_testes[], sombra}` |
| `cmd/treinar` | — | treino em batch a partir do Postgres; pesos em `model_version` |
| `RecarregarModelos` | — | relê os cabeçotes do banco (na subida e após treino) |

`sombra` é o campo novo: a suposição da rede enquanto ela ainda não decide
(§14.1). Não vai para a tela — vai para `rat_comparacao`, que é onde ela é
medida contra a realidade.

### Motor em duas camadas, mesma saída

1. **Regra determinística** sobre limiar + frequência histórica.
   Ex.: `degradação de I/O antes do degrau 3 AND SMART reallocated > 0
   → disco degradado`.
2. **Rede neural**, por status negativo.

Ambas respondem no **mesmo schema**. A tela não sabe qual respondeu. Enquanto o
parque não gerar volume, roda a camada 1; a rede assume causa por causa, à medida
que houver caso fechado e verificado suficiente para calibrar.

**O gate de segurança do stress fica fora das duas** — regra pura, determinística,
nunca decisão de modelo.

### A rede

- **Entrada:** features derivadas da curva — degrau de quebra, inclinação da
  degradação, duração e tempo de recuperação de trava, deltas térmicos, SMART,
  inventário de hardware.
- **Saída:** softmax sobre o conjunto **fechado** de causas daquele status
  negativo. Um cabeçote por status, não um modelo universal.
- **Treino:** cross-entropy + calibração por temperatura no conjunto de
  validação. Abstenção quando a entropia passa do limite.
- **Custo:** CPU, mesmo host, treino em minutos. Não exige GPU.

---

## 4. Modelo de dados (migrations 0072+)

### `negative_status`
Catálogo fechado. É a espinha da ontologia.
Campos: `codigo`, `descricao`, `sinais[]` (métricas que o produzem),
`causas_candidatas[]`, `testes_discriminantes[]`.

### `stress_run`
Uma execução da escada unificada.
Campos: `device_id`, `perfil`, `degraus_planejados`, `degrau_alcancado`,
`motivo_aborto`, `gates_aplicados[]`, `consentimento_ref`, `iniciado_por`.

### `stress_sample`
A série bruta. `(run_id, stage, load_level, t_ms, metrica, valor)`.

### `stall_event`
Travas, com **origem dupla**:
- `agent_ts` — ring buffer local de alta resolução, despejado após o evento
- `server_gap` — buraco de heartbeat detectado pelo `api-core`
- `duracao_conciliada`, `confianca`

### `telemetry_sample`
Camada contínua (§7). Agregados por recurso, top-N processos normalizados,
contadores de pressão, eventos de mudança. Retenção longa.

### `incident_burst`
Rajada de alta resolução em volta de um incidente (§7). Recorte do ring buffer,
lista integral de processos, eventos do sistema. Retenção curta, expurgo
automático, campos sensíveis só com consentimento registrado.

### `stage_duration_stat`
Base da previsão de duração (§10.2). `(classe_dispositivo, estagio) → p50, p90,
n`. Alimentada por regressão simples sobre execuções anteriores, não por rede.

### `log_signature`
Assinaturas diagnósticas derivadas do corpus (§8). `fonte`, `padrao`,
`campos_extraidos[]`, `status_implicado`, `causas_implicadas[]`, `peso`,
`origem_corpus`, `revisado_por`.

### `diagnosis`
Saída do motor: `run_id` **ou** `telemetry_window` (diagnóstico passivo),
`status_codigo`, `causas` (top-3 + prob), `abstain`, `motor`
(`regra` | `modelo`), `versao_modelo` (FK para `model_version`, §14.5),
`nivel_alerta` (`nenhum` | `1` | `2`), e depois o rótulo de recidiva
(`recidiva_7d`, `recidiva_30d`).

### Demais tabelas, definidas onde nascem

`log_signature` (§8), `tool_catalog` / `cause_requirement` / `os_scope` /
`os_validation` (§11.7), `text_template` (§12.2), `corpus_thread` /
`corpus_post` / `corpus_case` / `corpus_prior` (§13.7), `coverage_report`
(§13.6), `model_version` (§14.5). As tabelas de corpus ficam em schema separado e
não são lidas em runtime.

---

## 5. A escada unificada

O teste manual do supervisor passa a ser **um procedimento único**, não um menu.

- **Degraus definidos**, tempo fixo por degrau, ordem fixa, mesma escada em toda
  máquina. Sem reprodutibilidade não existe limiar aprendível.
- **Peça por peça primeiro, combinado no fim.** O estágio combinado é
  obrigatório: fonte, térmico e disputa de barramento só aparecem sob carga
  simultânea — e são justamente as causas que o técnico erra sozinho.
- **O registro do teste é rótulo, não só ação.** Cada resultado confirma ou
  exclui causas. É o que faz o dossiê convergir em vez de só engordar.

### Forma do degrau — valores de partida do perfil `v1`

Estes números são o perfil inicial versionado, não constantes de código. A poda
de A4 (§13.6) pode remover estágios; **não** pode mudar a forma do degrau sem
gerar `perfil` novo, porque execuções de perfis diferentes não são comparáveis.

- **5 degraus por estágio**, carga em 20 / 40 / 60 / 80 / 100 % do teto medido
  no próprio dispositivo. Percentual do teto local, nunca valor absoluto — é o
  que torna a curva comparável entre máquinas desiguais.
- **90 s por degrau**, com os **15 s iniciais descartados** da análise
  (aquecimento). Amostra a **1 Hz** durante todo o degrau.
- **Ordem fixa:** CPU → RAM → disco sequencial → disco aleatório → rede →
  **combinado** (CPU+disco+RAM simultâneos, 100 %, 180 s).
- **Repetição do degrau de quebra:** ao detectar quebra, o estágio repete aquele
  degrau **uma vez**. Quebra que não se repete entra no dossiê como
  `nao_reproduzida` e não sustenta veredito — é o que separa "quebrou" de
  "quebra".
- **Teto de execução:** 45 min para a escada completa. Estourou, aborta com
  `motivo_aborto = teto_de_tempo` e o que foi medido vale; nada fica pela metade
  em silêncio.

Escada completa `v1`: 6 estágios, ~34 min de carga efetiva — dentro da faixa que
§10.2 promete ao supervisor.

### Gates de segurança (regra determinística, obrigatórios)

O teste é destrutivo por natureza. Disco em falha morre sob I/O pesado; notebook
empoeirado desliga; fonte no limite não volta.

- Consentimento explícito antes da execução, registrado em `stress_run`.
- SMART já degradado (`reallocated > 0`, `pending > 0` ou `wear_level < 10 %`)
  ⇒ estágio de disco vira **somente leitura**, sem exceção manual.
- Térmico em repouso acima de **75 °C** ⇒ o estágio combinado não roda e o
  dispositivo entra com lacuna declarada ("carga combinada não testável").
- Bateria de notebook fora da tomada ⇒ escada não inicia.
- Espaço livre < 10 % ⇒ estágio de disco só leitura.

**Parada automática por degrau** — o degrau é interrompido, e com ele o estágio,
quando qualquer um destes ocorrer:

| Condição | Limite |
| --- | --- |
| temperatura de qualquer sensor | ≥ 95 °C, ou ≥ 90 °C sustentado por 10 s |
| trava (§6) durante o degrau | ≥ 5 s sem heartbeat |
| erro de I/O reportado pelo sistema | qualquer um |
| queda de tensão / desligamento inesperado no degrau anterior | qualquer um |
| perda de contato com o agente | ≥ 30 s |

Parada por gate **não é falha da execução**: é resultado. Vira
`stress_gate_abort` com motivo, aparece marcada na curva (§10.6 B) e é evidência
diagnóstica por si — máquina que não atravessa o degrau 2 sem atingir 95 °C já
respondeu à pergunta térmica.

### Contrato de saída do agente — amostra, não veredito

É a mudança de contrato anunciada em §2. Hoje o teste devolve `map[string]any`
no fim; passa a emitir **evento por amostra**, pelo canal de controle já
existente, sem rota nova:

```json
{
  "tipo": "stress_sample",
  "run_id": "…",
  "stage": "disco_leitura_sequencial",
  "load_level": 3,
  "t_ms": 18400,
  "metricas": {"iops": 412, "lat_p99_ms": 310, "temp_c": 68}
}
```

Regras do contrato:

- **`load_level` é obrigatório em toda amostra.** É o eixo X; sem ele a amostra
  não é curva, é telemetria solta.
- **Cadência fixa por estágio**, declarada no perfil. Amostragem variável
  destrói comparabilidade entre execuções.
- **O agente não classifica.** Não emite "passou"/"falhou", não calcula limiar,
  não decide aborto por causa — só gates locais de segurança, que emitem
  `stress_event` com motivo.
- **Eventos irmãos no mesmo canal:** `stress_stage_start`, `stress_stage_end`,
  `stress_gate_abort` (com `motivo`), `stall_start` / `stall_end` (§6).
- **Perda tolerada, buraco declarado.** Amostra perdida não invalida a execução;
  o `api-core` registra a descontinuidade, e uma curva com buraco no degrau de
  quebra reduz a confiança do diagnóstico em vez de ser silenciosamente
  interpolada.
- **Idempotência por `(run_id, stage, load_level, t_ms)`** — reentrega após
  reconexão não duplica.

---

## 6. Detecção de trava — relógio externo

**Quem mede o travamento não pode ser quem trava.** O agente congelado não
carimba a hora do próprio congelamento — acorda depois e só sabe que o relógio
pulou, e mal.

- Heartbeat a **2 Hz** no canal já existente; o **servidor** detecta o buraco e é
  a verdade sobre início e duração. Buraco ≥ **1,5 s** (3 batidas perdidas) abre
  `stall_start`; a volta do heartbeat fecha com `stall_end`.
- O agente mantém ring buffer em memória de **60 s a 10 Hz** e despeja **após** o
  evento, fornecendo o contexto do que acontecia em volta.
- Conciliação dos dois produz duração com confiança explícita:

  | Situação | `confianca` |
  | --- | --- |
  | servidor e agente concordam dentro de 500 ms | `alta` |
  | só o servidor viu (agente não despejou buffer) | `media` — duração do servidor vale |
  | divergem acima de 500 ms | `media` — vale o servidor, divergência registrada |
  | só o agente reportou (sem buraco no servidor) | `baixa` — não sustenta veredito |

- **Trava de duração maior que a janela do ring buffer** (60 s) perde o contexto
  anterior, não a medição: a duração continua sendo a do servidor.
- Desconexão de rede é distinguida de trava pelo próprio agente ao voltar: se o
  relógio local correu normalmente durante o buraco, foi rede, não trava. Sem
  essa distinção toda queda de link viraria falso positivo de travamento.

Sem isso, todo dado de trava carrega incerteza do tamanho da própria trava.

---

## 7. Telemetria contínua — o dossiê passivo

A escada (§5) é o exame provocado. Este capítulo é o exame de rotina: o que o
servidor sabe do computador **sem** ter forçado nada. É ele que sustenta os
alertas ao cliente (§9) e que pré-carrega o dossiê antes de qualquer chamado.

O alvo é o gerenciador de tarefas completo — processos, CPU, RAM, disco, rede,
GPU, handles, uptime, serviços, drivers, eventos do sistema. O que muda não é o
alvo, é **como isso trafega**.

### 7.1 Duas velocidades

| Camada | Frequência | Conteúdo | Destino |
| --- | --- | --- | --- |
| **Contínua** | baixa, sempre ligada | agregados por recurso, **top-N processos** por CPU/RAM/IO, contadores de pressão, eventos de mudança (processo nasceu/morreu, serviço caiu) | `telemetry_sample` |
| **Rajada** | alta resolução, sob evento | recorte completo do ring buffer em volta do incidente — lista integral de processos, pilha de eventos, contadores por thread | `incident_burst` |

Cadência da camada contínua: **uma amostra a cada 60 s**, `top-5` processos por
CPU, RAM e I/O, enviada em lote a cada 5 min. Evento de mudança (serviço caiu,
driver falhou) sobe na hora, fora do lote — evento não espera janela.

Gatilhos de rajada, todos determinísticos:

| Gatilho | Condição |
| --- | --- |
| trava (§6) | `stall_start` emitido |
| pico sustentado | CPU ou I/O ≥ 90 % por ≥ 120 s, ou RAM disponível < 5 % |
| reboot inesperado | classe determinística do log (§7.3) |
| bugcheck | qualquer |
| queda de serviço crítico | serviço da lista fechada, qualquer parada não planejada |
| abertura de chamado | sempre |

Cada rajada recorta **60 s antes e 30 s depois** do instante do gatilho. Máximo
de **6 rajadas por dispositivo por dia**; excedente é contado, não enviado — o
gatilho que dispara sem parar já é, ele mesmo, o sintoma, e não precisa de mais
amostras para ser reconhecido.

O ring buffer do agente já é requisito de §6 — aqui ele é reaproveitado. Enviar
tudo o tempo todo encheria o banco antes de virar inteligência; enviar só
agregado perderia o incidente. As duas velocidades resolvem os dois.

### 7.2 Privacidade — obrigatório, não opcional

Nome de processo, linha de comando e título de janela revelam o que a pessoa faz,
que documentos abre, que aplicativos usa. O parque tem cliente empresa e cliente
avulso; isso é dado pessoal.

- **Sempre:** nome de executável **normalizado** contra catálogo conhecido,
  editor assinante, hash. Desconhecido vira `desconhecido:<hash>`.
- **Nunca por padrão:** linha de comando completa, título de janela, caminho de
  usuário, nome de arquivo aberto.
- **Só em rajada, só com consentimento registrado:** os campos acima, quando o
  incidente exige, com retenção curta e expurgo automático.
- Retenção declarada por camada; agregado vive longo, rajada vive curto.

### 7.3 Reboot e desligamento — determinístico antes de probabilístico

O exemplo "desligou do nada e voltou em 3 minutos" **não precisa de rede neural
para ser classificado**. O sistema operacional já registra a diferença entre
desligamento inesperado, bugcheck, falta de energia, proteção térmica e reinício
planejado por atualização — com código de evento.

Portanto a camada contínua **precisa incluir extração do log de eventos**, e a
classificação da *classe* de desligamento é regra determinística. A rede entra
depois, para distribuir probabilidade sobre as causas **dentro** da classe. Sem
isso, o modelo reaprenderia do zero, com muito menos precisão, algo que o sistema
já responde de graça.

Mesmo princípio vale para queda de serviço, falha de driver e erro de disco:
**se o sistema já diz, não se adivinha.**

### 7.4 Retenção declarada

"Retenção declarada por camada" (§7.2) só é regra se os números existirem. São
configuração versionada, não constante em código, e o expurgo é um job do
`api-core` — nunca limpeza manual:

| Dado | Retenção | Razão |
| --- | --- | --- |
| `telemetry_sample` bruto | 90 dias | janela de recidiva 30d com folga de comparação |
| agregado diário derivado | 24 meses | curva de degradação de longo prazo (tela D) |
| `incident_burst` sem consentimento | 7 dias | só serve para fechar o incidente corrente |
| `incident_burst` com campos sensíveis | 72 h após o fechamento do chamado | dado pessoal vive o mínimo |
| `stress_run` + `stress_sample` | permanente | é o dado de treino; sem ele o modelo não existe |
| `stall_event`, `diagnosis` | permanente | rótulo e histórico |
| `corpus_*` | permanente, schema separado | material de construção, nunca runtime |

Duas consequências que não são negociáveis:

- **Expurgo é irreversível e automático.** Não existe "guardar mais um pouco por
  garantia" para campo sensível — se o incidente exigir mais tempo, o que se
  estende é o consentimento, registrado de novo.
- **O que sobrevive ao expurgo é o derivado, não o bruto.** Antes de apagar
  `telemetry_sample`, o agregado diário já foi calculado; a série longa da tela D
  nunca depende de dado que vai ser apagado.

---

## 8. Assinaturas de log — o que o corpus realmente entrega

O fluxo típico de uma thread de fórum resolvida é:

> reclamação → rodada de testes ou log já existente → é pedido um `.txt` →
> números e strings do log são analisados → causa provável declarada

A consequência é que o corpus (§13) não entrega apenas vocabulário de sintoma.
Ele entrega, de graça, **quais linhas de log são diagnósticas** — a assinatura
que um humano usou para decidir, junto com a conclusão a que ela levou.

### Tabela `log_signature`

Campos: `fonte` (event log, driver, aplicativo, SMART, dump), `padrao`
(regex ou chave estruturada), `campos_extraidos[]`, `status_implicado`,
`causas_implicadas[]`, `peso`, `origem_corpus`, `revisado_por`.

O agente extrai; o `api-core` casa contra as assinaturas; o resultado entra no
dossiê como **evidência nomeada**, não como texto solto. Uma evidência de
assinatura vale mais que uma métrica agregada, porque é literal e citável na
tela de resultado.

Assinatura também é revisada por humano antes de valer — mesma regra dos
templates.

---

## 9. Alertas ao cliente — dois níveis

Com telemetria contínua e sem escada, as probabilidades são amplas. Isso não
impede alertar; impede **afirmar**. Dois níveis, com barras de confiança
diferentes:

**Nível 1 — sintoma, sem causa.** Quando a massa de probabilidade está espalhada.
O texto descreve o que foi observado e pede verificação profunda:

> "Seu computador travou 4 vezes nos últimos 7 dias. A causa não foi
> identificada à distância — abra um chamado para verificação."

Nunca nomeia causa. Nomear causa com probabilidade baixa é como o produto perde
confiança.

**Nível 2 — causa nomeada.** Só quando a probabilidade é **≥ 0,90** *e* a causa
está `promovido` ou tem regra com ≥ 30 casos internos confirmados. Abaixo de
qualquer uma das duas, cai para nível 1. Texto direto e acionável:

> "Seu computador está com pouca memória livre com frequência.
> Fale com um técnico."

### Regras da camada de alerta

- **Barra mais alta que a do técnico.** O supervisor lê probabilidade e curva; o
  cliente lê uma frase. Frase exige mais certeza que gráfico.
- **Linguagem de leigo, sempre.** Mesmo mecanismo de `text_template` (§12), nível
  `cliente`. Vale igual para cliente empresa e avulso.
- **Nunca alertar sem ação possível.** Alerta que não diz o que fazer é ruído.
- **Anti-repetição.** Mesmo `(dispositivo, status)` não realerta antes de
  **14 dias**, e nunca enquanto houver chamado aberto para aquele status. Alerta
  descartado pelo cliente silencia por **30 dias**.
- **Rebaixamento automático.** Se a probabilidade cair abaixo de 0,90, o alerta
  volta a nível 1; abaixo de **0,50** some. Não fica preso na tela.
- **Teto de dois alertas simultâneos** por dispositivo, os de maior
  probabilidade. Três avisos ao mesmo tempo é ruído, e ruído treina o cliente a
  ignorar o produto.

---

## 10. Front-end e fluxo de chamado

### 10.0 O que existe hoje, e por que precisa mudar

| Arquivo | Hoje | Depois |
| --- | --- | --- |
| `diagnostics_dialog.dart` (1254 l.) | diálogo com menu de **30 testes**, histórico e `_DiagnosticLinePainter` | substituído pelas quatro telas (§10.6); o painter é a semente do gráfico de curva |
| `diagnostic_text.dart` (118 l.) | mapa `id → nome/descrição` no cliente | vira consumidor de `text_template` servido pelo `api-core`; o padrão de "texto é desta camada" já está certo e se mantém |
| `support_page.dart` (1984 l.) | fluxo de chamado atual | reduzido à ação única (§10.1) |
| `ticket_type_form.dart` (193 l.) | seleção de tipo pelo usuário | tipo passa a ser **sugerido** pelo dossiê, com correção manual |
| `technician_home_page.dart` | entrada do supervisor | entra o pré-voo com estimativa |

Catálogo atual já tem 30 testes, muitos deles passivos por natureza —
`critical_events`, `driver_errors`, `service_failures`, `process_pressure`,
`temperature_sensors`, `smart_extended`, `startup_inventory`. Isso é
**reclassificação, não construção**: eles migram para a camada contínua (§7) e
deixam de ser item de menu.

A descrição atual de `all_tests` — *"pode levar horas ou dias"* — é o sintoma
exato do problema: hoje o supervisor escolhe entre 30 itens e recebe uma duração
ilimitada. É isso que a ação única elimina.

### 10.1 Ação única e estimativa

**Um botão.** O supervisor não escolhe testes. Escolhe *executar a escada*, e o
servidor decide a composição a partir do dispositivo, do motivo do chamado e do
que o dossiê passivo já sabe.

Consequências:

- **Menu de 30 itens sai da tela principal.** Vira "avançado", fora do fluxo
  normal, para o caso raro em que o supervisor quer um teste isolado.
- **Escada adaptativa, não fixa.** Máquina com SMART limpo pula a leitura
  integral de superfície; máquina com suspeita de RAM ganha degraus extras de
  memória. A composição é decisão do servidor e fica registrada em
  `stress_run.perfil`.
- **Composição é dado, não código.** Perfil versionado, para que execuções
  continuem comparáveis entre si.

### 10.2 Previsão de duração

A estimativa é o que torna a ação única aceitável — ninguém aperta um botão que
pode levar "horas ou dias".

- **Base:** duração medida por estágio, por classe de dispositivo (tipo de disco
  e tamanho, núcleos, RAM, se é notebook), a partir das execuções anteriores do
  parque. Regressão simples, não rede.
- **Exibição:** faixa, não número seco — "estimado 12–18 min". Faixa honesta vale
  mais que ponto falso.
- **Ao vivo:** a estimativa é recalculada durante a execução e mostrada como
  restante. Se o dispositivo for mais lento que o previsto, o número sobe na
  cara do supervisor em vez de estourar em silêncio.
- **Frio:** sem histórico para aquela classe, mostra faixa larga marcada como
  estimativa grosseira. Nunca esconde a incerteza.
- **Tabela `stage_duration_stat`:** `(classe_dispositivo, estagio) → p50, p90, n`.

### 10.3 Fluxo de chamado simplificado

O chamado deixa de começar por formulário e passa a começar por dossiê.

```
Hoje:  cliente escolhe tipo → descreve → supervisor lê → escolhe testes → executa
Depois: dossiê passivo já existe → uma ação → escada → resultado com causa
```

- **Abertura pelo cliente:** descreve em texto livre ou aceita o alerta que já
  apareceu (§9). Não escolhe tipo. O tipo é **sugerido** pelo status negativo que
  o dossiê passivo indica, com correção manual pelo supervisor.
- **Chegada ao supervisor:** o chamado já vem com dossiê passivo, status negativo
  provável e testes sugeridos. Ele não parte do zero.
- **Ação única:** pré-voo (gates + consentimento + estimativa) → executar.
- **Fechamento:** causa registrada, ação registrada, e o dispositivo continua sob
  monitoramento para o rótulo de recidiva (§13.5). O fechamento é o que produz o
  dado de treino — então o campo de causa é obrigatório e vem do conjunto fechado,
  nunca texto livre.

**Invariante do fluxo:** entre o chamado chegar e a escada começar existe
**uma** decisão humana — consentir e executar. Todo o resto o servidor propõe.

### 10.4 Respostas pré-calculadas

A ação única só é honesta se o que ela mostra já estiver pronto **antes** de
alguém clicar. Nada é calculado na abertura da tela.

O que precisa estar pré-calculado e trafegando pelo canal:

| Pré-calculado | Quando é atualizado |
| --- | --- |
| status negativo provável + top-3 causas passivas | a cada janela de telemetria contínua |
| tipo de chamado sugerido | junto com o status negativo |
| perfil de escada proposto para aquele dispositivo | ao mudar inventário, SMART ou status |
| gates de segurança que serão aplicados, com motivo | idem |
| faixa de duração estimada | ao mudar `stage_duration_stat` ou o perfil |
| alerta ao cliente e seu nível | ao cruzar/rebaixar limiar (§9) |

Consequências de desenho:

- **Nenhuma tela busca dado ao montar.** Ela se desenha do que já chegou pelo
  canal. Vale para o cliente e para o supervisor.
- **O cálculo é do servidor, o desenho é do cliente.** Só dado modular no fio.
- **A abertura de chamado não dispara inferência** — apenas *materializa* o
  `diagnosis` passivo que já existia, congelando-o como ponto de partida do
  chamado. O que muda é o estado, não o cálculo.
- **Invalidação explícita.** Todo pré-cálculo carrega o que o gerou (versão de
  modelo, versão de perfil, janela de telemetria). Quando a origem muda, o
  servidor empurra a nova versão; o cliente nunca reconsulta.

### 10.5 Anatomia das duas respostas ao supervisor

São dois momentos com **bases de evidência diferentes**, e por isso duas
linguagens diferentes. Confundi-los é o erro que faria o supervisor parar de
confiar no número.

| | Diagnóstico inicial | Diagnóstico pós-teste |
| --- | --- | --- |
| Base | telemetria contínua, log de eventos, assinaturas, inventário | tudo isso **+ curva com limiar** |
| Tem intervenção? | não | sim |
| Linguagem | hipótese | veredito |
| Teto de confiança | limitado (§10.5.1) | livre, se calibrado |
| Pergunta que responde | "o que testar primeiro?" | "qual é a causa?" |

#### 10.5.1 Diagnóstico inicial — linguagem de hipótese

Sem intervenção não existe limiar; então não existe veredito. A resposta é uma
**lista ordenada de hipóteses com o que as separa**.

Campos obrigatórios:

1. **Status negativo** observado, em uma frase, com a contagem que o sustenta
   ("travou 4 vezes em 7 dias").
2. **Até 3 hipóteses**, cada uma com probabilidade **e faixa** — inicial nunca
   mostra número seco.
3. **Evidência literal por hipótese** — a linha de log, o contador, o valor
   medido. Nunca "indícios sugerem".
4. **O que não se sabe.** Bloco explícito. É o que impede a leitura de veredito.
5. **Teste que mais separa as hipóteses** — o de maior ganho de informação, não
   o mais rápido nem o mais completo.
6. **Custo daquele teste:** faixa de duração e gates que vão disparar.

Regras:

- Probabilidade inicial tem **teto de 0,85**. Acima disso, o texto passa
  a "muito provável", nunca "confirmado" — porque nada foi forçado ainda.
- Se nenhuma hipótese domina, a resposta correta é **abstenção com direção**:
  "sem hipótese dominante — o teste X separa mais".
- Se a classe já é determinística por log (§7.3), ela aparece como **fato**, e as
  hipóteses ficam só para a causa dentro da classe.

Forma:

> **Travamentos sob uso normal** — 4 ocorrências em 7 dias, a mais longa de 11s.
> Classe do último reinício: desligamento inesperado (fato, log de eventos).
>
> 1. Disco degradado — 55% (40–70%) · SMART: 12 setores realocados; latência p99
>    de 180ms em uso leve
> 2. Memória instável — 25% (12–38%) · 2 falhas de página não corrigidas no log
> 3. Superaquecimento — 12% (5–22%) · picos de 92 °C sem carga declarada
>
> **Não se sabe:** comportamento sob carga; nenhum teste foi executado.
> **Separa mais:** escada de disco + memória — 14 a 20 min. Disco entra em
> leitura apenas (SMART já degradado).

#### 10.5.2 Diagnóstico pós-teste — linguagem de veredito

Agora existe curva, existe limiar, existe repetição. A resposta muda de forma.

Campos obrigatórios:

1. **Veredito em uma frase**, com o limiar que o define.
2. **Causa 1 com probabilidade**, e as demais só se ainda relevantes.
3. **A curva com o ponto de quebra marcado.**
4. **Medido × esperado**, literal, por evidência.
5. **O que o teste excluiu.** Tão importante quanto o que confirmou — é o que
   impede o supervisor de refazer trabalho e o que mostra que a escada rendeu.
6. **Delta contra o diagnóstico inicial** — o que subiu, o que caiu, e por quê.
7. **Ação recomendada** e **o que fazer se ela não resolver**.
8. **Campo de fechamento** com causa do conjunto fechado (obrigatório, §10.3).

Forma:

> **Disco degradado** — parou de responder por 4,2s no degrau 3 de carga de
> leitura; repetido, quebrou no mesmo degrau. Probabilidade 88%.
>
> Medido: 310ms p99 · Esperado para esta classe: <40ms p99
> **Excluído:** memória instável (0 erros em 3 padrões) e superaquecimento
> (máx. 71 °C sob carga combinada).
> **Mudou desde o inicial:** memória caiu de 25% para 2%; disco subiu de 55%
> para 88%.
>
> **Ação:** substituir o disco e restaurar. **Se não resolver:** controladora
> ou cabo — a escada não separa esses dois; exige troca de porta e reteste.

#### 10.5.3 Calibração visível

Ao lado de cada probabilidade, o histórico da faixa:

> "quando dizemos 70–80%, acertamos 74% em 112 casos"

É isso que transforma o número em argumento em vez de oráculo, e é o que permite
ao supervisor perceber sozinho se o modelo começou a mentir. Enquanto não houver
casos suficientes para a faixa, o rótulo é "sem histórico suficiente" — nunca um
número inventado.

### 10.6 Telas

Quatro telas, todas alimentadas pelo canal de controle. Nenhuma busca dado ao
montar — cada uma se desenha a partir do que chega no WebSocket.

**A — Pré-voo (antes de rodar a escada)**
Inventário resumido, estado de repouso (térmico, SMART, memória livre), quais
gates de segurança vão ser aplicados e **por quê**, duração estimada, e o botão
de consentimento explícito. O técnico precisa ver antes de começar que o disco
vai rodar só em leitura porque o SMART já acusou realocação. Consentimento
registrado em `stress_run.consentimento_ref`.

**B — Execução ao vivo**
Escada visível como progresso por estágio e degrau: qual peça está sendo forçada,
qual degrau, quanto falta. Curva desenhando em tempo real. Trava aparece na hora,
marcada na curva, com duração ainda em aberto ("travado há 3s…") e fechando
quando o heartbeat volta. Pausa e cancelamento sempre disponíveis — já existem no
agente (`diagnosticPauseGate`). Aborto por gate aparece como evento na curva, não
como erro.

**C — Resultado**
A tela principal. De cima para baixo:
1. **Veredito curto** — uma frase, gerada por template (§12).
2. **Top-3 causas** com barra de probabilidade. Ou o bloco de abstenção.
3. **A curva com o ponto de quebra marcado** — é a explicação, não a ilustração.
4. **Evidências que sustentam a causa nº 1**, em lista curta e literal
   (métrica, valor medido, limiar esperado).
5. **Próximos passos** — testes sugeridos, ou ação de resolução.

**D — Dossiê**
Histórico do dispositivo: execuções anteriores, curvas sobrepostas para comparar
degradação ao longo do tempo, diagnósticos passados e se houve recidiva em 7/30
dias. É aqui que o técnico vê que a máquina está piorando.

### 10.7 Estados obrigatórios

Toda tela precisa dos cinco: **vazio** (nunca rodou), **executando**,
**abortado por gate**, **abstenção**, **resultado**. Abstenção não é erro nem
estado degradado — é uma resposta de primeira classe, com o mesmo peso visual do
resultado, dizendo o que rodar em seguida.

### 10.8 Linguagem visual

Empresta-se a **gramática de leitura** das ferramentas de referência, não o
cromo. O técnico já sabe ler aquela forma — refazer a forma cobra dele um
retreinamento gratuito.

- **Copia:** eixo, unidade, escala, o que é vermelho e por quê, ordem em que os
  números aparecem. É o que carrega o significado aprendido.
- **Não copia:** nome do produto, moldura, ícone, marca. Não carrega significado
  e envelhece junto com o original.

Compilado no tema TGDesk, charts style TGDesk.

Uma probabilidade sozinha na tela é pedir ao técnico que confie no oráculo; a
mesma probabilidade ancorada na curva é argumento.

---

## 11. Escopo da OS — do diagnóstico ao que levar

O diagnóstico não termina em "causa provável". Termina em **escopo de ordem de
serviço**: o que precisa ser feito, com quais ferramentas, peças, insumos e
tempo. É a última tradução da probabilidade em ação.

### 11.1 Escopo se deriva do top-3, não da causa nº 1

O técnico de campo vai **uma vez**. Se a hipótese 2 tem 25%, voltar depois custa
mais caro que levar a peça junto. Então:

> escopo = **união** das necessidades sobre as hipóteses plausíveis, ponderada
> pela probabilidade **e pelo custo de faltar**.

Item barato e leve com 20% de chance de ser necessário entra. Item caro e
volumoso com 20% vira "sob demanda", com o técnico avisado de que pode haver
segunda visita. O critério é explícito e revisável, não intuição de quem monta a
mala:

> **levar** ⟺ `prob(causa) × custo_de_faltar ≥ custo_de_levar`

com `custo_de_faltar` na escala 1–5 e `custo_de_levar` **deslocado para começar
em zero**, vindos de `tool_catalog`:

- `custo_de_levar` = (`custo_relativo` − 1) + 1 se `portatil = false`.
  O deslocamento não é detalhe: a escala 1–5 do catálogo é a de **cadastro**
  (quem digita não tem como registrar custo zero), mas a da conta é a de
  **incômodo**, e o incômodo de levar uma chave de fenda é zero. Sem isso, o
  próprio exemplo abaixo — item trivial entrando por 20% — não se reproduz.
- `custo_de_faltar` = 5 para item que bloqueia (essencial), 3 para necessária,
  1 para facilitadora.
- `requer_aprovacao = true` nunca entra automaticamente: vira sugestão pendente,
  qualquer que seja o produto.

Exemplo: chave de recuperação de volume criptografado tem `custo_de_levar` 1 e
`custo_de_faltar` 5 — entra com 20% de probabilidade e entraria com 5%. Disco de
reposição de 2 TB tem `custo_de_levar` 5 — precisa de ~100% para ir junto sem
aprovação. É a regra que produz o comportamento certo sem ninguém decidir na
hora.

### 11.2 Os quatro níveis

| Nível | Definição | Efeito se faltar |
| --- | --- | --- |
| **Essencial** | sem isso a OS não pode nem começar | bloqueia; a OS não é liberada |
| **Necessária** | exigida pela causa nº 1 | trabalho para pela metade |
| **Facilitadora** | reduz tempo ou risco, mas há alternativa | atraso, não bloqueio |
| **Dispensável** | conveniência | nenhum |

O nível é por `(causa, ação)`, mas **essencial é calculado sobre a união** — se
qualquer hipótese plausível exigir, é essencial. Um item que é facilitador para a
causa 1 e essencial para a causa 2 sobe para essencial.

### 11.3 O que o dossiê já calcula sozinho

Boa parte do escopo não precisa ser digitada — a telemetria já sabe:

| Derivado | Fonte |
| --- | --- |
| tamanho do backup | espaço em uso nos volumes |
| mídia de destino necessária | tamanho + margem |
| modelo, capacidade e interface do disco de reposição | inventário |
| se é notebook (ferramenta e acesso diferentes) | inventário |
| **estado de criptografia do volume** | inventário |
| versão e edição do sistema, para mídia de recuperação | inventário |
| janela de indisponibilidade estimada | escopo + histórico |

**Volume criptografado é caso de nível essencial.** Se há criptografia ativa, a
chave de recuperação vira item que não pode faltar — e é exatamente o tipo de
coisa que se descobre tarde demais, com a máquina já aberta. O escopo tem que
exigir a chave **antes** de liberar a OS.

### 11.4 Máquina ligada × máquina desligada

São duas conversas, e o sistema precisa dizer qual é.

- **Ligada:** há telemetria, há dossiê, há hipótese com evidência. O escopo é
  derivado e a confiança é a do diagnóstico.
- **Desligada / sem agente:** não há observação atual. O escopo é derivado do
  **último dossiê conhecido** mais o sintoma declarado, e é marcado como
  **escopo cego** — confiança menor, lista de ferramentas mais larga por
  precaução, e a primeira ação em campo passa a ser *estabelecer observação*
  (ligar, medir, decidir), não *executar reparo*.

Escopo cego nunca se apresenta com a mesma cara de escopo derivado. A tela diz
qual dos dois é.

### 11.5 Quando o escopo dispensa a escada

O diagnóstico inicial (§10.5.1) é o que justifica ter pedido ao cliente que
abrisse chamado, e é também o que define o escopo inicial. Em parte dos casos
ele já basta:

- **Causa dominante ≥ 0,80 + ação de risco `baixo`** (classe declarada em
  `cause_requirement`: sem abertura do equipamento, sem perda de dado, reversível)
  ⇒ o escopo é
  liberado direto, sem escada. Forçar uma máquina que já se explicou é desgaste
  sem ganho de informação.
- **Caso contrário** ⇒ a escada roda antes, e o escopo é recalculado com a curva.

Essa é a regra que libera o supervisor de executar o super-teste em toda OS. E
ela é determinística: limiar + classe de risco da ação, nunca decisão do modelo
sozinho.

### 11.6 Validação da execução em campo

O supervisor é responsável por validar o que o técnico de campo fez — e
**validação é reteste, não relato**.

- O dispositivo volta a se comunicar; a **mesma escada** (mesmo perfil, mesma
  versão) roda de novo.
- Valida-se comparando **limiar antes × limiar depois**: quebrava no degrau 3,
  agora atravessa a escada inteira. Isso é evidência; "trocado e testado" não é.
- Se o limiar não se moveu, a OS não fecha como resolvida — vira causa
  reclassificada, e isso é dado de treino tão valioso quanto o acerto.
- O fechamento validado alimenta automaticamente o rótulo de recidiva 7/30d
  (§13.5).

### 11.7 Tabelas

- **`tool_catalog`** — `codigo`, `nome`, `tipo` (ferramenta, peça, insumo,
  credencial, mídia, software), `portatil` (bool), `custo_relativo`,
  `requer_aprovacao`.
- **`cause_requirement`** — `(causa, acao) → tool_codigo, nivel, quantidade,
  condicao` (ex.: `so_se_volume_criptografado`, `so_se_notebook`).
- **`os_scope`** — escopo materializado da OS: `chamado_id`, `diagnosis_id`,
  `itens[]` com nível resolvido, derivados calculados (tamanho de backup, mídia,
  peça), `modo` (`derivado` | `cego`), `dispensa_escada` (bool + motivo),
  `janela_estimada`.
- **`os_validation`** — `os_scope_id`, `stress_run_antes`, `stress_run_depois`,
  `limiar_antes`, `limiar_depois`, `veredito`
  (`resolvido` | `nao_resolvido` | `causa_reclassificada`), `validado_por`.

O nível de cada item é **derivado** de `cause_requirement` sobre as hipóteses —
nunca digitado à mão na OS. O que se digita à mão é exceção, e fica registrada
como tal.

---

## 12. Camada de texto — como a explicação é escrita

### 12.1 A rede não escreve o texto

Regra dura: **nenhuma frase mostrada ao técnico é gerada em runtime por modelo
generativo.** Se a rede escrevesse frase livre, tudo o que a arquitetura constrói
se perderia — probabilidade calibrada viraria parágrafo confiante, o técnico não
conseguiria auditar, e um erro de redação seria indistinguível de um erro de
diagnóstico.

A separação:

| Camada | Responsabilidade |
| --- | --- |
| Classificador | distribuição de probabilidade sobre causas do conjunto fechado |
| Motor de texto | template determinístico por `(status, causa, faixa de evidência)` |
| Front-end | preenche lacunas com os valores medidos e desenha a curva |

### 12.2 Tabela `text_template`

Campos: `chave` (`status.causa.variante`), `idioma`, `nivel`
(`tecnico` | `cliente`), `titulo`, `corpo`, `slots[]`, `versao`, `revisado_por`.

Slots são nomeados e tipados — `{degrau_quebra}`, `{duracao_trava}`,
`{metrica}`, `{valor_medido}`, `{limiar_esperado}`, `{probabilidade}`. O
renderizador falha alto se um slot exigido não tiver valor: melhor não mostrar
frase do que mostrar frase com buraco.

Exemplo de corpo:

> Parou de responder por {duracao_trava} sob carga de {peca} no degrau
> {degrau_quebra}. Causa provável: {causa} ({probabilidade}). O esperado nessa
> carga seria {limiar_esperado}; medimos {valor_medido}.

**Dois níveis obrigatórios.** O mesmo diagnóstico tem versão técnica (para o
supervisor) e versão cliente (linguagem simples, sem jargão) — é o que permite
a explicação "simples e rápida" sem perder a precisão de quem executa.

### 12.3 Onde o modelo generativo entra — e onde não entra

Entra **offline, na construção**: lê o corpus de fórum (§13) e propõe rascunho de
template para cada par `(status, causa)`, junto com a lista de sintomas em
linguagem de usuário que mapeiam para aquele status. Sai daí como sugestão, vai
para revisão humana, e só entra no banco com `revisado_por` preenchido.

Não entra **em runtime**, em nenhuma hipótese. O caminho do técnico é
`classificador → chave de template → render`.

### 12.4 Backend do texto

Os templates ficam no Postgres, servidos pelo `api-core` e cacheados no cliente
por `versao`. O motor devolve **chaves e valores**, nunca prosa:

```json
{
  "status": "trava_sob_carga_io",
  "abstain": false,
  "causas": [
    {"codigo": "disco_degradado", "prob": 0.72,
     "template": "trava_sob_carga_io.disco_degradado.v1",
     "slots": {"duracao_trava": "4,2s", "degrau_quebra": 3, "peca": "disco",
               "valor_medido": "310ms p99", "limiar_esperado": "<40ms p99"}}
  ],
  "proximos_testes": []
}
```

Isso torna o texto traduzível, versionável, testável e corrigível sem retreinar
nada.

---

## 13. Corpus de fórum — aquisição, rotulagem e uso

### 13.1 São dois corpora, com propósitos distintos

Não misturar. É o erro que mataria o projeto.

| Corpus | Conteúdo | Serve para |
| --- | --- | --- |
| **Externo** (fórum) | texto de casos humanos, sem telemetria | ontologia (§4), templates (§12), **priors** de frequência causa\|sintoma |
| **Interno** (TGDesk) | `stress_run` + curva + ação + recidiva | **treinar o classificador** |

O corpus de fórum, **em texto corrido**, não treina o classificador — não tem
curva, não tem limiar, não tem medida. Ele constrói o vocabulário e os priors
que a camada de regra usa enquanto o parque não gera volume próprio.

> **Revisão desta regra (§19).** Ela vale para a thread comum. Mas há um
> subconjunto — o **caso real**: sintoma relatado + **bloco de log colado** +
> resolução confirmada pelo criador — que carrega medida de verdade, porque o
> log traz valores e códigos literais. Esse subconjunto **pode** virar dado de
> treino, por simulação, e é o que destrava a rede antes de o parque crescer.
> Medido no dump do Superuser: **753 casos**, sendo 650 com log colado por quem
> relatou o problema.

### 13.2 Aquisição — ordem de preferência

1. **Data dump do Stack Exchange** (Superuser é exatamente o domínio-alvo).
   Publicado sob CC BY-SA, baixável em bloco, e já traz **resposta aceita e
   votos** — rótulo nativo, sem heurística. É por aqui que se começa.
2. Fóruns de thread com termos que permitam coleta, para o que o dump não cobre
   (hardware específico, OEM, drivers).
3. Qualquer outra fonte **só após verificar ToS e `robots.txt` caso a caso**.
   Coleta respeitosa: taxa limitada, identificada, incremental.

Somente texto. Sem imagens, sem anexos.

### 13.3 Rotulagem — a heurística primeira/última

Para fóruns sem campo de resposta aceita:

- **Rótulo de desfecho** = comparação entre a **primeira** mensagem do autor do
  tópico e a **última do próprio autor**. Classes: `resolvido`,
  `não resolvido`, `abandonado` (autor nunca voltou), `inconclusivo`.
- **Conteúdo causal** ≠ mensagem do autor. Na maioria das threads resolvidas a
  solução está na mensagem **de outra pessoa**, e a última do autor é só "valeu,
  resolveu". Segunda etapa obrigatória: seguir a citação, o agradecimento ou a
  referência para localizar a mensagem que carrega a causa. Sem isso o corpus
  vira milhares de "obrigado, funcionou" sem causa nenhuma.

**Filtros de descarte** (aplicados já na ingestão):

- autor nunca retornou ⇒ fora do conjunto de causas, mantido só para vocabulário
  de sintoma;
- desfecho por reinstalação de sistema, troca de máquina ou "sumiu sozinho"
  ⇒ informação causal nula;
- thread revivida meses depois por terceiro ⇒ separar como caso distinto;
- solução sem teste algum citado ⇒ prior fraco, marcado como tal.

### 13.4 Viés que permanece, e como é contido

Fórum sobrerrepresenta o difícil e o exótico; o caso trivial ninguém posta. E
"resolvido" continua significando "parei de reclamar", não "essa era a causa" —
a heurística melhora o rótulo, não o conserta.

Contenção: o corpus externo **só produz prior e vocabulário, nunca veredito**.
O prior é substituído por frequência interna assim que houver `stress_run`
fechado suficiente para a causa em questão. O decaimento é explícito na
configuração — não implícito no modelo:

> `peso_externo = k / (k + n_interno)`, com **k = 20**

Ou seja: com 0 casos internos o prior externo vale 1,0; com 20 vale 0,5; com 100
vale 0,17; e nunca chega a zero, porque causa rara continua precisando de prior.
`k` é campo de configuração por causa — causa em que o fórum é notoriamente
enviesado entra com `k` menor e sai de cena mais rápido.

`corpus_prior.peso_atual` guarda o valor calculado, recomputado a cada
fechamento de chamado. É consultável: dá para olhar uma probabilidade e saber
quanto dela ainda vem de fórum.

### 13.5 O rótulo bom é o interno

> chamado fechado = snapshot de telemetria antes + escada executada + ação
> tomada + **o mesmo dispositivo segue sob monitoramento depois**.

Se o sintoma não voltou em 7/30 dias, foi solução. Se voltou, foi paliativo.
Nenhum fórum consegue produzir esse rótulo — é a vantagem estrutural do produto,
e é o que empurra o módulo neural para o fim da fila, não para o começo.

### 13.6 O corpus define o catálogo — não o contrário

**Ordem causal da missão:** a pesquisa nos fóruns, a análise que os participantes
fizeram e a resolução declarada pelo criador do tópico é que definem **quais
testes e qual telemetria precisam existir**. Não se parte do que o agente já
sabe medir; parte-se do que os casos reais exigiram para serem resolvidos.

Consequência direta: os 30 testes hoje em `diagnostic_text.dart` deixam de ser
ponto de partida e viram **conjunto candidato**, sujeito ao mesmo crivo.

#### Derivação, em quatro passagens

1. **Extração.** Para cada `corpus_case` resolvido: que sinal foi olhado, que
   teste foi rodado, que ferramenta foi usada, que linha de log decidiu.
2. **Agregação.** Frequência de cada sinal e de cada teste por causa. O que
   aparece em muitos casos e separa bem é essencial; o que aparece pouco ou não
   separa nada é dispensável.
3. **Viabilidade.** Cada sinal exigido recebe um veredito:

   | Veredito | Significado | Destino |
   | --- | --- | --- |
   | `existe` | o agente já mede | mapear para o teste atual |
   | `adaptar` | mede parcial, precisa de série ou resolução maior | backlog de agente |
   | `construir` | não existe, mas é viável | backlog de agente |
   | `inviável` | exige kernel, hardware externo ou inspeção física | **lacuna declarada** |

   Lacuna inviável não some: entra em `negative_status.limitacoes` e aparece na
   tela como "esta causa não é separável à distância".

4. **Poda.** Teste candidato que nenhum caso do corpus usou para decidir sai do
   fluxo principal. Sinal que nenhuma causa consome sai da telemetria — carregar
   dado que não muda probabilidade é custo puro.

#### Cobertura — critério de aceite da missão

Com o corpus na mão, a pergunta "detectamos todos os tipos de problema?" vira um
número mensurável:

> **cobertura** = fração dos `corpus_case` resolvidos cujo desfecho o catálogo
> atual de testes + telemetria **conseguiria** ter discriminado.

Medida por classe de problema (disco, memória, térmico, energia, software,
rede, driver), não em agregado — cobertura alta na média pode esconder uma
classe inteira em zero. A cada teste adicionado, mede-se de novo. É o que
substitui achismo sobre o catálogo estar completo.

Tabela `coverage_report`: `(classe, versao_catalogo) → casos_total,
casos_discriminaveis, cobertura, lacunas[]`.

### 13.7 Tabelas do corpus

- **`corpus_thread`** — `id`, `fonte`, `url`, `titulo`, `licenca`, `data`,
  `hash`, `autor_id_criador`, `total_mensagens`, `resolvido_nativo`
  (quando a fonte tem resposta aceita).

- **`corpus_post`** — a granularidade que permite a filtragem que você quer.
  Uma linha por mensagem: `thread_id`, `seq` (ordem na thread), `autor_id`,
  `is_criador` (bool), `is_primeira_do_autor`, `is_ultima_do_autor`,
  `responde_a_seq`, `cita_seq`, `data`, `corpo_txt`, `tem_bloco_log`,
  `logs_extraidos[]`.

  Com essas colunas se consulta direto:
  *só o criador* (`is_criador = true`), *primeira e última do criador*
  (`is_primeira_do_autor` / `is_ultima_do_autor`), *um participante específico*
  (`autor_id`), *a mensagem que a última do criador cita* (`cita_seq`), ou
  *toda a thread em ordem* (`seq`). É o que torna a filtragem por tópico
  completa em vez de heurística sobre texto corrido.

- **`corpus_case`** — uma linha por thread útil: `thread_id`, sintoma
  normalizado, `desfecho` (`resolvido` | `nao_resolvido` | `abandonado` |
  `inconclusivo`), `seq_da_causa` (aponta para o `corpus_post` que carrega a
  solução), causa extraída, testes citados, ferramentas citadas, confiança da
  extração.

- **`corpus_prior`** — `(status, causa) → frequência, n, peso_atual`.

Somente texto, sem imagens. `corpo_txt` guarda o corpo já limpo de marcação;
`logs_extraidos[]` guarda os blocos de log separados, que são a matéria-prima de
`log_signature` (§8).

Ficam em schema separado do dado operacional. Nunca são lidas em runtime pelo
caminho do diagnóstico — alimentam `negative_status`, `text_template` e
`corpus_prior` em etapa de construção.

---

## 14. Gate de calibração — como um modelo entra em produção

O documento repete que "modelo só é promovido com calibração verificada". Este
capítulo diz o que isso significa em número, senão a regra é slogan.

### 14.1 Promoção é por causa, não por modelo

Cada cabeçote de status tem, por causa, um de três estados:

| Estado | Quem responde | O que aparece na tela |
| --- | --- | --- |
| `regra` | camada determinística + `corpus_prior` | probabilidade da regra, marcada como prior |
| `sombra` | rede roda, **saída descartada**, só registrada | nada; a rede está sendo medida contra a realidade |
| `promovido` | rede | probabilidade da rede, com calibração visível (§10.5.3) |

Sombra é obrigatória: nenhuma causa vai de `regra` a `promovido` sem ter passado
por um período em que a rede respondeu no escuro e errou sem custo.

### 14.2 Critérios de promoção

Todos precisam valer ao mesmo tempo, no conjunto de validação **temporalmente
separado** (treino no passado, validação no futuro — nunca amostragem aleatória,
que vaza o mesmo dispositivo para os dois lados):

- **n mínimo:** 150 casos fechados e validados por reteste (§11.6) para aquela
  causa. Abaixo disso a faixa de confiança não é estimável, e o rótulo na tela é
  "sem histórico suficiente".
- **ECE ≤ 0,05** por faixa de 10 pontos percentuais. Erro de calibração, não de
  acurácia — é o requisito de engenharia declarado em §1.
- **Nenhuma faixa individual com desvio > 15 pp.** Média boa com uma faixa
  mentindo é exatamente o modo de falha que o técnico sente e o agregado esconde.
- **Não pior que a regra que substitui**, medido em log-loss. Rede que empata com
  a regra não entra — complexidade sem ganho.
- **Abstenção funcionando:** nos casos em que o modelo abstém, a distribuição
  real precisa ser de fato ambígua. Abstenção que esconde erro sistemático é pior
  que erro declarado.

### 14.3 Rebaixamento automático

Promoção não é permanente. O `api-core` recalcula a calibração em janela móvel
sobre casos fechados; se o ECE da causa passar de 0,08 ou uma faixa desviar mais
de 20 pp, a causa **volta para `regra`** sozinha, sem intervenção, e o evento
fica registrado. É a contrapartida do §10.5.3: se o técnico consegue ver o modelo
mentindo, o servidor tem que ver antes dele.

### 14.4 O caminho abaixo do n mínimo — definido, não pendente

n = 150 por causa não é alcançável com o parque atual, e o sistema **não fica
esperando**. O caminho entre zero e a promoção é ele mesmo o produto, com
comportamento definido em cada faixa:

| `n_interno` da causa | Quem responde | O que a tela mostra |
| --- | --- | --- |
| 0–9 | regra + prior externo | probabilidade marcada como **prior de fórum**; nível 2 de alerta bloqueado |
| 10–29 | regra, prior decaindo (`k=20`) | probabilidade normal; faixa de confiança larga |
| 30–149 | regra; rede em **sombra**, medida a cada fechamento | "sem histórico suficiente" no lugar da calibração visível |
| ≥ 150 | rede, se passar §14.2 | calibração visível com histórico real |

A consequência é que **nenhuma faixa é um estado degradado**. Com n = 0 o produto
já responde — com regra, prior de fórum e evidência literal — e a única coisa que
falta é o número de calibração, que aparece declarado como ausente em vez de
inventado. A rede não é pré-requisito de nada: é o que substitui a regra, causa a
causa, quando houver dado que prove que ela é melhor.

Isso fecha o parâmetro: 150 é o gate de promoção, não o gate de funcionamento.

### 14.5 Tabela `model_version`

`codigo`, `status_codigo`, `causa_codigo`, `estado`
(`sombra` | `promovido` | `rebaixado`), `treinado_em`, `n_treino`, `n_validacao`,
`ece`, `log_loss`, `log_loss_regra`, `promovido_em`, `promovido_por`,
`rebaixado_em`, `motivo_rebaixamento`, `hash_pesos`.

Toda `diagnosis` gravada aponta para a `model_version` que a produziu. Sem isso
não é possível auditar retroativamente um diagnóstico errado — e auditar
retroativamente é a única forma de descobrir que o modelo começou a mentir.

---

## 15. Ordem de execução

**Trilha A — corpus (corre primeiro; A4 é pré-requisito do passo 2):**

- A1. Ingestão do dump do Stack Exchange → `corpus_thread` / `corpus_post` /
  `corpus_case`.
- A2. Rotulagem primeira/última + extração da mensagem causal (`seq_da_causa`).
- A3. Derivação de `negative_status`, `corpus_prior`, `log_signature` e rascunho
  de `text_template` — **com revisão humana antes de entrar no banco.**
- A4. **Derivação do catálogo de testes e da telemetria** (§13.6): extração,
  agregação, viabilidade e poda. Saída: lista definitiva de testes e sinais,
  backlog de agente por veredito, lacunas declaradas e primeiro
  `coverage_report`.

**A trilha A não é paralela até o fim: A4 destrava o passo 2.** A escada só pode
ser composta depois que o corpus disser quais estágios precisam existir.

**Trilha B — caminho crítico do produto:**

1. **Catálogo `negative_status`** — sem isso nada tem chave. Consome A3, mas a
   decisão final é humana. Trabalho de ontologia antes de código.
2. **Escada unificada** — **depende de A4**. Implementar os estágios que o corpus
   exigiu (adaptando os existentes, construindo os que faltam, podando os que
   nenhum caso usou); emitir amostra por degrau em vez de veredito; sequência
   única (peça por peça → combinado); gates de segurança e consentimento.
3. **Detecção de trava por relógio externo** — heartbeat + detecção de buraco no
   `api-core`, ring buffer no agente.
4. **Telemetria contínua em duas velocidades** — **sinais definidos por A4**;
   agregados + top-N sempre;
   rajada sob evento reaproveitando o ring buffer; política de privacidade e
   retenção; extração do log de eventos com classificação determinística de
   reboot/desligamento.
5. **Persistência do dossiê** — as tabelas. A partir daqui já se acumula dado
   mesmo sem inteligência nenhuma.

**Troca de motor, escopo e simplificação do fluxo (6–14):**

6. Motor de diagnóstico em `internal/diagnostico`, camada de regra + `corpus_prior` + `log_signature`
   apenas. Contrato fechado.
7. Camada de texto — `text_template`, renderizador, dois níveis (técnico e
   cliente).
8. Front-end do técnico — as quatro telas e os cinco estados, substituindo
   `diagnostics_dialog.dart`; menu de 30 testes sai do fluxo principal.
9. **Camada de pré-cálculo** (§10.4) — status provável, tipo sugerido, perfil de
   escada, gates, faixa de duração e nível de alerta calculados no servidor e
   empurrados pelo canal, com invalidação explícita por versão de origem.
10. **Refatoração do `support_page.dart`** — passo próprio, ~2000 linhas. Reduz
    o fluxo de chamado à ação única consumindo **apenas** o pré-cálculo do passo 9;
    nenhuma busca ao montar, nenhum cálculo no cliente. Depende de 7, 8 e 9
    estarem fechados — refatorar antes disso obrigaria a refazer.
11. **Escopo da OS** (§11) — `tool_catalog`, `cause_requirement`, derivação do
    escopo sobre o top-3, níveis essencial/necessária/facilitadora/dispensável,
    derivados do dossiê (backup, mídia, peça, criptografia), escopo cego para
    máquina desligada, regra de dispensa da escada e validação por reteste.
12. Alertas ao cliente — dois níveis, anti-repetição, rebaixamento automático.
13. Rótulo de recidiva 7/30d, alimentado pela telemetria existente.
14. Rede treinada por status, rodando primeiro em **sombra** e promovida causa a
    causa apenas pelo **gate de calibração** (§14); peso do prior externo
    decaindo conforme o dado interno cresce; rebaixamento automático ativo desde
    a primeira promoção.

---

## 16. Goal da missão

> Construir o pipeline de diagnóstico probabilístico do TGDesk: ingestão de
> corpus público de casos resolvidos para derivar ontologia, priors, assinaturas
> de log e templates de texto; catálogo fechado de status negativos; telemetria
> contínua em duas velocidades com política de privacidade; bateria de esforço
> unificada em escada emitindo série por degrau; detecção de trava com relógio
> externo; persistência do dossiê; o motor de diagnóstico dentro do `api-core`; o
> front-end de quatro telas para o técnico substituindo o menu de 30 testes;
> fluxo de chamado reduzido a uma única ação com previsão de duração por classe
> de dispositivo; escopo de OS derivado do top-3 com ferramentas em quatro níveis
> e validação por reteste; e alertas ao cliente em dois níveis —
> servindo top-3 causas calibradas com abstenção e explicação por template
> determinístico, por regra primeiro e por rede treinada depois — promovida causa
> a causa por gate de calibração, com rebaixamento automático — sem alterar o
> plano de controle WebSocket existente.

---

## 17. Invariantes da missão

- Tudo é WebSocket; polling é proibido. O motor não abre canal com cliente.
- **Um container por projeto.** A rede vive dentro do `api-core`; os pesos moram
  em `model_version`, nunca em volume.
- Uma lógica só: mesma base para todos os níveis; a chave só dá permissão.
- Sem compatibilidade retroativa.
- Gate de segurança do stress é regra determinística, nunca decisão de modelo.
- Modelo só é promovido com calibração verificada; abstenção sempre disponível.
- Nenhum veredito sem curva que o sustente na tela.
- **Nenhum texto gerado por modelo em runtime.** Toda frase vem de template
  revisado; o modelo generativo só atua offline, na construção, sob revisão.
- Corpus externo produz prior e vocabulário; nunca veredito.
- **O corpus define o catálogo de testes e a telemetria**, não o inverso. Sinal
  que nenhuma causa consome não entra; teste que nenhum caso usou para decidir
  sai do fluxo principal.
- Lacuna inviável é declarada, nunca omitida: a tela diz quando uma causa não é
  separável à distância.
- Cobertura é medida por classe de problema, nunca em agregado.
- Escopo de OS deriva do **top-3**, não da causa vencedora; essencial é calculado
  sobre a união das hipóteses plausíveis.
- Nível de item é derivado de `cause_requirement`; digitação manual é exceção
  registrada.
- Escopo cego (máquina desligada) nunca se apresenta como escopo derivado.
- **Validação é reteste, não relato:** OS só fecha como resolvida se o limiar se
  moveu na mesma escada.
- Coleta só de fonte cujos termos permitem; somente texto, sem imagens.
- **Se o sistema operacional já diz, não se adivinha.** Classe de evento é regra
  determinística; o modelo só distribui probabilidade dentro da classe.
- Linha de comando, título de janela e caminho de usuário não sobem por padrão —
  só em rajada de incidente, com consentimento e retenção curta.
- Alerta ao cliente nível 2 (causa nomeada) exige barra de confiança mais alta
  que a tela do técnico; nível 1 descreve sintoma e nunca nomeia causa.
- Nenhum alerta sem ação possível.
- **Uma decisão humana entre o chamado chegar e a escada começar:** consentir e
  executar. Todo o resto o servidor propõe.
- Nenhuma execução sem estimativa de duração em faixa; incerteza aparece, nunca
  se esconde.
- Causa de fechamento vem do conjunto fechado, nunca texto livre — é o dado de
  treino.
- Nenhuma tela calcula ou busca ao montar: tudo chega pré-calculado pelo canal,
  com a versão de origem que o gerou.
- **O agente mede, não julga:** emite amostra com `load_level`, nunca veredito,
  nunca limiar calculado localmente. A única decisão local é gate de segurança.
- Curva com buraco reduz confiança declarada; nunca é interpolada em silêncio.
- **Promoção de modelo é por causa, precedida de sombra, e reversível:** o
  rebaixamento é automático e não espera humano.
- Toda `diagnosis` aponta para a `model_version` que a produziu — diagnóstico não
  auditável retroativamente não deveria ter sido mostrado.
- Retenção é número declarado e expurgo é job, nunca limpeza manual; o derivado é
  calculado antes de o bruto ser apagado.
- **Caso simulado é marcado como simulado.** Treina, nunca calibra: métrica de
  calibração só se calcula com caso interno real (§19.3).
- **Simulação nunca inventa valor.** O que se sintetiza é o formato; o número
  vem do log do caso. Campo sem valor no caso fica **ausente**, nunca zero.
- **Simulação treina; realidade promove.** Rede que só viu caso simulado roda em
  sombra, não em produção.
- **A RAT do técnico é a verdade contra a qual a suposição da rede é medida**
  (§19.4). Divergência ajusta a rede, não o técnico.
- **Nenhum limiar mora no código.** Todo número deste documento é configuração
  versionada (§18); mudar um valor de escada gera perfil novo, porque execuções
  de perfis diferentes não são comparáveis.

---

## 18. Parâmetros — valores de partida

Tudo o que o documento chama de limiar, janela ou teto está aqui, com o valor
inicial e onde é definido. **Nenhum deles é constante de código:** todos vivem em
configuração versionada, e a versão vigente acompanha cada `stress_run`,
`diagnosis` e alerta gravados.

| Parâmetro | Valor `v1` | Onde |
| --- | --- | --- |
| degraus por estágio | 5 (20/40/60/80/100 % do teto local) | §5 |
| duração do degrau / descarte inicial | 90 s / 15 s | §5 |
| amostragem durante a escada | 1 Hz | §5 |
| estágio combinado | 100 %, 180 s | §5 |
| repetição do degrau de quebra | 1× | §5 |
| teto da escada completa | 45 min | §5 |
| parada por temperatura | 95 °C, ou 90 °C por 10 s | §5 |
| parada por trava | 5 s | §5 |
| bloqueio do estágio combinado | ≥ 75 °C em repouso | §5 |
| frequência do heartbeat | 2 Hz | §6 |
| buraco que abre `stall_start` | 1,5 s | §6 |
| ring buffer do agente | 60 s a 10 Hz | §6 |
| tolerância de conciliação agente × servidor | 500 ms | §6 |
| amostra da telemetria contínua | 60 s, lote a cada 5 min | §7.1 |
| processos reportados | top-5 por CPU, RAM e I/O | §7.1 |
| pico sustentado (gatilho) | ≥ 90 % por 120 s, ou RAM livre < 5 % | §7.1 |
| recorte da rajada | −60 s / +30 s | §7.1 |
| teto de rajadas | 6 por dispositivo por dia | §7.1 |
| retenção | tabela completa | §7.4 |
| alerta nível 2 | prob ≥ 0,90 **e** causa promovida ou ≥ 30 casos | §9 |
| alerta some | prob < 0,50 | §9 |
| anti-repetição de alerta | 14 dias; 30 dias se descartado | §9 |
| alertas simultâneos | máx. 2 por dispositivo | §9 |
| teto da probabilidade inicial | 0,85 | §10.5.1 |
| causas mostradas | máx. 3 | §1, §10.5 |
| dispensa da escada | prob ≥ 0,80 + ação de risco baixo | §11.5 |
| regra de levar item | `prob × custo_de_faltar ≥ custo_de_levar` | §11.1 |
| decaimento do prior externo | `k / (k + n)`, k = 20 | §13.4 |
| n mínimo para promoção | 150 casos validados por causa | §14.2 |
| ECE máximo para promoção / rebaixamento | 0,05 / 0,08 | §14.2, §14.3 |
| desvio máximo por faixa | 15 pp / 20 pp para rebaixar | §14.2, §14.3 |
| janela de recidiva | 7 e 30 dias | §13.5 |

Os valores da escada e da telemetria são revisáveis por A4 (§13.6) — é o corpus
que diz se um estágio precisa existir. Os valores de calibração e de alerta não
são: mexer neles é decisão de produto, e cada mudança invalida a comparação com o
histórico anterior, por isso gera versão nova em vez de edição no lugar.

---

## 19. Caso real, simulação e o laço com a RAT

Este capítulo corrige a **ordem** do restante do documento. A §15 punha a rede
no fim da fila porque supunha que o único rótulo bom viria do parque próprio
(§13.5). Isso continua verdade para o rótulo *definitivo* — mas não obriga a
rede a esperar, e esperar custa caro: sem rede, cada estágio da escada entrega
menos do que poderia.

### 19.1 O que é um caso real

Não é toda thread resolvida. É o subconjunto que carrega **medida**:

> **sintoma relatado** + **bloco de log colado** (números e strings literais) +
> **resolução confirmada pelo criador** — descartadas imagens e anexos.

O log é o que muda tudo. "Meu PC trava" é vocabulário; `Event ID 51`,
`0x0000007A`, `Reallocated_Sector_Ct 12`, `CPU 97 °C` são **medidas**, com
unidade, no mesmo formato que a telemetria do agente coleta. Um caso desses não
é relato: é um exame já feito, por outra pessoa, com o desfecho anotado.

Medido no dump do Superuser: **753 casos** (650 com log colado pelo próprio
autor), distribuídos em disco 168, boot 164, trava 161, memória 76, driver 37,
energia 29, e cauda menor nas demais classes.

### 19.2 Os casos reais fazem duas coisas ao mesmo tempo

É a inversão que estava faltando no documento — as duas saem da mesma passagem,
em paralelo, não em sequência:

1. **Parametrizam o teste unificado.** Cada caso diz qual medida decidiu, em que
   faixa, sob que carga. Isso é o degrau da escada e o limiar dele, vindos de
   caso real em vez de arbítrio.
2. **Definem a telemetria necessária.** A pergunta que o dossiê passivo tem que
   responder não é "o que dá para medir?", é **"o que é preciso saber para
   apontar a peça a trocar ou o upgrade a fazer?"**. Um caso real que terminou em
   "troque o disco" diz exatamente quais leituras sustentavam essa conclusão —
   e, por consequência, quais leituras a telemetria precisa carregar.

Isso reordena §13.6: a derivação do catálogo deixa de ser um passo isolado e
passa a ser **um dos dois produtos** da leitura dos casos reais.

### 19.3 Simulação — o caso real vira exemplo de treino

Um caso real tem entrada (as medidas do log) e saída (a causa confirmada). Falta
só a forma: telemetria e resultado de teste unificado no formato do TGDesk.

> **caso real → medidas extraídas → dossiê sintético no formato da escada →
> exemplo de treino rotulado com a causa que os humanos confirmaram**

O alvo do treino é explícito: **a rede tem que chegar ao mesmo desfecho a que o
grupo de humanos chegou naquele caso.** É um rótulo que já existe, gratuito e em
volume — 753 exemplos hoje, contra os 150 por causa que §14.2 exige e que o
parque atual levaria anos para produzir.

**O risco, dito antes de alguém descobrir sozinho:** uma rede treinada em
telemetria simulada aprende, em parte, o simulador. Três contenções, todas
obrigatórias:

- **Os valores vêm do log, não de gerador.** O que se sintetiza é o *formato*
  (colocar `Reallocated_Sector_Ct 12` no campo certo do dossiê), nunca o número.
  Onde o caso não disser o valor, o campo fica **ausente** — e ausência é
  informação, não é zero.
- **Caso simulado é marcado como simulado**, sempre, em coluna própria. Nenhuma
  métrica de calibração (§14.2) pode ser calculada só com eles.
- **A promoção continua exigindo caso interno** (§14.4). Simulação treina;
  realidade promove. Uma rede que só viu simulação roda em sombra, não em
  produção.

### 19.4 O laço que fecha: a RAT contra a suposição

A parte que faltava para o aprendizado não parar no primeiro treino.

Hoje o técnico já produz uma **RAT** — o relatório de atendimento, construído no
fluxo da OS, dizendo o que ele encontrou e o que fez. Ela é a realidade. A
suposição da rede é o que o sistema achou antes.

> A cada atendimento fechado: **suposição da rede × RAT do técnico**, comparadas
> campo a campo, com o supervisor avaliando.

Disso saem três coisas, e nenhuma delas existe hoje:

- **O rótulo de treino de melhor qualidade que o produto consegue.** Não é
  "resolvido/não resolvido": é *a causa que a rede apontou* contra *a causa que
  o técnico encontrou com a máquina na mão*.
- **A calibração medida em campo.** É a evidência que §14.2 e §10.5.3 exigem, e
  é o que permite dizer "quando dizemos 70–80%, acertamos 74% em 112 casos" com
  números que vieram de atendimento real.
- **A resposta parcial melhorando por estágio.** Como a rede vê a suposição
  sendo corrigida, ela passa a acertar mais cedo — o valor não está só no
  veredito final, está em o estágio 2 já dizer o que antes só o estágio 5 dizia.

**Regras do laço, para ele não virar teatro:**

- A avaliação é **estruturada**, do conjunto fechado de causas: o técnico marca
  a causa encontrada, não escreve texto livre (§10.3).
- O supervisor avalia se a suposição **ajudou, atrapalhou ou foi indiferente**.
  Uma rede que acerta a causa mas sugere o teste errado precisa ser corrigida
  nas duas dimensões.
- **Divergência não é erro do técnico.** Quando a RAT contradiz a rede, o que se
  ajusta é a rede — e o caso vira exemplo de treino com peso maior, porque é
  justamente onde ela estava errada.
- A RAT continua sendo **documento do atendimento**, não formulário de treino.
  O que o treino consome é o que ela já registra; pedir campo a mais só para
  alimentar modelo transformaria o técnico em rotulador.

### 19.5 Ordem revisada

O que este capítulo reordena, em relação a §15:

| Antes | Agora |
| --- | --- |
| corpus dá prior e vocabulário; rede espera o parque | corpus dá prior, vocabulário **e casos reais**; a rede começa a treinar com eles |
| catálogo de testes derivado em passo isolado (A4) | catálogo e telemetria derivados **junto** com os casos reais, na mesma passagem |
| rede é o passo 14, no fim | rede entra em **sombra** assim que houver casos simulados; segue para promoção com casos internos |
| validação = reteste (§11.6) | reteste **mais** o laço RAT × suposição, que é o que faz a rede aprender continuamente |

O que **não** muda, e não deve mudar: a promoção por gate de calibração, a
abstenção sempre disponível, o texto por template, e a regra de que nenhum
veredito aparece sem a curva que o sustenta.

