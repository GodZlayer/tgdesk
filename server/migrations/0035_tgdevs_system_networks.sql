-- TGDesk v1.1.11: TGDevs e o plano de controle obrigatorio.
ALTER TABLE networks
    ADD COLUMN IF NOT EXISTS system_key TEXT,
    ADD COLUMN IF NOT EXISTS peer_isolation BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS networks_system_key_unique
    ON networks(system_key) WHERE system_key IS NOT NULL;

WITH tgdevs AS (
    INSERT INTO organizations(name,status)
    VALUES ('TGDevs','ativa')
    ON CONFLICT (name) DO UPDATE SET status='ativa'
    RETURNING id
)
INSERT INTO networks(organization_id,name,status,system_key,peer_isolation)
SELECT id,v.name,'ativa',v.system_key,v.peer_isolation
FROM tgdevs
CROSS JOIN (VALUES
    ('Principal','tgdevs.principal',false),
    ('Supervisores','tgdevs.supervisores',true),
    ('Técnicos','tgdevs.tecnicos',true),
    ('Clientes avulsos','tgdevs.clientes_avulsos',true),
    ('Clientes','tgdevs.clientes',true)
) AS v(name,system_key,peer_isolation)
ON CONFLICT (organization_id,name) DO UPDATE
SET status='ativa',system_key=excluded.system_key,
    peer_isolation=excluded.peer_isolation;

INSERT INTO technician_assignments(
    technician_id,network_id,assignment_scope,permissions_level)
SELECT t.id,n.id,'network','full'
FROM technicians t
JOIN networks n ON n.system_key=CASE
    WHEN t.role='super_admin' THEN 'tgdevs.principal'
    WHEN t.role='supervisor' THEN 'tgdevs.supervisores'
    WHEN t.role IN ('tecnico','freelancer') THEN 'tgdevs.tecnicos'
    WHEN t.role='cliente_avulso' THEN 'tgdevs.clientes_avulsos'
    ELSE 'tgdevs.clientes'
END
WHERE NOT EXISTS (
    SELECT 1 FROM technician_assignments ta
    WHERE ta.technician_id=t.id AND ta.network_id=n.id
);

-- Todo dispositivo participa do plano de controle TGDevs sem perder os
-- vinculos de sua organizacao operacional.
INSERT INTO device_networks(device_id,network_id)
SELECT d.id,n.id
FROM devices d
LEFT JOIN technicians t ON t.id=d.control_technician_id
JOIN networks n ON n.system_key=CASE
    WHEN t.role='super_admin' THEN 'tgdevs.principal'
    WHEN t.role='supervisor' THEN 'tgdevs.supervisores'
    WHEN t.role IN ('tecnico','freelancer') THEN 'tgdevs.tecnicos'
    ELSE 'tgdevs.clientes'
END
ON CONFLICT (device_id,network_id) DO NOTHING;

-- Corrige vinculos antigos de dispositivos de controle em Principal.
DELETE FROM device_networks dn
USING devices d,technicians t,networks n
WHERE dn.device_id=d.id AND d.control_technician_id=t.id
  AND dn.network_id=n.id AND n.system_key='tgdevs.principal'
  AND t.role<>'super_admin';

CREATE OR REPLACE FUNCTION protect_tgdevs_system_networks()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' AND OLD.system_key IS NOT NULL THEN
        RAISE EXCEPTION 'rede de sistema TGDevs nao pode ser excluida';
    END IF;
    IF TG_OP='UPDATE' AND OLD.system_key IS NOT NULL AND (
        NEW.name IS DISTINCT FROM OLD.name OR
        NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
        NEW.status IS DISTINCT FROM OLD.status OR
        NEW.system_key IS DISTINCT FROM OLD.system_key OR
        NEW.peer_isolation IS DISTINCT FROM OLD.peer_isolation
    ) THEN
        RAISE EXCEPTION 'rede de sistema TGDevs nao pode ser editada';
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS protect_tgdevs_system_networks_trigger ON networks;
CREATE TRIGGER protect_tgdevs_system_networks_trigger
BEFORE UPDATE OR DELETE ON networks
FOR EACH ROW EXECUTE FUNCTION protect_tgdevs_system_networks();

CREATE OR REPLACE FUNCTION keep_device_tgdevs_membership()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM networks WHERE id=OLD.network_id AND system_key IS NOT NULL)
       AND NOT EXISTS(
           SELECT 1 FROM device_networks dn JOIN networks n ON n.id=dn.network_id
           WHERE dn.device_id=OLD.device_id AND dn.network_id<>OLD.network_id
             AND n.system_key IS NOT NULL
       ) THEN
        RAISE EXCEPTION 'vinculo obrigatorio do dispositivo com TGDevs';
    END IF;
    RETURN OLD;
END $$;

DROP TRIGGER IF EXISTS keep_device_tgdevs_membership_trigger ON device_networks;
CREATE TRIGGER keep_device_tgdevs_membership_trigger
BEFORE DELETE ON device_networks
FOR EACH ROW EXECUTE FUNCTION keep_device_tgdevs_membership();

CREATE OR REPLACE FUNCTION reconcile_device_tgdevs_membership()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE required_network UUID;
BEGIN
    SELECT n.id INTO required_network
    FROM networks n
    LEFT JOIN technicians t ON t.id=NEW.control_technician_id
    WHERE n.system_key=CASE
        WHEN t.role='super_admin' THEN 'tgdevs.principal'
        WHEN t.role='supervisor' THEN 'tgdevs.supervisores'
        WHEN t.role IN ('tecnico','freelancer') THEN 'tgdevs.tecnicos'
        ELSE 'tgdevs.clientes'
    END;
    INSERT INTO device_networks(device_id,network_id)
    VALUES(NEW.id,required_network) ON CONFLICT DO NOTHING;
    DELETE FROM device_networks dn USING networks n
    WHERE dn.network_id=n.id AND dn.device_id=NEW.id
      AND n.system_key IS NOT NULL AND dn.network_id<>required_network;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS reconcile_device_tgdevs_membership_trigger ON devices;
CREATE TRIGGER reconcile_device_tgdevs_membership_trigger
AFTER INSERT OR UPDATE OF control_technician_id ON devices
FOR EACH ROW EXECUTE FUNCTION reconcile_device_tgdevs_membership();
