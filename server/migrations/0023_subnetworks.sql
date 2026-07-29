CREATE TABLE IF NOT EXISTS subnetworks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ativa' CHECK (status IN ('ativa', 'suspensa')),
    created_by_technician_id UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (network_id, name)
);

CREATE INDEX IF NOT EXISTS idx_subnetworks_network
    ON subnetworks(network_id, created_at);

ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS subnetwork_id UUID
    REFERENCES subnetworks(id) ON DELETE SET NULL;

INSERT INTO subnetworks(network_id, name, created_by_technician_id)
SELECT n.id, 'Principal', n.created_by_technician_id
FROM networks n
ON CONFLICT (network_id, name) DO NOTHING;

UPDATE devices d
SET subnetwork_id = s.id
FROM subnetworks s
WHERE d.network_id = s.network_id
  AND s.name = 'Principal'
  AND d.subnetwork_id IS NULL;
