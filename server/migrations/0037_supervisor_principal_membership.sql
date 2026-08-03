-- TGDesk v1.1.12: supervisor pode ocupar Principal ou Supervisores.
CREATE OR REPLACE FUNCTION reconcile_device_tgdevs_membership()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE required_network UUID;
BEGIN
    IF EXISTS(
        SELECT 1 FROM device_networks dn JOIN networks n ON n.id=dn.network_id
        WHERE dn.device_id=NEW.id AND n.system_key IS NOT NULL
    ) THEN
        RETURN NEW;
    END IF;
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
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION sync_control_technician_tgdevs_assignment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_device UUID;
DECLARE target_network UUID;
DECLARE target_technician UUID;
BEGIN
    target_device := CASE WHEN TG_OP='DELETE' THEN OLD.device_id ELSE NEW.device_id END;
    target_network := CASE WHEN TG_OP='DELETE' THEN OLD.network_id ELSE NEW.network_id END;
    SELECT d.control_technician_id INTO target_technician FROM devices d WHERE d.id=target_device;
    IF target_technician IS NULL OR NOT EXISTS(
        SELECT 1 FROM networks WHERE id=target_network AND system_key IS NOT NULL
    ) THEN
        RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    END IF;
    IF TG_OP='INSERT' THEN
        INSERT INTO technician_assignments(
            technician_id,network_id,assignment_scope,permissions_level)
        SELECT target_technician,target_network,'network','full'
        WHERE NOT EXISTS(
            SELECT 1 FROM technician_assignments
            WHERE technician_id=target_technician AND network_id=target_network
        );
    ELSE
        DELETE FROM technician_assignments ta
        WHERE ta.technician_id=target_technician AND ta.network_id=target_network
          AND NOT EXISTS(
              SELECT 1 FROM devices d JOIN device_networks dn ON dn.device_id=d.id
              WHERE d.control_technician_id=target_technician
                AND dn.network_id=target_network
          );
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS sync_control_technician_tgdevs_assignment_trigger ON device_networks;
CREATE TRIGGER sync_control_technician_tgdevs_assignment_trigger
AFTER INSERT OR DELETE ON device_networks
FOR EACH ROW EXECUTE FUNCTION sync_control_technician_tgdevs_assignment();
