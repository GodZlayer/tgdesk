-- Substitui definitivamente a terminologia antiga na auditoria preservando
-- todos os registros históricos.
ALTER TABLE admin_actions DROP CONSTRAINT IF EXISTS admin_actions_tipo_check;

UPDATE admin_actions SET tipo = CASE tipo
    WHEN 'kill_switch_tecnico' THEN 'suspender_tecnico'
    WHEN 'kill_switch_rede' THEN 'suspender_rede'
    WHEN 'kill_switch_dispositivo' THEN 'suspender_dispositivo'
    WHEN 'kill_switch_organizacao' THEN 'suspender_organizacao'
    WHEN 'reativacao' THEN 'reativar_dispositivo'
    ELSE tipo
END;

ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'suspender_tecnico', 'suspender_rede', 'suspender_dispositivo',
    'suspender_organizacao', 'reativar_tecnico', 'reativar_rede',
    'reativar_dispositivo', 'reativar_organizacao', 'vinculacao', 'wake',
    'delete_organizacao', 'delete_rede', 'delete_tecnico'
));
