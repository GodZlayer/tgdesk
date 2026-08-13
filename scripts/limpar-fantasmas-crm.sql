BEGIN;

CREATE TEMP TABLE fantasmas AS
SELECT id FROM devices
WHERE hostname = 'wpp-crm-server' AND state = 'guest'
  AND wg_virtual_ip IS NULL
  AND NOT EXISTS (SELECT 1 FROM telemetry_snapshots t WHERE t.device_id = devices.id)
  AND NOT EXISTS (SELECT 1 FROM support_tickets s WHERE s.device_id = devices.id);

-- Trava: o dispositivo REAL do CRM (ativo, com IP) não pode entrar aqui.
DO $$
DECLARE n INT;
BEGIN
    SELECT count(*) INTO n FROM fantasmas f
    JOIN devices d ON d.id = f.id
    WHERE d.state <> 'guest' OR d.wg_virtual_ip IS NOT NULL;
    IF n > 0 THEN
        RAISE EXCEPTION 'seleção alcançou % dispositivo(s) em uso. Abortado.', n;
    END IF;
END $$;

ALTER TABLE device_networks DISABLE TRIGGER USER;
ALTER TABLE device_subnetworks DISABLE TRIGGER USER;

DELETE FROM device_networks    WHERE device_id IN (SELECT id FROM fantasmas);
DELETE FROM device_subnetworks WHERE device_id IN (SELECT id FROM fantasmas);
DELETE FROM devices            WHERE id IN (SELECT id FROM fantasmas);

ALTER TABLE device_networks ENABLE TRIGGER USER;
ALTER TABLE device_subnetworks ENABLE TRIGGER USER;

COMMIT;

SELECT hostname, state, coalesce(wg_virtual_ip,'—') ip, coalesce(mac,'—') mac
FROM devices ORDER BY hostname;
