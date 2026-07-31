-- TGDesk v1.1.0: consolidacao do modelo de papeis, cascata de suspensao e validacao de integridade.
--
-- Papeis (5): super_admin, supervisor, cliente, freelancer, cliente_avulso.
-- Cascata de suspensao:
--   suspender supervisor -> org dele -> redes -> subredes -> dispositivos
--   suspender rede       -> subredes -> dispositivos

-- Step 1: log de auditoria da migracao
CREATE TABLE IF NOT EXISTS migration_audit_0030 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    affected_count INT,
    details JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_migration_audit_0030_action
    ON migration_audit_0030(action, created_at);

-- Step 2: garantir suspension_scope coerente com a cascata em todos os niveis
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_suspension_scope_check;
ALTER TABLE devices ADD CONSTRAINT devices_suspension_scope_check
    CHECK (suspension_scope IN ('device', 'subnetwork', 'network', 'organization', 'technician'));

ALTER TABLE subnetworks
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT;
ALTER TABLE subnetworks DROP CONSTRAINT IF EXISTS subnetworks_suspension_scope_check;
ALTER TABLE subnetworks ADD CONSTRAINT subnetworks_suspension_scope_check
    CHECK (suspension_scope IN ('subnetwork', 'network', 'organization', 'technician'));

ALTER TABLE networks DROP CONSTRAINT IF EXISTS networks_suspension_scope_check;
ALTER TABLE networks ADD CONSTRAINT networks_suspension_scope_check
    CHECK (suspension_scope IN ('network', 'organization', 'technician'));

ALTER TABLE organizations
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT;
ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organizations_suspension_scope_check;
ALTER TABLE organizations ADD CONSTRAINT organizations_suspension_scope_check
    CHECK (suspension_scope IN ('organization', 'technician'));

-- Backfill do escopo em registros ja suspensos sem escopo declarado
UPDATE organizations SET suspension_scope = 'organization'
    WHERE status = 'suspensa' AND suspension_scope IS NULL;
UPDATE networks      SET suspension_scope = 'network'
    WHERE status = 'suspensa' AND suspension_scope IS NULL;
UPDATE subnetworks   SET suspension_scope = 'subnetwork'
    WHERE status = 'suspensa' AND suspension_scope IS NULL;
UPDATE devices       SET suspension_scope = 'device'
    WHERE state  = 'suspenso' AND suspension_scope IS NULL;

-- Step 3: indices de apoio a cascata
CREATE INDEX IF NOT EXISTS idx_organizations_owner_technician
    ON organizations(owner_technician_id);
CREATE INDEX IF NOT EXISTS idx_networks_organization
    ON networks(organization_id);
CREATE INDEX IF NOT EXISTS idx_networks_created_by_technician
    ON networks(created_by_technician_id);
CREATE INDEX IF NOT EXISTS idx_subnetworks_network_id
    ON subnetworks(network_id);
CREATE INDEX IF NOT EXISTS idx_subnetworks_created_by_technician
    ON subnetworks(created_by_technician_id);
CREATE INDEX IF NOT EXISTS idx_devices_network_id
    ON devices(network_id);
CREATE INDEX IF NOT EXISTS idx_devices_subnetwork_id
    ON devices(subnetwork_id);
CREATE INDEX IF NOT EXISTS idx_devices_control_technician
    ON devices(control_technician_id);

-- Step 4: limpeza de vinculos orfaos em technician_assignments
DO $$
DECLARE
    orphaned INT;
BEGIN
    SELECT COUNT(*) INTO orphaned
    FROM technician_assignments ta
    WHERE NOT EXISTS (SELECT 1 FROM technicians t WHERE t.id = ta.technician_id)
       OR (ta.organization_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.id = ta.organization_id))
       OR (ta.network_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM networks n WHERE n.id = ta.network_id))
       OR (ta.subnetwork_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM subnetworks s WHERE s.id = ta.subnetwork_id))
       OR (ta.device_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = ta.device_id));

    IF orphaned > 0 THEN
        DELETE FROM technician_assignments ta
        WHERE NOT EXISTS (SELECT 1 FROM technicians t WHERE t.id = ta.technician_id)
           OR (ta.organization_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.id = ta.organization_id))
           OR (ta.network_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM networks n WHERE n.id = ta.network_id))
           OR (ta.subnetwork_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM subnetworks s WHERE s.id = ta.subnetwork_id))
           OR (ta.device_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM devices d WHERE d.id = ta.device_id));

        INSERT INTO migration_audit_0030 (action, affected_count, details)
        VALUES ('cleaned_orphaned_assignments', orphaned,
                jsonb_build_object('action', 'deleted_orphaned_records'));
        RAISE WARNING 'Removidos % vinculos orfaos em technician_assignments', orphaned;
    ELSE
        RAISE NOTICE 'technician_assignments: nenhum vinculo orfao';
    END IF;
END $$;

-- Step 5: papeis avulsos nao podem ter org/rede/subrede proprias
--         (freelancer e cliente_avulso ficam fora da hierarquia de org)
DO $$
DECLARE
    bad_owned INT;
BEGIN
    SELECT COUNT(*) INTO bad_owned
    FROM organizations o
    JOIN technicians t ON t.id = o.owner_technician_id
    WHERE t.role IN ('freelancer', 'cliente_avulso', 'cliente');

    IF bad_owned > 0 THEN
        INSERT INTO migration_audit_0030 (action, affected_count, details)
        VALUES ('orgs_owned_by_non_supervisor', bad_owned,
                jsonb_build_object('severity', 'warning',
                                   'rule', 'apenas super_admin e supervisor possuem organizacao'));
        RAISE WARNING 'Encontradas % organizacoes com dono que nao e supervisor/super_admin', bad_owned;
    ELSE
        RAISE NOTICE 'Propriedade de organizacoes coerente com o modelo de papeis';
    END IF;
END $$;

-- Step 6: cliente e freelancer precisam estar vinculados a um supervisor
--   cliente    -> preso ao supervisor que o atende
--   freelancer -> vinculado ao supervisor cuja organizacao o despacha
--                 (vinculo de despacho/organizacao, nao de gestao hierarquica)
DO $$
DECLARE
    unlinked_cliente INT;
    unlinked_freelancer INT;
BEGIN
    SELECT COUNT(*) INTO unlinked_cliente
    FROM technicians
    WHERE role = 'cliente' AND supervisor_id IS NULL;

    IF unlinked_cliente > 0 THEN
        INSERT INTO migration_audit_0030 (action, affected_count, details)
        VALUES ('clientes_sem_supervisor', unlinked_cliente,
                jsonb_build_object('severity', 'warning'));
        RAISE WARNING 'Existem % clientes sem supervisor vinculado', unlinked_cliente;
    ELSE
        RAISE NOTICE 'Todos os clientes possuem supervisor vinculado';
    END IF;

    -- backfill: freelancer herda o supervisor ja declarado em freelancer_profiles
    UPDATE technicians t
    SET supervisor_id = fp.supervisor_id
    FROM freelancer_profiles fp
    WHERE fp.technician_id = t.id
      AND t.role = 'freelancer'
      AND t.supervisor_id IS NULL;

    SELECT COUNT(*) INTO unlinked_freelancer
    FROM technicians
    WHERE role = 'freelancer' AND supervisor_id IS NULL;

    IF unlinked_freelancer > 0 THEN
        INSERT INTO migration_audit_0030 (action, affected_count, details)
        VALUES ('freelancers_sem_supervisor', unlinked_freelancer,
                jsonb_build_object('severity', 'warning'));
        RAISE WARNING 'Existem % freelancers sem supervisor vinculado', unlinked_freelancer;
    ELSE
        RAISE NOTICE 'Todos os freelancers possuem supervisor vinculado';
    END IF;
END $$;

-- Step 7: integridade de papeis (nenhum papel legado pode sobreviver)
DO $$
DECLARE
    invalid_roles INT;
    super_admin_count INT;
    supervisor_count INT;
    cliente_count INT;
    freelancer_count INT;
    cliente_avulso_count INT;
BEGIN
    SELECT COUNT(*) INTO invalid_roles
    FROM technicians
    WHERE role NOT IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso');

    IF invalid_roles > 0 THEN
        RAISE EXCEPTION 'Encontrados % usuarios com papel invalido - modelo de papeis corrompido', invalid_roles;
    END IF;

    SELECT COUNT(*) INTO super_admin_count    FROM technicians WHERE role = 'super_admin';
    SELECT COUNT(*) INTO supervisor_count     FROM technicians WHERE role = 'supervisor';
    SELECT COUNT(*) INTO cliente_count        FROM technicians WHERE role = 'cliente';
    SELECT COUNT(*) INTO freelancer_count     FROM technicians WHERE role = 'freelancer';
    SELECT COUNT(*) INTO cliente_avulso_count FROM technicians WHERE role = 'cliente_avulso';

    INSERT INTO migration_audit_0030 (action, affected_count, details)
    VALUES ('role_integrity_check',
            super_admin_count + supervisor_count + cliente_count + freelancer_count + cliente_avulso_count,
            jsonb_build_object(
                'super_admin', super_admin_count,
                'supervisor', supervisor_count,
                'cliente', cliente_count,
                'freelancer', freelancer_count,
                'cliente_avulso', cliente_avulso_count));

    RAISE NOTICE 'Papeis: super_admin=%, supervisor=%, cliente=%, freelancer=%, cliente_avulso=%',
        super_admin_count, supervisor_count, cliente_count, freelancer_count, cliente_avulso_count;
END $$;

-- Step 8: cobertura da matriz de permissoes e da hierarquia
DO $$
DECLARE
    roles_with_perms INT;
    hierarchy_rows INT;
BEGIN
    SELECT COUNT(DISTINCT role) INTO roles_with_perms FROM explicit_permissions;
    SELECT COUNT(*) INTO hierarchy_rows FROM role_hierarchy;

    IF roles_with_perms <> 5 THEN
        RAISE EXCEPTION 'Matriz de permissoes incompleta: % papeis cobertos (esperado 5)', roles_with_perms;
    END IF;

    INSERT INTO migration_audit_0030 (action, affected_count, details)
    VALUES ('permissions_coverage', roles_with_perms,
            jsonb_build_object('role_hierarchy_rows', hierarchy_rows));

    RAISE NOTICE 'Permissoes cobrem % papeis; hierarquia com % relacoes', roles_with_perms, hierarchy_rows;
END $$;

-- Step 9: funcao de validacao continua do schema
CREATE OR REPLACE FUNCTION validate_schema_integrity()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details JSONB
) AS $$
BEGIN
    -- 1: papeis validos
    RETURN QUERY
    SELECT
        'role_validity'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object('invalid_roles', COUNT(*)::INT)
    FROM technicians
    WHERE role NOT IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso');

    -- 2: integridade dos vinculos
    RETURN QUERY
    SELECT
        'assignment_integrity'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object('invalid_assignments', COUNT(*)::INT)
    FROM technician_assignments ta
    WHERE NOT EXISTS (SELECT 1 FROM technicians t WHERE t.id = ta.technician_id)
       OR (ta.organization_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM organizations o WHERE o.id = ta.organization_id))
       OR (ta.network_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM networks n WHERE n.id = ta.network_id));

    -- 3: cliente e freelancer sempre vinculados a um supervisor
    RETURN QUERY
    SELECT
        'cliente_supervisor_link'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object(
            'clientes_sem_supervisor',
            COUNT(*) FILTER (WHERE role = 'cliente')::INT,
            'freelancers_sem_supervisor',
            COUNT(*) FILTER (WHERE role = 'freelancer')::INT)
    FROM technicians
    WHERE role IN ('cliente', 'freelancer') AND supervisor_id IS NULL;

    -- 4: papeis avulsos sem organizacao propria
    RETURN QUERY
    SELECT
        'avulsos_sem_org'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object('orgs_indevidas', COUNT(*)::INT)
    FROM organizations o
    JOIN technicians t ON t.id = o.owner_technician_id
    WHERE t.role IN ('freelancer', 'cliente_avulso', 'cliente');

    -- 5: cobertura de permissoes para os 5 papeis
    RETURN QUERY
    SELECT
        'permissions_coverage'::TEXT,
        CASE WHEN COUNT(DISTINCT role) = 5 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object('roles_with_permissions', COUNT(DISTINCT role)::INT)
    FROM explicit_permissions;

    -- 6: supervisor nao manda em papeis avulsos
    RETURN QUERY
    SELECT
        'supervisor_sem_autoridade_sobre_avulsos'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        jsonb_build_object('relacoes_indevidas', COUNT(*)::INT)
    FROM role_hierarchy
    WHERE parent_role = 'supervisor'
      AND child_role IN ('freelancer', 'cliente_avulso');
END;
$$ LANGUAGE plpgsql STABLE;

-- Step 10: relatorio final
DO $$
DECLARE
    total_technicians INT;
    total_assignments INT;
    total_permissions INT;
    total_roles INT;
BEGIN
    SELECT COUNT(*) INTO total_technicians FROM technicians;
    SELECT COUNT(*) INTO total_assignments FROM technician_assignments;
    SELECT COUNT(*) INTO total_permissions FROM explicit_permissions;
    SELECT COUNT(*) INTO total_roles       FROM role_hierarchy;

    INSERT INTO migration_audit_0030 (action, affected_count, details)
    VALUES ('final_integrity_report', total_technicians, jsonb_build_object(
        'total_technicians', total_technicians,
        'total_assignments', total_assignments,
        'total_permissions', total_permissions,
        'total_role_relationships', total_roles,
        'status', 'integrity_check_complete'));

    RAISE NOTICE 'Migracao 0030 concluida: usuarios=%, vinculos=%, permissoes=%, relacoes=%',
        total_technicians, total_assignments, total_permissions, total_roles;
END $$;
