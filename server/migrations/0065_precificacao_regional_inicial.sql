-- TGDesk: precifica??o inicial por regi?o via regra de tr?s.
-- Fontes usadas como proxy p?blico:
-- 1) IBGE PNAD Cont?nua 2024: rendimento domiciliar per capita por UF; Brasil=R$ 2.069, MA=R$ 1.077, DF=R$ 3.444.
-- 2) IBGE Cidades/PIB municipal: base territorial e econ?mica oficial.
-- 3) Pesquisa de mercado de assist?ncia t?cnica: faixas p?blicas de servi?os comuns; os valores abaixo s?o ponto inicial edit?vel.
-- F?rmula: pre?o_regi?o = pre?o_base_brasil * ?ndice_regional.
-- ?ndice_regional = clamp(0.72, 1.45, 0.65*(renda_uf/renda_brasil) + 0.35*ajuste_tipo_regi?o).
-- ajuste_tipo_regi?o: capital=1.12, metropolitana=1.08, commercial/local/immediate=1.00.

CREATE TABLE IF NOT EXISTS regional_cost_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_key TEXT NOT NULL UNIQUE,
    label TEXT NOT NULL,
    url TEXT NOT NULL DEFAULT '',
    reference_year INTEGER NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS uf_cost_living_index (
    uf_sigla TEXT PRIMARY KEY,
    per_capita_income_cents BIGINT NOT NULL CHECK (per_capita_income_cents > 0),
    national_income_cents BIGINT NOT NULL CHECK (national_income_cents > 0),
    income_ratio NUMERIC(8,4) GENERATED ALWAYS AS (per_capita_income_cents::numeric / national_income_cents::numeric) STORED,
    source_key TEXT NOT NULL REFERENCES regional_cost_sources(source_key) ON UPDATE CASCADE,
    reference_year INTEGER NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS region_cost_living_index (
    region_id UUID PRIMARY KEY REFERENCES regions(id) ON DELETE CASCADE,
    uf_sigla TEXT NOT NULL,
    relation_kind TEXT NOT NULL,
    per_capita_income_cents BIGINT NOT NULL,
    national_income_cents BIGINT NOT NULL,
    income_ratio NUMERIC(8,4) NOT NULL,
    locality_factor NUMERIC(8,4) NOT NULL DEFAULT 1,
    cost_index NUMERIC(8,4) NOT NULL,
    formula TEXT NOT NULL,
    source_key TEXT NOT NULL REFERENCES regional_cost_sources(source_key) ON UPDATE CASCADE,
    reference_year INTEGER NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_market_price_references (
    service_key TEXT PRIMARY KEY REFERENCES service_catalog(key) ON UPDATE CASCADE ON DELETE CASCADE,
    national_base_cents BIGINT NOT NULL CHECK (national_base_cents >= 0),
    min_observed_cents BIGINT,
    max_observed_cents BIGINT,
    source_note TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO regional_cost_sources(source_key,label,url,reference_year,note) VALUES
    ('ibge_pnad_income_uf_2024','IBGE PNAD Cont?nua - rendimento domiciliar per capita por UF 2024','https://agenciadenoticias.ibge.gov.br/agencia-sala-de-imprensa/2013-agencia-de-noticias/releases/42761-ibge-divulga-rendimento-domiciliar-per-capita-2024-para-brasil-e-unidades-da-federacao',2024,'Proxy p?blico para custo de vida/poder aquisitivo regional.'),
    ('ibge_pib_municipios_2023','IBGE Produto Interno Bruto dos Munic?pios 2023','https://www.ibge.gov.br/estatisticas/economicas/contas-nacionais/9088-produto-interno-bruto-dos-municipios.html',2023,'Refer?ncia econ?mica municipal para evolu??o futura do ?ndice.'),
    ('market_it_services_2025_2026','Pesquisa web de mercado de servi?os t?cnicos 2025-2026','',2026,'Faixas p?blicas encontradas para formata??o, limpeza, troca de SSD, diagn?stico, rede e manuten??o; ponto inicial edit?vel pelo admin.')
ON CONFLICT(source_key) DO UPDATE SET label=excluded.label,url=excluded.url,reference_year=excluded.reference_year,note=excluded.note,updated_at=now();

INSERT INTO uf_cost_living_index(uf_sigla,per_capita_income_cents,national_income_cents,source_key,reference_year) VALUES
    ('AC',134200,206900,'ibge_pnad_income_uf_2024',2024),
    ('AL',111000,206900,'ibge_pnad_income_uf_2024',2024),
    ('AM',137300,206900,'ibge_pnad_income_uf_2024',2024),
    ('AP',152700,206900,'ibge_pnad_income_uf_2024',2024),
    ('BA',117200,206900,'ibge_pnad_income_uf_2024',2024),
    ('CE',116600,206900,'ibge_pnad_income_uf_2024',2024),
    ('DF',344400,206900,'ibge_pnad_income_uf_2024',2024),
    ('ES',201700,206900,'ibge_pnad_income_uf_2024',2024),
    ('GO',203000,206900,'ibge_pnad_income_uf_2024',2024),
    ('MA',107700,206900,'ibge_pnad_income_uf_2024',2024),
    ('MG',199100,206900,'ibge_pnad_income_uf_2024',2024),
    ('MS',226900,206900,'ibge_pnad_income_uf_2024',2024),
    ('MT',211500,206900,'ibge_pnad_income_uf_2024',2024),
    ('PA',113900,206900,'ibge_pnad_income_uf_2024',2024),
    ('PB',128200,206900,'ibge_pnad_income_uf_2024',2024),
    ('PE',121800,206900,'ibge_pnad_income_uf_2024',2024),
    ('PI',132000,206900,'ibge_pnad_income_uf_2024',2024),
    ('PR',230400,206900,'ibge_pnad_income_uf_2024',2024),
    ('RJ',249200,206900,'ibge_pnad_income_uf_2024',2024),
    ('RN',152000,206900,'ibge_pnad_income_uf_2024',2024),
    ('RO',191500,206900,'ibge_pnad_income_uf_2024',2024),
    ('RR',191800,206900,'ibge_pnad_income_uf_2024',2024),
    ('RS',236700,206900,'ibge_pnad_income_uf_2024',2024),
    ('SC',258800,206900,'ibge_pnad_income_uf_2024',2024),
    ('SE',142500,206900,'ibge_pnad_income_uf_2024',2024),
    ('SP',266200,206900,'ibge_pnad_income_uf_2024',2024),
    ('TO',158100,206900,'ibge_pnad_income_uf_2024',2024)
ON CONFLICT(uf_sigla) DO UPDATE SET
    per_capita_income_cents=excluded.per_capita_income_cents,
    national_income_cents=excluded.national_income_cents,
    source_key=excluded.source_key,
    reference_year=excluded.reference_year,
    updated_at=now();

INSERT INTO service_market_price_references(service_key,national_base_cents,min_observed_cents,max_observed_cents,source_note) VALUES
    ('cftv_acesso_remoto',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_configurar_nvr_dvr',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_instalacao_camera',24000,15600,39600,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_instalacao_dvr_nvr',32000,20800,52800,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_manutencao_imagem',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_substituir_camera',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('cftv_troca_hd_gravador',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('dados_clonagem_disco',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('dados_recuperacao_basica',30000,19500,49500,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('energia_diagnostico_tomada',10000,6500,16500,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('energia_teste_nobreak',12000,7800,19800,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('energia_troca_bateria_nobreak',14000,9100,23100,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_diagnostico_bancada',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_diagnostico_intermitencia',26000,16900,42900,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_limpeza_preventiva',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_montagem_pc',26000,16900,42900,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_reparo_conector_dc',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_bateria_note',12000,7800,19800,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_cooler',14000,9100,23100,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_fonte',14000,9100,23100,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_memoria',9000,5850,14850,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_placa_mae',26000,16900,42900,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_processador',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_ssd_hd',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_teclado_note',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_troca_tela_note',26000,16900,42900,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('hardware_upgrade_pc',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('impressora_instalacao',13000,8450,21450,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('impressora_manutencao_fila',10000,6500,16500,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('impressora_rede_scan',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('periferico_instalacao_webcam',9000,5850,14850,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_configuracao_roteador',15000,9750,24750,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_crimpagem_ponto',8000,5200,13200,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_firewall_basico',26000,16900,42900,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_instalacao_rack',35000,22750,57750,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_mesh_wifi',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_passagem_cabo',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_patch_panel',30000,19500,49500,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_ponto_adicional',20000,13000,33000,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_site_survey_wifi',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('rede_vlan_basica',24000,15600,39600,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_antivirus_edr',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_atualizacao_bios',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_configuracao_backup',15000,9750,24750,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_diagnostico_profundo',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_dual_boot',24000,15600,39600,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_erp_certificado',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_formatacao_windows',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_instalacao_linux',17000,11050,28050,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_limpeza_temporarios',9000,5850,14850,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_migracao_perfil',22000,14300,36300,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_office_email',12000,7800,19800,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_otimizacao_inicializacao',14000,9100,23100,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_recuperacao_sistema',20000,13000,33000,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_reinstalacao_driver',10000,6500,16500,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_remocao_malware',18000,11700,29700,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_virtualizacao',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.'),
    ('software_vpn_acesso_remoto',16000,10400,26400,'Base nacional inicial por pesquisa de mercado; pre?o final usa ?ndice regional e pode ser editado.')
ON CONFLICT(service_key) DO UPDATE SET
    national_base_cents=excluded.national_base_cents,
    min_observed_cents=excluded.min_observed_cents,
    max_observed_cents=excluded.max_observed_cents,
    source_note=excluded.source_note,
    updated_at=now();

UPDATE service_catalog s
SET price_cents = r.national_base_cents,
    updated_at = now()
FROM service_market_price_references r
WHERE r.service_key=s.key AND s.price_cents=0;

INSERT INTO region_cost_living_index(region_id,uf_sigla,relation_kind,per_capita_income_cents,national_income_cents,income_ratio,locality_factor,cost_index,formula,source_key,reference_year)
SELECT DISTINCT ON (r.id)
    r.id,
    m.uf_sigla,
    rm.relation_kind,
    uf.per_capita_income_cents,
    uf.national_income_cents,
    uf.income_ratio,
    CASE rm.relation_kind
        WHEN 'capital' THEN 1.12
        WHEN 'metropolitan' THEN 1.08
        ELSE 1.00
    END AS locality_factor,
    LEAST(1.45, GREATEST(0.72,
        (0.65 * uf.income_ratio) +
        (0.35 * CASE rm.relation_kind WHEN 'capital' THEN 1.12 WHEN 'metropolitan' THEN 1.08 ELSE 1.00 END)
    )) AS cost_index,
    'clamp(0.72,1.45,0.65*(renda_uf/renda_brasil)+0.35*ajuste_tipo_regiao)' AS formula,
    'ibge_pnad_income_uf_2024',
    2024
FROM regions r
JOIN region_municipalities rm ON rm.region_id=r.id
JOIN brazil_municipalities m ON m.ibge_id=rm.municipality_id
JOIN uf_cost_living_index uf ON uf.uf_sigla=m.uf_sigla
ORDER BY r.id,
    CASE rm.relation_kind WHEN 'commercial' THEN 10 WHEN 'local' THEN 20 WHEN 'immediate' THEN 30 WHEN 'metropolitan' THEN 40 WHEN 'capital' THEN 50 ELSE 100 END
ON CONFLICT(region_id) DO UPDATE SET
    uf_sigla=excluded.uf_sigla,
    relation_kind=excluded.relation_kind,
    per_capita_income_cents=excluded.per_capita_income_cents,
    national_income_cents=excluded.national_income_cents,
    income_ratio=excluded.income_ratio,
    locality_factor=excluded.locality_factor,
    cost_index=excluded.cost_index,
    formula=excluded.formula,
    source_key=excluded.source_key,
    reference_year=excluded.reference_year,
    updated_at=now();

INSERT INTO pricing_rules(kind,ticket_type_key,min_cents,max_cents,note,active) VALUES
    ('bounds','atendimento_avulso_orientacao',8000,18000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','backup_dados',12000,35000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','backup_migracao_dados',12000,35000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','certificado_erp_email',12000,30000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','cftv_acesso_remoto',10000,28000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','cftv_camera',12000,38000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','cftv_gravador',15000,45000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','cftv_nvr_dvr',12000,40000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','computador',10000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','diagnostico_geral',8000,18000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','driver_firmware_bios',8000,22000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','energia_nobreak',9000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','energia_nobreak_bateria',9000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','energia_tomada_protecao',8000,22000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','hardware_desktop',12000,32000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','hardware_notebook',15000,38000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','impressao_perifericos',9000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','impressora_scanner',9000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','instalacao_postos_loja',20000,70000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','instalacao_programas',8000,18000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','lentidao_intermitente',10000,22000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','limpeza_termica',10000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','malware_seguranca',12000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','manutencao_hardware',12000,32000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','manutencao_preventiva_contrato',6000,18000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','manutencao_sistema_operacional',12000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','manutencao_software',10000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','perifericos_usb_audio_video',6000,18000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_cabeada_wifi',12000,36000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_cabeamento',12000,36000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_diagnostico',10000,28000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_rack_switch',18000,60000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_roteador_firewall',12000,35000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','rede_wifi',12000,32000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','troca_armazenamento',12000,30000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','troca_componente',8000,26000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','troca_fonte_energia_pc',8000,22000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','troca_memoria',6000,16000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true),
    ('bounds','troca_placa_processador',15000,45000,'Base nacional inicial pesquisada; valores regionais s?o gerados por ?ndice de custo de vida.',true)
ON CONFLICT DO NOTHING;

WITH base_bounds(ticket_type_key,min_cents,max_cents) AS (
    VALUES
    ('atendimento_avulso_orientacao',8000,18000),
    ('backup_dados',12000,35000),
    ('backup_migracao_dados',12000,35000),
    ('certificado_erp_email',12000,30000),
    ('cftv_acesso_remoto',10000,28000),
    ('cftv_camera',12000,38000),
    ('cftv_gravador',15000,45000),
    ('cftv_nvr_dvr',12000,40000),
    ('computador',10000,26000),
    ('diagnostico_geral',8000,18000),
    ('driver_firmware_bios',8000,22000),
    ('energia_nobreak',9000,26000),
    ('energia_nobreak_bateria',9000,26000),
    ('energia_tomada_protecao',8000,22000),
    ('hardware_desktop',12000,32000),
    ('hardware_notebook',15000,38000),
    ('impressao_perifericos',9000,26000),
    ('impressora_scanner',9000,26000),
    ('instalacao_postos_loja',20000,70000),
    ('instalacao_programas',8000,18000),
    ('lentidao_intermitente',10000,22000),
    ('limpeza_termica',10000,26000),
    ('malware_seguranca',12000,26000),
    ('manutencao_hardware',12000,32000),
    ('manutencao_preventiva_contrato',6000,18000),
    ('manutencao_sistema_operacional',12000,26000),
    ('manutencao_software',10000,26000),
    ('perifericos_usb_audio_video',6000,18000),
    ('rede_cabeada_wifi',12000,36000),
    ('rede_cabeamento',12000,36000),
    ('rede_diagnostico',10000,28000),
    ('rede_rack_switch',18000,60000),
    ('rede_roteador_firewall',12000,35000),
    ('rede_wifi',12000,32000),
    ('troca_armazenamento',12000,30000),
    ('troca_componente',8000,26000),
    ('troca_fonte_energia_pc',8000,22000),
    ('troca_memoria',6000,16000),
    ('troca_placa_processador',15000,45000)
)
INSERT INTO pricing_rules(kind,ticket_type_key,region_id,min_cents,max_cents,note,active)
SELECT
    'bounds',
    base.ticket_type_key,
    idx.region_id,
    GREATEST(5000, ROUND(base.min_cents * idx.cost_index / 100.0)::bigint * 100),
    GREATEST(8000, ROUND(base.max_cents * idx.cost_index / 100.0)::bigint * 100),
    'Inicial regional por regra de tr?s: base nacional * ?ndice regional de custo de vida IBGE. Edit?vel no admin.',
    true
FROM base_bounds base
CROSS JOIN region_cost_living_index idx
ON CONFLICT DO NOTHING;
