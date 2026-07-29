-- TGDesk 0.4.0 / 1.0.0 / 1.1.0: chamados, despacho e cliente avulso.
ALTER TABLE technicians DROP CONSTRAINT IF EXISTS technicians_role_check;
ALTER TABLE technicians ADD CONSTRAINT technicians_role_check
    CHECK (role IN ('super_admin', 'tecnico', 'freelancer'));

CREATE TABLE support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    network_id UUID REFERENCES networks(id) ON DELETE SET NULL,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    opened_by_device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    supervisor_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    assigned_freelancer_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    modality TEXT NOT NULL DEFAULT 'virtual' CHECK (modality IN ('virtual','onsite')),
    priority SMALLINT NOT NULL DEFAULT 2 CHECK (priority BETWEEN 1 AND 5),
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','offered','accepted','in_progress','closed','cancelled','expired','reopened')),
    standalone BOOLEAN NOT NULL DEFAULT false,
    location JSONB NOT NULL DEFAULT '{}'::jsonb,
    deadline_at TIMESTAMPTZ,
    accepted_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX support_tickets_scope_idx ON support_tickets(organization_id,status,priority,created_at);

CREATE TABLE ticket_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    actor_technician_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    actor_device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ticket_events_ticket_idx ON ticket_events(ticket_id,created_at);

CREATE TABLE service_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL UNIQUE REFERENCES support_tickets(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','completed','cancelled')),
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    values JSONB NOT NULL DEFAULT '{}'::jsonb,
    customer_acceptance JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE freelancer_profiles (
    technician_id UUID PRIMARY KEY REFERENCES technicians(id) ON DELETE CASCADE,
    supervisor_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    availability BOOLEAN NOT NULL DEFAULT true,
    quality_score NUMERIC(5,2) NOT NULL DEFAULT 50 CHECK (quality_score BETWEEN 0 AND 100),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE dispatch_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    freelancer_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    rank SMALLINT NOT NULL,
    available_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    UNIQUE(ticket_id,freelancer_id)
);
CREATE INDEX dispatch_offers_queue_idx ON dispatch_offers(freelancer_id,available_at,expires_at);

CREATE TABLE onsite_evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    service_order_id UUID REFERENCES service_orders(id) ON DELETE CASCADE,
    evidence_type TEXT NOT NULL CHECK (evidence_type IN
        ('geolocation','arrival_photo','execution_photo','completion_photo','signature','signed_document')),
    idempotency_key TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    captured_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(ticket_id,idempotency_key)
);

CREATE TABLE temporary_ticket_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    freelancer_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    allow_remote BOOLEAN NOT NULL DEFAULT false,
    allow_analysis BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    UNIQUE(ticket_id,freelancer_id,device_id)
);

CREATE TABLE standalone_scope (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK(singleton),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE RESTRICT
);
