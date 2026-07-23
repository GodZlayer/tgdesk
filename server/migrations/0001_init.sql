-- TGDesk Fase 0 — schema inicial
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa', 'suspensa')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE networks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    cidr_virtual TEXT,
    status TEXT NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa', 'suspensa')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organization_id, name)
);

CREATE TABLE technicians (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('super_admin', 'tecnico')),
    created_via_env BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo', 'suspenso')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE technician_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    technician_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    network_id UUID REFERENCES networks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (organization_id IS NOT NULL OR network_id IS NOT NULL),
    UNIQUE (technician_id, organization_id, network_id)
);

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID REFERENCES networks(id) ON DELETE SET NULL,
    hostname TEXT NOT NULL,
    mac TEXT,
    wg_pubkey TEXT,
    role TEXT NOT NULL DEFAULT 'host' CHECK (role IN ('host', 'tecnico')),
    state TEXT NOT NULL DEFAULT 'guest' CHECK (state IN ('guest', 'ativo', 'suspenso')),
    pairing_code TEXT UNIQUE,
    device_token TEXT NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(24), 'hex'),
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    technician_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL CHECK (tipo IN ('tela', 'usb')),
    inicio TIMESTAMPTZ NOT NULL DEFAULT now(),
    fim TIMESTAMPTZ
);

CREATE TABLE admin_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID NOT NULL REFERENCES technicians(id),
    tipo TEXT NOT NULL CHECK (tipo IN (
        'kill_switch_tecnico', 'kill_switch_rede', 'kill_switch_dispositivo',
        'kill_switch_organizacao', 'vinculacao', 'reativacao'
    )),
    alvo_id UUID,
    detalhes JSONB,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE telemetry_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    cpu REAL,
    mem REAL,
    disco REAL,
    temp REAL,
    coletado_em TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_telemetry_device_time ON telemetry_snapshots (device_id, coletado_em DESC);

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL,
    severidade TEXT NOT NULL CHECK (severidade IN ('info', 'aviso', 'critico')),
    mensagem TEXT NOT NULL,
    resolvido BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_devices_network ON devices (network_id);
CREATE INDEX idx_networks_org ON networks (organization_id);
CREATE INDEX idx_assignments_technician ON technician_assignments (technician_id);
