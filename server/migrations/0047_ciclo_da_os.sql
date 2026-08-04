-- TGDesk: ciclo de vida completo da OS e fechamento por confirmação.
--
-- Fluxo ditado pelo dono do produto:
--
--   acionamento (cliente empresarial | cliente avulso | supervisor)
--        → supervisor assume
--        → supervisor define o necessário e CONVERTE EM OS
--        → a OS vai para a fila dos técnicos (a OS é o que é ofertado)
--        → um técnico aceita e a oferta sai da fila
--        → execução acontece na data e no local marcados, não na hora do aceite
--        → técnico inicia, executa etapas, finaliza
--        → o finalizar libera as confirmações de encerramento
--        → empresarial: técnico + supervisor. Avulso: técnico + supervisor +
--          cliente.

-- 1) Nota única para todos os papéis: 1,00 a 5,00 estrelas, começando no
--    máximo.
--
-- O técnico era o único fora do padrão: quality_score em escala 0–100 com
-- default 50 (metade), enquanto supervisor e cliente já usavam 1–5 com default
-- 5,00. Os valores existentes são convertidos dividindo por 20.
ALTER TABLE freelancer_profiles DROP CONSTRAINT IF EXISTS freelancer_profiles_quality_score_check;

UPDATE freelancer_profiles
SET quality_score = LEAST(5.00, GREATEST(1.00, round((quality_score / 20.0)::numeric, 2)));

ALTER TABLE freelancer_profiles
    ALTER COLUMN quality_score TYPE NUMERIC(3,2),
    ALTER COLUMN quality_score SET DEFAULT 5.00;

ALTER TABLE freelancer_profiles
    ADD CONSTRAINT freelancer_profiles_quality_score_check
    CHECK (quality_score BETWEEN 1 AND 5);

-- 2) A OS ganha ciclo de vida próprio.
--
-- Antes ela nascia 'open' e ficava 'open' para sempre: nada movia o status, e
-- fechar o chamado deixava a OS aberta.
ALTER TABLE service_orders DROP CONSTRAINT IF EXISTS service_orders_status_check;

ALTER TABLE service_orders
    ADD CONSTRAINT service_orders_status_check
    CHECK (status IN (
        'open',                  -- criada, ainda não ofertada
        'offered',               -- na fila dos técnicos
        'assigned',              -- técnico aceitou; aguarda a data marcada
        'in_progress',           -- técnico iniciou a execução
        'awaiting_confirmation', -- técnico finalizou; falta confirmar
        'completed',
        'cancelled'
    ));

ALTER TABLE service_orders
    -- Execução é agendada: aceitar não é executar.
    ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS scheduled_location JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS assigned_technician_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS service_orders_status_idx ON service_orders(status);

-- 3) Fechamento por confirmação de cada parte.
--
-- O encerramento deixa de ser ato de um só. Cada participante registra a sua
-- confirmação depois que o técnico finaliza a execução; o chamado só fecha
-- quando todas as exigidas estão presentes.
--
-- O cliente confirma pelo dispositivo (nao tem conta de técnico), por isso
-- actor_id nao tem FK: aponta para technicians(id) ou devices(id) conforme o
-- papel, mesma convenção ja usada em ticket_ratings.
CREATE TABLE IF NOT EXISTS ticket_closure_confirmations (
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('freelancer','supervisor','cliente')),
    actor_id UUID NOT NULL,
    confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (ticket_id, role)
);

-- 4) Estados do chamado acompanham o ciclo da OS.
--
-- 'awaiting_confirmation' é o intervalo entre o técnico finalizar e todas as
-- partes confirmarem.
ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_status_check;

ALTER TABLE support_tickets
    ADD CONSTRAINT support_tickets_status_check
    CHECK (status IN ('open','offered_supervisor','offered','accepted','in_progress',
                      'awaiting_confirmation','closed','cancelled','expired','reopened'));
