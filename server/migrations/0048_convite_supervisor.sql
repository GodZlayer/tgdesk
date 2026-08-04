-- TGDesk: uma organização pode ter mais de um supervisor.
--
-- A visibilidade dos chamados já era da organização, não do dono: qualquer
-- supervisor em technician_assignments daquela org enxerga a fila dela (ver
-- Authorizer.CanListTickets). O que faltava era o meio de vincular o segundo
-- supervisor — daí o convite por código.
--
-- O código é gerado pelo supervisor dono e resgatado pelo outro na tela
-- Cliente da máquina dele, do mesmo jeito que o dispositivo se vincula por
-- código de pareamento: uma lógica só, mudando apenas o que a credencial
-- libera.

CREATE TABLE IF NOT EXISTS supervisor_invites (
    code TEXT PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
    consumed_at TIMESTAMPTZ,
    consumed_by UUID REFERENCES technicians(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS supervisor_invites_org_idx
    ON supervisor_invites(organization_id) WHERE consumed_at IS NULL;
