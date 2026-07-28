ALTER TABLE admin_actions DROP CONSTRAINT IF EXISTS admin_actions_tipo_check;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'suspender_tecnico', 'suspender_rede', 'suspender_dispositivo',
    'suspender_organizacao', 'reativar_tecnico', 'reativar_rede',
    'reativar_dispositivo', 'reativar_organizacao', 'vinculacao', 'wake',
    'acesso_remoto', 'delete_organizacao', 'delete_rede', 'delete_tecnico'
));
