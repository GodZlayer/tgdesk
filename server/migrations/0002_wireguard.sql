-- TGDesk Fase 1 — alocação de IP virtual por rede (wg-orchestrator)

CREATE SEQUENCE network_cidr_octet_seq START 2; -- .0 e .1 reservados (rede/hub)

ALTER TABLE networks ADD COLUMN cidr_octet INTEGER UNIQUE;
ALTER TABLE networks ADD COLUMN next_host_octet INTEGER NOT NULL DEFAULT 2;

CREATE OR REPLACE FUNCTION assign_network_cidr() RETURNS trigger AS $$
BEGIN
    IF NEW.cidr_octet IS NULL THEN
        NEW.cidr_octet := nextval('network_cidr_octet_seq');
    END IF;
    IF NEW.cidr_virtual IS NULL THEN
        NEW.cidr_virtual := '10.70.' || NEW.cidr_octet || '.0/24';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assign_network_cidr
    BEFORE INSERT ON networks
    FOR EACH ROW EXECUTE FUNCTION assign_network_cidr();

ALTER TABLE devices ADD COLUMN wg_virtual_ip TEXT;
