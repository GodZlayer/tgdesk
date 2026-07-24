ALTER TABLE telemetry_snapshots
    ADD COLUMN IF NOT EXISTS disks JSONB NOT NULL DEFAULT '[]'::jsonb;
