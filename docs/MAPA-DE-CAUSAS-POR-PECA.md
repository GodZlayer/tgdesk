# Mapa de causas por peça — TGDesk

Este documento é o **transposto** de [TAXONOMIA-DE-DEFEITOS.md](TAXONOMIA-DE-DEFEITOS.md).
Lá as causas estão organizadas por *tipo de defeito*; aqui, por *peça*. As duas
vistas descrevem o mesmo conjunto e servem a perguntas diferentes:

- a taxonomia responde **"que tipo de problema é este?"**
- este mapa responde **"o que pode dar errado nesta peça?"**

A segunda é a que o técnico tem na mão diante de uma máquina.

---

## 0. A regra de inferência

**Defeito de hardware é condição suficiente para sintoma no software, nunca
condição necessária.**

Toda peça com defeito aparece no uso. Nem tudo que aparece no uso é peça com
defeito. A implicação é assimétrica e define a ordem do diagnóstico:

> **Do software você nunca conclui hardware — você só elimina.**

Confirmar hardware exige medir a peça diretamente. Eliminar hardware é barato,
tem referência pública e resolve a maioria dos casos. Por isso se elimina
primeiro, e o que sobra é o espaço de software, configuração, carga e
expectativa.

O erro que essa regra previne já foi cometido neste projeto: numa máquina com
disco cheio e engasgos, a correlação fechava — disco cheio explica engasgo. O
que não foi perguntado é se *aquele* hardware, para *aquele* uso, deveria
engasgar. A resposta era não, e a leitura estava rasa.

### As quatro perguntas de cada peça

| eixo | pergunta | o que revela |
| --- | --- | --- |
| Saúde declarada | a peça se diz saudável? | defeito que ela própria reconhece |
| Entrega | ela rende o que deveria? | peça abaixo da classe dela |
| Parte ruim | existe uma região dela pior que o resto? | defeito localizado |
| Sob uso real | como ela se comporta acompanhada? | o problema que só existe em conjunto |

O quarto eixo é o que nenhuma ferramenta de bancada faz, porque todas assumem
máquina dedicada ao teste.

---

## 1. Armazenamento

A peça com mais causas distintas, e onde confundi-las custa mais caro: as
resoluções vão de **grátis** (redimensionar) a **substituir o disco**.

### 1.1 Três coisas diferentes que se chamam "disco cheio"

| condição | como se distingue | resolução |
| --- | --- | --- |
| Partição cheia, **disco com espaço não alocado** | soma das partições < tamanho do disco | **redimensionar** — grátis, sem mover nada |
| Partição cheia, disco cheio, **outro disco com folga** | volume saturado + folga em outro dispositivo da mesma máquina | **mover arquivos** — grátis |
| Todos os volumes cheios | nenhuma folga em lugar nenhum | **adicionar armazenamento** |

Nenhuma das três é detectável olhando um volume isolado. A pergunta que separa
é **"existe folga em outro lugar desta máquina?"**, e ela precisa ser feita no
conjunto dos discos.

> Caso real do parque: uma máquina com C: a 98,2% e mais de 400 GB livres em
> outros três discos. A resolução não custa nada, e o sistema não a enxergava
> porque só olhava ocupação por volume.

### 1.2 Mídia degradada — a categoria que raciocínio por saturação não vê

Um disco com setores ruins atrapalha **mesmo vazio**, e mesmo numa partição que
o sistema nunca usa. Basta o Windows enumerar, indexar ou verificar o volume
para a operação ficar presa esperando uma leitura que não retorna.

Isso não é capacidade, não é ocupação, não é carga. É uma peça que prejudica a
máquina **só por estar presente e ser tocada de vez em quando**.

| característica | consequência para o diagnóstico |
| --- | --- |
| independe de ocupação | limite percentual não detecta |
| independe de carga | telemetria de saturação não detecta |
| gatilho raro e imprevisível | amostragem contínua provavelmente nunca pega no ato |
| localizada na mídia | **só varredura de superfície encontra** |

É também a categoria que justifica o custo da varredura: ela é o único
instrumento que responde essa pergunta.

### 1.3 As demais causas

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Controlador sem folga** | colapso sob carga com mídia íntegra e ocupação alta | liberar espaço |
| **Controlador falhando** | colapso sob carga **com** espaço livre e mídia íntegra | substituir |
| **SSD desgastado** | `life_pct` / wear abaixo do limiar | substituir |
| **Disco lento para a função** | entrega dentro da classe, classe aquém do uso | trocar por classe superior |
| **Cabo, porta ou contato** | erros intermitentes que mudam ao trocar de porta | manutenção física |
| **Dispositivo removível atrapalhando** | lentidão que some ao desconectar | remover ou substituir |
| **Sistema de arquivos corrompido** | erros de estrutura sem erro de mídia | software, não peça |
| **Fragmentação (HDD)** | leitura sequencial muito abaixo da classe em disco mecânico | manutenção lógica |

### 1.4 Erros de instrumento a evitar

- **Ocupação não é diagnóstico.** No parque, uma máquina a 98,3% responde em
  0,73 ms sob carga e outra a 93,7% desaba para 577 ms. O limite tolerável é
  do controlador, não da porcentagem.
- **Métrica agregada de "disco" não existe em máquina com vários discos.** O
  contador `PhysicalDisk(_Total)` soma todos: num equipamento com cinco
  unidades, o número resultante não descreve nenhuma delas.
- **Média apaga engasgo.** Um disco que responde bem quase sempre e trava por
  segundos raramente tem média excelente. A distinção mora no p99 e na razão
  entre p99 e mediana.
- **Varredura sequencial confunde tempo com espaço.** Carga concorrente durante
  um trecho do exame aparece como região ruim do disco. A defesa é visitar as
  regiões fora de ordem.

---

## 2. Memória

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Módulo defeituoso** | erro em teste de padrões; erros de paridade no log | substituir o módulo |
| **Quantidade insuficiente** | commit alto de forma sustentada, compressão de memória ativa | adicionar |
| **Canal único** | um módulo só, ou módulos no mesmo canal | **mover de slot — grátis** |
| **Frequência abaixo do perfil** | velocidade medida < a nominal do módulo | aplicar perfil na BIOS |
| **Módulos díspares** | capacidades/frequências diferentes entre slots | padronizar |
| **Contato sujo ou mal encaixado** | erros intermitentes que somem ao reassentar | manutenção física |
| **Consumida por vazamento** | um processo cresce sem parar até reiniciar | software |
| **Disputada com vídeo integrado** | GPU sem memória dedicada | mais RAM, ou vídeo dedicado |

**A causa que mais engana:** canal único. A memória está perfeita, a quantidade
está certa, todo teste de integridade passa — e a máquina entrega metade da
banda. É defeito de *instalação*, não de peça, e a resolução não custa nada.

**Cobertura é o ponto fraco atual:** o teste de integridade cobre 256 MB. Numa
máquina de 32 GB isso é 0,8% da memória, e um defeito fora dessa faixa passa
despercebido.

---

## 3. Processador

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Núcleo defeituoso** | um núcleo rende muito abaixo dos irmãos | substituir |
| **Throttling térmico** | frequência cai quando a temperatura sobe | manutenção da refrigeração |
| **Throttling por energia** | frequência limitada com temperatura normal | plano de energia, alimentação |
| **Insuficiente para a carga** | uso alto sustentado com fila de processos | melhorar a peça ou reduzir a carga |
| **Refrigeração mal condicionada** | temperatura alta em repouso | pasta térmica, limpeza |
| **Esperando memória** | uso baixo com fila alta e banda saturada | é memória, não processador |

**A distinção que mais importa:** processador com uso alto não é
necessariamente processador insuficiente. Um núcleo esperando memória ou disco
aparece como ocupado. Fila de processos separa os dois — uso alto com fila zero
é trabalho útil; fila alta é gargalo real.

---

## 4. Vídeo

| causa | como se distingue | resolução |
| --- | --- | --- |
| **GPU falhando** | TDR, artefatos, erros de driver de vídeo no log | substituir |
| **Driver incompatível** | erros que somem ao reverter versão | software |
| **Memória de vídeo insuficiente** | uso de VRAM no teto com queda de desempenho | melhorar a peça |
| **Integrada disputando RAM** | `dedicated_memory` zero, memória compartilhada | mais RAM, ou vídeo dedicado |
| **Throttling térmico** | frequência cai com a temperatura | refrigeração |
| **Alimentação insuficiente** | quedas sob carga apenas em jogo/render | fonte |
| **Cabo, saída ou monitor** | sintoma muda ao trocar cabo ou porta | manutenção física |

**Lacuna declarada:** o coletor lê vídeo por NVML, que só enxerga NVIDIA.
Placas Intel e AMD, incluindo toda GPU integrada, são invisíveis hoje. Isso não
é "não está sendo usada" — é "não temos como saber".

---

## 5. Alimentação e placa-mãe

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Fonte falhando** | desligamento sob carga, sem log, tensões fora de faixa | substituir |
| **Capacitores** | por exclusão de todo o resto | manutenção ou substituir |
| **Mau contato** | sintoma muda ao reassentar peças | manutenção física |

**Declaração honesta:** não existe medição confiável de fonte por software. O
máximo é ler tensão dos trilhos, que é indireto e pouco confiável. Avaliação
real exige equipamento. Esta é a peça com menos instrumento e maior gravidade,
e nenhum truque de telemetria muda isso.

---

## 6. Térmico e ambiente

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Refrigeração insuficiente** | temperatura alta sob carga, ventoinha no máximo | melhorar refrigeração |
| **Ventoinha parada** | temperatura alta com rotação zero ou ausente | substituir |
| **Poeira** | temperatura alta que cai após limpeza | manutenção |
| **Ambiente quente** | temperatura alta em repouso, em toda a máquina | agir fora do gabinete |

**Lacuna declarada:** rotação de ventoinha não é legível por API padrão em
desktop de consumo — exige acesso ao controlador embutido. Temperatura de
processador retorna "acesso negado" ao usuário comum; o agente, rodando como
sistema, tem chance de conseguir e isso ainda não foi tentado.

---

## 7. Rede

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Adaptador falhando** | erros de link, quedas recorrentes | substituir |
| **Cabo ou porta** | sintoma muda ao trocar cabo/porta | manutenção física |
| **Sinal sem fio fraco** | latência e perda variando com posição | posicionamento, repetidor |
| **Banda insuficiente** | saturação sustentada do link | contratar mais |
| **Rota ou DNS** | latência normal com resolução lenta | software |

Rede tem o terceiro eixo bem servido: cada salto é uma "parte" inspecionável, e
o caminho é endereçável.

---

## 8. Bateria

| causa | como se distingue | resolução |
| --- | --- | --- |
| **Capacidade degradada** | capacidade atual muito abaixo da de projeto | substituir |
| **Ciclos excedidos** | contagem de ciclos alta | substituir |
| **Carregador ou porta** | não carrega, ou carrega intermitente | manutenção |

---

## 9. O que este mapa muda no instrumental

Cruzando as causas acima com o que existe hoje:

| lacuna | consequência |
| --- | --- |
| Atividade de disco só agregada | máquina com vários discos não é diagnosticável |
| Espaço não alocado não é calculado | a resolução mais barata que existe é invisível |
| Folga em outro disco não é considerada | recomenda-se compra onde bastava mover arquivo |
| Vídeo lido só por NVML | toda GPU integrada e AMD é cega |
| Temperatura de processador ausente | superaquecimento sem sensor |
| Rotação de ventoinha ausente | refrigeração sem sensor |
| Cobertura de memória em 0,8% | defeito fora da faixa testada passa |
| Sem medição de fonte | a peça mais grave é a menos observável |

**A ordem de construção que este mapa sugere** não é "mais exames", é fechar as
lacunas que hoje tornam causas inteiras indetectáveis — começando pelas que têm
resolução gratuita, porque errar nelas custa ao cliente dinheiro que ele não
precisava gastar.
