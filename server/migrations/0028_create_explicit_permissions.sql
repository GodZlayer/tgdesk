-- TGDesk v1.1.0: matriz de permissoes explicitas (RBAC).
--
-- Papeis (5): super_admin, supervisor, cliente, freelancer, cliente_avulso.
--   super_admin    : tudo, em todos os resource_types e actions.
--   supervisor     : CRUD completo dentro da PROPRIA org. Nada fora dela.
--   cliente        : nenhuma acao de gestao. device(read) do proprio e ticket(create/read) proprios.
--   freelancer     : ticket(read/update) so dos atribuidos; device(read) so via permissao temporaria.
--   cliente_avulso : ticket(create/read) proprios; device(read) proprio. Nada mais.

-- Step 1: tabela
CREATE TABLE IF NOT EXISTS explicit_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role TEXT NOT NULL
        CHECK (role IN ('super_admin', 'supervisor', 'cliente', 'freelancer', 'cliente_avulso')),
    resource_type TEXT NOT NULL
        CHECK (resource_type IN (
            'organization',
            'network',
            'subnetwork',
            'device',
            'support_ticket',
            'freelancer_profile',
            'technician',
            'cliente',
            'admin_actions'
        )),
    action TEXT NOT NULL
        CHECK (action IN (
            'create',
            'read',
            'update',
            'delete',
            'suspend',
            'resume',
            'assign',
            'dispatch',
            'view_audit',
            'manage_permissions'
        )),
    -- limite de alcance da permissao
    scope TEXT NOT NULL DEFAULT 'own'
        CHECK (scope IN ('global', 'own_org', 'assigned', 'own')),
    grant_default BOOLEAN NOT NULL DEFAULT false,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (role, resource_type, action)
);

-- Step 2: indices
CREATE INDEX IF NOT EXISTS idx_explicit_permissions_role
    ON explicit_permissions(role);
CREATE INDEX IF NOT EXISTS idx_explicit_permissions_resource
    ON explicit_permissions(resource_type);
CREATE INDEX IF NOT EXISTS idx_explicit_permissions_action
    ON explicit_permissions(action);
CREATE INDEX IF NOT EXISTS idx_explicit_permissions_grant
    ON explicit_permissions(role, resource_type, grant_default);
CREATE INDEX IF NOT EXISTS idx_explicit_permissions_scope
    ON explicit_permissions(scope);

-- Step 3: super_admin -> TUDO (produto cartesiano resource_type x action), escopo global
INSERT INTO explicit_permissions (role, resource_type, action, scope, grant_default, description)
SELECT 'super_admin', r.resource_type, a.action, 'global', true,
       'Super admin: controle total de ' || r.resource_type
FROM (VALUES
        ('organization'), ('network'), ('subnetwork'), ('device'),
        ('support_ticket'), ('freelancer_profile'), ('technician'),
        ('cliente'), ('admin_actions')
     ) AS r(resource_type)
CROSS JOIN (VALUES
        ('create'), ('read'), ('update'), ('delete'), ('suspend'),
        ('resume'), ('assign'), ('dispatch'), ('view_audit'), ('manage_permissions')
     ) AS a(action)
ON CONFLICT (role, resource_type, action) DO NOTHING;

-- Step 4: supervisor -> CRUD completo dentro da PROPRIA org (escopo own_org)
INSERT INTO explicit_permissions (role, resource_type, action, scope, grant_default, description) VALUES
('supervisor', 'organization',   'read',     'own_org', true, 'Ler a propria organizacao'),
('supervisor', 'organization',   'update',   'own_org', true, 'Atualizar a propria organizacao'),
('supervisor', 'network',        'create',   'own_org', true, 'Criar redes na propria org'),
('supervisor', 'network',        'read',     'own_org', true, 'Ler redes da propria org'),
('supervisor', 'network',        'update',   'own_org', true, 'Atualizar redes da propria org'),
('supervisor', 'network',        'delete',   'own_org', true, 'Remover redes da propria org'),
('supervisor', 'network',        'suspend',  'own_org', true, 'Suspender rede (cascata em subredes/dispositivos)'),
('supervisor', 'network',        'resume',   'own_org', true, 'Reativar rede da propria org'),
('supervisor', 'subnetwork',     'create',   'own_org', true, 'Criar subredes na propria org'),
('supervisor', 'subnetwork',     'read',     'own_org', true, 'Ler subredes da propria org'),
('supervisor', 'subnetwork',     'update',   'own_org', true, 'Atualizar subredes da propria org'),
('supervisor', 'subnetwork',     'delete',   'own_org', true, 'Remover subredes da propria org'),
('supervisor', 'subnetwork',     'suspend',  'own_org', true, 'Suspender subrede (cascata em dispositivos)'),
('supervisor', 'subnetwork',     'resume',   'own_org', true, 'Reativar subrede da propria org'),
('supervisor', 'device',         'read',     'own_org', true, 'Ler dispositivos da propria org'),
('supervisor', 'device',         'update',   'own_org', true, 'Atualizar dispositivos da propria org'),
('supervisor', 'device',         'suspend',  'own_org', true, 'Suspender dispositivo da propria org'),
('supervisor', 'device',         'resume',   'own_org', true, 'Reativar dispositivo da propria org'),
('supervisor', 'device',         'assign',   'own_org', true, 'Vincular dispositivo a rede/subrede da propria org'),
('supervisor', 'support_ticket', 'create',   'own_org', true, 'Abrir chamado na propria org'),
('supervisor', 'support_ticket', 'read',     'own_org', true, 'Ler chamados da propria org'),
('supervisor', 'support_ticket', 'update',   'own_org', true, 'Atualizar chamados da propria org'),
('supervisor', 'support_ticket', 'dispatch', 'own_org', true, 'Despachar chamado para freelancer'),
('supervisor', 'cliente',        'create',   'own_org', true, 'Criar cliente vinculado a si'),
('supervisor', 'cliente',        'read',     'own_org', true, 'Ler os proprios clientes'),
('supervisor', 'cliente',        'update',   'own_org', true, 'Atualizar os proprios clientes'),
('supervisor', 'cliente',        'suspend',  'own_org', true, 'Suspender os proprios clientes')
ON CONFLICT (role, resource_type, action) DO NOTHING;

-- Step 5: cliente -> nenhuma acao de gestao
INSERT INTO explicit_permissions (role, resource_type, action, scope, grant_default, description) VALUES
('cliente', 'device',         'read',   'own', true, 'Ler o proprio dispositivo'),
('cliente', 'support_ticket', 'create', 'own', true, 'Abrir os proprios chamados'),
('cliente', 'support_ticket', 'read',   'own', true, 'Ler os proprios chamados')
ON CONFLICT (role, resource_type, action) DO NOTHING;

-- Step 6: freelancer -> so tickets atribuidos; device apenas via permissao temporaria de ticket
INSERT INTO explicit_permissions (role, resource_type, action, scope, grant_default, description) VALUES
('freelancer', 'support_ticket',     'read',   'assigned', true,  'Ler apenas os chamados atribuidos a ele'),
('freelancer', 'support_ticket',     'update', 'assigned', true,  'Atualizar apenas os chamados atribuidos a ele'),
('freelancer', 'device',             'read',   'assigned', false, 'Ler dispositivo somente via permissao temporaria de ticket'),
('freelancer', 'freelancer_profile', 'read',   'own',      true,  'Ler o proprio perfil'),
('freelancer', 'freelancer_profile', 'update', 'own',      true,  'Atualizar o proprio perfil')
ON CONFLICT (role, resource_type, action) DO NOTHING;

-- Step 7: cliente_avulso -> so os proprios chamados e o proprio dispositivo
INSERT INTO explicit_permissions (role, resource_type, action, scope, grant_default, description) VALUES
('cliente_avulso', 'support_ticket', 'create', 'own', true, 'Abrir os proprios chamados'),
('cliente_avulso', 'support_ticket', 'read',   'own', true, 'Ler os proprios chamados'),
('cliente_avulso', 'device',         'read',   'own', true, 'Ler o proprio dispositivo')
ON CONFLICT (role, resource_type, action) DO NOTHING;

-- Step 8: relatorio
DO $$
DECLARE
    total_perms INT;
    granted_perms INT;
    roles_covered INT;
BEGIN
    SELECT COUNT(*) INTO total_perms   FROM explicit_permissions;
    SELECT COUNT(*) INTO granted_perms FROM explicit_permissions WHERE grant_default = true;
    SELECT COUNT(DISTINCT role) INTO roles_covered FROM explicit_permissions;
    RAISE NOTICE 'explicit_permissions: total=%, default_granted=%, papeis_cobertos=%',
        total_perms, granted_perms, roles_covered;
END $$;
