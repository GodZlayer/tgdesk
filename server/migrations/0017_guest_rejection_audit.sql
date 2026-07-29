ALTER TABLE admin_actions DROP CONSTRAINT IF EXISTS admin_actions_tipo_check;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'suspender_tecnico', 'suspender_rede', 'suspender_dispositivo',
    'suspender_organizacao', 'vinculacao', 'reativacao',
    'resume_tecnico', 'resume_rede', 'resume_dispositivo',
    'resume_organizacao', 'wake', 'delete_organizacao',
    'delete_rede', 'delete_tecnico', 'acesso_remoto',
    'recusar_dispositivo_guest'
));
