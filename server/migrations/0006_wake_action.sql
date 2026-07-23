-- Módulo E — permite registrar o disparo de Wake-on-LAN na auditoria.
ALTER TABLE admin_actions DROP CONSTRAINT admin_actions_tipo_check;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'kill_switch_tecnico', 'kill_switch_rede', 'kill_switch_dispositivo',
    'kill_switch_organizacao', 'vinculacao', 'reativacao', 'wake'
));
