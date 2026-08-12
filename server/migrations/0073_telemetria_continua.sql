-- TGDesk: telemetria contínua em duas velocidades + assinaturas de log.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §7 (exame de rotina) e §8
-- (assinaturas). A 0072 cobriu o exame provocado; aqui é o que o servidor sabe
-- do computador SEM ter forçado nada — o que sustenta os alertas (§9) e
-- pré-carrega o dossiê antes de qualquer chamado.
--
-- `telemetry_snapshots` (0001/0009) continua sendo o snapshot de inventário e
-- não é tocada. O que nasce aqui é outra coisa: série com política de retenção,
-- privacidade declarada e rajada sob evento.

-- ---------------------------------------------------------------------------
-- telemetry_sample — camada contínua (§7.1)
--
-- Baixa frequência, sempre ligada. Agregados + top-N, nunca lista integral:
-- enviar tudo o tempo todo encheria o banco antes de virar inteligência.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS telemetry_sample (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    coletado_em TIMESTAMPTZ NOT NULL,
    -- agregados por recurso (cpu, ram, disco, rede, gpu, handles, uptime)
    agregados JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- top-N processos com nome NORMALIZADO contra catálogo (§7.2). Nome cru de
    -- executável revela o que a pessoa faz; desconhecido vira
    -- 'desconhecido:<hash>' antes de sair da máquina, não aqui.
    top_processos JSONB NOT NULL DEFAULT '[]'::jsonb,
    contadores_pressao JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- processo nasceu/morreu, serviço caiu, driver falhou. Evento não espera
    -- janela de lote (§7.1).
    eventos_mudanca JSONB NOT NULL DEFAULT '[]'::jsonb,
    PRIMARY KEY (device_id, coletado_em)
);

CREATE INDEX IF NOT EXISTS idx_telemetry_sample_janela
    ON telemetry_sample (coletado_em);

-- Agregado diário: é ele que sobrevive ao expurgo dos 90 dias (§7.4). A curva
-- longa da tela D nunca pode depender de dado que vai ser apagado.
CREATE TABLE IF NOT EXISTS telemetry_daily (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    dia DATE NOT NULL,
    metricas JSONB NOT NULL DEFAULT '{}'::jsonb,
    n_amostras INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, dia)
);

-- ---------------------------------------------------------------------------
-- incident_burst — rajada de alta resolução (§7.1, §7.2)
--
-- Recorte do ring buffer em volta do incidente. Retenção CURTA e expurgo
-- automático: aqui moram os campos que revelam o que a pessoa faz.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS incident_burst (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    gatilho TEXT NOT NULL CHECK (gatilho IN (
        'trava','pico_sustentado','reboot_inesperado','bugcheck',
        'queda_servico','abertura_chamado'
    )),
    stall_event_id UUID REFERENCES stall_event(id) ON DELETE SET NULL,
    -- recorte -60s/+30s do instante do gatilho (§7.1)
    janela TSTZRANGE NOT NULL,
    processos JSONB NOT NULL DEFAULT '[]'::jsonb,
    eventos_sistema JSONB NOT NULL DEFAULT '[]'::jsonb,
    contadores JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Campos sensíveis (linha de comando, título de janela, caminho de usuário)
    -- só existem com consentimento registrado. O CHECK torna isso estrutural:
    -- não há caminho de código capaz de gravar sensível sem referência de
    -- consentimento (§7.2).
    sensivel JSONB,
    consentimento_ref UUID,
    -- quando este registro deve deixar de existir. O job de expurgo lê daqui,
    -- não de constante em código (§7.4).
    expurgar_em TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT incident_burst_sensivel_exige_consentimento
        CHECK (sensivel IS NULL OR consentimento_ref IS NOT NULL),
    -- Mesma razão da diagnosis_janela_nao_vazia: rajada sem recorte é rajada
    -- que não recortou nada.
    CONSTRAINT incident_burst_janela_nao_vazia
        CHECK (NOT isempty(janela))
);

CREATE INDEX IF NOT EXISTS idx_incident_burst_device_time
    ON incident_burst (device_id, created_at DESC);
-- O job de expurgo varre por aqui. Retenção só é regra se for automática.
CREATE INDEX IF NOT EXISTS idx_incident_burst_expurgo
    ON incident_burst (expurgar_em);

-- Teto de 6 rajadas por dispositivo por dia (§7.1). O excedente é CONTADO, não
-- enviado: o gatilho que dispara sem parar já é o sintoma, e não precisa de
-- mais amostras para ser reconhecido.
CREATE TABLE IF NOT EXISTS incident_burst_quota (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    dia DATE NOT NULL,
    enviadas INTEGER NOT NULL DEFAULT 0,
    suprimidas INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, dia)
);

-- ---------------------------------------------------------------------------
-- log_signature — o que o corpus entrega de graça (§8)
--
-- A assinatura que um humano usou para decidir, junto com a conclusão a que ela
-- levou. Evidência de assinatura vale mais que métrica agregada porque é
-- literal e citável na tela de resultado.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS log_signature (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fonte TEXT NOT NULL CHECK (fonte IN (
        'event_log','driver','aplicativo','smart','dump'
    )),
    padrao TEXT NOT NULL,
    campos_extraidos JSONB NOT NULL DEFAULT '[]'::jsonb,
    status_implicado TEXT REFERENCES negative_status(codigo) ON DELETE CASCADE,
    causas_implicadas JSONB NOT NULL DEFAULT '[]'::jsonb,
    peso REAL NOT NULL DEFAULT 1.0,
    origem_corpus TEXT,
    -- Mesma regra dos templates: assinatura não revisada não vale (§8).
    revisado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    revisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- O casamento em runtime só considera assinatura revisada.
CREATE INDEX IF NOT EXISTS idx_log_signature_ativa
    ON log_signature (fonte) WHERE revisado_por IS NOT NULL;

-- Evidência nomeada que casou num dispositivo — entra no dossiê como citação,
-- nunca como texto solto.
CREATE TABLE IF NOT EXISTS log_signature_hit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    signature_id UUID NOT NULL REFERENCES log_signature(id) ON DELETE CASCADE,
    ocorrido_em TIMESTAMPTZ NOT NULL,
    -- a linha literal, já com os campos extraídos separados
    trecho TEXT NOT NULL,
    valores JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_log_signature_hit_device
    ON log_signature_hit (device_id, ocorrido_em DESC);
