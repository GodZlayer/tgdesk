-- O catálogo contém apenas a validade operacional dos itens. Preços existem
-- nas faixas por serviço e região, nunca no catálogo.

ALTER TABLE service_catalog DROP COLUMN IF EXISTS price_cents;
ALTER TABLE part_catalog DROP COLUMN IF EXISTS price_cents;
ALTER TABLE part_catalog DROP COLUMN IF EXISTS cost_cents;

CREATE TABLE IF NOT EXISTS regional_service_price_bounds (
    region_id UUID NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
    service_key TEXT NOT NULL REFERENCES service_catalog(key) ON UPDATE CASCADE ON DELETE CASCADE,
    min_cents BIGINT NOT NULL CHECK (min_cents >= 0),
    max_cents BIGINT NOT NULL CHECK (max_cents >= min_cents),
    active BOOLEAN NOT NULL DEFAULT true,
    source_note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(region_id, service_key)
);

INSERT INTO regional_service_price_bounds(region_id,service_key,min_cents,max_cents,source_note)
SELECT regional.region_id,
       reference.service_key,
       round(reference.min_observed_cents * regional.cost_index)::BIGINT,
       round(reference.max_observed_cents * regional.cost_index)::BIGINT,
       'Faixa inicial calculada pela referência nacional e pelo índice regional.'
FROM region_cost_living_index regional
JOIN service_market_price_references reference ON true
WHERE reference.min_observed_cents IS NOT NULL
  AND reference.max_observed_cents IS NOT NULL
ON CONFLICT(region_id,service_key) DO NOTHING;
