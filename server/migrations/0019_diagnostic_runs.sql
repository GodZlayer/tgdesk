CREATE TABLE IF NOT EXISTS diagnostic_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    requested_by UUID REFERENCES technicians(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued','running','completed','failed','cancelled')),
    tests JSONB NOT NULL DEFAULT '[]'::jsonb,
    progress INTEGER NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
    current_test TEXT,
    results JSONB NOT NULL DEFAULT '[]'::jsonb,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_diagnostic_runs_device_created
    ON diagnostic_runs (device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_diagnostic_runs_dispatch
    ON diagnostic_runs (device_id, status, created_at);
