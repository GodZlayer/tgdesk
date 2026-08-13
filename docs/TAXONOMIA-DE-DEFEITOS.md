# Taxonomia de defeitos — TGDesk

Documento para revisão. Define, de cima para baixo, **o que pode estar errado
num computador**, antes de qualquer código.

Substitui a abordagem anterior, que era errada por construção: as causas nasciam
uma a uma, conforme o defeito aparecia, e o conjunto nunca ficava completo.

---

## 0. A regra que organiza tudo

> **Duas coisas são causas diferentes quando geram CONDUTAS diferentes.**

Não quando têm nomes diferentes, não quando a peça é diferente. Se a ação é a
mesma, é a mesma causa. Se a ação muda, precisam ser separadas — mesmo que a
peça seja a mesma.

É por isso que "disco cheio", "disco lento" e "disco falhando" são **três**
causas: limpar, trocar por melhor, e fazer backup urgente. E é por isso que
"disco falhando" e "cabo SATA solto" podem ser a **mesma conduta inicial**
(abrir e verificar) mesmo sendo peças diferentes.

### Uma correção estrutural

O modelo anterior era uma árvore `status → causas`. Está errado.

Um problema real produz **vários** status, e um status admite **vários**
problemas. Disco falhando produz lentidão, trava, corrupção e não-inicializa —
os quatro. A relação é muitos-para-muitos, e forçá-la em árvore foi o que fez o
conjunto de causas ficar torto.

**Ordem correta:** tipo → problema real → discriminador → conduta. E, à parte,
o mapa problema ⇄ status observável.

### Por que a taxonomia não sai do corpus

O corpus de fórum tem 6832 casos resolvidos rotulados por classe. Amostrando as
mensagens causais, elas são majoritariamente **instruções**, não diagnósticos:

    memoria    :: "go to system properties... startup tab"
    disco      :: "norton ghost is the traditional commercial tool"
    desempenho :: "duplicating frames is the wrong approach"

Servem para vocabulário e prior fraco. Não servem para fundar a ontologia, e
tratá-las como causa confirmada foi um erro da versão anterior.

---

## 1. Nível 1 — Tipagens base

Sete tipos. O critério de existência de cada um é a **família de conduta**.

| # | Tipo | O que caracteriza | Família de conduta |
| --- | --- | --- | --- |
| 1 | **Peça falhando** | hardware com defeito, progressivo ou súbito | substituir; com urgência de backup quando o defeito é no dado |
| 2 | **Peça insuficiente** | hardware SÃO, aquém da carga | melhorar a peça, ou reduzir a carga |
| 3 | **Peça mal condicionada** | hardware são e suficiente, operando fora das condições | manutenção física |
| 4 | **Recurso esgotado** | estado, não peça: espaço, memória, handles, portas | liberar |
| 5 | **Software / configuração** | programa, serviço, driver, sistema, malware | remover, reconfigurar, atualizar, reverter, reinstalar |
| 6 | **Ambiente externo** | fora do gabinete: energia, rede, temperatura do ambiente | agir fora da máquina |
| 7 | **Expectativa** | a máquina faz o que ela é; a expectativa é maior | conversa e dimensionamento — não é conserto |

### Sobre o tipo 7

Existe de propósito, e é o mais fácil de esquecer. Sem ele, um produto de
diagnóstico **sempre encontra um defeito**, porque foi construído para isso — e
começa a mandar trocar peça sã. O tipo 7 é a saída honesta para "está tudo certo
e mesmo assim está ruim para o que você precisa".

### Sobre a distinção 1 × 2

É a que mais muda dinheiro. "Falhando" gera troca urgente e risco de perda de
dado; "insuficiente" gera upgrade planejado. Confundir os dois é ou assustar o
cliente à toa, ou perder o dado dele.

O discriminador é sempre o mesmo: **a peça está fora de especificação, ou dentro
da especificação e a especificação é baixa?** SMART com erro é o primeiro; disco
sadio de 5400 rpm é o segundo.

---

## 2. Nível 2 — Problemas reais por tipo

Cada linha é um problema com conduta própria. A coluna **Medida** diz o veredito
de §13.6: `existe` (o agente já mede), `adaptar` (mede parcial), `construir`
(viável, não existe), `inviável` (exige presença física ou hardware externo).

### Tipo 1 — Peça falhando

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Disco degradado | SMART fora de `Healthy`, setores realocados/pendentes, erros de I/O no log | **existe** |
| Disco desgastado (SSD) | `life_pct` / wear-leveling abaixo do limiar | **existe** |
| Memória defeituosa | erros de paridade/ECC no log; falha em teste de memória | **adaptar** — o teste existe sob demanda; falta o evento contínuo |
| Fonte falhando | quedas sob carga, tensões fora de faixa, desligamento sem log | **construir** — hoje só se infere pela ausência |
| Bateria degradada | ciclos, capacidade de projeto × atual | **existe** |
| GPU falhando | erros de driver de vídeo, TDR, artefatos | **adaptar** |
| Placa-mãe / capacitores | por exclusão de todo o resto | **inviável** à distância |

### Tipo 2 — Peça insuficiente

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Disco lento para a carga | latência de I/O alta **com SMART saudável**; HDD onde a carga pede SSD | **existe** (desde 1.2.53) |
| Memória insuficiente | uso sustentado no teto **com paginação**, sem erro de memória | **adaptar** — falta o contador de paginação |
| Processador insuficiente | uso sustentado alto **sem pico isolado**, fila de processador alta | **existe** |
| GPU insuficiente | uso de GPU no teto durante a tarefa reclamada | **adaptar** |
| Rede insuficiente | banda contratada abaixo do uso | **construir** |

### Tipo 3 — Peça mal condicionada

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Refrigeração suja / pasta ressecada | temperatura alta **com carga normal**, throttling térmico | **existe** |
| Ventoinha parada ou irregular | RPM zero ou fora de faixa | **adaptar** |
| Mau contato / cabo ruim | erros de I/O intermitentes que somem ao reassentar | **inviável** à distância — exige mão na máquina |
| Fluxo de ar obstruído | delta térmico alto entre peças | **adaptar** |

### Tipo 4 — Recurso esgotado

Reversível sem tocar em hardware — e é o que torna este tipo o de melhor
custo-benefício para resolver primeiro.

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Disco cheio | ocupação ≥ 90 %, folga abaixo do necessário para paginação | **existe** |
| Memória ocupada por processo | uso alto **atribuível a um processo** | **construir** — falta top-N de processos contínuo |
| Handles / threads vazando | contadores crescendo monotonicamente | **construir** |
| Portas / conexões esgotadas | contagem de sockets no teto | **construir** |
| Perfil de usuário inchado | tamanho do perfil, tempo de login | **construir** |

### Tipo 5 — Software / configuração

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Processo em segundo plano consumindo | top-N de processos durante o episódio, por dominância | **existe** (desde 1.2.58) |
| Serviço em falha / reiniciando | eventos de falha de serviço no log | **adaptar** |
| Driver incompatível ou defeituoso | código de erro de driver, TDR, bugcheck ligado a driver | **adaptar** |
| Sistema de arquivos corrompido | chkdsk/sfc com erro, eventos de corrupção | **adaptar** |
| Malware / minerador | consumo sem processo legítimo correspondente | **construir** |
| Atualização mal aplicada | correlação temporal com instalação de atualização | **construir** |
| Inicialização pesada | tempo de boot, quantidade de itens de inicialização | **existe** |

### Tipo 6 — Ambiente externo

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Rede elétrica instável | desligamentos sem bugcheck, eventos de energia | **adaptar** |
| Temperatura do ambiente alta | temperatura alta em TODAS as peças, inclusive em repouso | **existe** |
| Enlace de rede instável | perda e latência no enlace | **existe** |
| Provedor / rota externa | latência que aparece só além do gateway | **existe** |

### Tipo 7 — Expectativa

| Problema | Como se separa | Medida |
| --- | --- | --- |
| Máquina dentro do esperado para a classe dela | todas as medidas dentro da faixa da classe do equipamento | **construir** — exige a faixa por classe |
| Uso mudou, máquina não | carga atual acima do que a máquina foi dimensionada | **construir** |

---

## 3. Nível 3 — O mapa problema ⇄ status

O que o usuário RELATA (status) e o que está errado (problema) são eixos
diferentes. Um exemplo de por que a árvore antiga não servia:

| Problema | lentidão intermitente | lentidão profunda | trava | desliga | não inicia | corrupção |
| --- | :---: | :---: | :---: | :---: | :---: | :---: |
| Disco degradado | | ● | ● | | ● | ● |
| Disco lento | | ● | | | | |
| Disco cheio | ● | ● | | | ● | |
| Memória insuficiente | ● | ● | ● | | | |
| Memória defeituosa | | | ● | ● | ● | ● |
| Processo em segundo plano | ● | | | | | |
| CPU insuficiente | ● | ● | | | | |
| Refrigeração | ● | | ● | ● | | |
| Fonte | | | ● | ● | ● | |
| Driver | ● | | ● | ● | | |

Lendo por coluna sai o conjunto de causas candidatas de cada status. Lendo por
linha sai quais sintomas um problema explica — que é o que permite dizer "isto
também explicaria aquele travamento de semana passada".

---

## 4. O que isto expõe

### As três lacunas mais caras

1. ~~Top-N de processos contínuo.~~ **FECHADA na 1.2.58.** O agente reporta
   os 8 maiores por CPU e por memória, com a CPU normalizada por núcleo e só o
   nome do executável (§7.2). O servidor emite `processo_dominante` por
   DOMINÂNCIA, não por intensidade: 40% da máquina num processo só já é um
   processo mandando, mesmo com o total fora do teto.

   Primeira leitura do parque, e ela já separa as três máquinas por causas
   diferentes:

   | Máquina | maior consumidor | leitura |
   | --- | --- | --- |
   | Daniel | `vmmemWSL` — 29% CPU, 5,7 GB | processo dominante |
   | Arthur | `vmmemWSL` — 5,7 GB | processo dominante (memória) |
   | Dani | `obs64` 5%, `parsecd` 4% | nenhum domina — a causa dela é o disco |

2. **Faixa esperada por classe de equipamento.** Sem ela não existe o tipo 7, e
   o produto sempre acha defeito.
3. **Contador de paginação.** É o que separa "memória insuficiente" de "memória
   apenas ocupada" — falta e é barato.

### O que já dá para separar hoje

Disco cheio × lento × degradado; CPU insuficiente; processo dominante;
térmico; rede; bateria; desgaste de SSD; inicialização pesada. **Oito**
problemas com discriminador medido.

### O que nunca será separável à distância

Mau contato, cabo ruim, capacitor. Entram como **lacuna declarada**: a tela diz
"não separável à distância", em vez de sumir com a hipótese.

---

## 5. Perguntas abertas para revisão

1. **Os sete tipos estão certos?** Em particular: "mal condicionada" merece ser
   tipo próprio, ou é subtipo de "falhando"?
2. **O tipo 7 (expectativa) deve existir no produto**, ou é conversa comercial
   que não cabe no diagnóstico?
3. **Falta algum problema real** nas tabelas do nível 2?
4. **A matriz do nível 3 está correta** para o que você vê no parque?
5. **Prioridade das lacunas**: top-N de processos primeiro, ou faixa por classe?
