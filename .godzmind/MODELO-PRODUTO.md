# TGDesk — modelo de produto

Ditado pelo dono do produto em 2026-07-31. Documento vivo (parte 1: o mínimo).

## O que é

App de **suporte com acesso remoto e verificação de hardware**, pensado em nível empresarial.

O **núcleo é a VPN**. Tudo trafega de forma segura por ela: comunicação entre os dispositivos
com TGDesk instalado e o servidor. Sobre a VPN correm três sistemas:

1. **Telemetria** — análise contínua do sistema
2. **Acesso remoto**
3. **Benchmarks de hardware** — de armazenamento (badblock, SMART) a poder de computação

## Papéis

| Papel | Responsabilidade |
|---|---|
| **super_admin** | Eu. Gerencio tudo e todos, possuo todas as funções. |
| **supervisor** | Responsável por todos os dispositivos vinculados a ele, dentro de todas as **empresas** que gerencia. Cada empresa tem diversas **lojas** (franquias ou filiais). |
| **técnico** | Agente de campo. Atua por acesso remoto digital ou manutenção presencial. |
| **cliente** | Usuário do dispositivo de uma loja. |
| **cliente avulso** | Usuário sem loja. |

## Base lógica — todo dispositivo é "cliente"

Independente de quem está logado nele (super_admin, supervisor, técnico ou cliente),
**todo dispositivo com TGDesk instalado roda a mesma base funcional**:
- pode ser **acessado remotamente**
- faz **telemetria** (análise contínua do sistema)
- executa **testes de benchmark de hardware**
- pode **abrir um chamado de suporte**

Isso não é a "tela de cliente" — é uma camada de baixo nível presente em toda instalação.
A máquina de um supervisor, de um técnico ou do super_admin também roda essa base: ela
TEM telemetria, TEM benchmark, TEM a capacidade de chamado, além de qualquer UI adicional
que o papel do usuário logado nela adicione por cima.

Consequência de modelagem: "cliente" não é um papel exclusivo de usuário — é o
comportamento base de todo device. Papéis mais altos (supervisor, técnico, admin) SOMAM
capacidades por cima dessa base, não a substituem. Isso explica G11 ("o tech também
possui a tela de client") e por que o supervisor também deveria ver a própria máquina
como um dispositivo cliente comum.

### Exceções — o que a base NÃO inclui para quem opera com papel elevado

Duas capacidades da base "cliente" ficam restritas quando quem está logado tem papel
técnico/supervisor/admin (não é regra de "alvo = própria máquina", é regra de PAPEL):

- **Acesso remoto à própria máquina** — nunca deve ser possível, para ninguém, em
  nenhum papel. Regra por ALVO (dispositivo == localDeviceId). Já implementada:
  `canOfferRemote` em `ui_contract.dart` exclui `id == localDeviceId`.

- **Botão "Abrir chamado"** — simplesmente não é exibido para quem está logado com
  role técnico, supervisor ou admin. Regra por PAPEL do usuário logado, não por qual
  dispositivo é o alvo. Só aparece para quem está logado como `cliente`/`cliente_avulso`.

Telemetria e benchmark continuam disponíveis normalmente para todo dispositivo,
independente do papel de quem está operando.

## Hierarquia

    organização  →  rede      →  subrede  →  dispositivo
    (supervisor)    (empresa)    (loja)

## Objetivo do acesso remoto

O supervisor acessa **diretamente qualquer dispositivo** da sua rede/org/subrede,
**sem confirmação do cliente** — ele por si só já é o responsável.

Os dispositivos têm telemetria para análise remota sem ir ao estabelecimento, além dos
benchmarks e testes de qualidade (SMART, badblock etc.).

## Fluxo de chamado / OS

### Origem 1 — cliente vinculado
Cliente percebe lentidão, ou a análise na tela aponta um problema → pede chamado →
entra na **fila única e exclusiva do seu supervisor**.

### Origem 2 — cliente avulso
Mesmo sistema do cliente vinculado, mas o chamado vai para uma **fila dinâmica que aparece
em tempos diferentes para os supervisores, baseada na nota do supervisor**.

### Triagem — sempre do supervisor
O supervisor avalia o caso e **libera ou finaliza** o chamado, conforme a necessidade real
de um agente de campo para resolver o problema.

### Origem 3 — supervisor cria chamado
O supervisor pode criar chamados com um **dispositivo como alvo**. Esses vão para uma
**fila dinâmica que aparece em tempos diferentes para cada técnico, baseada na nota do técnico**.

### Execução — técnico
O técnico tem acesso **apenas** à fila de chamados liberados para técnicos.
**Todo chamado obrigatoriamente tem a supervisão de um supervisor.**

---

## Duas filas dinâmicas distintas

| Fila | Origem | Aparece para | Critério de ordem |
|---|---|---|---|
| **A** | cliente avulso | supervisores | nota do supervisor |
| **B** | supervisor libera / cria | técnicos | nota do técnico |

E uma fila **não dinâmica**: cliente vinculado → fila exclusiva do seu supervisor.

## Adoção do avulso — lógica "corrida de Uber"

"Cliente avulso" é um **estado inicial**, não um tipo permanente de chamado. O modelo é
literalmente o de despacho de corrida: o pedido é OFERECIDO, não distribuído — só um
supervisor pode pegar, e quem pega vira dono.

    cliente avulso pede chamado
            │
            ▼
      Fila A — OFERTA simultânea a vários supervisores,
      supervisores com nota melhor recebem a oferta primeiro
      (mesmo padrão de onda/expiração do despacho a técnico, G6)
            │
            ▼
      Um supervisor ACEITA (corrida: primeiro a aceitar leva,
      a oferta para os demais é cancelada/expira)
            │
            ▼
      O dispositivo do cliente avulso passa a ser RESPONSABILIDADE
      desse supervisor a partir do aceite — mesmo enquanto o chamado
      ainda está "na fila" (ou seja, responsabilidade nasce no aceite,
      não só quando o atendimento de fato começa)
            │
            ▼
      Supervisor decide: resolve remoto ele mesmo, OU libera pro técnico
            │
            ▼
      Fila B (dinâmica, por nota do técnico) — só se liberado
      A partir daqui é um chamado NORMAL do supervisor que aceitou

Pontos que a analogia Uber deixa explícitos:
- É **oferta concorrente**, não fila FIFO nem atribuição pelo servidor — vários
  supervisores veem o pedido "aparecer" e o aceite é uma corrida entre eles.
  Precisa de exclusão mútua real (quem aceita primeiro trava o ticket).
- A responsabilidade pelo **dispositivo** (não só pelo ticket) passa ao supervisor
  no momento do aceite. Antes disso o dispositivo do avulso não pertence a ninguém.
- Depois do aceite, o chamado **deixa de ser avulso** e vira um chamado normal do
  supervisor que o adotou — mesmo tratamento que um chamado nascido de cliente vinculado.

Regra absoluta resultante: **nenhum chamado chega a um técnico sem um `supervisor_id`
dono.** O vinculado já nasce com dono (o supervisor da loja); o avulso só ganha dono
ao ser aceito na Fila A. Um chamado avulso NUNCA pula direto para a Fila B.

Consequência de modelagem: `origin: vinculado|avulso`; `supervisor_id` preenchido a
partir do aceite (não da criação, no caso avulso); e o aceite da Fila A precisa da
mesma primitiva de "oferta com corrida e exclusão mútua" que falta hoje na Fila B (G6).

## Sistema de nota (quality score)

Todos começam com nota **5,00** (máxima, duas casas decimais) — não é 0 a 5 crescendo,
é 5,00 e só pode cair (ou, presume-se, se recuperar depois de cair — a confirmar).

Ao final de um chamado, há avaliação **cruzada entre os 3 papéis envolvidos**, cada par
avalia o outro nos dois sentidos:

| Quem avalia | Quem é avaliado |
|---|---|
| supervisor | técnico |
| cliente | técnico |
| técnico | supervisor |
| cliente | supervisor |
| supervisor | cliente |
| técnico | cliente |

6 avaliações possíveis por chamado — total, não por papel. Isso alimenta:
- nota do **técnico** → ordena a Fila B (oferta pro técnico)
- nota do **supervisor** → ordena a Fila A (oferta de avulso pro supervisor)
- nota do **cliente** → detalhe exibido na fila (ver abaixo), não ordena fila nenhuma

**Cálculo**: a nota é a **média histórica** de todas as avaliações recebidas — não um
placar que só cai. É uma média corrida: sobe e desce normalmente conforme entram novas
avaliações. Mas há uma consequência aritmética natural: uma vez que a média cai abaixo
de 5,00, ela **nunca mais volta a ser exatamente 5,00** (a não ser que TODAS as
avaliações, desde a primeira, fossem 5 — o que deixa de ser possível assim que uma
avaliação menor entra na média).

**Chamado que não envolve técnico** (resolvido só pelo supervisor): remove-se do cálculo
qualquer avaliação que envolva a role técnico. Sobram só as 2 avaliações
supervisor↔cliente.

**Uso da nota do cliente**: é só um **detalhe exibido nas filas**. Quando um técnico
avalia se aceita um chamado, ele vê os dados do chamado + a nota do cliente, e decide
com base nisso (ex.: cliente com nota ruim pode ser sinal de atendimento difícil no
passado). Não entra em nenhum algoritmo de ordenação — é informativo, não funcional.

## Interface do técnico

Combina **cliente + técnico** num só app: fila de chamados, histórico de chamados,
perfil próprio.

- **Antes de aceitar**: vê os dados que o supervisor liberou sobre o chamado, e o
  **endereço da loja** (relevante sobretudo pra decidir sobre atendimento presencial).
- **Depois de aceitar**: ganha **chat direto com o supervisor**, dentro do próprio app.

Esta interface completa (fila, histórico, perfil, chat, geoloc/foto/assinatura do
presencial) é de um **app separado a ser desenvolvido depois**. O que precisa existir
JÁ é o **backend/contrato de API** que sustenta o fluxo inteiro de ponta a ponta — o
app cliente vem depois, mas o fluxo tem que ser válido e testável via API desde agora.
Isso rebaixa a prioridade de G7 (UI nativa do técnico) e reclassifica G10: a prioridade
imediata é o backend (endpoints de geoloc/foto/assinatura/export), não a captura nativa
de câmera/GPS/canvas — essa é responsabilidade do app futuro.

## Rede "pública" da VPN — correção

Não é uma rede normal nem visível na hierarquia de organizações. É uma rede **interna
à VPN, invisível para supervisores e técnicos — só o super_admin vê que ela existe**.
Ela **não libera interação direta entre os participantes** (peers nela não se enxergam
nem se acessam entre si); existe **apenas para o funcionamento lógico do sistema**, que
depende de todo dispositivo estar dentro da VPN para operar (telemetria, benchmark,
chamado). É o "estacionamento" de rede onde o dispositivo do cliente avulso vive
enquanto não tem um supervisor dono.

(Isso invalida a implementação atual: hoje a org "Atendimento Avulso TGDesk" tem
`cidr_virtual = NULL` — ou seja, não está na VPN de fato. Precisa ser uma rede real
dentro do hub WireGuard, só que sem peer-to-peer entre os membros e sem visibilidade
fora do super_admin.)

### É a MESMA rede para todo dispositivo sem organização

Essa rede-base não é exclusiva do cliente avulso — é **a rede de qualquer dispositivo
sem organização própria**, o que inclui também o **freelancer** (que, como já
registrado, não tem rede própria). Um único espaço lógico, servindo só pra "existir no
sistema": registro, telemetria, permanência em fila. Sem visibilidade entre os
participantes, visível só ao super_admin.

### Subrede temporária por sessão ativa

Quando uma sessão de acesso remoto precisa **de fato funcionar** (OS virtual aceita),
o sistema monta uma **subrede temporária** contendo só os 3 participantes daquela
sessão — cliente avulso, supervisor (ou técnico, conforme quem ficou com o acesso) —
**sem que nenhum deles enxergue ou gerencie essa subrede como conceito**. É pura
infraestrutura: existe só para o túnel WireGuard da sessão funcionar, e presumivelmente
é desfeita ao fim do atendimento.

Resumo da arquitetura de rede do avulso:
- **Rede-base "sem organização"**: permanente, compartilhada entre todo freelancer e
  todo dispositivo avulso não-adotado, zero visibilidade entre peers, só super_admin
  sabe que existe.
- **Subrede temporária de sessão**: efêmera, escopada aos 3 participantes de UMA sessão
  específica, invisível para os próprios participantes (não aparece como algo que eles
  administram), existe só enquanto a sessão de acesso remoto está ativa.

## Telemetria e benchmark do avulso — quando o supervisor pode agir

O supervisor **sempre pode ver a telemetria** do dispositivo avulso (mesmo antes de
aceitar — é um dos dados que embasam a decisão de aceitar ou não).
Mas só pode **executar benchmarks e testes remotos depois de aceitar** o pedido.

**Chat com o cliente avulso**: só existe **depois do aceite**. Antes disso não faz
sentido — o dispositivo "não é de ninguém" ainda, não há responsável pra conversar
com o cliente.

## O que acontece quando ninguém aceita

- **Nenhum técnico aceita** (oferta expira na Fila B) → o pedido **volta pro
  supervisor**, que pode **relançá-lo** manualmente pra fila.
- **Nenhum supervisor aceita** (oferta expira na Fila A) → é **exibido pro cliente**,
  que pode **pedir novamente** (novo ciclo de oferta, presumivelmente).

Em nenhum dos dois casos há re-despacho automático — a ação de tentar de novo é manual
(do supervisor num caso, do cliente no outro).

**É o MESMO pedido/ticket que volta pra fila**, não um novo — o ID do ticket persiste
através dos ciclos de reoferta. Mesmo se o cliente fechar o pedido e abrir um novo, isso
não afeta nota de ninguém: a nota só é influenciada pelas avaliações que existem quando
um chamado é **finalizado** de fato. Reofertar ou reabrir não gera avaliação nenhuma.

## Duas fontes distintas de chamados para o supervisor

O supervisor recebe chamados de **duas fontes diferentes**, que NÃO se misturam na
mesma lista:

| Fonte | Visibilidade | Como aparece |
|---|---|---|
| **Cliente vinculado** (dispositivo dentro da própria org do supervisor) | **PRIVADA** — só aquele supervisor vê | Com alerta indicando que é da própria org, mostrando **de qual rede (empresa) e subrede (loja)** é o chamado |
| **Cliente avulso** | **PÚBLICA** (Fila A) — todos os supervisores veem | Sem dono ainda; corrida por aceite, ordenada por nota (já documentado acima) |

Ou seja: o "chamado exclusivo do próprio supervisor" (mencionado logo no início deste
documento) e a "Fila A pública de avulsos" são **duas caixas de entrada separadas** na
tela do supervisor, não uma fila única — mesmo que ambas eventualmente virem OS sob a
responsabilidade dele. A fonte "org própria" nunca é ofertada a outros supervisores;
só a fonte "avulso" passa pela corrida de aceite.

## Vínculo técnico→supervisor NÃO restringe fila — é só marketing multinível

O vínculo `freelancer_profiles.supervisor_id` (técnico pertence a um supervisor) é
**metodologia de marketing multinível** (referência/comissionamento), **não é uma
restrição de acesso do sistema**. Ele não limita o que o técnico vê ou pode pegar.

Consequência direta: **a Fila B é verdadeiramente pública e global** — todo técnico do
sistema, independente de qual supervisor ele está formalmente vinculado, vê e pode
aceitar a OS de **qualquer** supervisor. O vínculo existe no cadastro (provavelmente
pra rastrear comissão/indicação), mas não é um filtro de fila.

Isso também deixa explícito, por simetria, que a **Fila A é pública para todos os
supervisores** (já registrado acima) — nenhuma das duas filas é escopada por
organização ou vínculo, ambas são globais dentro do sistema.

## Chamado → OS: a transformação real

"Converter em OS" não é renomear o ticket — é uma etapa de decisão:

    Chamado (ticket) chega → Fila A pública pra TODOS os supervisores
            │
            ▼
      Um supervisor ACEITA (corrida — quem pega primeiro)
      Dispositivo passa a ser responsabilidade desse supervisor
            │
            ▼
      Supervisor DEFINE O ESCOPO REAL do que é necessário
            │
            ▼
      Supervisor CONVERTE o chamado em OS (Ordem de Serviço)
      A OS tem um tipo/modalidade — ao menos "virtual" é uma delas
            │
            ▼
      Se a OS é do tipo VIRTUAL e vai para um técnico (Fila B):
      o ACESSO REMOTO ao dispositivo passa a ser EXCLUSIVO do técnico
      (não fica compartilhado/duplicado com o supervisor)

**Por que o acesso vira exclusivo do técnico**: o supervisor frequentemente atende
**vários chamados simultaneamente** — não tem como também executar pessoalmente cada
sessão remota. Por isso, ao delegar como "OS para acesso virtual", ele transfere o
acesso remoto de fato pro técnico que aceitou, em vez de manter os dois com acesso
concorrente ao mesmo dispositivo.

Em aberto (não bloqueia, registrar para depois): quais OUTROS tipos de OS existem além
de "virtual" — presumivelmente um equivalente para presencial — e se o supervisor
mantém acesso de supervisão/observação (não necessariamente de controle) enquanto a OS
está com o técnico.

## Sem "recusar" — só "aceitar primeiro"

Não existe ação de recusa. A fila é **pública** (todo supervisor vê a Fila A inteira;
todo técnico vê a Fila B inteira) — "aparecer em tempos diferentes por nota" não é
visibilidade restrita, é apenas **ordem de exibição**: quem tem nota melhor vê o pedido
mais cedo na lista, mas ninguém é excluído nem obrigado a agir. É "quem pega primeiro,
pega" — puro first-come-first-served sobre uma lista ordenada por nota, sem obrigação
de resposta e sem penalidade por ignorar.
