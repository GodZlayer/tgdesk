-- Cobertura territorial detalhada: país > estado > região > cidade > bairro > rua.
-- CEP é obrigatório em cada rua cadastrada.
CREATE TABLE IF NOT EXISTS region_coverage_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    region_id UUID NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
    country_code TEXT NOT NULL DEFAULT 'BR',
    state_code TEXT NOT NULL,
    municipality_id INTEGER NOT NULL REFERENCES brazil_municipalities(ibge_id) ON DELETE CASCADE,
    neighborhood TEXT NOT NULL,
    street TEXT NOT NULL,
    cep TEXT NOT NULL CHECK (cep ~ '^[0-9]{5}-?[0-9]{3}$'),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(region_id, municipality_id, neighborhood, street, cep)
);
CREATE INDEX IF NOT EXISTS region_coverage_addresses_region_idx
    ON region_coverage_addresses(region_id, state_code, municipality_id, neighborhood, street);
