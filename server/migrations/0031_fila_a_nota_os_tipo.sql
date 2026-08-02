-- TGDesk: Fila A (oferta de avulso a supervisores), sistema de nota cruzada,
-- OS com tipo real (virtual/onsite), visibilidade de organizacoes internas,
-- exclusividade de acesso remoto e amostras de diagnostico em serie temporal.
-- Ver .godzmind/MODELO-PRODUTO.md para o modelo de negocio completo.

-- 1) Fila A: oferta de chamado avulso a supervisores (espelha dispatch_offers, 0025).
CREATE TABLE IF NOT EXISTS supervisor_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    supervisor_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    rank SMALLINT NOT NULL,
    available_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    UNIQUE(ticket_id,supervisor_id)
);
CREATE INDEX IF NOT EXISTS supervisor_offers_queue_idx
    ON supervisor_offers(supervisor_id,available_at,expires_at);

-- 2) Sistema de nota (avaliacao cruzada ao final do chamado).
--
-- rater_id / ratee_id NAO tem FK direta: o papel determina a tabela de origem.
-- Quando rater_role/ratee_role in ('supervisor','freelancer') o id referencia
-- technicians(id); quando in ('cliente','cliente_avulso') o id referencia
-- devices(id) (o dispositivo E o "cliente" - ver MODELO-PRODUTO.md, "Base logica").
-- Por isso a coluna fica sem REFERENCES: uma unica coluna nao pode apontar pra
-- duas tabelas diferentes dependendo do valor de outra coluna sem trigger dedicado.
CREATE TABLE IF NOT EXISTS ticket_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    rater_role TEXT NOT NULL CHECK (rater_role IN ('supervisor','freelancer','cliente','cliente_avulso')),
    rater_id UUID NOT NULL,
    ratee_role TEXT NOT NULL CHECK (ratee_role IN ('supervisor','freelancer','cliente','cliente_avulso')),
    ratee_id UUID NOT NULL,
    stars NUMERIC(2,1) NOT NULL CHECK (stars BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(ticket_id,rater_id,ratee_id)
);

-- Nota do supervisor: media historica corrida das avaliacoes recebidas, usada
-- para ordenar a Fila A (oferta de avulso pro supervisor). Espelha freelancer_profiles (0025).
CREATE TABLE IF NOT EXISTS supervisor_profiles (
    technician_id UUID PRIMARY KEY REFERENCES technicians(id) ON DELETE CASCADE,
    rating_avg NUMERIC(3,2) NOT NULL DEFAULT 5.00 CHECK (rating_avg BETWEEN 1 AND 5),
    rating_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Nota do cliente: so exibida como detalhe na fila do tecnico, nao ordena nada
-- (ver MODELO-PRODUTO.md, "Uso da nota do cliente"). O "cliente" e o device.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS client_rating_avg NUMERIC(3,2) NOT NULL DEFAULT 5.00
    CHECK (client_rating_avg BETWEEN 1 AND 5);
ALTER TABLE devices ADD COLUMN IF NOT EXISTS client_rating_count INT NOT NULL DEFAULT 0;

-- freelancer_profiles.quality_score (0025, NUMERIC(5,2) 0-100) NAO muda de schema
-- aqui: continua sendo usado no ranking de despacho combinado com distancia
-- geografica. A partir desta migration, porem, deixa de ser um valor estatico e
-- passa a ser recalculado a cada avaliacao recebida pelo tecnico (nota do
-- tecnico, ver MODELO-PRODUTO.md "Sistema de nota"), mantendo a mesma escala
-- 0-100 para nao quebrar o algoritmo de ranking existente.

-- 3) OS real: tipo (virtual/presencial) e escopo definido pelo supervisor.
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS os_type TEXT NOT NULL DEFAULT 'virtual'
    CHECK (os_type IN ('virtual','onsite'));
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS scope_notes TEXT NOT NULL DEFAULT '';

-- 4) Visibilidade: organizacoes internas ao sistema (ex.: "Atendimento Avulso
-- TGDesk") nao devem aparecer como organizacao normal pro super_admin.
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS system_internal BOOLEAN NOT NULL DEFAULT false;

-- Idempotente: roda mesmo se a org ainda nao existir, sem erro.
UPDATE organizations SET system_internal = true WHERE name = 'Atendimento Avulso TGDesk';

-- 5) Estados: novo status 'offered_supervisor' para a Fila A (oferta ao supervisor,
-- distinta de 'offered' que e a oferta ao tecnico na Fila B).
ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_status_check;
ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_status_check
    CHECK (status IN ('open','offered_supervisor','offered','accepted','in_progress','closed','cancelled','expired','reopened'));

-- 6) Exclusividade de acesso: quando a OS vira virtual pra um tecnico, o acesso
-- remoto passa a ser EXCLUSIVO dele, revogando o do supervisor enquanto ativo
-- (ver MODELO-PRODUTO.md, "Chamado -> OS: a transformacao real").
ALTER TABLE temporary_ticket_permissions ADD COLUMN IF NOT EXISTS exclusive BOOLEAN NOT NULL DEFAULT false;

-- 7) Dados tecnicos estruturados do chamado (categoria, urgencia, coordenadas
-- estruturadas), em vez de tudo cair em description livre.
ALTER TABLE support_tickets ADD COLUMN IF NOT EXISTS structured_data JSONB NOT NULL DEFAULT '{}'::jsonb;

-- 8) Amostras de diagnostico em serie temporal, vinculadas a uma diagnostic_runs (0019).
CREATE TABLE IF NOT EXISTS diagnostic_samples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES diagnostic_runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    metric TEXT NOT NULL,
    value DOUBLE PRECISION NOT NULL
);
CREATE INDEX IF NOT EXISTS diagnostic_samples_run_ts_idx ON diagnostic_samples(run_id,ts);
