-- TGDesk v1.1.0: modelo de papeis definitivo.
--
-- Conjunto FINAL e EXATO de roles (5):
--   super_admin    -> o Admin. Gerente geral de absolutamente tudo.
--   supervisor     -> admin da propria org + redes + subredes (RENAME do antigo papel operador).
--   cliente        -> vinculado a um supervisor; sem uso operacional, existe para ser atendido.
--   freelancer     -> atende chamados/servicos avulsos. Sem org propria, sem rede propria.
--   cliente_avulso -> nao participa de rede nem de org. So abre chamado.
--
-- Hierarquia base (cascata): super_admin > supervisor > cliente
-- Avulsos (fora da hierarquia, respondem so ao super_admin): freelancer, cliente_avulso

-- Step 1: remove o CHECK antigo de technicians.role
ALTER TABLE technicians DROP CONSTRAINT IF EXISTS technicians_role_check;

-- Step 2: backfill - qualquer papel legado (fora do conjunto final) vira 'supervisor'.
--         Converte 100% dos operadores antigos, sem condicao.
UPDATE technicians
SET role = 'supervisor'
WHERE role NOT IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso');

-- Step 3: aplica o CHECK definitivo (5 papeis, nem mais nem menos)
ALTER TABLE technicians ADD CONSTRAINT technicians_role_check
    CHECK (role IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso'));

-- Step 4: vinculo ao supervisor.
--   cliente    -> preso a um supervisor (supervisor_id obrigatorio)
--   freelancer -> VINCULADO a um supervisor, dentro da organizacao desse supervisor
--                 (supervisor_id obrigatorio; coerente com freelancer_profiles.supervisor_id NOT NULL).
--                 Atencao: o vinculo e de despacho/organizacao, NAO de gestao hierarquica.
--                 O supervisor continua SEM autoridade administrativa sobre o freelancer (ver 0029).
--   super_admin / supervisor -> topo da hierarquia, nunca tem supervisor (NULL)
--   cliente_avulso           -> nao participa de org nem de rede, nunca tem supervisor (NULL)
ALTER TABLE technicians
    ADD COLUMN IF NOT EXISTS supervisor_id UUID
    REFERENCES technicians(id) ON DELETE CASCADE;

ALTER TABLE technicians DROP CONSTRAINT IF EXISTS technicians_supervisor_link_check;
-- NOT VALID: a coluna acabou de ser criada (todas as linhas com NULL) e podem existir
-- clientes/freelancers legados ainda sem vinculo. A constraint passa a valer para toda
-- escrita nova; o backfill/validacao das linhas legadas e reportado em 0030 (Step 6).
-- Para validar apos o backfill:
--   ALTER TABLE technicians VALIDATE CONSTRAINT technicians_supervisor_link_check;
ALTER TABLE technicians ADD CONSTRAINT technicians_supervisor_link_check
    CHECK (
        (role IN ('super_admin', 'supervisor', 'cliente_avulso') AND supervisor_id IS NULL)
        OR (role IN ('cliente', 'freelancer') AND supervisor_id IS NOT NULL)
    ) NOT VALID;

-- Step 5: credenciais de maquina seguem o mesmo conjunto de papeis
UPDATE technician_machine_credentials
SET control_role = 'supervisor'
WHERE control_role NOT IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso');

ALTER TABLE technician_machine_credentials
    ALTER COLUMN control_role SET DEFAULT 'supervisor';

ALTER TABLE technician_machine_credentials
    DROP CONSTRAINT IF EXISTS technician_machine_credentials_control_role_check;

ALTER TABLE technician_machine_credentials
    ADD CONSTRAINT technician_machine_credentials_control_role_check
    CHECK (control_role IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso'));

-- Step 5b: devices.role e um namespace DIFERENTE de technicians.role.
--          Indica a FUNCAO DA MAQUINA, nao o papel do usuario:
--            'host'       -> maquina atendida
--            'supervisor' -> maquina de controle do supervisor (RENAME do antigo 'tecnico')
--          O CHECK original vem de 0001_init.sql (migration historica, nao editavel).
UPDATE devices
SET role = 'supervisor'
WHERE role NOT IN ('host', 'supervisor');

ALTER TABLE devices ALTER COLUMN role SET DEFAULT 'host';

ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_role_check;

ALTER TABLE devices ADD CONSTRAINT devices_role_check
    CHECK (role IN ('host', 'supervisor'));

-- Step 5c: admin_actions.tipo - o CHECK vigente (0024) ainda usa os nomes de acao
--          legados '*_tecnico'. O Go agora grava 'suspender_supervisor',
--          'reativar_supervisor' e 'delete_supervisor' (handlers/admin.go, handlers/deletes.go),
--          o que viola o CHECK em runtime. RENAME consistente com o Step 2.
UPDATE admin_actions SET tipo = 'suspender_supervisor' WHERE tipo = 'suspender_tecnico';
UPDATE admin_actions SET tipo = 'reativar_supervisor'  WHERE tipo = 'reativar_tecnico';
UPDATE admin_actions SET tipo = 'delete_supervisor'    WHERE tipo = 'delete_tecnico';

ALTER TABLE admin_actions DROP CONSTRAINT IF EXISTS admin_actions_tipo_check;
ALTER TABLE admin_actions ADD CONSTRAINT admin_actions_tipo_check CHECK (tipo IN (
    'suspender_supervisor', 'suspender_rede', 'suspender_subrede',
    'suspender_dispositivo', 'suspender_organizacao',
    'reativar_supervisor', 'reativar_rede', 'reativar_subrede',
    'reativar_dispositivo', 'reativar_organizacao',
    'vinculacao', 'wake', 'acesso_remoto',
    'delete_organizacao', 'delete_rede', 'delete_supervisor',
    'recusar_dispositivo_guest', 'renomear_organizacao',
    'renomear_rede', 'excluir_subrede'
));

-- Step 6: indices (FKs e role)
CREATE INDEX IF NOT EXISTS idx_technicians_role ON technicians(role);
CREATE INDEX IF NOT EXISTS idx_technicians_supervisor_id ON technicians(supervisor_id);
CREATE INDEX IF NOT EXISTS idx_technicians_role_status ON technicians(role, status);
CREATE INDEX IF NOT EXISTS idx_tmc_technician_id ON technician_machine_credentials(technician_id);
CREATE INDEX IF NOT EXISTS idx_tmc_control_role ON technician_machine_credentials(control_role);

-- Step 7: relatorio de auditoria
DO $$
DECLARE
    super_admin_count INT;
    supervisor_count INT;
    cliente_count INT;
    freelancer_count INT;
    cliente_avulso_count INT;
BEGIN
    SELECT COUNT(*) INTO super_admin_count    FROM technicians WHERE role = 'super_admin';
    SELECT COUNT(*) INTO supervisor_count     FROM technicians WHERE role = 'supervisor';
    SELECT COUNT(*) INTO cliente_count        FROM technicians WHERE role = 'cliente';
    SELECT COUNT(*) INTO freelancer_count     FROM technicians WHERE role = 'freelancer';
    SELECT COUNT(*) INTO cliente_avulso_count FROM technicians WHERE role = 'cliente_avulso';

    RAISE NOTICE 'Roles apos 0026: super_admin=%, supervisor=%, cliente=%, freelancer=%, cliente_avulso=%',
        super_admin_count, supervisor_count, cliente_count, freelancer_count, cliente_avulso_count;
END $$;
