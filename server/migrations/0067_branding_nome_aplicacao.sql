-- TGDesk: o supervisor escolhe a composição do nome da aplicação da marca.
-- brand_name é a marca base. brand_name_mode define como ela aparece nos
-- atalhos/aplicação dos clientes vinculados.

ALTER TABLE technicians
    ADD COLUMN IF NOT EXISTS brand_name_mode TEXT NOT NULL DEFAULT 'brand_only'
        CHECK (brand_name_mode IN ('brand_only','brand_suffix','suffix_brand','brand_dash_suffix','brand_space_suffix')),
    ADD COLUMN IF NOT EXISTS brand_name_suffix TEXT NOT NULL DEFAULT '';

