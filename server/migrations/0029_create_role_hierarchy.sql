-- TGDesk v1.1.0: hierarquia de papeis e heranca de permissao.
--
-- Hierarquia base (cascata):
--   super_admin > supervisor > cliente
--
-- Avulsos (fora da hierarquia, respondem SO ao super_admin):
--   freelancer, cliente_avulso
--
-- O supervisor NAO tem autoridade alguma sobre freelancer nem sobre cliente_avulso.
--
-- Nota: technicians.supervisor_id do freelancer (ver 0026) e vinculo de despacho/organizacao,
-- NAO implica autoridade administrativa. A hierarquia abaixo permanece inalterada.

-- Step 1: tabela
CREATE TABLE IF NOT EXISTS role_hierarchy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_role TEXT NOT NULL
        CHECK (parent_role IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso')),
    child_role TEXT NOT NULL
        CHECK (child_role IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso')),
    permission_inheritance TEXT NOT NULL DEFAULT 'full'
        CHECK (permission_inheritance IN ('full', 'partial', 'none')),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (parent_role, child_role),
    CHECK (parent_role <> child_role)
);

-- Step 2: indices
CREATE INDEX IF NOT EXISTS idx_role_hierarchy_parent
    ON role_hierarchy(parent_role);
CREATE INDEX IF NOT EXISTS idx_role_hierarchy_child
    ON role_hierarchy(child_role);
CREATE INDEX IF NOT EXISTS idx_role_hierarchy_inheritance
    ON role_hierarchy(permission_inheritance);

-- Step 3: relacoes autoritativas (5 linhas, nem mais nem menos)
INSERT INTO role_hierarchy (parent_role, child_role, permission_inheritance, description) VALUES
('super_admin', 'supervisor',     'full',    'Super admin manda em todo supervisor'),
('super_admin', 'cliente',        'full',    'Super admin manda em todo cliente'),
('supervisor',  'cliente',        'full',    'Supervisor manda nos clientes vinculados a ele'),
('super_admin', 'freelancer',     'partial', 'Freelancer e avulso e responde apenas ao super admin'),
('super_admin', 'cliente_avulso', 'partial', 'Cliente avulso e avulso e responde apenas ao super admin')
ON CONFLICT (parent_role, child_role) DO NOTHING;

-- Step 4: view de consulta
DROP VIEW IF EXISTS role_inheritance_matrix;
CREATE VIEW role_inheritance_matrix AS
SELECT
    parent_role,
    child_role,
    permission_inheritance,
    CASE permission_inheritance
        WHEN 'full'    THEN 1.0
        WHEN 'partial' THEN 0.5
        ELSE 0.0
    END AS inheritance_weight
FROM role_hierarchy;

-- Step 5: funcao de autoridade (transitiva). super_admin > supervisor > cliente.
CREATE OR REPLACE FUNCTION check_role_inheritance(
    p_parent_role TEXT,
    p_child_role TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_parent_role = p_child_role THEN
        RETURN true;
    END IF;

    RETURN EXISTS (
        WITH RECURSIVE descendants AS (
            SELECT rh.child_role
            FROM role_hierarchy rh
            WHERE rh.parent_role = p_parent_role
            UNION
            SELECT rh.child_role
            FROM role_hierarchy rh
            JOIN descendants d ON rh.parent_role = d.child_role
        )
        SELECT 1 FROM descendants WHERE child_role = p_child_role
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Step 6: permissoes efetivas de um papel (diretas + herdadas dos ancestrais)
CREATE OR REPLACE FUNCTION get_inherited_permissions(p_role TEXT)
RETURNS TABLE (
    resource_type TEXT,
    action TEXT,
    scope TEXT,
    direct_grant BOOLEAN,
    inherited_from TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE ancestors AS (
        SELECT p_role::TEXT AS role
        UNION
        SELECT rh.parent_role
        FROM role_hierarchy rh
        JOIN ancestors a ON rh.child_role = a.role
    )
    SELECT
        ep.resource_type,
        ep.action,
        ep.scope,
        (ep.role = p_role) AS direct_grant,
        ep.role AS inherited_from
    FROM explicit_permissions ep
    JOIN ancestors a ON ep.role = a.role
    ORDER BY ep.resource_type, ep.action;
END;
$$ LANGUAGE plpgsql STABLE;

-- Step 7: verificacao de integridade da hierarquia
DO $$
DECLARE
    hierarchy_count INT;
    bad_supervisor_links INT;
BEGIN
    SELECT COUNT(*) INTO hierarchy_count FROM role_hierarchy;

    -- supervisor nao pode ter autoridade sobre avulsos
    SELECT COUNT(*) INTO bad_supervisor_links
    FROM role_hierarchy
    WHERE parent_role = 'supervisor'
      AND child_role IN ('freelancer', 'cliente_avulso');

    IF bad_supervisor_links > 0 THEN
        RAISE EXCEPTION 'Hierarquia invalida: supervisor nao pode ter autoridade sobre papeis avulsos';
    END IF;

    RAISE NOTICE 'role_hierarchy: % relacoes criadas', hierarchy_count;
END $$;
