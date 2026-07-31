-- TGDesk v1.1.0: escopo e nivel de permissao em technician_assignments.
-- assignment_scope : device | subnetwork | network | organization
-- permissions_level: full | read | limited
--
-- Papeis validos: super_admin, supervisor, cliente, freelancer, cliente_avulso.

-- Step 1: novas colunas de escopo/nivel
ALTER TABLE technician_assignments
    ADD COLUMN IF NOT EXISTS assignment_scope TEXT NOT NULL DEFAULT 'organization';

ALTER TABLE technician_assignments
    ADD COLUMN IF NOT EXISTS permissions_level TEXT NOT NULL DEFAULT 'full';

ALTER TABLE technician_assignments
    DROP CONSTRAINT IF EXISTS technician_assignments_assignment_scope_check;
ALTER TABLE technician_assignments
    ADD CONSTRAINT technician_assignments_assignment_scope_check
    CHECK (assignment_scope IN ('device', 'subnetwork', 'network', 'organization'));

ALTER TABLE technician_assignments
    DROP CONSTRAINT IF EXISTS technician_assignments_permissions_level_check;
ALTER TABLE technician_assignments
    ADD CONSTRAINT technician_assignments_permissions_level_check
    CHECK (permissions_level IN ('full', 'read', 'limited'));

-- Step 2: alvos opcionais para escopos device/subnetwork
ALTER TABLE technician_assignments
    ADD COLUMN IF NOT EXISTS device_id UUID REFERENCES devices(id) ON DELETE CASCADE;

ALTER TABLE technician_assignments
    ADD COLUMN IF NOT EXISTS subnetwork_id UUID REFERENCES subnetworks(id) ON DELETE CASCADE;

-- Step 3: coerencia escopo x alvo
ALTER TABLE technician_assignments DROP CONSTRAINT IF EXISTS technician_assignments_check;
ALTER TABLE technician_assignments DROP CONSTRAINT IF EXISTS technician_assignments_scope_check;

ALTER TABLE technician_assignments
    ADD CONSTRAINT technician_assignments_scope_check
    CHECK (
        (assignment_scope = 'organization' AND organization_id IS NOT NULL) OR
        (assignment_scope = 'network'      AND network_id     IS NOT NULL) OR
        (assignment_scope = 'subnetwork'   AND subnetwork_id  IS NOT NULL) OR
        (assignment_scope = 'device'       AND device_id      IS NOT NULL)
    );

-- Step 4: backfill do nivel de permissao conforme o papel
--   supervisor  -> full    (manda em tudo dentro da propria org)
--   super_admin -> full
--   freelancer  -> limited (so o que o ticket conceder)
--   cliente / cliente_avulso -> read (sem gestao)
UPDATE technician_assignments ta
SET permissions_level = CASE
        WHEN t.role IN ('super_admin', 'supervisor') THEN 'full'
        WHEN t.role = 'freelancer' THEN 'limited'
        WHEN t.role IN ('cliente', 'cliente_avulso') THEN 'read'
        ELSE 'limited'
    END
FROM technicians t
WHERE ta.technician_id = t.id;

-- Step 5: indices (todas as FKs + combinacoes de consulta)
CREATE INDEX IF NOT EXISTS idx_technician_assignments_technician
    ON technician_assignments(technician_id);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_organization
    ON technician_assignments(organization_id);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_network
    ON technician_assignments(network_id);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_subnetwork
    ON technician_assignments(subnetwork_id);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_device
    ON technician_assignments(device_id);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_tech_org_scope
    ON technician_assignments(technician_id, organization_id, assignment_scope);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_tech_network_scope
    ON technician_assignments(technician_id, network_id, assignment_scope);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_permissions
    ON technician_assignments(technician_id, permissions_level);
CREATE INDEX IF NOT EXISTS idx_technician_assignments_org_scope
    ON technician_assignments(organization_id, assignment_scope);

-- Step 6: relatorio
DO $$
DECLARE
    full_perms_count INT;
    read_perms_count INT;
    limited_perms_count INT;
    org_scope_count INT;
    net_scope_count INT;
BEGIN
    SELECT COUNT(*) INTO full_perms_count    FROM technician_assignments WHERE permissions_level = 'full';
    SELECT COUNT(*) INTO read_perms_count    FROM technician_assignments WHERE permissions_level = 'read';
    SELECT COUNT(*) INTO limited_perms_count FROM technician_assignments WHERE permissions_level = 'limited';
    SELECT COUNT(*) INTO org_scope_count     FROM technician_assignments WHERE assignment_scope = 'organization';
    SELECT COUNT(*) INTO net_scope_count     FROM technician_assignments WHERE assignment_scope = 'network';

    RAISE NOTICE 'Assignments apos 0027: full=%, read=%, limited=% | escopos: org=%, net=%',
        full_perms_count, read_perms_count, limited_perms_count, org_scope_count, net_scope_count;
END $$;
