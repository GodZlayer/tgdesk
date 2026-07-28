-- v2.5 hardcut: o snapshot físico substitui métricas agregadas por partição.
ALTER TABLE telemetry_snapshots
    ADD COLUMN IF NOT EXISTS hardware JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_telemetry_hardware_gin
    ON telemetry_snapshots USING GIN (hardware);

ALTER TABLE telemetry_snapshots
    DROP COLUMN IF EXISTS cpu,
    DROP COLUMN IF EXISTS mem,
    DROP COLUMN IF EXISTS disco,
    DROP COLUMN IF EXISTS temp,
    DROP COLUMN IF EXISTS disks;
