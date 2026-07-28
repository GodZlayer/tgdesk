-- TGDesk 0.3.0: a chave de controle só é consumida pelo instalador.
-- O papel é copiado para a credencial para permitir a unicidade do Admin.
ALTER TABLE technician_machine_credentials
    ADD COLUMN control_role TEXT NOT NULL DEFAULT 'tecnico'
        CHECK (control_role IN ('super_admin', 'tecnico'));

CREATE UNIQUE INDEX uq_single_active_tgdesk_admin
    ON technician_machine_credentials (control_role)
    WHERE control_role = 'super_admin' AND status = 'ativo';

ALTER TABLE technician_machine_credentials
    ADD COLUMN machine_fingerprint TEXT;

UPDATE technician_machine_credentials
SET machine_fingerprint = machine_id
WHERE machine_fingerprint IS NULL;

ALTER TABLE technician_machine_credentials
    ALTER COLUMN machine_fingerprint SET NOT NULL;

