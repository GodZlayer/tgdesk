-- Suporte a exclusão real (não só suspensão) de organizações, redes e
-- técnicos, pedida pelo Super Admin depois de ver que só existia kill-switch.
ALTER TABLE admin_actions DROP CONSTRAINT admin_actions_tipo_check;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'kill_switch_tecnico', 'kill_switch_rede', 'kill_switch_dispositivo',
    'kill_switch_organizacao', 'vinculacao', 'reativacao', 'wake',
    'delete_organizacao', 'delete_rede', 'delete_tecnico'
));

-- actor_id precisa aceitar NULL: sem isso, apagar um técnico que já tem
-- ações de auditoria (quase todo técnico ativo) falha com violação de FK.
-- ON DELETE SET NULL preserva o histórico ("alguém apagado fez isso"), só
-- perde a referência de quem foi.
ALTER TABLE admin_actions ALTER COLUMN actor_id DROP NOT NULL;
ALTER TABLE admin_actions DROP CONSTRAINT admin_actions_actor_id_fkey;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_actor_id_fkey
    FOREIGN KEY (actor_id) REFERENCES technicians(id) ON DELETE SET NULL;
