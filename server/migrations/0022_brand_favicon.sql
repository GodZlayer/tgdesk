ALTER TABLE technicians
    ADD COLUMN IF NOT EXISTS brand_favicon_file TEXT NOT NULL DEFAULT '';
