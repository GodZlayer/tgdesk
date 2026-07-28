ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT
    CHECK (suspension_scope IN ('device', 'network', 'organization'));

ALTER TABLE networks
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT
    CHECK (suspension_scope IN ('network', 'organization'));

