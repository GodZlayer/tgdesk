-- TGDesk: grade percentual inicial da OS.
--
-- Estes percentuais são configuração, não fórmula fixa. A tela altera as
-- linhas; o servidor resolve por escopo e vigência. A soma padrão é 100% do
-- valor dos serviços. Peças e consumíveis entram como custo do cliente.

INSERT INTO pricing_rules(kind, role, percent, note, active)
VALUES
    ('share','technician',60,'Padrão: técnico recebe 60% do valor de serviços',true),
    ('share','supervisor',15,'Padrão: supervisor da OS recebe 15% do valor de serviços',true),
    ('share','tgdesk',20,'Padrão: TGDesk recebe 20% do valor de serviços',true),
    ('share','referrer_supervisor',5,'Padrão: supervisor indicador recebe 5% do valor de serviços',true)
ON CONFLICT DO NOTHING;

UPDATE part_catalog
SET item_kind='consumable', requires_invoice_photo=true
WHERE sku IN (
    'PASTA-TERMICA-G',
    'ALCOOL-ISOPROPILICO-ML',
    'CABO-UTP-CAT5E-M',
    'CABO-UTP-CAT6-M'
);
