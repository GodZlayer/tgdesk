-- TGDesk: regra obrigat?ria de regi?o din?mica por munic?pio.
-- Todo munic?pio brasileiro passa a pertencer a uma regi?o comercial padr?o
-- baseada na Regi?o Geogr?fica Imediata do IBGE. Regi?es metropolitanas e
-- capitais entram como camadas adicionais, mas o pre?o din?mico usa uma
-- regi?o resolvida e congelada no chamado.

ALTER TABLE organizations
    ADD COLUMN IF NOT EXISTS municipality_id INTEGER REFERENCES brazil_municipalities(ibge_id) ON DELETE SET NULL;
ALTER TABLE devices
    ADD COLUMN IF NOT EXISTS municipality_id INTEGER REFERENCES brazil_municipalities(ibge_id) ON DELETE SET NULL;
ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS municipality_id INTEGER REFERENCES brazil_municipalities(ibge_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS organizations_municipality_idx
    ON organizations(municipality_id) WHERE municipality_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS devices_municipality_idx
    ON devices(municipality_id) WHERE municipality_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS support_tickets_municipality_idx
    ON support_tickets(municipality_id) WHERE municipality_id IS NOT NULL;

ALTER TABLE region_municipalities
    DROP CONSTRAINT IF EXISTS region_municipalities_relation_kind_check;
ALTER TABLE region_municipalities
    ADD CONSTRAINT region_municipalities_relation_kind_check
    CHECK (relation_kind IN ('commercial','local','immediate','metropolitan','capital','manual'));

CREATE TABLE IF NOT EXISTS brazil_capitals (
    municipality_id INTEGER PRIMARY KEY REFERENCES brazil_municipalities(ibge_id) ON DELETE CASCADE,
    name TEXT NOT NULL
);

INSERT INTO brazil_capitals(municipality_id,name) VALUES
    (1100205,'Porto Velho'),
    (1200401,'Rio Branco'),
    (1302603,'Manaus'),
    (1400100,'Boa Vista'),
    (1501402,'Bel?m'),
    (1600303,'Macap?'),
    (1702109,'Palmas'),
    (2111300,'S?o Lu?s'),
    (2211001,'Teresina'),
    (2304400,'Fortaleza'),
    (2408102,'Natal'),
    (2507507,'Jo?o Pessoa'),
    (2611606,'Recife'),
    (2704302,'Macei?'),
    (2800308,'Aracaju'),
    (2927408,'Salvador'),
    (3106200,'Belo Horizonte'),
    (3205309,'Vit?ria'),
    (3304557,'Rio de Janeiro'),
    (3550308,'S?o Paulo'),
    (4106902,'Curitiba'),
    (4205407,'Florian?polis'),
    (4314902,'Porto Alegre'),
    (5002704,'Campo Grande'),
    (5103403,'Cuiab?'),
    (5208707,'Goi?nia'),
    (5300108,'Bras?lia')
ON CONFLICT (municipality_id) DO UPDATE SET name=excluded.name;

INSERT INTO regions(key,label,position,active)
SELECT 'ibge_immediate_' || immediate_region_id,
       'Regi?o de ' || immediate_region_name,
       2000 + row_number() OVER (ORDER BY immediate_region_name),
       true
FROM (SELECT DISTINCT immediate_region_id, immediate_region_name FROM brazil_municipalities) r
ON CONFLICT(key) DO UPDATE SET
    label=excluded.label,
    position=excluded.position,
    active=true,
    updated_at=now();

INSERT INTO region_municipalities(region_id,municipality_id,relation_kind)
SELECT r.id, m.ibge_id, 'immediate'
FROM brazil_municipalities m
JOIN regions r ON r.key = 'ibge_immediate_' || m.immediate_region_id
ON CONFLICT (region_id,municipality_id,relation_kind) DO NOTHING;

INSERT INTO regions(key,label,position,active)
SELECT 'ibge_metro_' || ibge_id,
       name,
       1000 + row_number() OVER (ORDER BY name),
       true
FROM brazil_metropolitan_areas
ON CONFLICT(key) DO UPDATE SET
    label=excluded.label,
    position=excluded.position,
    active=true,
    updated_at=now();

INSERT INTO region_municipalities(region_id,municipality_id,relation_kind)
SELECT r.id, mm.municipality_id, 'metropolitan'
FROM brazil_metropolitan_area_municipalities mm
JOIN regions r ON r.key = 'ibge_metro_' || mm.metropolitan_area_id
ON CONFLICT (region_id,municipality_id,relation_kind) DO NOTHING;

INSERT INTO regions(key,label,position,active)
SELECT 'capital_' || lower(m.uf_sigla),
       'Capital ' || m.name || ' - ' || m.uf_sigla,
       500 + row_number() OVER (ORDER BY m.uf_sigla),
       true
FROM brazil_capitals c
JOIN brazil_municipalities m ON m.ibge_id=c.municipality_id
ON CONFLICT(key) DO UPDATE SET
    label=excluded.label,
    position=excluded.position,
    active=true,
    updated_at=now();

INSERT INTO region_municipalities(region_id,municipality_id,relation_kind)
SELECT r.id, c.municipality_id, 'capital'
FROM brazil_capitals c
JOIN brazil_municipalities m ON m.ibge_id=c.municipality_id
JOIN regions r ON r.key = 'capital_' || lower(m.uf_sigla)
ON CONFLICT (region_id,municipality_id,relation_kind) DO NOTHING;

-- Exemplo comercial citado: Manhumirim fica operacionalmente na regi?o de Manhua?u.
-- A regra geral imediata j? cobre esse agrupamento no IBGE, mas esta linha deixa
-- o v?nculo expl?cito e edit?vel como rela??o comercial.
INSERT INTO regions(key,label,position,active)
VALUES ('comercial_manhua?u_mg','Regi?o comercial de Manhua?u - MG',300,true)
ON CONFLICT(key) DO UPDATE SET label=excluded.label, position=excluded.position, active=true, updated_at=now();

INSERT INTO region_municipalities(region_id,municipality_id,relation_kind)
SELECT r.id, m.ibge_id, 'commercial'
FROM regions r
JOIN brazil_municipalities m ON m.uf_sigla='MG' AND m.immediate_region_name='Manhua?u'
WHERE r.key='comercial_manhua?u_mg'
ON CONFLICT (region_id,municipality_id,relation_kind) DO NOTHING;


UPDATE organizations o
SET region_id = (
    SELECT rm.region_id
    FROM region_municipalities rm
    JOIN regions r ON r.id=rm.region_id AND r.active
    WHERE rm.municipality_id=o.municipality_id
    ORDER BY CASE rm.relation_kind
        WHEN 'commercial' THEN 10 WHEN 'local' THEN 20 WHEN 'immediate' THEN 30
        WHEN 'metropolitan' THEN 40 WHEN 'capital' THEN 50 ELSE 100 END,
        r.position, r.label
    LIMIT 1
)
WHERE o.municipality_id IS NOT NULL AND o.region_id IS NULL;

UPDATE devices d
SET region_id = (
    SELECT rm.region_id
    FROM region_municipalities rm
    JOIN regions r ON r.id=rm.region_id AND r.active
    WHERE rm.municipality_id=d.municipality_id
    ORDER BY CASE rm.relation_kind
        WHEN 'commercial' THEN 10 WHEN 'local' THEN 20 WHEN 'immediate' THEN 30
        WHEN 'metropolitan' THEN 40 WHEN 'capital' THEN 50 ELSE 100 END,
        r.position, r.label
    LIMIT 1
)
WHERE d.municipality_id IS NOT NULL AND d.region_id IS NULL;

UPDATE support_tickets t
SET region_id = (
    SELECT rm.region_id
    FROM region_municipalities rm
    JOIN regions r ON r.id=rm.region_id AND r.active
    WHERE rm.municipality_id=t.municipality_id
    ORDER BY CASE rm.relation_kind
        WHEN 'commercial' THEN 10 WHEN 'local' THEN 20 WHEN 'immediate' THEN 30
        WHEN 'metropolitan' THEN 40 WHEN 'capital' THEN 50 ELSE 100 END,
        r.position, r.label
    LIMIT 1
)
WHERE t.municipality_id IS NOT NULL AND t.region_id IS NULL;
