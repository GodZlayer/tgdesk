-- TGDesk 0.3.0: provisionamento Tech por arquivo-chave de uso único.
-- O segredo original nunca é persistido; somente SHA-256. O consumo é feito
-- com SELECT ... FOR UPDATE no api-core para impedir duas ativações.
CREATE TABLE technician_enrollment_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    secret_hash BYTEA NOT NULL,
    expires_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    consumed_machine_id TEXT,
    created_by UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_technician_enrollment_keys_technician
    ON technician_enrollment_keys (technician_id, created_at DESC);

CREATE TABLE technician_machine_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    machine_id TEXT NOT NULL,
    credential_hash BYTEA NOT NULL,
    status TEXT NOT NULL DEFAULT 'ativo'
        CHECK (status IN ('ativo', 'revogado')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at TIMESTAMPTZ,
    UNIQUE (technician_id, machine_id)
);

CREATE INDEX idx_technician_machine_credentials_lookup
    ON technician_machine_credentials (id, status);
