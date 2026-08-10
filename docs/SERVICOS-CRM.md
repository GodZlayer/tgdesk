# Servidores de serviço na VPN (tier `crm`)

Como colocar um servidor de produto — o CRM é o primeiro — dentro da VPN TGDesk,
e como o app cliente desse produto obtém acesso a ele.

## O modelo em uma frase

No TGDesk, dois dispositivos se alcançam **se compartilham uma subrede não
isolada**. Nada mais concede alcance: o firewall do hub (`wg/hub.go`) mantém
`DROP` em todo tráfego peer→peer e só abre os pares que
`ReconcileSessionIsolation` deriva do banco. Papel, tier e credencial não
aparecem nessa decisão e não passam a aparecer.

Um servidor de serviço não é exceção a isso. Ele é um dispositivo comum numa
subrede comum. A única coisa que o tier `crm` muda é **quem pode pedir para
entrar naquela subrede**: por ser uma máquina sem operador humano, é legítimo
qualquer dispositivo da VPN pedir para alcançá-la. Alcançar o servidor é chegar
à porta; entrar é problema do login do produto que roda ali.

## Topologia

```
organização do produto (ex.: "CRM")
└── rede
    └── subrede Principal          <- não isolada
        ├── servidor CRM           <- tier 'crm', IP VPN fixo
        ├── cliente da empresa A
        ├── cliente da empresa B
        └── ...
```

Os clientes continuam pertencendo à organização da empresa deles. Entrar na
subrede do CRM é um vínculo **adicional** — o TGDesk permite um dispositivo em
várias organizações, com **uma subrede por organização** (é o que
`UpdateDeviceSubnetworks` defende). `CRMJoin` nunca remove vínculo existente:
se o dispositivo já estiver em outro servidor da mesma organização, ele recusa
(`ja_vinculado_a_outro_servico`) em vez de trocar em silêncio.

Nenhum Windows ganha um segundo adaptador WireGuard. O servidor, quando roda em
Linux/Docker, tem o próprio peer no ambiente dele.

Separação entre empresas clientes **não** é feita pela VPN nesta topologia: é
multi-tenant dentro do banco do produto. Se um dia cada empresa precisar de uma
rede TGDesk própria, o servidor precisará estar em várias subredes da mesma
organização — o que hoje é recusado e exigiria uma dispensa explícita para o
tier `crm`.

## Parte 1 — Colocar o servidor na VPN

### 1. Criar a organização e a rede do produto

Pelo fluxo normal de admin. A subrede `Principal` nasce junto com a rede.

Confira que ela **não** está isolada: em subrede isolada nem os membros se
enxergam, e `CRMJoin` recusa o ingresso justamente para não conceder um acesso
que não funcionaria.

### 2. Instalar o TGDesk na máquina do servidor

Instalação normal, vinculada à rede criada acima. Ao fim, a máquina é um
dispositivo `ativo`, com `wg_virtual_ip` atribuído.

O IP é a identidade pública do servidor daqui em diante — é o que o app cliente
vai carregar. Anote.

### 3. Promover a tier `crm`

Painel do admin → **Serviços / CRM** → seção *Candidatos* → **Promover**.

Duas regras valem aqui, e ambas moram no servidor, não na tela:

- **Janela de 2 horas desde o vínculo.** Passado o prazo, a promoção é recusada
  (`promocao_fora_da_janela`). Promover é declarar que aquela máquina acabou de
  ser instalada como servidor; um avulso antigo, já em operação e já esquecido,
  não pode virar destino de ingresso aberto por engano ou por abuso. Se o prazo
  passar, vincule a máquina de novo.
- **Não pode ser máquina de controle de alguém.** Uma máquina com dono humano
  ficaria alcançável por todo dispositivo que pedisse, **nos dois sentidos** —
  `ApplySessionPairs` libera o par nas duas direções.

Rebaixar não tem prazo: um servidor promovido por engano precisa poder ser
desfeito a qualquer momento.

Equivalente por API (super admin, pela VPN):

```
PUT /api/v1/admin/devices/{device_id}/crm-tier
{ "enabled": true }
```

### 4. Subir o produto na máquina

O servidor do produto escuta no IP VPN da máquina. Não abra porta pública: quem
precisa alcançar já está na VPN.

## Parte 2 — Como o cliente chama

### O que o app do cliente precisa ter

**Um dado só:** o `crm_ip`, que vem da configuração do próprio produto — o IP
anotado no passo 2.

O app **não** precisa da identidade TGDesk da máquina, e não deve tentar lê-la
em disco. Quem faz o pedido é identificado pelo IP de origem do túnel, e esse
endereço é credencial: `AddPeer` autoriza cada peer com `allowed_ip /32`, então
o WireGuard descarta qualquer pacote daquele peer com origem diferente. Forjar
exigiria a chave privada do dispositivo.

Consequência prática: qualquer programa rodando naquela máquina, com permissão
de usuário comum, consegue fazer o ingresso — sem elevação e sem acesso a
`C:\ProgramData\TGDesk\identity\device.json`.

O servidor é nomeado pelo endereço, e não por `device_id`, porque o cliente é
sempre construído depois que o servidor já existe: o endereço é o que o
instalador do produto conhece e é o mesmo que o app usará para conversar
depois. Um UUID seria um segundo identificador para a mesma coisa.

### O ingresso

Na primeira abertura, antes de qualquer tentativa de falar com o servidor:

```http
POST http://10.70.0.1/api/v1/crm/join
Content-Type: application/json

{ "crm_ip": "10.70.x.y" }
```

`10.70.0.1` é o hub. Esse pedido funciona **agora**, antes de existir qualquer
liberação, porque tráfego para o hub é entrega local e nunca passa por
`FORWARD`. É por isso que o pedido cabe aqui e não caberia em nenhum outro
lugar: um pedido dirigido ao próprio servidor teria de trafegar exatamente pelo
caminho que ainda está fechado.

Resposta:

```json
{
  "service_ip": "10.70.x.y",
  "organization_id": "...",
  "network_id": "...",
  "subnetwork_id": "..."
}
```

Nesse ponto o firewall já foi reconciliado — `CRMJoin` chama
`ReconcileSessionIsolation` na hora, sem esperar a passada periódica de 30
segundos. O app pode falar com `service_ip` imediatamente, e a primeira tela que
o usuário vê é o **login do produto**. A VPN resolveu tudo antes, sem interação.

### Erros e o que fazer

| Código | Significado | Ação |
|---|---|---|
| `dispositivo_invalido` | o IP de origem não corresponde a nenhum dispositivo | o túnel subiu com endereço desconhecido; recuperar o TGDesk |
| `dispositivo_sem_acesso` | dispositivo suspenso ou ainda não vinculado | terminar a instalação/vínculo do TGDesk |
| `servico_indisponivel` | nenhum servidor tier `crm` naquele IP, ou a subrede dele é isolada | conferir o IP na configuração do app e o estado do servidor |
| `ja_vinculado_a_outro_servico` | já está em outro servidor da mesma organização | desvincular pelo admin; o ingresso não troca sozinho |
| `operacao_disponivel_somente_vpn` | o pedido não veio pelo túnel | o TGDesk não está conectado |

### Chamadas seguintes

O app pode ir direto ao `service_ip` guardado. Vale rechamar `join` quando a
conexão falhar: é idempotente e reconstrói o vínculo se ele tiver sido removido.

## O que este desenho deliberadamente não faz

- **Não filtra quem pede.** Qualquer dispositivo da VPN pode ingressar. Foi
  decisão de produto: a porta do CRM fica alcançável por todo TGDesk instalado,
  e a barreira real é o login do produto. Ele precisa estar pronto no primeiro
  dia — senha, limite de tentativas, registro de quem tentou.
- **Não dá poder ao tier.** `crm` não vê nada a mais, não administra ninguém e
  não aparece em nenhuma decisão de autorização.
- **Não muda a regra de rede.** `ReconcileSessionIsolation` e o firewall do hub
  não foram tocados.

## Referências no código

| Onde | O quê |
|---|---|
| `server/migrations/0071_dispositivo_de_servico_crm.sql` | tier `crm` e a proibição de servidor com dono |
| `server/api-core/internal/handlers/crm_service.go` | `CRMJoin`, `SetCRMTier`, `ListCRMDevices` |
| `server/api-core/internal/handlers/session_isolation.go` | derivação dos pares a partir das subredes |
| `server/api-core/internal/wg/hub.go` | `DROP` padrão e liberação por par |
| `client-rustdesk-src/flutter/lib/tgdesk/admin_crm_services_tab.dart` | aba Serviços / CRM |
