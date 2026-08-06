-- TGDesk: a região vira dado, porque o preço dinâmico depende dela.
--
-- O preço por demanda precisa de três contagens, e as três são por região:
-- quantos chamados estão esperando, quantos técnicos existem para atendê-los e
-- quantos clientes (empresariais e avulsos) o lugar tem. Sem região, o recorte
-- disponível era a rede — que é fronteira administrativa, não geográfica: duas
-- redes da mesma empresa podem estar em cidades diferentes, e dois avulsos da
-- mesma rua não compartilham rede nenhuma.
--
-- Geolocalização já existia no produto, mas só no despacho: dispatchToFreelancers
-- ordena a fila por distância usando freelancer_profiles.latitude/longitude e
-- service_orders.scheduled_location. O que não existia era o agrupamento — o
-- lugar como coisa contável.

-- ---------------------------------------------------------------------------
-- 1) O catálogo de regiões.
-- ---------------------------------------------------------------------------
--
-- Região é cadastro do admin, como o tipo de chamado e o catálogo de peças:
-- abrir operação numa cidade nova é uma linha, não um release.
--
-- Centro e raio, e não polígono: o produto não tem mapa nem biblioteca de
-- geometria, e um círculo responde à única pergunta que se faz aqui — "este
-- ponto pertence a esta região?". Trocar por PostGIS depois não muda quem
-- pergunta, só como se responde.
CREATE TABLE IF NOT EXISTS regions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key        TEXT NOT NULL UNIQUE,
    label      TEXT NOT NULL,
    center_lat DOUBLE PRECISION,
    center_lon DOUBLE PRECISION,
    radius_km  DOUBLE PRECISION NOT NULL DEFAULT 50 CHECK (radius_km > 0),
    -- Região sem centro é a região "por atribuição": vale para quem foi posto
    -- nela à mão, e nunca é escolhida por coordenada. Serve para o caso em que
    -- o admin quer agrupar por contrato, e não por mapa.
    position   INTEGER NOT NULL DEFAULT 100,
    active     BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT regions_centro_completo
        CHECK ((center_lat IS NULL) = (center_lon IS NULL))
);

CREATE INDEX IF NOT EXISTS regions_pick_idx ON regions(active, position, label);

-- ---------------------------------------------------------------------------
-- 2) Quem pertence a uma região.
-- ---------------------------------------------------------------------------
--
-- Cada uma das três contagens que a fórmula usa sai de uma destas colunas:
--
--   técnicos na região   -> freelancer_profiles.region_id
--   clientes na região   -> devices.region_id        (empresarial e avulso)
--   chamados na região   -> support_tickets.region_id
--
-- ON DELETE SET NULL em todas: apagar uma região não pode apagar técnico,
-- dispositivo nem chamado. O que acontece é o que deve acontecer — eles voltam
-- a não ter região, e o preço volta ao global.
ALTER TABLE freelancer_profiles
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES regions(id) ON DELETE SET NULL;

ALTER TABLE organizations
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES regions(id) ON DELETE SET NULL;

ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES regions(id) ON DELETE SET NULL;

-- No chamado a região é congelada na abertura, e não lida da organização na
-- hora de cobrar. São coisas diferentes: a empresa pode mudar de região
-- amanhã, e o que precificou este chamado foi onde ele nasceu.
ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES regions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS freelancer_profiles_region_idx
    ON freelancer_profiles(region_id) WHERE region_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS devices_region_idx
    ON devices(region_id) WHERE region_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS support_tickets_region_idx
    ON support_tickets(region_id, status);

-- ---------------------------------------------------------------------------
-- 3) A precificação passa a enxergar região.
-- ---------------------------------------------------------------------------
--
-- Entra na resolução por especificidade como as demais colunas de escopo. O
-- peso fica entre a organização e a rede: uma regra para a cidade inteira é
-- mais específica que uma para a empresa toda, e menos que uma para uma rede
-- dentro dela.
--
-- A coluna 'specificity' é gerada, então mudá-la é recriar: por isso o DROP.
ALTER TABLE pricing_rules
    ADD COLUMN IF NOT EXISTS region_id UUID REFERENCES regions(id) ON DELETE CASCADE;

ALTER TABLE pricing_rules DROP COLUMN IF EXISTS specificity;

ALTER TABLE pricing_rules
    ADD COLUMN specificity INTEGER GENERATED ALWAYS AS (
        (CASE WHEN standalone      IS NOT NULL THEN 1  ELSE 0 END) +
        (CASE WHEN ticket_type_key IS NOT NULL THEN 2  ELSE 0 END) +
        (CASE WHEN organization_id IS NOT NULL THEN 4  ELSE 0 END) +
        (CASE WHEN region_id       IS NOT NULL THEN 8  ELSE 0 END) +
        (CASE WHEN network_id      IS NOT NULL THEN 16 ELSE 0 END) +
        (CASE WHEN subnetwork_id   IS NOT NULL THEN 32 ELSE 0 END) +
        (CASE WHEN technician_id   IS NOT NULL THEN 64 ELSE 0 END)
    ) STORED;

DROP INDEX IF EXISTS pricing_rules_resolve_idx;
CREATE INDEX pricing_rules_resolve_idx
    ON pricing_rules(kind, active, specificity DESC);

-- A promoção continua única por escopo, agora com a região dentro dele.
DROP INDEX IF EXISTS pricing_rules_promo_unica_por_escopo;
CREATE UNIQUE INDEX pricing_rules_promo_unica_por_escopo
    ON pricing_rules(
        coalesce(ticket_type_key,''),
        coalesce(organization_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(region_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(network_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(subnetwork_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(technician_id,'00000000-0000-0000-0000-000000000000'::uuid),
        coalesce(standalone::text,''))
    WHERE kind='promo' AND active;
