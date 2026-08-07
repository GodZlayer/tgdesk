-- TGDesk: auditoria completa por dom?nio e relat?rio live para investidor/admin.
-- O PDF final ? uma renderiza??o cliente. O servidor entrega snapshot estruturado,
-- se??es, m?tricas e detalhes profundos para popups sem o cliente calcular nada.

CREATE TABLE IF NOT EXISTS audit_domains (
    key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    position INTEGER NOT NULL DEFAULT 100,
    investor_visible BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO audit_domains(key,label,description,position,investor_visible) VALUES
    ('connections','Conex?es e acesso remoto','Conex?es, consentimentos, sess?es remotas, chat e presen?a.',10,true),
    ('bindings','V?nculos e rede operacional','Organiza??es, redes, subredes, dispositivos, t?cnicos, supervisores e chaves.',20,true),
    ('financial','Financeiro e precifica??o','Or?amentos, percentuais, regras regionais, entrada, repasses, pe?as e consum?veis.',30,true),
    ('service_orders','Ordens de servi?o','Abertura, montagem, execu??o, evid?ncias, nota fiscal, fechamento e avalia??o.',40,true),
    ('diagnostics','Diagn?stico e sa?de','Coletas t?cnicas, press?o de CPU/GPU/mem?ria/disco, rein?cios e hist?rico.',50,true),
    ('territory','Regi?es e demanda','Munic?pios, regi?es comerciais, demanda regional, t?cnicos dispon?veis e clientes ativos.',60,true),
    ('catalog','Cat?logos e configura??o','Tipos de chamado, servi?os, pe?as, consum?veis e contratos do editor admin.',70,true),
    ('security','Seguran?a e permiss?es','Login, autoriza??o, suspens?o, reativa??o, exclus?o e a??es administrativas.',80,true),
    ('system','Sistema e atualiza??es','Vers?es, atualiza??es, migrations, servi?os e eventos internos.',90,false)
ON CONFLICT(key) DO UPDATE SET
    label=excluded.label,
    description=excluded.description,
    position=excluded.position,
    investor_visible=excluded.investor_visible,
    updated_at=now();

CREATE TABLE IF NOT EXISTS audit_event_classifiers (
    pattern TEXT PRIMARY KEY,
    domain_key TEXT NOT NULL REFERENCES audit_domains(key) ON UPDATE CASCADE,
    severity TEXT NOT NULL DEFAULT 'info' CHECK (severity IN ('debug','info','notice','warning','critical')),
    relation_degree TEXT NOT NULL DEFAULT 'operational'
        CHECK (relation_degree IN ('system','commercial','operational','financial','security','territorial')),
    label TEXT NOT NULL DEFAULT '',
    investor_visible BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO audit_event_classifiers(pattern,domain_key,severity,relation_degree,label,investor_visible) VALUES
    ('opened','service_orders','notice','operational','Chamado aberto',true),
    ('diagnosis','diagnostics','notice','operational','Diagn?stico anexado',true),
    ('message','connections','info','operational','Mensagem interna',false),
    ('client_message','connections','info','commercial','Mensagem do cliente',false),
    ('remote_access_requested','connections','notice','security','Acesso remoto solicitado',true),
    ('remote_access_response','connections','notice','security','Resposta de acesso remoto',true),
    ('service_order','service_orders','notice','financial','OS criada/alterada',true),
    ('os_started','service_orders','notice','operational','Execu??o iniciada',true),
    ('os_finished','service_orders','notice','financial','Execu??o finalizada',true),
    ('os_step','service_orders','info','operational','Etapa de OS',true),
    ('transition','service_orders','info','operational','Mudan?a de estado',true),
    ('closure_confirmed','service_orders','notice','commercial','Fechamento confirmado',true),
    ('dispatch_offered','bindings','notice','operational','Oferta de despacho',true),
    ('dispatch_accepted','bindings','notice','operational','Despacho aceito',true),
    ('supervisor_offer_accepted','bindings','notice','commercial','Supervisor aceitou oferta',true),
    ('invoice_photo','financial','notice','financial','Nota fiscal/evid?ncia financeira',true),
    ('pricing_rules','financial','notice','financial','Regra de pre?o alterada',true),
    ('regions','territory','notice','territorial','Regi?o alterada',true),
    ('os_catalog','catalog','notice','operational','Cat?logo de OS alterado',true),
    ('suspender','security','warning','security','Suspens?o administrativa',true),
    ('reativar','security','notice','security','Reativa??o administrativa',true),
    ('delete','security','warning','security','Exclus?o administrativa',true),
    ('excluir','security','warning','security','Exclus?o administrativa',true),
    ('recusar','security','warning','security','Recusa administrativa',true),
    ('acesso_remoto','connections','notice','security','Acesso remoto administrativo',true)
ON CONFLICT(pattern) DO UPDATE SET
    domain_key=excluded.domain_key,
    severity=excluded.severity,
    relation_degree=excluded.relation_degree,
    label=excluded.label,
    investor_visible=excluded.investor_visible,
    updated_at=now();

CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    domain_key TEXT NOT NULL REFERENCES audit_domains(key) ON UPDATE CASCADE,
    severity TEXT NOT NULL DEFAULT 'info' CHECK (severity IN ('debug','info','notice','warning','critical')),
    relation_degree TEXT NOT NULL DEFAULT 'operational'
        CHECK (relation_degree IN ('system','commercial','operational','financial','security','territorial')),
    event_type TEXT NOT NULL,
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id TEXT NOT NULL DEFAULT '',
    actor_technician_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    actor_device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    network_id UUID REFERENCES networks(id) ON DELETE SET NULL,
    ticket_id UUID REFERENCES support_tickets(id) ON DELETE SET NULL,
    region_id UUID REFERENCES regions(id) ON DELETE SET NULL,
    amount_cents BIGINT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    source_table TEXT NOT NULL DEFAULT 'audit_events',
    source_id TEXT NOT NULL DEFAULT '',
    investor_visible BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(source_table, source_id)
);

CREATE INDEX IF NOT EXISTS audit_events_domain_created_idx ON audit_events(domain_key, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_events_relation_created_idx ON audit_events(relation_degree, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_events_ticket_idx ON audit_events(ticket_id, created_at DESC) WHERE ticket_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS audit_events_org_idx ON audit_events(organization_id, created_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS audit_events_region_idx ON audit_events(region_id, created_at DESC) WHERE region_id IS NOT NULL;

INSERT INTO audit_events(domain_key,severity,relation_degree,event_type,entity_type,entity_id,
    actor_technician_id,actor_device_id,organization_id,network_id,ticket_id,region_id,payload,
    source_table,source_id,investor_visible,created_at)
SELECT
    COALESCE(c.domain_key,'service_orders'),
    COALESCE(c.severity,'info'),
    COALESCE(c.relation_degree,'operational'),
    e.event_type,
    'ticket',
    e.ticket_id::text,
    e.actor_technician_id,
    e.actor_device_id,
    t.organization_id,
    t.network_id,
    e.ticket_id,
    t.region_id,
    e.payload,
    'ticket_events',
    e.id::text,
    COALESCE(c.investor_visible,true),
    e.created_at
FROM ticket_events e
LEFT JOIN support_tickets t ON t.id=e.ticket_id
LEFT JOIN LATERAL (
    SELECT * FROM audit_event_classifiers c
    WHERE e.event_type ILIKE '%' || c.pattern || '%'
    ORDER BY length(c.pattern) DESC
    LIMIT 1
) c ON true
ON CONFLICT(source_table,source_id) DO NOTHING;
