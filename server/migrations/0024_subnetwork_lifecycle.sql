ALTER TABLE subnetworks
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT;

CREATE INDEX IF NOT EXISTS idx_devices_subnetwork
    ON devices(subnetwork_id);

ALTER TABLE devices
    DROP CONSTRAINT IF EXISTS devices_suspension_scope_check;
ALTER TABLE devices
    ADD CONSTRAINT devices_suspension_scope_check
    CHECK (suspension_scope IN (
        'device', 'subnetwork', 'network', 'organization', 'technician'
    ));

ALTER TABLE admin_actions
    DROP CONSTRAINT IF EXISTS admin_actions_tipo_check;
ALTER TABLE admin_actions
    ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
        'suspender_tecnico', 'suspender_rede', 'suspender_subrede',
        'suspender_dispositivo', 'suspender_organizacao',
        'reativar_tecnico', 'reativar_rede', 'reativar_subrede',
        'reativar_dispositivo', 'reativar_organizacao',
        'vinculacao', 'wake', 'acesso_remoto',
        'delete_organizacao', 'delete_rede', 'delete_tecnico',
        'recusar_dispositivo_guest', 'renomear_organizacao',
        'renomear_rede', 'excluir_subrede'
    ));
