-- TGDesk: contratos que faltavam para o editor único obedecer ao modelo.
--
-- 1) Peça e consumível são catálogo sem marca/preço final. A diferença é de
--    evidência e unidade: consumível pode ser metro/ml/g; peça costuma ser un.
-- 2) Precificação é percentual e regra; inclui os papéis comerciais reais da OS.
-- 3) Pagamento inicial é configuração do servidor, não cálculo do cliente.
-- 4) A região comercial pode ser vinculada a recortes oficiais do IBGE.

ALTER TABLE part_catalog
    ADD COLUMN IF NOT EXISTS item_kind TEXT NOT NULL DEFAULT 'part',
    ADD COLUMN IF NOT EXISTS requires_invoice_photo BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE part_catalog DROP CONSTRAINT IF EXISTS part_catalog_item_kind_check;
ALTER TABLE part_catalog
    ADD CONSTRAINT part_catalog_item_kind_check
    CHECK (item_kind IN ('part','consumable'));

UPDATE part_catalog
SET item_kind='consumable'
WHERE unit IN ('m','metro','metros','ml','g','kg','l')
   OR sku ILIKE '%CABO-UTP%'
   OR sku ILIKE '%PASTA%'
   OR sku ILIKE '%ALCOOL%';

ALTER TABLE pricing_rules DROP CONSTRAINT IF EXISTS pricing_rules_role_check;
ALTER TABLE pricing_rules
    ADD CONSTRAINT pricing_rules_role_check
    CHECK (role IS NULL OR role IN (
        'technician',
        'supervisor',
        'tgdesk',
        'referrer_supervisor',
        'super_admin',
        'freelancer',
        'cliente',
        'cliente_avulso'
    ));

CREATE TABLE IF NOT EXISTS product_payment_rules (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
    upfront_percent NUMERIC(6,3) NOT NULL DEFAULT 100
        CHECK (upfront_percent BETWEEN 0 AND 100),
    upfront_basis TEXT NOT NULL DEFAULT 'services_parts_consumables'
        CHECK (upfront_basis IN ('services_parts_consumables','services_only')),
    service_minimum_margin_percent NUMERIC(6,3) NOT NULL DEFAULT 0
        CHECK (service_minimum_margin_percent BETWEEN 0 AND 100),
    note TEXT NOT NULL DEFAULT '',
    updated_by UUID REFERENCES technicians(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO product_payment_rules(singleton)
VALUES (true)
ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE IF NOT EXISTS region_municipalities (
    region_id UUID NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
    municipality_id INTEGER NOT NULL REFERENCES brazil_municipalities(ibge_id) ON DELETE CASCADE,
    relation_kind TEXT NOT NULL DEFAULT 'commercial'
        CHECK (relation_kind IN ('commercial','metropolitan','immediate','intermediate','capital')),
    PRIMARY KEY (region_id, municipality_id, relation_kind)
);

CREATE INDEX IF NOT EXISTS region_municipalities_municipality_idx
    ON region_municipalities(municipality_id);
