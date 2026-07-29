ALTER TABLE technicians
    ADD COLUMN branding_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN brand_name TEXT NOT NULL DEFAULT '',
    ADD COLUMN brand_logo_file TEXT NOT NULL DEFAULT '',
    ADD COLUMN branding_updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

