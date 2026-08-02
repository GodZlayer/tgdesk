-- TGDesk 1.1.1: store the actual evidence artifact as well as its hash.
ALTER TABLE onsite_evidence
    ADD COLUMN IF NOT EXISTS storage_file TEXT NOT NULL DEFAULT '';
