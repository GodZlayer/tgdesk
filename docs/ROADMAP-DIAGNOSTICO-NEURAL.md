# Roadmap de execução — Diagnóstico Probabilístico

**Arquivo de estado da missão.** O que define *o que* construir é
[`ARQUITETURA-DIAGNOSTICO-NEURAL.md`](ARQUITETURA-DIAGNOSTICO-NEURAL.md); este
aqui registra *o que já foi construído, o que falta e como retomar*.

> **Se a sessão acabou no meio:** leia §0 (estado atual) e §2 (log). O item
> marcado `EM CURSO` diz exatamente onde parar de ler e começar a trabalhar.
> Nenhuma decisão precisa ser reconstruída de memória — o que foi decidido está
> em §3.

**Regra de manutenção:** este arquivo é atualizado **no mesmo commit** que a
mudança que ele descreve. Roadmap que se atualiza depois é roadmap que mente.

---

## 0. Estado atual

| Campo | Valor |
| --- | --- |
| Última atualização | 2026-08-12 |
| Passo em curso | **pipeline em produção**: ontologia gravada, rede treinada em sombra, parque reduzido aos 4 reais |
| Próxima ação concreta | build do cliente para as telas chegarem às 3 máquinas (o código está ligado; `flutter analyze` limpo) |
| Migration mais alta no repo | `0078_rede_neural_e_laco_rat.sql` |
| Migration aplicada em produção | `0078` (era **0071** até hoje) |
| Bloqueio ativo | nenhum bloqueia o teste real; o volume de treino agora depende do laço RAT rodando no parque |

**Concluídos e verificados:** B5 (persistência), B3 (detecção de trava), A1
(ingestão), A2 (rotulagem). As 76 migrations aplicam do zero em Postgres 16 com
as invariantes testadas contra o banco; 40+ testes passando nos dois módulos,
`-race` limpo. Ver §2.

### Por que a próxima coisa é a trilha A

Com B5 e B3 prontos, o que sobra em B ou depende de A4 (B2 escada, B4 sinais da
telemetria) ou depende de ontologia que só o corpus produz (B1, B6, B7). Seguir
em B agora significaria inventar status e causas — e chute vira rótulo de
treino, que é o erro mais caro possível neste projeto.

*(Esse parágrafo é de quando A1 nem tinha começado; ficou aqui porque a razão
continua valendo. As tabelas do corpus existem desde a 0075.)*

### Por que começar por B5 e não por B1

A ordem de §15 é de *dependência lógica*, não de execução literal. B1
(`negative_status`) e B2 (escada) dependem do corpus (A4), que é trabalho de
ingestão e revisão humana. A persistência (B5) **não depende de nenhum dos
dois**: as tabelas existem independentemente de quais status e estágios as
preencherão, e sem elas nada mais pode ser gravado.

Construir o esquema primeiro também vale como verificação do documento: tabela
que não consegue ser escrita em DDL é tabela que estava mal especificada.

---

## 1. Checklist

Legenda: `[ ]` não iniciado · `[~]` em curso · `[x]` concluído e verificado ·
`[!]` bloqueado (motivo no log).

### Trilha A — corpus

- [x] **A1** Ingestão do dump do Stack Exchange → `corpus_thread` / `corpus_post`
      / `corpus_case` — dump completo, ingestor validado, carga rodando no banco
      dedicado
- [x] **A2** Rotulagem: rótulo nativo primeiro, heurística primeira/última como
      fallback, `seq_da_causa` apontando a mensagem causal
- [~] **A3** Derivação — extração de sinais/testes roda; falta `negative_status`,
      `log_signature` e rascunho de `text_template` (e toda a revisão humana)
- [~] **A4** Derivação do catálogo (§13.6) — as quatro passagens rodam, e a saída
      já é utilizável: backlog de sinais por evidência + cobertura crua e
      instrumentada por classe. **Falta a revisão humana**, que é o que destrava
      B2 e B4.

### Trilha B — produto

- [ ] **B1** Catálogo `negative_status` (consome A3; decisão final humana)
- [ ] **B2** Escada unificada — depende de **A4**
- [x] **B3** Detecção de trava por relógio externo — servidor + agente, 12
      testes, `-race` limpo
- [ ] **B4** Telemetria contínua em duas velocidades — sinais definidos por **A4**
- [x] **B5** Persistência do dossiê — migrations 0072/0073/0074, aplicadas e
      testadas do zero
- [x] **B6** `tgdesk-brain` no compose — serviço, contrato, camada de regra e
      cliente no `api-core`; testado ponta a ponta contra o container real
- [~] **B7** Camada de texto — tabela, renderizador e os dois níveis prontos e
      testados; falta o **conteúdo** dos templates (vem de A3) e o cache por versão
- [x] **B8** Front-end do técnico — quatro telas ligadas ao canal via
      `diagnostico_page.dart`, entrada em `devices_page.dart`; o menu de 30
      testes virou "avançado", fora do fluxo normal
- [x] **B9** Camada de pré-cálculo — produtor em `dossie_passivo.go`, entregue
      no `snapshot` do canal; a fonte de evidência cresce quando B4 existir
- [ ] **B10** Refatoração do `support_page.dart` — depende de B7, B8, B9
- [~] **B11** Escopo da OS (§11) — esquema (0076) e derivação testados; falta
      ligar ao banco e os derivados do dossiê (depende de A3)
- [~] **B12** Alertas ao cliente — decisão de nível, anti-repetição, rebaixamento
      e teto prontos e testados; falta o disparo pelo canal e o texto (B7)
- [~] **B13** Recidiva 7/30d — avaliação pronta e testada; falta o job que varre
      `idx_diagnosis_recidiva_pendente` e grava
- [ ] **B14** Rede treinada por status + gate de calibração (§14)

### Verificação transversal (não é passo, é critério)

- [x] Nenhum limiar hard-coded — os 50 parâmetros da §18 vivem em `diag_param`,
      versionados, com a seção que justifica cada um (falta o código *consumir*
      a tabela, o que acontece em cada passo que usar um limiar)
- [ ] Nenhuma tela busca dado ao montar (§10.4)
- [ ] Nenhum polling introduzido (invariante §17)
- [ ] Toda `diagnosis` aponta para a `model_version` que a produziu

---

## 2. Log de execução

Ordem cronológica inversa (mais recente no topo). Cada entrada diz **o que
mudou**, **em quais arquivos** e **o que ficou faltando**.

### 2026-08-13 — TELEMETRIA LOCAL, EXAME COMO EVIDÊNCIA, E O CASO REAL

Quatro coisas, e a primeira muda o que o produto consegue saber.

**Telemetria local com entrega diferida.** Até aqui a telemetria só existia se
houvesse conexão no instante da coleta — e a máquina sem internet é justamente
a que costuma estar com problema: o buraco no histórico coincidia com o período
que mais interessa.

Agora a coleta é local e a entrega é oportunista. Spool em disco, janela de
5 min, append-only, teto de 64 MB. A linha só sai depois que o servidor aceita:
queda de conexão custa reenvio, nunca perda. O carimbo é o da COLETA.

*A janela de 5 min custou uma versão para aparecer:* com rotação horária, o
arquivo aberto não pode ser entregue, e uma máquina ONLINE esperava até 60 min
para mandar a primeira amostra — o oposto do requisito.

**Custo, medido.** A coleta contínua é só syscall:

| | por amostra |
| --- | --- |
| coleta barata | **105 µs** |
| script PowerShell | **9–13 s** |

Cinco ordens de grandeza. Nas máquinas: 117 MB no total dos 4 processos, CPU
praticamente zero, spool drenando (1,8 KB pendentes).

**Duas lacunas da taxonomia fechadas:** `commit` separa "memória insuficiente"
de "memória ocupada"; `handles` e `threads` tornam vazamento detectável — é o
problema que só aparece na derivada.

**O exame virou evidência.** `diagnostic_runs.results` acumulava e nunca era
lido: o técnico rodava o teste completo e o diagnóstico não mudava. A pior
combinação possível, porque o exame custa tempo da máquina do cliente.

A extração mais valiosa é a superfície: 240 regiões cronometradas separam três
coisas que a telemetria confunde — **erro de leitura** (degradado, backup
urgente), **região lenta isolada** (setor morrendo) e **todas lentas por igual**
(lento, upgrade planejado). A primeira e a terceira são a distinção que mais
muda dinheiro.

**A varredura lia o disco INTEIRO.** `for diskRead < disk.Size`. Medido durante
o exame autorizado: 1 TB a 341 MB/s ≈ 50 min por máquina, toda vez, com
desgaste e calor no computador do cliente. As "240 regiões" eram baldes de
agregação sobre uma leitura completa. Passa a amostrar: 1,9 GB, segundos.

**O caso real vira exemplo de treino.** O par (evidência, causa) só existe no
fechamento: as medidas vêm do dossiê e do exame, o rótulo vem do técnico que
abriu a máquina. Nenhum dos dois sozinho ensina. Era o que faltava para o
conjunto deixar de ser 100% simulado de fórum.

**Central do supervisor.** Admin e supervisor são papéis diferentes, não níveis
do mesmo: o admin administra o PRODUTO e muda raramente; o supervisor opera o
PARQUE. A central agrupa por organização, ordenada por urgência.

### 2026-08-13 — LENTIDÃO É DOIS STATUS, e a medida que faltava

Correção vinda de quem convive com as máquinas: *"'lentidão persistente' não é
correto nem para Dani nem para Daniel — Daniel tem lentidões ocasionais
rápidas, Dani tem momentos de lentidão profunda; o sentimento é diferente,
quanto a causa e a solução também"*.

Estava certo, e o corpus nunca daria isso: no fórum os dois casos se escrevem
"slow". Um status só (`lentidao_persistente`) colapsava dois fenômenos com
condutas OPOSTAS — controlar um processo contra trocar uma peça.

**O histograma confirmou antes de eu mudar qualquer coisa:**

| | amostras de CPU | acima de 95% | taxa | média |
| --- | --- | --- | --- | --- |
| Daniel | 97.025 | 422 | **2,17%** | 29% |
| Dani | 66.692 | 31 | **0,19%** | 15% |

Dez vezes mais pico no Daniel — e a lentidão **mais severa** é a da Dani. Não é
intensidade, é FORMA.

**O que isso revelou:** a lentidão da Dani não era explicada por NENHUM sinal
coletado. CPU tranquila, memória tranquila. A métrica `storage` que existia era
**ocupação** (94% cheio), não atividade. Disco cheio e disco lento são coisas
diferentes, e só o primeiro estava sendo medido.

**A medida nova** (`disk_activity` no agente, 1.2.53): `busy_pct`, `latency_ms`
e `queue_length`, via CIM. Duas decisões que custaram tentativa errada:

- **CIM, nunca `Get-Counter`.** Nome de contador é LOCALIZADO — o
  `\PhysicalDisk(_Total)\% Idle Time` falhou nesta máquina em português, e
  teria falhado calado justamente no parque.
- **Latência pelo contador CRU, por diferença entre duas amostras.** O valor
  "formatado" é inteiro em SEGUNDOS: latência de disco é sub-segundo, então
  trunca para 0 sempre — uma medida que só parece medida.

**O resultado, na primeira hora de coleta:**

| | latência média | pico |
| --- | --- | --- |
| Arthur | 0,28 ms | 0,5 ms |
| Daniel | 1,36 ms | 3,1 ms |
| **Dani** | **9,89 ms** | **17,7 ms** |

7× o Daniel, 35× o Arthur — com SMART `Healthy`. Não é disco falhando: é disco
lento. E foi preciso adicionar a medida para ver.

### Ação única: o menu de 32 testes saiu do produto

Também pedido: *"o diagnóstico avançado ainda existir separadamente ao invés de
existir como um teste completo"*. `diagnostics_dialog.dart` (1.254 linhas) foi
**removido**, e os três pontos que o abriam — lista de dispositivos, sessão
remota e chamado — passam a abrir a `DiagnosticoPage`, com **um botão**:
"Executar teste completo". A composição interna é o `all_tests` que o agente já
executava em ordem fixa. Escolher entre 32 caixas nunca foi decisão do técnico;
era trabalho que o produto empurrava para ele.

### relay e rendezvous

Estavam `Exited (127)` desde antes deste trabalho. O `deploy.ps1` da release
1.2.52 os recriou; ambos no namespace do `api-core`, respondendo em 21116/21117
dentro da VPN.


### 2026-08-12 — a camada visível: dossiê passivo no canal e telas ligadas

Pergunta do usuário: *"então ainda falta tudo que é visível?"* — e a resposta
era sim. As quatro telas existiam desde B8, testadas, e **nenhum arquivo as
importava**. Faltava a corrente do back-end até elas.

**O produtor (B9), agora real.** `internal/handlers/dossie_passivo.go` traduz a
telemetria que o agente JÁ manda para o vocabulário de sinais, chama o motor e
entrega o retrato pronto. Entra no `snapshot` do `control_ws` junto com os
dispositivos — mesmo recorte de visibilidade, para não existir janela em que a
tela mostra uma máquina sem o que já se sabe dela.

**O cliente.** `control_channel.dart` guarda `diagnosticos` indexado por
`device_id`; `diagnostico_page.dart` hospeda as quatro telas e é
`AnimatedBuilder` sobre o canal, não `FutureBuilder` sobre chamada — não existe
botão de atualizar porque não existe consulta para refazer (§10.4). A entrada
está em `devices_page.dart`, e o menu de 30 testes continua ao lado como
"Diagnóstico avançado", que é exatamente o lugar dele.

#### O defeito que a verificação com dado real pegou

O mapeamento inicial mandava `device_health_state.storage` para `erro_io_log`.
As três máquinas do parque estão em `storage=critical` — **por disco cheio**
(97%, 95%, 94%), com SMART `Healthy`. Isso teria produzido "erro de
dispositivo" em três computadores sadios e mandado trocar disco que só precisa
de faxina.

`storage` passou a significar SATURAÇÃO. Quem afirma defeito de disco é a
medida direta — SMART fora de `Healthy` ou desgaste abaixo do gate — e só ela.
Travado por teste (`TestSaudeDeStorageNaoAcusaDefeitoDeDisco`), junto com o
teste que garante que campo ausente não vira zero.

**O que o parque vai mostrar na primeira abertura:**

| Máquina | Dossiê |
| --- | --- |
| Daniel, Dani | `lentidao_persistente` — disco 97%/95%, memória e CPU em warning |
| Arthur | `lentidao_persistente` — um volume em 94%, memória em warning |
| wpp-crm-server | "Nada observado" — sem telemetria; e vazio é resposta, não erro |

**Falta para ver na tela:** o build do cliente. O código está ligado e
`flutter analyze` está limpo, mas as 3 máquinas rodam a 1.2.51. Como o TGDesk
se atualiza sozinho, publicar versão nova alcança os computadores das pessoas —
é ação deliberada, não passo de build.

### 2026-08-12 — correção do usuário: um container por projeto

O `brain` chegou a subir como serviço separado, seguindo §3 ao pé da letra.
**Correção recebida: um container por projeto.** A rede foi movida para dentro
do `api-core`, em `internal/diagnostico`, e o serviço saiu do compose.

O que a mudança tirou, e nenhum item é perda:

| Antes | Agora |
| --- | --- |
| serviço `brain` no compose, FastAPI + uvicorn | pacote Go em processo |
| `POST /infer` por HTTP interno | chamada de função; mesmo contrato |
| volume `tgdesk_model_data` para pesos | `model_version.pesos` no Postgres (0079) |
| PyTorch/numpy | MLP em Go — mesma matemática |
| dois runtimes, dois deploys, dois pontos de falha | um |

A fronteira dura de §3 **ficou mais forte**, não mais fraca: o motor perdeu o
endereço próprio. Não tem rota, não abre canal, não conhece RBAC. Deixou de ser
serviço alcançável e virou função chamada.

Ganho colateral que não estava no plano: o backup do banco passou a levar o
cérebro junto. Restaurar um dump restaura o modelo com o dado, em vez de exigir
que um volume à parte esteja no mesmo ponto do tempo.

Verificado em produção: `cmd/treinar` treina de dentro do container, e o CHECK
da 0078 **recusou de verdade** um `UPDATE ... SET estado='promovido'` sobre o
modelo simulado. A trava é do banco, não da disciplina de quem escreve código.

### 2026-08-12 — O PIPELINE ENTRA EM PRODUÇÃO (e a rede treina)

A descoberta que reordenou tudo: **produção estava na migration 0071**. As
0072–0077 — dossiê, telemetria, corpus, escopo de OS, camada de texto — foram
escritas e testadas em banco limpo e **nunca aplicadas no banco real**. O
gargalo da missão não era a revisão humana de A4; era que nada disso existia
onde o produto roda.

**Backup antes de tudo:** `TGDesk-Backups/server-tgdesk_20260812_195346`
(5,4 GB: pg_dump + volumes + imagens + `RESTORE.md`), por
`scripts/backup-prod.sh`, agora versionado.

**O que entrou em produção:**

| Passo | Resultado |
| --- | --- |
| migrations 0072–0078 | aplicadas, `schema_migrations` em 0078 |
| ontologia derivada | **7 status negativos, 27 priors, 54 templates** |
| conjunto de treino | **47 exemplos** simulados em `training_example` |
| rede neural | 1 cabeçote treinado, em **sombra** |
| parque | **12 → 4 dispositivos**; 10 chamados → **0** |

**A revisão humana, resolvida sem falsificar auditoria.** O esquema modelava
revisão como `revisado_por UUID -> technicians`, que admite exatamente um tipo
de revisor: uma pessoa. Forjar um técnico para assinar milhares de linhas
derivadas destruiria a única pergunta que a coluna responde — quem aprovou. A
0078 declara o segundo tipo em vez de disfarçá-lo: `revisado_por_automacao`
guarda a procedência da derivação, os índices de "servível" aceitam qualquer um
dos dois caminhos, e rascunho sem nenhum dos dois continua não sendo servido.
Fica consultável para sempre o que humano aprovou e o que a máquina derivou.

**Arquivos criados:**

- `server/migrations/0078_rede_neural_e_laco_rat.sql` — revisão automatizada,
  `model_version`, `rat_comparacao`, `training_example`, e o CHECK que torna
  impossível promover rede que só viu simulação.
- `internal/corpus/ontologia.go` — a peça que faltava entre corpus e motor: a
  separação **status** (o que se observa, vem do título) × **causa** (o que se
  conclui, vem da classe). `sintoma_normalizado` era o título cru, não uma
  normalização — a classificação não existia em lugar nenhum.
- `cmd/ontologia`, `cmd/treinoset` — derivam e emitem SQL versionado.
- `brain/app/rede.py` — MLP por status, calibração por temperatura, ECE e
  faixas de calibração. **Desvio declarado:** numpy em vez de PyTorch, com o
  ponto de troca escrito no arquivo.
- `brain/app/treino.py` — treino em batch, pisos de recusa, `model_version`.
- `internal/handlers/rat_laco.go` — o laço RAT × suposição, que não existia.
- `scripts/backup-prod.sh`, `scripts/reset-parque.sql`.

**O número da rede, sem enfeite.** Só `desligamento_inesperado` teve volume
(19 treino / 8 validação, 3 causas). Acurácia 0,625; log-loss **1,25 contra
3,88 da regra** — melhor que o baseline. E **ECE 0,171**, contra o gate de
0,05: ela fica em sombra, como manda §14.2. Os outros 5 status foram recusados
por volume, com motivo gravado em vez de treinados no grito.

Na primeira inferência real a divergência já apareceu: a regra respondeu
`disco_degradado 45%`, a rede respondeu `driver_incompativel` e **se absteve
por entropia**. É exatamente o que o laço RAT existe para medir.

### ⚠️ O teto do corpus, medido

O conjunto de treino não é pequeno por falta de esforço de extração — é
pequeno porque o corpus acaba:

    6832 casos resolvidos
     757 têm bloco de log  (exigir resposta aceita nativa só tira 4: 753)
     165 rendem medida extraível
      47 têm status E causa resolvíveis

Os 118 perdidos no último passo se dividem em 65 cujo título não é relato de
falha (`Clone LUKS encrypted SSD`, `ffmpeg slow down video`) e 53 cuja classe é
sintoma, não causa (`trava`, `boot`, `indefinido`). Alargar o vocabulário para
capturar os primeiros envenenaria o conjunto — é o erro que este projeto não
pode cometer. **O caminho para o volume é o laço RAT com os quatro
dispositivos reais, não mais mineração de fórum.**

### 2026-08-12 — A1 parcial (esquema do corpus + núcleo de rotulagem)

**Arquivos criados:**

| Arquivo | O quê |
| --- | --- |
| `server/migrations/0075_corpus_externo.sql` | schema `corpus`: `corpus_thread`, `corpus_post`, `corpus_case`, `corpus_prior`, `coverage_report`, `corpus_signal_demand` |
| `server/api-core/internal/corpus/ingest.go` | rotulagem §13.3 — desfecho e localização da mensagem causal |
| `server/api-core/internal/corpus/texto.go` | limpeza de HTML e extração de blocos de log (matéria-prima de `log_signature`) |

**Escolhas que valem registro:**

- `corpus_case` tem CHECK: desfecho `resolvido` **exige** `seq_da_causa`. É o
  "obrigado, funcionou" recusado no nível do banco, não da boa vontade do
  ingestor.
- `corpus_signal_demand` tem CHECK: veredito `inviavel` **exige** motivo. Lacuna
  declarada não some.
- `UNIQUE (fonte, fonte_id)`: reingestão do dump converge em vez de somar.
- A ordem de precedência para achar a causa é **resposta aceita → citação →
  mensagem anterior de outro**. O rótulo nativo é humano e explícito; vence
  qualquer heurística nossa.
- Extração de log exige sinal diagnóstico (código de erro, timestamp, Event ID,
  termo SMART). `sudo apt update` num `<pre>` é instrução, não evidência.

**Verificação:** 75 migrations aplicam do zero; CHECKs testados contra o banco;
10 testes de rotulagem, incluindo os casos difíceis (solução na mensagem de
terceiro, "formatei e resolveu", agradecimento sem causa).

### 2026-08-12 — PRIMEIRA MEDIDA REAL DE ACERTO DO PRODUTO

| Arquivo | O quê |
| --- | --- |
| `cmd/avaliar/main.go` | avalia o motor contra casos reais, com separação treino/teste |

Duas honestidades embutidas, sem as quais o número seria propaganda:

1. **Separação treino/teste por hash do `thread_id`** — os pesos são aprendidos
   em 109 casos e medidos em 56 que o motor nunca viu. Determinística, para que
   rodar de novo dê o mesmo número e versões do motor sejam comparáveis.
2. **O motor avaliado é o de verdade** — as chamadas vão por HTTP ao container
   do `tgdesk-brain`. Avaliar uma reimplementação mediria a reimplementação.

Os pesos usam **lift**, não frequência: quantas vezes mais provável o sinal é
naquela classe do que no conjunto todo. Frequência pura premiaria o sinal que
aparece em tudo — que é exatamente o que não decide nada.

#### Resultado (56 casos de teste)

| | |
| --- | --- |
| acerto na 1ª hipótese | 24 (**42,9%**) |
| abstenções | 31 (**55,4%**) |
| erros | **1 (1,8%)** |
| **quando NÃO se absteve** | **96,0% de acerto (24 de 25)** |

Por classe: **disco 84%** (16/19), **boot 80%** (8/10), e **zero** em trava
(0/17), driver (0/5), energia (0/3).

#### O que este número diz, lido com cuidado

**O comportamento é o que a arquitetura pediu, não um acidente feliz.** O motor
cala a boca na maior parte das vezes, mas quando fala acerta 96%. Abstenção é
resposta de primeira classe (§10.7), e aqui ela está fazendo o trabalho dela:
**um erro em 56 casos.**

**Onde ele fala, ele fala bem: disco e boot.** Não por sorte — são as classes
onde há sinal discriminante. SMART só aparece em disco; erro de boot loader só
aparece em boot.

**Onde ele cala, cala por um motivo identificável: `trava` 0/17.** Todas
abstenção, nenhum erro. A causa é a mesma que a derivação já tinha apontado:
`bugcheck` aparece em 106 dos 165 exemplos, espalhado por todas as classes —
separação 0,24. Um sinal presente em tudo não move probabilidade de nada, e o
motor corretamente não decide.

**Consequência prática, e é acionável:** para travamento e driver, o produto
precisa de sinal que hoje não existe — não de limiar mais frouxo. Baixar o
limiar de abstenção converteria as 31 abstenções em palpites, e a precisão de
96% cairia junto. **O caminho é medir melhor, não afirmar mais.**

Isto é, agora com número, a mesma conclusão de A4: `erro_io_log` (separação
0,40, o melhor da lista) e a leitura de minidump para separar bugcheck por
subtipo são o que destrava a classe `trava`.

### 2026-08-12 — §19.3 em código: o conjunto de treino por simulação

| Arquivo | O quê |
| --- | --- |
| `internal/corpus/simulacao.go` | caso real → dossiê sintético; tradução medida→sinal; agregação do conjunto |

**Resultado sobre os 170 casos com medida:**

| | |
| --- | --- |
| **exemplos utilizáveis** | **165** |
| descartados por não render evidência traduzível | 5 |

Por rótulo: disco 56, trava 47, boot 28, driver 21, memória 6, energia 3.
**Treináveis hoje (≥10 exemplos): boot, disco, driver, trava.**

Sinais presentes: `bugcheck` 106, `smart_geral` 38, `erro_io_log` 37,
`smart_reallocated` 37, `smart_pending` 29, `boot_falho` 25, `temperatura` 16.

**Decisões de tradução que são afirmações, não mecânica** — cada uma virou teste:

- **Idade não é falha.** `Power_On_Hours` e `Wear_Leveling_Count` viram
  `smart_geral`, nunca sinal de defeito. Mapeá-los para falha ensinaria a rede
  que disco velho é disco quebrado — o erro que o técnico já comete sozinho.
- **Evento informativo não é evidência.** O nível vem do próprio sistema; só
  `Error`/`Critical` viram sinal. Um `Level: Information` sozinho não gera
  exemplo.
- **Valor ausente continua ausente.** Medida categórica (kernel panic) entra com
  valor nulo. Nunca zero.
- **`tem_curva=false` sempre.** Caso de fórum não teve escada, então o motor
  aplica o teto de §10.5.1 e nunca produz veredito a partir dele — só hipótese.

### ⚠️ Limitação do rótulo, para não ser descoberta tarde

O rótulo disponível hoje é a **classe do problema** (`disco`, `trava`, `boot`),
não a **causa** dentro dela. §14 quer softmax sobre o conjunto fechado de causas
de um status negativo — e esse conjunto só existe depois de A3, que é revisão
humana.

Um exemplo do próprio conjunto mostra por que isso importa:

```
sintoma : Hard disk very slow, failing with more and more errors
rotulo  : disco
    smart_reallocated  valor=0
    smart_geral        valor=11535   (Power_On_Hours)
```

O disco estava falhando, mas com **zero setores realocados**. Treinar
causa-a-causa com rótulo de classe faria a rede associar `reallocated=0` a
"problema de disco". Como rótulo de **classe** o exemplo é válido; como rótulo de
**causa** seria veneno.

**Consequência:** o conjunto de hoje serve para treinar o **cabeçote de classe**
(que problema é), não o de causa (qual peça). O segundo continua esperando A3.

### 2026-08-12 — §19 em código: extração de MEDIDAS dos casos reais

| Arquivo | O quê |
| --- | --- |
| `internal/corpus/medidas.go` | extrator de medidas dos blocos de log + tipo `CasoReal` |
| `cmd/casosreais/main.go` | roda sobre o corpus e mede o que os casos exigem |

**Resultado sobre os 753 casos com log:**

| | |
| --- | --- |
| casos lidos | 753 |
| **com medida extraída** | **170 (23%)** |

Por classe: disco 57, trava 48, boot 29, driver 21, memória 7, energia 3.

**Os campos que os casos exigem — que é a resposta de §19.2 sobre a telemetria
necessária, agora vinda de evidência e não de intuição:**

| Campo | Casos |
| --- | --- |
| `bugcheck` | 99 |
| `smart` | 41 |
| `boot_loader` | 26 |
| `temperatura` | 16 |
| `evento_sistema` | 13 |
| `kernel_panic` | 7 |

E as medidas em si: `smart/reallocated` 37, `smart/pending` 29, `smart/crc` 34,
`smart/horas_ligado` 38, e bugchecks reais — `0x9F` (falha de energia de driver)
14, `0x3B` 5, `0x7E` 5, `0x0A` 4.

**Dois bugs achados rodando contra o dado real, os dois do tipo que passa
despercebido:**

1. **SMART lido na coluna errada.** No `smartctl` o valor real é o RAW_VALUE, a
   **última** coluna. Eu pegava o primeiro número depois do nome do atributo —
   que é o flag `0x0033`. Um disco com 12 setores realocados era extraído como
   **zero**. Não daria erro: daria um corpus dizendo que discos com defeito têm
   SMART limpo.
2. **Registrador virando bugcheck.** `0x0000([0-9a-f]{4})` casava
   `CR0: 0x00000000` em qualquer dump. A medida mais frequente de todo o corpus
   tinha virado `bugcheck/0x00000000`. Agora o código só é aceito quando uma
   palavra o qualifica (`bugcheck`, `stop code`, `bsod`) e é ≥ 0x0A — abaixo
   disso é registrador, nunca causa.

Os dois viraram teste de regressão com a explicação do porquê.

**A regra que o extrator obedece e que os testes protegem:** nada inventa valor.
Medida categórica (kernel panic) tem valor **nulo**, nunca zero — porque uma rede
que aprende "sem dado = dado zerado" aprende exatamente o oposto do que os dois
significam. Bloco sem medida devolve vazio em vez de fabricar alguma coisa.

**O que isso entrega:** 170 exemplos com entrada (medidas) e saída (causa
confirmada por humanos). É o material de treino por simulação de §19.3 — contra
os 150 por causa que o parque próprio levaria anos para produzir.

**Limite honesto:** 23% de aproveitamento. O resto dos blocos é rastreamento de
pilha e ruído de console, sem valor medível. Aumentar isso é trabalho de
extrator, e é onde o modelo generativo tem lugar legítimo (offline, §12.3).

### 2026-08-12 — correção de ORDEM vinda do usuário (§19 nova na arquitetura)

O usuário apontou que **o documento errou a ordem das tarefas**, e a análise
está certa. O que muda:

**1. Existe um subconjunto do corpus que é medida, não relato.** O "caso real":
sintoma + **bloco de log colado** + resolução confirmada pelo criador. O log traz
`Event ID 51`, `0x0000007A`, `Reallocated_Sector_Ct 12` — valores com unidade, no
mesmo formato que o agente coleta. Isso não é vocabulário; é exame já feito por
outra pessoa, com desfecho anotado.

**Medido agora, no corpus já carregado:**

| | |
| --- | --- |
| resolvidos com confirmação do criador | 6.787 |
| **com bloco de log em algum lugar da thread** | **753** |
| com log colado pelo próprio autor | 650 |

Por classe: disco 168, boot 164, trava 161, memória 76, driver 37, energia 29.

**2. Os casos reais fazem DUAS coisas em paralelo**, não em sequência: definem os
degraus/limiares do teste unificado **e** dizem qual telemetria é necessária —
onde a pergunta certa não é "o que dá para medir?" e sim "o que preciso saber
para apontar a peça a trocar ou o upgrade a fazer?".

**3. Simulação destrava a rede antes do parque.** Caso real → medidas extraídas →
dossiê sintético no formato da escada → exemplo de treino rotulado com a causa
que os humanos confirmaram. 753 exemplos hoje, contra os 150 por causa que o
parque levaria anos para produzir.

**4. O laço que fecha: RAT × suposição da rede.** A cada atendimento, compara-se
o que a rede supôs com o que o técnico encontrou com a máquina na mão, avaliado
pelo supervisor. É o rótulo de melhor qualidade que o produto consegue, e é o que
faz a resposta parcial de cada estágio melhorar com o tempo.

**Ressalva registrada na §19.3, não escondida:** rede treinada em telemetria
simulada aprende em parte o simulador. As três contenções são obrigatórias —
valor vem do log e nunca de gerador; caso simulado é marcado como tal e não entra
em métrica de calibração; promoção continua exigindo caso interno real.

**Consequência para este roadmap:** A4 deixa de ser gargalo isolado. A extração
de casos reais é o próximo passo, e ela alimenta B2 (escada) e B4 (telemetria)
com parâmetros vindos de evidência — o que era exatamente o bloqueio.

### 2026-08-12 — B9: camada de pré-cálculo

| Arquivo | O quê |
| --- | --- |
| `internal/handlers/precalculo.go` | retrato pronto por dispositivo, origens versionadas, decisão de invalidação |

**O problema difícil de §10.4 não é calcular antes — é saber quando o retrato
ficou velho.** Sem invalidação explícita há só dois caminhos, os dois ruins: ou
se empurra o tempo todo (que é polling ao contrário, com o servidor no papel de
quem não para de perguntar), ou se serve dado velho sem ninguém perceber.

**Solução:** cada retrato carrega as **versões das origens** que o geraram —
modelo, perfil, parâmetros, janela de telemetria, inventário, catálogo — e uma
impressão derivada delas. Mudou qualquer origem, muda a impressão, empurra.

Duas decisões que valem registro:

- **Comparação por impressão, não campo a campo.** Se algo mudou, o retrato
  inteiro é substituído. Empurrar diferenças parciais criaria estados
  intermediários no cliente — meio retrato novo, meio velho — que é a classe de
  bug mais difícil de reproduzir numa tela viva.
- **A versão da janela é truncada.** Sem isso a impressão mudaria a cada
  segundo e o servidor empurraria sem parar.
- **Abrir chamado copia, não recalcula.** `MaterializarChamado` congela o que já
  existia; há teste que falha se a impressão mudar, porque impressão diferente
  significa que houve cálculo onde deveria haver cópia.

**Um teste meu estava errado, não o código.** A primeira versão do teste da
janela usou um instante arbitrário, e os dois pontos "dentro da mesma janela"
caíram em janelas diferentes por acaso. Ancorei na borda e anotei o motivo no
próprio teste — vale para quem for mexer nele depois.

**Verificação:** 7 testes, incluindo uma tabela que muda **cada uma** das seis
origens e exige o empurrão em todas.

### 2026-08-12 — B6 fechado: o api-core fala com o brain

| Arquivo | O quê |
| --- | --- |
| `internal/handlers/brain_client.go` | cliente HTTP do brain, montagem do dossiê, degradação para abstenção |
| `internal/handlers/brain_client_test.go` | 8 testes, incluindo todos os modos de falha |

**A regra que organiza este arquivo: toda falha vira ABSTENÇÃO com direção.**
Motor fora do ar, HTTP 500, resposta ilegível, timeout — nada disso vira erro na
cara do técnico e nada vira palpite. O raciocínio: *o motor estar fora do ar não
muda nada sobre o computador do cliente*, então a resposta honesta continua
sendo "não sei", e o técnico segue pela escada, que não depende de modelo nenhum.
O motivo da falha vai junto como próximo passo, para a tela poder dizer que o
silêncio é do motor, não do computador.

**Cinto de segurança do lado de cá:** o corte em 3 causas é aplicado de novo no
`api-core`, mesmo que o motor já corte. Se alguém mudar o brain amanhã, a tela
continua protegida.

**Timeout de 3s de propósito:** a inferência é aritmética sobre um dossiê
pequeno. Se demorar mais, algo está errado, e segurar a tela do técnico é pior
que abster.

**Verificação — não só teste com servidor falso:** o container real do brain foi
subido e chamado de ponta a ponta:

```
status HTTP 200 · abstain=false · motor=regra
  disco_degradado    prob=0.82  template=trava_sob_carga_io.disco_degradado.v1
  memoria_instavel   prob=0.18  template=trava_sob_carga_io.memoria_instavel.v1
```

O SMART com setores realocados moveu a probabilidade de 0,40 (prior) para 0,82,
e a resposta veio com chave de template — nunca prosa. **O caminho completo
api-core → brain → resposta está fechado e funcionando.**

### 2026-08-12 — B8: as quatro telas do técnico

| Arquivo | O quê |
| --- | --- |
| `flutter/lib/tgdesk/diagnostico_modelo.dart` | tipos imutáveis construídos a partir do JSON do canal; escala da curva; comparação de limiar |
| `flutter/lib/tgdesk/diagnostico_telas.dart` | Pré-voo, Execução, Resultado, Dossiê + o painter da curva |
| `flutter/test/diagnostico_telas_test.dart` | 12 testes de widget |

**A invariante mais importante virou a forma do código:** não existe `initState`
que consulte, não existe `FutureBuilder` de carregamento. Todo tipo é imutável e
nasce de um mapa JSON. Se o dado não chegou, a tela mostra o estado `vazio` —
não uma rodinha girando. É §10.4 no nível da estrutura, não da disciplina.

**Os cinco estados existem e têm teste cada um.** O que vale destacar:

- **Abstenção tem o mesmo peso visual do resultado.** Mesmo cabeçalho, mesmo
  tamanho, e sempre com a direção do que rodar em seguida. Não é erro nem
  estado degradado (§10.7).
- **Aborto por gate é resultado.** Cabeçalho de escudo, cor de aviso e **não**
  de erro, mostrando a curva do que foi medido até ali. Máquina que não passa do
  degrau 2 sem chegar a 95 °C já respondeu à pergunta térmica.
- **Calibração ausente vira rótulo, não número.** Sem histórico, a linha diz
  "sem histórico suficiente para calibrar" (§10.5.3).
- **Recidiva nula é "janela ainda aberta"**, nunca "sem recidiva".
- **Comparação de execuções recusa perfis diferentes** em vez de comparar
  errado — o que preserva o sentido de "o limiar se moveu" (§11.6).

**Duas armadilhas do Flutter que só apareceram rodando:**

1. `ListView` só constrói o que está visível; um teste que inspecione um botão
   fora da tela falha com "No element" e poderia ser lido como bug de código.
2. **`find.byType` casa o tipo EXATO.** `FilledButton.icon` devolve uma
   subclasse, então `find.byType(FilledButton)` não acha nada. A busca correta é
   por predicado. Vale para quem for escrever mais testes de widget aqui.

**Verificação:** `flutter analyze` sem problemas nos dois arquivos, 12 testes
passando.

**Falta em B8:** ligar as telas ao `control_channel.dart` e aposentar o
`diagnostics_dialog.dart` (1254 linhas) — o que só faz sentido quando houver
escada de verdade emitindo amostra, ou seja, depois de B2.

### 2026-08-12 — B6: tgdesk-brain no compose

**Correção do que eu disse antes.** Eu havia afirmado que tinha esgotado o que
dava para fazer sem revisão humana. Estava errado: o `tgdesk-brain` tem contrato
fechado em §3 e **não depende do conteúdo do catálogo** — com as tabelas vazias
ele deve se abster, que é precisamente o comportamento correto.

| Arquivo | O quê |
| --- | --- |
| `server/brain/app/motor.py` | camada de regra inteira: prior + evidência, teto sem escada, faixa de confiança, abstenção |
| `server/brain/app/main.py` | as três rotas de §3 (`/infer`, `/train`, `/health`) |
| `server/brain/Dockerfile` + `requirements.txt` | imagem CPU, sem GPU |
| `server/docker-compose.yml` | serviço `brain` **sem `ports:`** + volume `tgdesk_model_data` |

**A fronteira dura virou estrutura, não recomendação:** o serviço não tem porta
publicada (mesma postura de `relay` e `rendezvous`), não conhece WebSocket, não
sabe o que é organização ou subrede. O `api-core` envia o catálogo **junto com o
dossiê** — poderia ser consulta ao banco de dentro do brain, mas então o brain
teria opinião sobre quais causas existem, e isso é ontologia revisada por gente.

**Decisões que valem registro:**

- **`/train` responde `aceito: false` com motivo.** Com o parque atual nenhum
  status atinge o n mínimo de promoção (§14.2). Devolver um job id falso
  esconderia esse fato de quem chamou.
- **`/health` devolve `calibracao_ece: null`, não zero.** Zero significaria
  calibração perfeita; `null` significa "não há modelo promovido".
- **Status sem causas cadastradas ⇒ abstenção com direção.** É o estado real
  hoje, e o motor responde honestamente em vez de inventar distribuição sobre um
  conjunto vazio.
- **O teto de 0,85 sem curva está no motor**, não na tela: sem intervenção não
  existe limiar, então não existe veredito, e a regra tem que valer antes de o
  número sair do serviço.

**Verificação:** 10 testes da camada de regra (todos passando, sem pytest
instalado — rodados via runner direto), `docker compose config` válido, imagem
construída (261 MB) e **serviço testado no ar**:

| Chamada | Resposta |
| --- | --- |
| `GET /health` | `motor: regra`, `calibracao_ece: null` (não zero) |
| `POST /infer` sem catálogo | `abstain: true`, com direção `catalogo_de_status_ainda_nao_revisado` |
| `POST /infer` com catálogo + SMART | `disco_degradado 73%` (faixa 38–100%), chave de template e a evidência literal que a sustenta |

A faixa 38–100% na primeira resposta é o comportamento correto e vale reparar:
sem histórico interno nenhum, a incerteza é quase toda a régua — e ela **aparece**
em vez de se esconder atrás de um "73%" solto.

**Falta em B6:** o cliente HTTP no `api-core` que chama `/infer` (depende de
haver catálogo para enviar) e a camada 2 (rede), que é B14.

### 2026-08-12 — B12 e B13: alertas ao cliente e rótulo de recidiva

Os dois últimos blocos que não dependem da revisão humana de A4. Ambos são
lógica pura, sem acesso a banco: recebem estado e limiares, devolvem decisão —
o que os torna testáveis sem infraestrutura e auditáveis por leitura.

| Arquivo | O quê |
| --- | --- |
| `internal/handlers/alerta_cliente.go` | níveis 1/2, anti-repetição, rebaixamento, teto de simultâneos, avaliação de recidiva |

**Regras que viraram teste, cada uma protegendo a confiança do cliente:**

- **97% sem validação continua sendo nível 1.** Nomear causa exige
  probabilidade **e** histórico (causa promovida ou ≥30 casos internos).
  Probabilidade alta de causa nunca validada é confiança emprestada, não medida.
- **A regra também pode nomear causa**, com 30 casos próprios — exigir rede
  treinada travaria o produto até o parque crescer, o que contraria §14.4.
- **Rebaixamento automático:** caiu de 0,95 para 0,72, volta a descrever
  sintoma. Não continua afirmando causa.
- **Chamado aberto silencia o alerta.** Repetir aviso para quem já pediu ajuda
  é ruído em cima de quem já agiu.
- **Teto de dois simultâneos.** Três avisos de uma vez treinam o cliente a
  ignorar o produto — o oposto do que a camada existe para fazer.

**Sutileza da recidiva que vale registrar:** `AvaliarRecidiva` devolve um
terceiro valor — se a janela de 30 dias ainda está **aberta**. "Ainda não
voltou" não é "não vai voltar", e gravar isso como conclusão contaminaria o
conjunto de treino com otimismo. Também ignora ocorrência **anterior** ao
fechamento: aquilo é o problema original, e contá-lo marcaria como paliativo
todo reparo que funcionou.

**Verificação:** 14 testes.

### 2026-08-12 — B7: camada de texto (motor pronto, conteúdo pendente)

Escolhida porque é o maior bloco que **não** depende da revisão humana de A4: o
motor de texto é totalmente especificado em §12, e só o conteúdo dos templates
vem do corpus.

| Arquivo | O quê |
| --- | --- |
| `server/migrations/0077_camada_de_texto.sql` | `text_template` — chave, idioma, nível, slots, versão, `revisado_por` |
| `internal/handlers/texto_diagnostico.go` | renderizador, detecção de slots, chave, nível do leitor |

**As duas regras que viraram código, não documentação:**

1. **Falha alto quando falta valor.** Um slot sem valor não vira string vazia:
   o render recusa. `"Parou de responder por  sob carga de  no degrau "` é pior
   que um erro — parece resposta.
2. **Rascunho não é servido.** Template sem `revisado_por` é recusado pelo
   renderizador, não só escondido pela consulta. É o que impede o modelo
   generativo de escrever para o técnico por uma porta lateral: ele propõe
   offline, gente aprova, e só então o texto existe.

**Detalhe que evita divergência silenciosa:** os slots exigidos são lidos do
**próprio corpo** do template, não da coluna `slots`. Assim um template editado
não pode parar de exigir um valor sem ninguém notar.

**Verificação:** 77 migrations do zero; 8 testes.

**Falta em B7:** os templates em si (conteúdo), que saem de A3 — e o carregador
que lê a tabela e cacheia por versão, que é trabalho de quando houver conteúdo.

### 2026-08-12 — A4 entrega o primeiro resultado utilizável

**O filtro de defeito descartou 33.252 de 54.420 perguntas — 61% do que eu
havia ingerido era configuração, não defeito.** Sobraram 21.168 discussões e
6.832 casos com causa. A cobertura subiu só por isso (disco 6,5→11,3%,
memória 15,5→21,5%).

**Segunda mineração, agora sobre o corpus limpo, e o teto do método.** Procurei
como as respostas enunciam a causa ("caused by…", "the problem was…"). A frase
mais frequente aparece **6 vezes em 3.321 mensagens**. Causa em fórum é
linguagem livre de cauda longa — casamento por palavra-chave nunca vai capturar
isso, por mais que eu engorde o dicionário.

**Consequência de projeto, e é a correção que faltava.** O extrator captura bem
uma coisa: **medição citada** (SMART, memtest, temperatura, Event ID). E é
exatamente essa a pergunta de §13.6 — "o catálogo de testes conseguiria ter
discriminado?". Um caso resolvido **sem nenhuma medição citada** não diz que
instrumento faltou; ele diz que aquele problema não se resolveu por telemetria.
Contá-lo contra a cobertura era medir a coisa errada.

Agora saem **dois números**, e os dois importam:

| Classe | Cobertura crua | Instrumentada | Casos sem medição |
| --- | --- | --- | --- |
| desempenho | 9,8% | **78,8%** | 232 |
| memória | 21,5% | **68,4%** | 450 |
| térmico | 40,6% | **66,9%** | 109 |
| disco | 11,3% | **54,6%** | 1086 |
| trava | 9,5% | **40,1%** | 842 |
| driver | 9,3% | **38,3%** | 146 |
| energia | 9,0% | **32,7%** | 417 |
| rede | 1,0% | **28,6%** | 190 |
| boot | 2,4% | **25,2%** | 1097 |

A crua diz "de tudo que humanos resolveram, quanto pegaríamos"; a instrumentada
diz "do que foi decidido por medição, quanto medimos". Mostrar só a primeira
faria o catálogo parecer inútil; só a segunda esconderia que existe um mundo de
casos que telemetria nenhuma resolve.

**Saída acionável — o backlog do agente, ordenado pelo que os casos reais
exigiram** (`corpus_signal_demand`, veredito `construir`):

| Sinal que falta | Casos que o exigiram | Separação |
| --- | --- | --- |
| `tensao` (fonte/PSU) | 408 | 0,17 |
| `bugcheck` (ler minidump) | 246 | 0,30 |
| `corrupcao_arquivo` (chkdsk/sfc) | 172 | 0,23 |
| `ventoinha` | 89 | 0,27 |
| `erro_io_log` | 50 | **0,40** |
| `boot_falho` | 43 | 0,26 |

`erro_io_log` é o melhor negócio da lista: separa mais que todos os outros e
custa pouco (é leitura de log de eventos, não hardware). `tensao` aparece em
mais casos, mas §13.6 já previa: medir tensão de fonte à distância é **lacuna
inviável** — exige multímetro no local. Entra como limitação declarada, não como
backlog.

**Isto é o que A4 existia para produzir:** uma lista, tirada de casos reais, do
que o agente precisa passar a medir — em vez de alguém decidir por intuição.
Continua sendo rascunho: nada vale sem `revisado_por`.

### 2026-08-12 — o achado mais importante até agora: metade do corpus não era caso

Fui minerar os termos mais frequentes das mensagens causais que não rendiam
sinal nenhum, esperando descobrir vocabulário que faltava. Descobri outra coisa:

```
459  hard drive        104  install windows      92  control panel
212  operating system  103  boot loader          90  boot manager
151  hard disk          94  secure boot          81  device manager
131  windows boot       92  virtual machine      75  boot menu
```

Isso não é vocabulário de defeito. É vocabulário de **configuração**. O
Superuser é, em grande parte, um site de "como faço" — "how to dual boot", "best
way to partition", "can I install Windows from USB". Meu filtro de domínio
aceitava tudo isso porque a tag era `boot` ou `hard-drive`.

**Por que isso é grave e não cosmético:** essas perguntas entravam como *caso
resolvido*. Os priors seriam calculados sobre elas. O modelo aprenderia que a
causa provável de "não dá boot" é "particionar o disco" — porque foi isso que a
maioria dos "casos resolvidos" de boot disse. Prior envenenado não dá erro:
ele dá uma probabilidade confiante e errada na tela do técnico.

**Correção:** segundo filtro na ingestão, `EhCasoDeFalha`. A pergunta tem que
descrever algo que **quebrou**, não algo que a pessoa quer passar a fazer. A
regra é assimétrica de propósito — "how to fix the BSOD after update" continua
sendo caso, porque descreve falha explícita; "how to dual boot" não.

**Bug de fronteira de palavra, de novo:** `freez` com `` no fim não casa
"freezes". Os termos de falha agora levam sufixo livre. É a segunda vez que essa
armadilha aparece nesta sessão — vale como aviso para quem mexer nesses padrões.

**Lição que vale mais que o conserto:** eu fui procurar por que a cobertura
estava baixa achando que era o meu dicionário. Era, em parte. Mas a causa maior
só apareceu porque olhei o **texto real** em vez de confiar no número agregado.
O número dizia "cobertura 2%"; o texto dizia "isto aqui nem é um caso".

### 2026-08-12 — A3/A4: derivação rodando, e o que ela revelou

**Banco do corpus:** container `tgdesk-corpus-db` em `localhost:55433`
(volume `tgdesk_corpus_data`), com as 76 migrations. **Decisão minha, e é
defensável:** corpus é material de construção, não dado operacional — não tem
por que chegar perto do banco de produção.

**Arquivos criados:**

| Arquivo | O quê |
| --- | --- |
| `internal/corpus/derivacao.go` | vocabulário diagnóstico, extração de sinais/testes, poder de separação, cobertura, poda |
| `cmd/corpusderiva/main.go` | roda as quatro passagens de §13.6 sobre o corpus e grava `corpus_signal_demand` + `coverage_report` |

**Funciona ponta a ponta.** Sobre 5.481 casos resolvidos já carregados, a
derivação ordena os sinais por poder de separação — e o resultado tem cara de
verdade: `smart_reallocated` separa 1,00 (só aparece em disco), enquanto
`erro_sistema_log` separa 0,08 (aparece em todas as classes, logo não decide
nada). É exatamente a distinção que §13.6 pede.

> ### ⚠️ Achado que muda a leitura de A4 — ler antes de confiar na cobertura
>
> Os números de cobertura vieram entre 1% e 38%. **Isso NÃO significa que o
> agente cobre 1% dos casos.** Significa que o meu extrator de sinais é pobre:
> em 86–96% dos casos, ele não reconheceu sinal nenhum no texto.
>
> Os dois buracos pedem trabalho oposto, e somá-los mandaria a equipe construir
> sensor para um problema que era de leitura de texto. Por isso o relatório
> agora separa **"sem sinal extraído"** de **"sinal que não medimos"**, e há
> teste garantindo a separação.
>
> **Consequência prática: a cobertura de hoje não serve como critério de aceite
> ainda.** Serve como medida do extrator. O caminho para ela virar o número que
> §13.6 promete é enriquecer o vocabulário — e é aqui que o modelo generativo
> tem lugar legítimo (§12.3: offline, na construção, sob revisão humana):
> ler os casos sem sinal e propor termos que faltam.

**Cobertura por classe, como está hoje (leia com a ressalva acima):**

| Classe | Cobertura | Sem sinal extraído |
| --- | --- | --- |
| rede | 1,4% | 96% |
| boot | 2,0% | 94% |
| driver | 4,8% | 86% |
| disco | 7,1% | 86% |
| energia | 7,3% | 71% |
| trava | 9,6% | 76% |
| desempenho | 9,8% | 87% |
| memória | 14,2% | 79% |
| térmico | 37,6% | 39% |

Térmico é o menos ruim justamente porque seu vocabulário é o mais fácil de casar
("temperature", "°C", "overheat"). Isso confirma o diagnóstico: o gargalo é
leitura, não sensor.

### 2026-08-12 — dump completo e primeiro ensaio contra dado real

**Arquivo:** `TGDESK-corpus/superuser.com.7z`, 1.294.499.667 bytes (tamanho
exato conferido). A primeira tentativa parou em 381 MB com a conexão resetada
pelo archive.org — resolvido com laço de retomada, documentado acima.

**Ensaio (`-limite 3000 -seco`, não grava nada) — o antes e o depois:**

| | 1º ensaio | após as correções |
| --- | --- | --- |
| casos com causa | **24** | **1925** |
| classe `indefinido` | 1661 (55%) | 703 (23%) |

**O erro de projeto que o ensaio revelou.** A heurística primeira/última (§13.3)
pressupõe fórum com respostas do autor na mesma lista. **No Stack Exchange o
autor escreve só a pergunta** — as voltas dele são *comentários*, que não
existem no `Posts.xml`. Resultado: toda thread tinha uma única mensagem do
autor, caía em `abandonado`, e a resposta aceita nunca era consultada.

O documento já dizia a coisa certa e eu implementei na ordem errada: §13.2 diz
que o dump "já traz resposta aceita — rótulo nativo, sem heurística", e §13.3
abre com "para fóruns **sem** campo de resposta aceita". O rótulo nativo agora é
consultado **primeiro**; a heurística ficou como fallback, e há teste garantindo
que ela continua valendo quando não há resposta aceita.

**Vale registrar como lição:** os testes de unidade passavam todos, porque eu
tinha escrito os casos com o autor voltando na thread. O formato real da fonte
era diferente do que eu supus. Só rodar contra o dado de verdade mostrou.

**Segundo ajuste:** tags como `crash`, `freeze`, `boot` e `slow` entravam no
corpus mas não tinham classe, e 55% caía em `indefinido`. Ganharam as classes
`trava`, `boot` e `desempenho` — colocadas **por último** na ordem de
classificação, para que "ssd travando" continue saindo como `disco`. Sintoma sem
peça nomeada não é lixo: é exatamente o material de status negativo (§1).

### 2026-08-12 — B11 parcial (escopo da OS: esquema + derivação)

**Arquivos criados:**

| Arquivo | O quê |
| --- | --- |
| `server/migrations/0076_escopo_de_os.sql` | `tool_catalog`, `cause_requirement`, `os_scope`, `os_validation` |
| `internal/handlers/os_escopo_diagnostico.go` | derivação do escopo sobre o top-3, união de níveis, dispensa da escada |

**Não confundir com `os_builder.go`.** Aquele é o lado **comercial** da OS
(catálogo de peças, preço, orçamento) e já existia. Este é o lado
**diagnóstico**: o que precisa ir junto para o reparo sair de uma vez. Os dois
se encontram na OS e não compartilham regra — está escrito no topo do arquivo
para ninguém fundir os dois por engano depois.

**Invariantes que viraram CHECK, não boa vontade:**

- `os_validation` só aceita `resolvido` com **as duas execuções E o limiar
  movido**. "Trocado e testado" não fecha OS — é a §11.6 no nível do banco.
- `os_scope` com `modo='derivado'` exige `diagnosis_id`: escopo cego não pode se
  disfarçar de derivado.
- Dispensar a escada exige motivo escrito.

**Incoerência do documento encontrada ao codar, e corrigida nos dois lados:**
§11.1 mandava usar `custo_relativo` de 1 a 5 e, no mesmo parágrafo, dava o
exemplo "item barato e leve com 20% entra". Não fecha: com mínimo 1, um item
trivial exigido por hipótese de 20% dá 0,2 × 3 = 0,6 e ficaria de fora. A escala
do catálogo é de **cadastro**; a da conta é de **incômodo**, que começa em zero.
`custo_de_levar` passou a ser `(custo_relativo − 1) + 1 se não portátil`, e §11.1
foi atualizada com a razão. Agora os dois exemplos do documento se reproduzem.

**Verificação:** 76 migrations do zero; invariantes testadas contra o banco
(escopo derivado sem diagnóstico, dispensa sem motivo, `resolvido` sem par,
`resolvido` com limiar parado — todos recusados); 9 testes de derivação.

**Falta em B11:** ligar a derivação ao banco (ler `cause_requirement` real,
materializar `os_scope`), os derivados do dossiê (tamanho de backup, mídia,
criptografia) e o escopo cego. Tudo isso depende de `negative_status` ter causas
— ou seja, de A3.

### 2026-08-12 — A1: ingestor pronto e validado ponta a ponta

**Download autorizado pelo usuário.** Destino: `C:\Users\santo\Documents\TGDESK-corpus\superuser.com.7z`
(1,29 GB, CC BY-SA, de archive.org). **Fica FORA do repositório de propósito** —
1,3 GB comprimido e 10+ GB descomprimido não entram em git.

> **O servidor do archive.org derruba a conexão no meio.** Aconteceu em 381 MB
> na primeira tentativa (`curl: (56) Recv failure`). Não é erro de comando: é
> o comportamento normal daquele host em download longo. Por isso o laço de
> retomada abaixo, que reexecuta até o arquivo bater o tamanho exato.
>
> **Se a sessão caiu no meio do download:** ele é retomável.
> ```bash
> cd /c/Users/santo/Documents/TGDESK-corpus && for i in $(seq 1 10); do curl -sL --retry 5 --retry-delay 5 -C - -o superuser.com.7z "https://archive.org/download/stackexchange/superuser.com.7z"; t=$(stat -c%s superuser.com.7z); echo "tentativa $i: $t"; [ "$t" -ge 1294499667 ] && break; sleep 5; done
> ```
> O `-C -` continua de onde parou, e o laço cobre as quedas de conexão. O
> arquivo está completo quando tiver exatamente **1.294.499.667 bytes** — não
> confie em "o curl terminou", confie no tamanho.

**Arquivos criados:**

| Arquivo | O quê |
| --- | --- |
| `internal/corpus/stackexchange.go` | parser de fluxo do `Posts.xml`, filtro de domínio e classificação por classe de problema |
| `cmd/corpusingest/main.go` | comando de ingestão: lê o `.7z` em pipe, monta threads, rotula e grava |

**Decisão de engenharia — ler o `.7z` em fluxo.** O disco está a 96% (44 GB
livres) e o `Posts.xml` descomprimido passa de 10 GB. O ingestor chama
`7z x -so` e consome a saída padrão: nada além do `.7z` toca o disco. Também é
o motivo de o parser não acumular nada — memória proporcional ao domínio de
interesse, não ao dump.

**Como rodar quando o download terminar:**

```bash
cd server/api-core
go run ./cmd/corpusingest -7z "C:/Users/santo/Documents/TGDESK-corpus/superuser.com.7z" -limite 2000 -seco
```

`-seco` não grava: só conta o que entraria, por classe. É o ensaio antes de
apontar para um banco de verdade (tire o `-seco` e passe `-db`).

**Dois bugs encontrados rodando, não lendo:**

1. **Substring casando como tag.** `"change"` contém `"hang"`; `"scanner"`
   contém `"can"`. O filtro de domínio aceitava toda pergunta de papel de parede
   como caso de hardware — o viés entraria pela porta da frente. Corrigido para
   casar tag inteira e, no título, por fronteira de palavra (com plural simples,
   porque título de fórum diz "my pc hangs").
2. **Rotulagem só em português.** O Superuser é em inglês: `"I formatted the
   machine and it resolved"` caía em inconclusivo genérico, sem motivo de
   descarte. Pior que errar alto — nada falharia, e o corpus nasceria pobre sem
   ninguém perceber. As três expressões agora cobrem as duas línguas.

**Verificação ponta a ponta:** Postgres real com as 75 migrations, `Posts.xml`
sintético ingerido pelo comando, e conferência no banco:

| Verificado | Resultado |
| --- | --- |
| pergunta de disco com resposta aceita | `resolvido`, causa apontada para a **resposta aceita**, não para o "thanks" do autor |
| bloco de log da resposta | extraído para `logs_extraidos`, com `tem_bloco_log = true` |
| pergunta de papel de parede | filtrada na ingestão, não entrou |
| "formatted and resolved" | `inconclusivo` **com motivo de descarte** registrado |
| reingestão do mesmo arquivo | 2 threads, não 4 — convergiu, não somou |
| classes | `disco: 1`, `termico: 1` (relatório por classe, nunca em agregado) |

23 testes no pacote `corpus`, todos passando.

### 2026-08-12 — B3 concluído (detecção de trava por relógio externo)

**Arquivos criados/alterados:**

| Arquivo | O quê |
| --- | --- |
| `server/api-core/internal/handlers/stall_watch.go` | detector por conexão: varre a 250 ms, abre `stall_event` no buraco, fecha na volta, concilia com o despejo do agente |
| `server/api-core/internal/handlers/diag_params.go` | leitor de `diag_param` com cache de 30 s — o **primeiro consumidor** da tabela de parâmetros |
| `server/api-core/internal/handlers/control_ws.go` | casos `hb` (2 Hz) e `stall_context`; watcher criado por conexão |
| `client-agent/cmd/agent/stall_buffer.go` | ring buffer 60 s @ 10 Hz, detecção de salto de relógio, despejo pós-evento |
| `client-agent/cmd/agent/control.go` | pulso de 500 ms e envio do despejo |

**Desenho que vale registrar:**

- `hb` é um caso **separado** do `heartbeat` de 5 s. O antigo consulta o banco,
  publica presença e decide atualização — a 2 Hz isso seria carga, não medição.
  O pulso não carrega payload nenhum: o que interessa dele é o buraco.
- O início da trava é a **última batida recebida**, não o instante da percepção.
  Medir a partir da percepção embutiria o intervalo de varredura na duração — há
  teste que falha se alguém trocar isso.
- Origem e confiança saíram do SQL e viraram funções puras em Go
  (`origemDaTrava`, `confiancaConciliada`). Regra de diagnóstico precisa ser
  legível e testável sem banco no meio.
- O ring buffer é **global do processo**, não da conexão: a trava costuma
  derrubar o canal, e um buffer por conexão perderia justamente o contexto do
  evento que existe para registrar.
- Conexão que cai com trava aberta fecha com `confianca='baixa'` e
  `origem='indeterminado'`. Trava aberta para sempre no banco seria pior que não
  registrar.

**Verificação:** 12 testes (7 servidor, 5 agente), `go test -race` limpo nos
dois lados, suíte completa do `api-core` passando.

**Decisões tomadas aqui:** D11, D12 (§3).

### 2026-08-12 — B5 concluído (persistência do dossiê)

**Arquivos criados:**

| Arquivo | Conteúdo |
| --- | --- |
| `server/migrations/0072_dossie_diagnostico.sql` | `negative_status`, `stress_run`, `stress_sample`, `stall_event`, `stage_duration_stat`, `diagnosis` |
| `server/migrations/0073_telemetria_continua.sql` | `telemetry_sample`, `telemetry_daily`, `incident_burst`, `incident_burst_quota`, `log_signature`, `log_signature_hit` |
| `server/migrations/0074_parametros_e_perfil_escada.sql` | `diag_param_set`, `diag_param` (50 parâmetros da §18), `stress_profile` + perfil `completa` v1 |

**Verificação feita (não é "parece certo", foi rodado):** container Postgres 16
descartável, as 74 migrations aplicadas do zero em ordem — 0 erros — e cada
invariante testada por INSERT que *deveria* falhar:

| Invariante | Resultado |
| --- | --- |
| `diagnosis` sem base, ou com as duas | recusado |
| `diagnosis` com 4 causas | recusado |
| abstenção sem `proximos_testes` | recusado |
| `incident_burst` com campo sensível sem consentimento | recusado |
| dois `diag_param_set` vigentes | recusado |
| `stress_run` executando sem consentimento | recusado |
| `stress_run` com perfil inexistente | recusado (FK) |
| amostra reentregue duplicando | recusado (PK de idempotência) |
| diagnóstico passivo válido / pré-voo válido | aceitos |

**Furo encontrado e corrigido durante o teste:** `tstzrange` vazio não é NULL,
então um diagnóstico "passivo" com janela vazia passava no XOR de base e seria
gravado sem base nenhuma. Fechado com `diagnosis_janela_nao_vazia` e o
equivalente em `incident_burst`. É o tipo de coisa que só aparece rodando.

**Decisões tomadas aqui:** D7, D9, D10 (§3).

**O que NÃO foi feito e por quê:**
- `diagnostic_runs` (0019) segue de pé — ainda é o que o menu de 30 testes usa.
  Sai em B8, sem ponte com o esquema novo (sem compatibilidade retroativa).
- `negative_status` e `log_signature` nascem **vazias**. É de propósito: quem as
  preenche é A3/A4 com revisão humana, e tabela cheia de chute vira rótulo de
  treino ruim.
- Nenhum código Go lê `diag_param` ainda; a tabela existe e está semeada, o
  consumo entra em cada passo que precisar de um limiar.

### 2026-08-12 — arquitetura fechada

- `ARQUITETURA-DIAGNOSTICO-NEURAL.md` completo (§1–§18), parâmetros
  consolidados em §18.
- Este arquivo de roadmap criado.

---

## 3. Decisões tomadas (não reabrir sem motivo)

| # | Decisão | Onde está a razão |
| --- | --- | --- |
| D1 | O `brain` nunca fala com o cliente; todo WS/RBAC fica no `api-core` | §3, fronteira dura |
| D2 | O agente mede, não julga: emite amostra com `load_level`, sem veredito | §5, contrato de saída |
| D3 | Quem mede a trava é o servidor (relógio externo), não o agente | §6 |
| D4 | Nenhum texto gerado por modelo em runtime | §12.1 |
| D5 | Corpus externo dá prior e vocabulário, nunca veredito | §13.4 |
| D6 | Promoção de modelo é por causa, com sombra antes e rebaixamento automático | §14 |
| D7 | Persistência (B5) vem antes do corpus estar pronto — não depende dele | §0 deste arquivo |
| D8 | Nenhum limiar em código; tudo em configuração versionada | §18 |
| D9 | Consentimento e recusa de sensível são **CHECK no banco**, não validação em Go — não existe caminho de código capaz de burlar | 0072/0073 |
| D10 | Idempotência da amostra é a PK `(run_id, stage, load_level, t_ms, metrica)` — reentrega após reconexão não duplica por construção | §5, 0072 |
| D11 | Pulso `hb` (2 Hz) é mensagem separada do `heartbeat` (5 s) e não toca o banco; o que persiste é o buraco, que é raro | `stall_watch.go` |
| D12 | O agente só tem autoridade para afirmar que o **próprio relógio saltou** — nunca a duração da trava | §6, `stall_buffer.go` |
| D13 | O dump vive fora do repositório (`Documents/TGDESK-corpus/`) e é lido **em fluxo** do `.7z`; o `Posts.xml` nunca é extraído para disco | disco a 96%; §13.2 |
| D14 | Filtro de domínio roda **na ingestão**, não depois: sinal que nenhuma causa consome não deveria nem entrar | §13.6, poda |
| D15 | Rotulagem cobre português e inglês no mesmo padrão — separar por idioma duplicaria a regra sem separar nada útil | `ingest.go` |

---

## 4. Lacunas declaradas

Coisas que o documento assume e que **ainda não têm dono no código**. Não são
esquecimento — são dívida conhecida, listada para não virar surpresa.

| Lacuna | Impacto | Quando resolve |
| --- | --- | --- |
| Dump baixando (1,29 GB, ~4 MB/min); corpus ainda vazio | A2–A4 parados, e com eles B2/B4 | ao fim do download |
| `corpus_prior` e `corpus_signal_demand` existem mas ninguém as popula | derivação (A3/A4) ainda não tem código | A3, A4 |
| Ring buffer guarda só a linha do tempo — sem métricas a 10 Hz | detecta o salto de relógio, mas o contexto que sobe é magro | B4, junto com a rajada |
| `stall_event.run_id` sempre NULL (trava durante escada não se liga à execução) | trava sob carga não aparece marcada na curva | B2 |
| `negative_status` sem conteúdo (só esquema) | motor não tem chave para responder | B1, após A3 |
| Classe de dispositivo (para `stage_duration_stat`) ainda não definida em código | previsão de duração cai na faixa larga de "estimativa grosseira" (§10.2) | B2 |
| `diag_param` existe e está semeada, mas nenhum código Go a lê ainda | limiares corretos no banco, ausentes no comportamento | cada passo que usar limiar |
| `diagnostic_runs` (0019) convive com o esquema novo | dois modelos de execução no repo até B8 | B8 |
