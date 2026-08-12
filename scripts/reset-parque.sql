-- Reduz o parque aos quatro dispositivos reais e apaga o histórico de chamados.
--
-- Por que existe: o pipeline de diagnóstico aprende com CASO FECHADO (§13.5).
-- Chamado de demonstração, sem device real por trás e sem desfecho verificado,
-- entraria no laço RAT como rótulo — e rótulo falso é o erro mais caro deste
-- projeto. Apagar não é limpeza cosmética: é impedir que dado inventado vire
-- treino.
--
-- IRREVERSÍVEL. Exige backup feito antes (scripts/backup-prod.sh).
--
-- Os quatro que ficam são os que têm agente vivo e reportando:
--   DESKTOP-JE50P4E (Daniel) · DESKTOP-U95MT6E (Arthur) · Dani · wpp-crm-server

BEGIN;

CREATE TEMP TABLE manter AS
SELECT id FROM devices
WHERE hostname IN ('DESKTOP-JE50P4E', 'DESKTOP-U95MT6E', 'Dani', 'wpp-crm-server');

-- Trava de segurança: se os quatro não estiverem lá, algo mudou desde que este
-- script foi escrito, e apagar às cegas seria pior que não rodar.
DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM manter;
    IF n <> 4 THEN
        RAISE EXCEPTION 'esperava 4 dispositivos a manter, encontrei %. Abortado.', n;
    END IF;
END $$;

-- 1. Chamados e tudo que pende deles. Ordem por dependência, do folha para a
--    raiz — nenhuma linha órfã fica para trás.
DELETE FROM ticket_ratings;
DELETE FROM ticket_closure_confirmations;
DELETE FROM temporary_ticket_permissions;
DELETE FROM ticket_events;
DELETE FROM onsite_evidence;
DELETE FROM dispatch_offers;
DELETE FROM service_order_items;
DELETE FROM service_orders;
DELETE FROM support_tickets;

-- 2. Dossiê de diagnóstico dos dispositivos que vão sair. O dado de diagnóstico
--    é permanente por §7.4 — mas isso vale para dispositivo real. Dossiê de
--    máquina que nunca existiu não é histórico, é ruído.
DELETE FROM diagnostic_runs   WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM telemetry_snapshots WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM device_health_state WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM device_metric_rollup WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM device_update_queue WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM remote_access_consents WHERE device_id NOT IN (SELECT id FROM manter);

-- 3. Os dispositivos.
--
-- `keep_device_tgdevs_membership` impede que um dispositivo perca o vínculo com
-- a rede de sistema. A invariante está certa e continua valendo — só que ela
-- fala de dispositivo VIVO, e o CASCADE da remoção passa por ela por tabela
-- interposta. Suspender a trigger DENTRO desta transação é o escopo correto:
-- ou o bloco inteiro aplica, ou nada aplica, e a trigger volta nos dois casos.
ALTER TABLE device_networks DISABLE TRIGGER USER;
ALTER TABLE device_subnetworks DISABLE TRIGGER USER;

DELETE FROM device_networks    WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM device_subnetworks WHERE device_id NOT IN (SELECT id FROM manter);
DELETE FROM devices            WHERE id NOT IN (SELECT id FROM manter);

ALTER TABLE device_networks ENABLE TRIGGER USER;
ALTER TABLE device_subnetworks ENABLE TRIGGER USER;

COMMIT;

-- Verificação: é isto que tem que sobrar.
SELECT hostname, coalesce(display_name, '—') AS nome, role, state,
       coalesce(rustdesk_id, '—') AS rustdesk, last_seen_at
FROM devices ORDER BY hostname;

SELECT 'devices'        AS tabela, count(*) FROM devices
UNION ALL SELECT 'support_tickets', count(*) FROM support_tickets
UNION ALL SELECT 'service_orders',  count(*) FROM service_orders
UNION ALL SELECT 'ticket_events',   count(*) FROM ticket_events;
