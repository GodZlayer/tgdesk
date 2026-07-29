ALTER TABLE devices
    DROP CONSTRAINT IF EXISTS devices_suspension_scope_check;

ALTER TABLE devices
    ADD CONSTRAINT devices_suspension_scope_check
    CHECK (suspension_scope IN ('device', 'network', 'organization', 'technician'));

ALTER TABLE networks
    DROP CONSTRAINT IF EXISTS networks_suspension_scope_check;

ALTER TABLE networks
    ADD CONSTRAINT networks_suspension_scope_check
    CHECK (suspension_scope IN ('network', 'organization', 'technician'));

ALTER TABLE organizations
    ADD COLUMN IF NOT EXISTS suspension_scope TEXT;

UPDATE organizations
SET suspension_scope='organization'
WHERE status='suspensa' AND suspension_scope IS NULL;

ALTER TABLE organizations
    DROP CONSTRAINT IF EXISTS organizations_suspension_scope_check;

ALTER TABLE organizations
    ADD CONSTRAINT organizations_suspension_scope_check
    CHECK (suspension_scope IN ('organization', 'technician'));
