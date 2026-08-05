-- TGDesk: o tipo de chamado vira dado, e o preço também.
--
-- Até aqui o produto só sabia atender computador, e não por decisão de código:
-- não havia ramo por tipo de equipamento em lugar nenhum. O que havia era a
-- ausência de tipo. support_tickets.structured_data era um JSONB sem contrato,
-- preenchido com {"description": ...} pelo app e lido por adivinhação do outro
-- lado — o técnico procurava endereço em 'address', 'endereco', 'store_address'
-- e 'loja_endereco' até uma bater. Acrescentar impressora, rede, TV, som ou
-- celular custava combinar nomes de chave entre quem escreve e quem lê.
--
-- Aqui o tipo passa a ser linha de tabela, com os campos que ele exige também
-- em tabela. Um tipo novo é cadastro pela tela do admin, não release. E o preço
-- segue a mesma regra: percentuais por classe, taxa do admin, promoção,
-- vigência e os limites entre os quais o valor dinâmico varia são todos dado
-- editável, resolvidos por uma lógica só.

-- ---------------------------------------------------------------------------
-- 1) Catálogo de tipos de chamado.
-- ---------------------------------------------------------------------------
--
-- A chave é texto, não enum: enum exigiria migration a cada tipo novo, que é
-- exatamente o custo que este trabalho existe para eliminar.
CREATE TABLE IF NOT EXISTS ticket_types (
    key         TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    -- Nome do ícone Material, resolvido pelo app. O desenho é do cliente; o que
    -- trafega é só qual ícone, não como ele é pintado.
    icon        TEXT NOT NULL DEFAULT 'devices_other',
    -- Ordem de exibição, para o admin controlar o que aparece primeiro.
    position    INTEGER NOT NULL DEFAULT 100,
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2) Campos de cada tipo.
-- ---------------------------------------------------------------------------
--
-- É o esquema que o formulário monta e que o leitor do chamado renderiza: uma
-- tela só para todos os tipos, nenhum widget por equipamento. O mesmo esquema
-- é o que o construtor de OS vai consumir depois.
--
-- depends_on/depends_value é o campo condicional: o campo só existe no
-- formulário quando outro campo do mesmo tipo está com o valor declarado aqui.
-- 'required' vale apenas quando a condição está satisfeita — campo escondido
-- não pode bloquear o envio.
CREATE TABLE IF NOT EXISTS ticket_type_fields (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type_key      TEXT NOT NULL REFERENCES ticket_types(key) ON UPDATE CASCADE ON DELETE CASCADE,
    field_key     TEXT NOT NULL,
    label         TEXT NOT NULL,
    help          TEXT NOT NULL DEFAULT '',
    kind          TEXT NOT NULL DEFAULT 'text'
                  CHECK (kind IN ('text','multiline','number','bool','choice','date','attachment')),
    -- Só para kind='choice': lista de {"value":...,"label":...}.
    options       JSONB NOT NULL DEFAULT '[]'::jsonb,
    required      BOOLEAN NOT NULL DEFAULT false,
    depends_on    TEXT,
    depends_value TEXT,
    position      INTEGER NOT NULL DEFAULT 100,
    active        BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (type_key, field_key)
);

CREATE INDEX IF NOT EXISTS ticket_type_fields_order_idx
    ON ticket_type_fields(type_key, position, field_key);

-- ---------------------------------------------------------------------------
-- 3) O chamado passa a declarar o seu tipo.
-- ---------------------------------------------------------------------------
--
-- O parque real hoje é só computador, então o default backfilla tudo que já
-- existe sem tocar em uma linha sequer de dado.
INSERT INTO ticket_types(key,label,icon,position) VALUES
    ('computador','Computador','desktop_windows_outlined',10)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS type_key TEXT NOT NULL DEFAULT 'computador'
        REFERENCES ticket_types(key) ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS support_tickets_type_idx ON support_tickets(type_key);

-- Os campos que o computador já usava de fato, agora declarados. 'description'
-- é o único que o app enviava; 'address' é o que o técnico procurava em quatro
-- grafias diferentes e agora tem uma só.
--
-- 'address' depende de modality='onsite': endereço não significa nada em
-- atendimento remoto. E 'modality' de propósito NÃO é declarado como campo —
-- ele já é coluna do chamado, e declará-lo aqui criaria uma segunda verdade
-- sobre a mesma coisa. A condição enxerga os atributos do próprio chamado
-- junto dos campos do tipo, então depender dele funciona sem duplicá-lo.
INSERT INTO ticket_type_fields
    (type_key,field_key,label,help,kind,required,depends_on,depends_value,position) VALUES
    ('computador','description','O que está acontecendo',
     'Descreva o problema com as suas palavras.','multiline',true,NULL,NULL,10),
    ('computador','address','Endereço do atendimento',
     'Onde o técnico deve comparecer.','text',true,'modality','onsite',20)
ON CONFLICT (type_key,field_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4) Precificação: uma tabela só, resolvida por especificidade.
-- ---------------------------------------------------------------------------
--
-- Tudo que decide dinheiro mora aqui: o percentual que cada classe recebe do
-- chamado, a taxa geral do admin, a promoção pontual e os limites entre os
-- quais o valor dinâmico varia. Separar isso em quatro tabelas daria quatro
-- resoluções de escopo iguais para manter; uma tabela com um 'kind' dá uma.
--
-- Escopo: toda coluna de escopo nula significa "vale para tudo". Preenchida,
-- restringe. A regra que vence é a mais específica que casa com o chamado —
-- 'specificity' é gerada da própria linha para que a escolha seja um ORDER BY,
-- e não código que pode divergir entre chamadas.
--
-- Os pesos são potências de dois em ordem crescente de precisão: um preço para
-- um técnico específico manda em um preço para a subrede dele, que manda em um
-- preço para a rede, e assim por diante até a regra global.
CREATE TABLE IF NOT EXISTS pricing_rules (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind            TEXT NOT NULL CHECK (kind IN ('share','fee','promo','bounds')),
    -- share: quanto desta classe sai do valor do chamado.
    -- fee:   taxa geral retirada pelo admin antes da divisão.
    -- promo: desconto pontual, único por escopo enquanto estiver ativo.
    -- bounds: piso e teto entre os quais o valor dinâmico pode variar.

    -- Só para 'share': de qual classe é o percentual.
    role            TEXT CHECK (role IN ('super_admin','supervisor','freelancer','cliente','cliente_avulso')),

    -- Escopo, do mais amplo ao mais específico.
    ticket_type_key TEXT REFERENCES ticket_types(key) ON UPDATE CASCADE ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    network_id      UUID REFERENCES networks(id) ON DELETE CASCADE,
    subnetwork_id   UUID REFERENCES subnetworks(id) ON DELETE CASCADE,
    technician_id   UUID REFERENCES technicians(id) ON DELETE CASCADE,
    -- Avulso é recorte, não organização: true vale só para chamado avulso,
    -- false só para empresarial, nulo para os dois.
    standalone      BOOLEAN,

    percent         NUMERIC(6,3) CHECK (percent IS NULL OR percent BETWEEN 0 AND 100),
    amount_cents    BIGINT       CHECK (amount_cents IS NULL OR amount_cents >= 0),
    min_cents       BIGINT       CHECK (min_cents IS NULL OR min_cents >= 0),
    max_cents       BIGINT       CHECK (max_cents IS NULL OR max_cents >= 0),

    -- Vigência: a taxa também vale por tempo. Nulo dos dois lados é permanente.
    valid_from      TIMESTAMPTZ,
    valid_until     TIMESTAMPTZ,

    note            TEXT NOT NULL DEFAULT '',
    active          BOOLEAN NOT NULL DEFAULT true,
    created_by      UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    specificity     INTEGER GENERATED ALWAYS AS (
        (CASE WHEN standalone      IS NOT NULL THEN 1  ELSE 0 END) +
        (CASE WHEN ticket_type_key IS NOT NULL THEN 2  ELSE 0 END) +
        (CASE WHEN organization_id IS NOT NULL THEN 4  ELSE 0 END) +
        (CASE WHEN network_id      IS NOT NULL THEN 8  ELSE 0 END) +
        (CASE WHEN subnetwork_id   IS NOT NULL THEN 16 ELSE 0 END) +
        (CASE WHEN technician_id   IS NOT NULL THEN 32 ELSE 0 END)
    ) STORED,

    -- Cada kind exige o que de fato usa: percentual sem número não decide nada,
    -- e limite sem piso nem teto é linha vazia ocupando a resolução.
    CONSTRAINT pricing_rules_share_precisa_role_e_percent
        CHECK (kind <> 'share' OR (role IS NOT NULL AND percent IS NOT NULL)),
    CONSTRAINT pricing_rules_fee_precisa_valor
        CHECK (kind <> 'fee' OR (percent IS NOT NULL OR amount_cents IS NOT NULL)),
    CONSTRAINT pricing_rules_promo_precisa_valor
        CHECK (kind <> 'promo' OR (percent IS NOT NULL OR amount_cents IS NOT NULL)),
    CONSTRAINT pricing_rules_bounds_precisa_limite
        CHECK (kind <> 'bounds' OR (min_cents IS NOT NULL OR max_cents IS NOT NULL)),
    CONSTRAINT pricing_rules_limites_coerentes
        CHECK (min_cents IS NULL OR max_cents IS NULL OR min_cents <= max_cents),
    CONSTRAINT pricing_rules_vigencia_coerente
        CHECK (valid_from IS NULL OR valid_until IS NULL OR valid_from < valid_until)
);

CREATE INDEX IF NOT EXISTS pricing_rules_resolve_idx
    ON pricing_rules(kind, active, specificity DESC);

-- Promoção é única por especificação: duas promoções ativas para o mesmo
-- recorte não teriam desempate que não fosse arbitrário. As demais regras não
-- têm essa restrição porque 'share' já se distingue por classe, e 'fee' e
-- 'bounds' desempatam pela especificidade.
CREATE UNIQUE INDEX IF NOT EXISTS pricing_rules_promo_unica_por_escopo
    ON pricing_rules(
        coalesce(ticket_type_key,''),
        coalesce(organization_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(network_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(subnetwork_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(technician_id,'00000000-0000-0000-0000-000000000000'::uuid),
        -- Em texto, e não coalesce(standalone,false): "vale para os dois" é um
        -- escopo diferente de "vale só para empresarial", e em booleano os dois
        -- colapsariam na mesma chave.
        coalesce(standalone::text,''))
    WHERE kind='promo' AND active;
