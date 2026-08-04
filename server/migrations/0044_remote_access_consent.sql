-- TGDesk: acesso remoto passa a exigir consentimento do cliente, pedido e
-- registrado dentro do chat do chamado.
--
-- O aviso NÃO é um portão de autorização. No empresarial o acesso já é
-- consentido — o supervisor é o responsável pelos dispositivos da sua rede e
-- acessa sem confirmação do cliente (MODELO-PRODUTO.md, "Objetivo do acesso
-- remoto"). O que o chat resolve é outra coisa: que o acesso não aconteça
-- enquanto o cliente está usando o computador, e que ele tenha noção de que
-- está sendo acessado.
--
-- Por isso quem assume o chamado continua recebendo allow_remote; o registro
-- aqui é do aviso e da ciência do cliente, não de uma permissão que precise
-- ser conquistada.
--
-- O ciclo fecha no encerramento do chamado/OS, não por prazo — um atendimento
-- pode legitimamente levar dias.

CREATE TABLE IF NOT EXISTS remote_access_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    technician_id UUID NOT NULL REFERENCES technicians(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','granted','denied','revoked')),
    motivo TEXT NOT NULL DEFAULT '',
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS remote_access_consents_ticket_idx
    ON remote_access_consents(ticket_id, status);

-- Um único pedido pendente por (chamado, técnico): clicar de novo reaproveita
-- o pedido em aberto em vez de encher o chat do cliente.
CREATE UNIQUE INDEX IF NOT EXISTS remote_access_consents_um_pendente
    ON remote_access_consents(ticket_id, technician_id)
    WHERE status = 'pending';

-- Nada a revogar: permissões existentes seguem valendo. O aviso é adicional,
-- não substitui o acesso já concedido a quem assumiu o chamado.
