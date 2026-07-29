ALTER TABLE organizations
    ADD COLUMN IF NOT EXISTS owner_technician_id UUID
    REFERENCES technicians(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS idx_organizations_one_per_technician
    ON organizations(owner_technician_id)
    WHERE owner_technician_id IS NOT NULL;

ALTER TABLE networks
    ADD COLUMN IF NOT EXISTS created_by_technician_id UUID
    REFERENCES technicians(id) ON DELETE SET NULL;

ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS control_technician_id UUID
    REFERENCES technicians(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS device_networks (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, network_id)
);

CREATE INDEX IF NOT EXISTS idx_device_networks_network
    ON device_networks(network_id, device_id);

INSERT INTO device_networks(device_id, network_id)
SELECT id, network_id FROM devices WHERE network_id IS NOT NULL
ON CONFLICT DO NOTHING;

DO $$
DECLARE
    tech RECORD;
    personal_org UUID;
    personal_name TEXT;
BEGIN
    FOR tech IN
        SELECT id, username FROM technicians WHERE role = 'tecnico'
    LOOP
        SELECT id INTO personal_org
        FROM organizations
        WHERE owner_technician_id = tech.id;

        IF personal_org IS NULL THEN
            SELECT id INTO personal_org
            FROM organizations
            WHERE name = tech.username AND owner_technician_id IS NULL;
        END IF;

        IF personal_org IS NOT NULL THEN
            UPDATE organizations
            SET owner_technician_id = tech.id
            WHERE id = personal_org;
        ELSE
            personal_name := tech.username;
            IF EXISTS (SELECT 1 FROM organizations WHERE name = personal_name) THEN
                personal_name := tech.username || ' - Técnico';
            END IF;
            INSERT INTO organizations(name, owner_technician_id)
            VALUES (personal_name, tech.id)
            RETURNING id INTO personal_org;
        END IF;

        INSERT INTO technician_assignments(technician_id, organization_id)
        SELECT tech.id, personal_org
        WHERE NOT EXISTS (
            SELECT 1 FROM technician_assignments
            WHERE technician_id = tech.id
              AND organization_id = personal_org
        );
    END LOOP;
END $$;

UPDATE networks n
SET created_by_technician_id = o.owner_technician_id
FROM organizations o
WHERE n.organization_id = o.id
  AND n.created_by_technician_id IS NULL
  AND o.owner_technician_id IS NOT NULL;
