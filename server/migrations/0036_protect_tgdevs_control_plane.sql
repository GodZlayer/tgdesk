-- TGDesk v1.1.11: fecha caminhos indiretos de alteracao do plano TGDevs.
CREATE OR REPLACE FUNCTION protect_tgdevs_organization()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF lower(OLD.name)='tgdevs' THEN
        IF TG_OP='DELETE' THEN
            RAISE EXCEPTION 'organizacao TGDevs nao pode ser excluida';
        END IF;
        IF NEW.name IS DISTINCT FROM OLD.name OR
           NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'organizacao TGDevs nao pode ser editada ou suspensa';
        END IF;
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS protect_tgdevs_organization_trigger ON organizations;
CREATE TRIGGER protect_tgdevs_organization_trigger
BEFORE UPDATE OR DELETE ON organizations
FOR EACH ROW EXECUTE FUNCTION protect_tgdevs_organization();

CREATE OR REPLACE FUNCTION assign_technician_tgdevs_network()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE required_network UUID;
BEGIN
    SELECT id INTO required_network FROM networks WHERE system_key=CASE
        WHEN NEW.role='super_admin' THEN 'tgdevs.principal'
        WHEN NEW.role='supervisor' THEN 'tgdevs.supervisores'
        WHEN NEW.role IN ('tecnico','freelancer') THEN 'tgdevs.tecnicos'
        WHEN NEW.role='cliente_avulso' THEN 'tgdevs.clientes_avulsos'
        ELSE 'tgdevs.clientes'
    END;
    IF required_network IS NOT NULL THEN
        INSERT INTO technician_assignments(
            technician_id,network_id,assignment_scope,permissions_level)
        SELECT NEW.id,required_network,'network','full'
        WHERE NOT EXISTS (
            SELECT 1 FROM technician_assignments
            WHERE technician_id=NEW.id AND network_id=required_network
        );
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS assign_technician_tgdevs_network_trigger ON technicians;
CREATE TRIGGER assign_technician_tgdevs_network_trigger
AFTER INSERT OR UPDATE OF role ON technicians
FOR EACH ROW EXECUTE FUNCTION assign_technician_tgdevs_network();
