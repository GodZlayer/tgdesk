-- TGDesk: a OS deixa de ser texto livre e vira orçamento montado de catálogo.
--
-- Até aqui "converter em OS" gravava dois campos soltos: 'items' e 'values',
-- ambos JSONB sem contrato, preenchidos com o que o técnico digitasse. Não
-- havia peça, não havia serviço com preço, e o valor do chamado não era
-- calculado em lugar nenhum — resolvePricing existia e não era chamado por
-- ninguém.
--
-- Aqui a OS passa a ser feita de linhas que apontam para um catálogo, com o
-- valor congelado no momento em que a linha foi criada. Congelar importa:
-- mudar o preço de uma peça amanhã não pode reescrever o que já foi orçado
-- ontem. O catálogo é cadastro pela tela do admin, seguindo o mesmo princípio
-- dos tipos de chamado e da precificação — tipo novo, peça nova e serviço novo
-- são linha de tabela, não release.

-- ---------------------------------------------------------------------------
-- 1) Catálogo de peças.
-- ---------------------------------------------------------------------------
--
-- 'cost_cents' é o que a peça custa para quem atende; 'price_cents' é o que
-- entra no orçamento. Os dois separados porque a margem é o que a regra de
-- precificação divide entre as classes, e sem o custo não há margem para
-- dividir.
CREATE TABLE IF NOT EXISTS part_catalog (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku          TEXT NOT NULL UNIQUE,
    label        TEXT NOT NULL,
    description  TEXT NOT NULL DEFAULT '',
    unit         TEXT NOT NULL DEFAULT 'un',
    cost_cents   BIGINT NOT NULL DEFAULT 0 CHECK (cost_cents  >= 0),
    price_cents  BIGINT NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
    -- Peça pode valer só para um tipo de chamado (um toner não entra numa OS
    -- de rede). Nulo vale para todos.
    ticket_type_key TEXT REFERENCES ticket_types(key) ON UPDATE CASCADE ON DELETE SET NULL,
    active       BOOLEAN NOT NULL DEFAULT true,
    position     INTEGER NOT NULL DEFAULT 100,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS part_catalog_pick_idx
    ON part_catalog(active, ticket_type_key, position, label);

-- ---------------------------------------------------------------------------
-- 2) Catálogo de serviços.
-- ---------------------------------------------------------------------------
--
-- É o "valor de serviço pré-estabelecido pelo servidor": o técnico escolhe da
-- lista em vez de arbitrar o preço. 'manual_url' é o PDF de instrução do
-- serviço — o que o técnico consulta antes de executar.
CREATE TABLE IF NOT EXISTS service_catalog (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key          TEXT NOT NULL UNIQUE,
    label        TEXT NOT NULL,
    description  TEXT NOT NULL DEFAULT '',
    price_cents  BIGINT NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
    -- Duração estimada, em minutos. Alimenta o agendamento e, adiante, a
    -- conta de disponibilidade que o preço dinâmico usa.
    duration_min INTEGER NOT NULL DEFAULT 60 CHECK (duration_min > 0),
    ticket_type_key TEXT REFERENCES ticket_types(key) ON UPDATE CASCADE ON DELETE SET NULL,
    -- 'virtual', 'onsite' ou nulo para os dois.
    os_type      TEXT CHECK (os_type IN ('virtual','onsite')),
    manual_url   TEXT NOT NULL DEFAULT '',
    active       BOOLEAN NOT NULL DEFAULT true,
    position     INTEGER NOT NULL DEFAULT 100,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS service_catalog_pick_idx
    ON service_catalog(active, ticket_type_key, position, label);

-- ---------------------------------------------------------------------------
-- 3) As linhas da OS.
-- ---------------------------------------------------------------------------
--
-- Uma linha é peça OU serviço, nunca os dois. Nenhum dos dois é permitido e
-- significa linha avulsa — o item que não estava no catálogo na hora do
-- atendimento; o rótulo e o valor vêm digitados e a linha vale por si.
--
-- As referências são ON DELETE SET NULL de propósito: apagar uma peça
-- do catálogo não pode apagar o histórico de quem já a comprou, e o rótulo e o
-- preço ficam guardados na própria linha justamente para que ela continue
-- legível depois que a origem sumir.
CREATE TABLE IF NOT EXISTS service_order_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
    part_id       UUID REFERENCES part_catalog(id) ON DELETE SET NULL,
    service_id    UUID REFERENCES service_catalog(id) ON DELETE SET NULL,
    -- Congelados na criação da linha.
    label         TEXT NOT NULL,
    unit_cents    BIGINT NOT NULL CHECK (unit_cents >= 0),
    cost_cents    BIGINT NOT NULL DEFAULT 0 CHECK (cost_cents >= 0),
    quantity      NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    note          TEXT NOT NULL DEFAULT '',
    position      INTEGER NOT NULL DEFAULT 100,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    total_cents   BIGINT GENERATED ALWAYS AS
                  (round(unit_cents * quantity)::bigint) STORED,

    CONSTRAINT service_order_items_peca_ou_servico
        CHECK ((part_id IS NULL) <> (service_id IS NULL)
               OR (part_id IS NULL AND service_id IS NULL))
);

CREATE INDEX IF NOT EXISTS service_order_items_os_idx
    ON service_order_items(service_order_id, position, created_at);

-- ---------------------------------------------------------------------------
-- 4) A OS ganha instrução e orçamento resolvido.
-- ---------------------------------------------------------------------------
--
-- 'instructions' é a instrução do chamado: o que o técnico deve fazer, escrito
-- por quem despachou. Não se confunde com 'scope_notes', que é o escopo
-- acordado com o cliente.
--
-- 'quote' guarda o resultado de resolvePricing junto do multiplicador de
-- demanda e do valor final, no momento em que o orçamento foi fechado. É
-- registro, não cache: recalcular amanhã daria outro número, e o que valeu é o
-- que estava na tela quando as partes concordaram.
ALTER TABLE service_orders
    ADD COLUMN IF NOT EXISTS instructions TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS manual_url   TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS quote        JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS total_cents  BIGINT NOT NULL DEFAULT 0
        CHECK (total_cents >= 0);

-- O tipo de chamado também pode ter manual próprio, para o técnico consultar
-- antes mesmo de existir OS.
ALTER TABLE ticket_types
    ADD COLUMN IF NOT EXISTS manual_url TEXT NOT NULL DEFAULT '';
