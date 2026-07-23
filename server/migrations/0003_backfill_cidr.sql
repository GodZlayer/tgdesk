-- Backfill de redes criadas antes do trigger de alocação de CIDR (migration 0002).
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM networks WHERE cidr_octet IS NULL ORDER BY created_at LOOP
        UPDATE networks
        SET cidr_octet = nextval('network_cidr_octet_seq'),
            cidr_virtual = NULL
        WHERE id = r.id;
    END LOOP;

    UPDATE networks SET cidr_virtual = '10.70.' || cidr_octet || '.0/24' WHERE cidr_virtual IS NULL;
END $$;
