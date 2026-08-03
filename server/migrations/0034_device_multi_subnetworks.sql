CREATE TABLE IF NOT EXISTS device_subnetworks (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    subnetwork_id UUID NOT NULL REFERENCES subnetworks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, subnetwork_id)
);

CREATE INDEX IF NOT EXISTS idx_device_subnetworks_subnetwork
    ON device_subnetworks(subnetwork_id, device_id);

INSERT INTO device_subnetworks(device_id, subnetwork_id)
SELECT id, subnetwork_id FROM devices WHERE subnetwork_id IS NOT NULL
ON CONFLICT DO NOTHING;
