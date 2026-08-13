# Mapa do diagnóstico TGDesk

Três recortes do mesmo modelo, do dado que está em produção hoje: 9 status
observáveis, 22 problemas, 73 ligações.

---

## 1. A cadeia inteira

O que o usuário percebe é **sintoma**. O que está errado é **problema**. Entre
os dois existe uma medida — e é ela que faz a diferença entre diagnóstico e
palpite.

```mermaid
flowchart LR
    A["<b>Sintoma</b><br/>o que a pessoa relata<br/><i>'tá lento'</i>"]
    B["<b>Status negativo</b><br/>o que se observa<br/><i>lentidão profunda</i>"]
    C["<b>Discriminador</b><br/>a medida que separa<br/><i>latência 9,9 ms</i>"]
    D["<b>Problema</b><br/>o que está errado<br/><i>disco lento</i>"]
    E["<b>Tipo</b><br/>família de conduta<br/><i>peça insuficiente</i>"]
    F["<b>Conduta</b><br/>o que fazer<br/><i>trocar por NVMe</i>"]

    A -->|"vocabulário<br/>do relato"| B
    B -->|"telemetria<br/>+ histórico"| C
    C -->|"probabilidade<br/>calibrada"| D
    D --> E
    E --> F

    style C fill:#1a4d7a,color:#fff
    style F fill:#1a5c3a,color:#fff
```

**Sem o passo do meio, o produto adivinha.** É por isso que causa sem
discriminador medido entra no catálogo marcada como lacuna, em vez de sumir.

---

## 2. O caminho real da lentidão

Este é o código que roda hoje, com os limiares que estão em produção. Cada
losango é uma medida, não uma opinião.

```mermaid
flowchart TD
    START(["Usuário: 'está lento'"]) --> P{"Um processo domina?<br/>≥40% CPU ou ≥4 GB"}

    P -->|sim| INT["<b>lentidão intermitente</b>"]
    INT --> C1["processo em segundo plano<br/><i>achar e controlar</i>"]

    P -->|não| L{"Latência de disco<br/>≥20 ms?"}
    L -->|sim| PROF["<b>lentidão profunda</b>"]

    L -->|não| S{"SMART fora<br/>de Healthy?"}
    S -->|sim| DISP["<b>erro de dispositivo</b>"]
    DISP --> C2["disco degradado<br/><i>backup urgente + trocar</i>"]

    S -->|não| F{"Forma do episódio<br/>no histórico de 7 dias"}
    F -->|"picos ≥1% das amostras<br/>e média <60%"| INT
    F -->|"média ≥60% sustentada"| PROF
    F -->|"nem um nem outro"| NC["<b>não caracterizada</b><br/>lacuna nomeada:<br/><i>falta histórico de episódios</i>"]

    PROF --> C3["disco lento · disco cheio<br/>memória insuficiente · CPU insuficiente"]

    style P fill:#1a4d7a,color:#fff
    style L fill:#1a4d7a,color:#fff
    style S fill:#1a4d7a,color:#fff
    style F fill:#1a4d7a,color:#fff
    style NC fill:#7a5c1a,color:#fff
    style C1 fill:#1a5c3a,color:#fff
    style C2 fill:#7a1a1a,color:#fff
```

**Onde cada máquina do parque cai hoje:**

| Máquina | Bifurcação que decide | Resultado |
| --- | --- | --- |
| Daniel | `vmmemWSL` com 5,7 GB → domina | lentidão intermitente |
| Arthur | `vmmemWSL` com 5,7 GB → domina | lentidão intermitente |
| Dani | ninguém domina; latência 9,9 ms (abaixo de 20) | ainda **não caracterizada** |

A Dani é o caso interessante: ela passa por todas as bifurcações sem disparar
nenhuma, e o sistema **diz que não sabe** em vez de escolher a hipótese menos
improvável. O limiar de 20 ms é chute meu, calibrado em três máquinas — se ela
sentir a lentidão e o número ficar em 10 ms, o limiar está errado.

---

## 3. A matriz completa

Todos os 9 status e os 22 problemas, agrupados pelos 7 tipos. A relação é
**muitos-para-muitos** — disco degradado sozinho produz cinco status.

```mermaid
flowchart LR
    subgraph SINTOMAS["O que o usuário percebe"]
        direction TB
        s1["lentidão<br/>intermitente"]
        s2["lentidão<br/>profunda"]
        s3["trava"]
        s4["desliga<br/>sozinho"]
        s5["não inicia"]
        s6["corrupção<br/>de dados"]
        s7["erro de<br/>dispositivo"]
        s8["superaquece"]
    end

    subgraph FALHA["1 · Peça falhando → substituir"]
        direction TB
        f1["disco degradado"]
        f2["disco desgastado"]
        f3["memória instável"]
        f4["fonte falhando"]
        f5["bateria degradada"]
        f6["GPU falhando"]
        f7["placa/capacitor 🚫"]
    end

    subgraph INSUF["2 · Peça insuficiente → melhorar"]
        direction TB
        i1["disco lento"]
        i2["memória insuficiente"]
        i3["CPU insuficiente"]
        i4["rede insuficiente"]
    end

    subgraph COND["3 · Mal condicionada → manutenção"]
        direction TB
        m1["refrigeração"]
        m2["mau contato 🚫"]
    end

    subgraph ESG["4 · Recurso esgotado → liberar"]
        direction TB
        e1["disco cheio"]
        e2["processo em<br/>segundo plano"]
    end

    subgraph SW["5 · Software → reconfigurar"]
        direction TB
        w1["software conflitante"]
        w2["driver incompatível"]
        w3["sistema corrompido"]
        w4["inicialização pesada"]
    end

    subgraph AMB["6 · Ambiente → agir fora"]
        direction TB
        a1["alimentação instável"]
        a2["ambiente quente"]
        a3["rede instável"]
    end

    subgraph EXP["7 · Expectativa → conversa"]
        x1["dentro do esperado"]
    end

    s1 --- e2
    s1 --- i2
    s1 --- i3
    s1 --- e1
    s1 --- w1
    s1 --- w2
    s1 --- w4
    s1 --- m1
    s1 --- a2
    s1 --- a3
    s1 --- x1

    s2 --- i1
    s2 --- e1
    s2 --- i2
    s2 --- i3
    s2 --- e2
    s2 --- f1
    s2 --- f2
    s2 --- a3
    s2 --- i4
    s2 --- x1

    s3 --- f1
    s3 --- f3
    s3 --- f4
    s3 --- f6
    s3 --- f7
    s3 --- i2
    s3 --- m1
    s3 --- m2
    s3 --- w1
    s3 --- w2
    s3 --- w3

    s4 --- a1
    s4 --- f4
    s4 --- f3
    s4 --- f5
    s4 --- f6
    s4 --- f7
    s4 --- w1
    s4 --- w2
    s4 --- m1

    s5 --- f1
    s5 --- f3
    s5 --- f4
    s5 --- f7
    s5 --- a1
    s5 --- e1
    s5 --- m2
    s5 --- w3

    s6 --- f1
    s6 --- f3
    s6 --- w3

    s7 --- f1
    s7 --- f2
    s7 --- e1
    s7 --- m2

    s8 --- m1
    s8 --- a2
```

🚫 = não separável à distância. Não some da tela: aparece como lacuna
declarada, porque uma causa que existe e não pode ser confirmada remotamente
precisa estar visível para o técnico decidir ir presencialmente.

---

## O que ler nesses três

**O nó mais conectado é `disco_degradado`** — cinco status. É por isso que a
distinção contra `disco_lento` e `disco_cheio` importa tanto: errar ali manda
trocar peça sã, ou perde o dado de alguém.

**`lentidão intermitente` tem 11 causas candidatas**, o maior conjunto entre os
sintomas de lentidão. Faz sentido: engasgo é o sintoma mais inespecífico que
existe, e é justamente por isso que ele exige a medida de dominância de processo
para decidir alguma coisa.

**Os dois 🚫 concentram-se em trava e não-inicia** — os dois sintomas onde o
diagnóstico remoto mais frequentemente termina em "precisa ir lá".
