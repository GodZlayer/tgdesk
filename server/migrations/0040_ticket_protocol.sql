-- TGDesk: número de protocolo do chamado.
--
-- A tela do cliente já exibia result['protocol'] desde sempre, mas nenhum
-- handler devolvia esse campo e nenhuma coluna o armazenava — a mensagem de
-- confirmação saía com o protocolo em branco. O UUID do ticket não serve para
-- o cliente ler ou ditar por telefone; o protocolo é o identificador humano.

CREATE SEQUENCE IF NOT EXISTS ticket_protocol_seq START 1;

ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS protocol TEXT;

-- Backfill em ordem de criação, para que protocolos antigos fiquem coerentes
-- com a cronologia dos chamados.
UPDATE support_tickets t
SET protocol='TG'||lpad(ordered.seq::text,6,'0')
FROM (
    SELECT id, row_number() OVER (ORDER BY created_at, id) AS seq
    FROM support_tickets WHERE protocol IS NULL
) ordered
WHERE t.id=ordered.id AND t.protocol IS NULL;

SELECT setval('ticket_protocol_seq',
    GREATEST((SELECT count(*) FROM support_tickets), 1));

ALTER TABLE support_tickets
    ALTER COLUMN protocol SET DEFAULT 'TG'||lpad(nextval('ticket_protocol_seq')::text,6,'0');

UPDATE support_tickets SET protocol='TG'||lpad(nextval('ticket_protocol_seq')::text,6,'0')
WHERE protocol IS NULL;

ALTER TABLE support_tickets
    ALTER COLUMN protocol SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS support_tickets_protocol_unique
    ON support_tickets(protocol);

-- Dedupe do pedido do cliente: o leigo clicando duas vezes não pode gerar dois
-- chamados para a mesma máquina. Estados terminais ficam de fora, para que ele
-- possa pedir de novo depois de encerrado.
--
-- A chave é opened_by_device_id, não device_id: o escopo é "pedido aberto PELO
-- dispositivo". Usar device_id bloquearia o supervisor de criar um chamado com
-- esse mesmo dispositivo como alvo (MODELO-PRODUTO.md, "Origem 3"), que é um
-- fluxo legítimo e independente.
--
-- Fecha duplicatas preexistentes antes de criar o índice, mantendo a mais
-- recente de cada dispositivo — senão a migration falha em bases que já têm
-- mais de um pedido aberto.
WITH ranked AS (
    SELECT id, row_number() OVER (
        PARTITION BY opened_by_device_id ORDER BY created_at DESC, id DESC) AS rn
    FROM support_tickets
    WHERE opened_by_device_id IS NOT NULL
      AND status NOT IN ('closed','cancelled','expired')
)
UPDATE support_tickets t
SET status='cancelled', updated_at=now()
FROM ranked WHERE t.id=ranked.id AND ranked.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS support_tickets_one_open_per_device
    ON support_tickets(opened_by_device_id)
    WHERE opened_by_device_id IS NOT NULL
      AND status NOT IN ('closed','cancelled','expired');
