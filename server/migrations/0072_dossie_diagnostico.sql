-- TGDesk: dossiê de diagnóstico probabilístico — esquema da escada.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §4 (modelo de dados), na parte
-- que sustenta o exame PROVOCADO: catálogo de status, execução da escada, série
-- por degrau, trava e diagnóstico. A telemetria contínua (exame de rotina) vem
-- na 0073; os parâmetros versionados, na 0074.
--
-- A razão de o esquema vir antes do corpus: as tabelas não dependem de QUAIS
-- status e estágios existirão, e sem elas nada pode ser gravado. Ver §0 do
-- ROADMAP-DIAGNOSTICO-NEURAL.md.
--
-- `diagnostic_runs` (0019) continua de pé por enquanto — é o que o menu de 30
-- testes ainda usa. Ela sai quando a escada substituir o menu (passo B2/B8), e
-- não ganha ponte nenhuma com o que está aqui: sem compatibilidade retroativa.

-- ---------------------------------------------------------------------------
-- negative_status — a espinha da ontologia (§4)
--
-- Catálogo FECHADO. Nasce vazio de propósito: quem o preenche é a derivação do
-- corpus (A3/A4) com revisão humana. Tabela cheia de chute agora é pior que
-- tabela vazia, porque chute vira rótulo de treino.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS negative_status (
    codigo TEXT PRIMARY KEY,
    descricao TEXT NOT NULL,
    -- métricas que produzem este status. Sinal que não está aqui não deveria
    -- estar sendo coletado (§13.6, poda).
    sinais JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- conjunto fechado de causas. É o domínio do softmax (§3) e o domínio do
    -- campo de fechamento de chamado (§10.3) — nunca texto livre.
    causas_candidatas JSONB NOT NULL DEFAULT '[]'::jsonb,
    testes_discriminantes JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- causas que este status NÃO consegue separar à distância. Aparecem na tela
    -- como lacuna declarada (§13.6) em vez de sumirem.
    limitacoes JSONB NOT NULL DEFAULT '[]'::jsonb,
    origem_corpus TEXT,
    revisado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    revisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Status não revisado não serve para diagnosticar. O motor filtra por aqui, e é
-- isso que impede rascunho de LLM de virar veredito sem passar por gente (§12.3).
CREATE INDEX IF NOT EXISTS idx_negative_status_revisado
    ON negative_status (revisado_por) WHERE revisado_por IS NOT NULL;

-- ---------------------------------------------------------------------------
-- stress_run — uma execução da escada unificada (§5)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stress_run (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    -- perfil VERSIONADO da escada. Duas execuções só são comparáveis se o
    -- perfil for o mesmo — por isso é dado, não código (§10.1, §18).
    perfil TEXT NOT NULL,
    perfil_versao INTEGER NOT NULL,
    degraus_planejados JSONB NOT NULL DEFAULT '[]'::jsonb,
    degrau_alcancado INTEGER,
    estado TEXT NOT NULL DEFAULT 'pre_voo'
        CHECK (estado IN ('pre_voo','executando','concluido','abortado','cancelado')),
    -- motivo obrigatório quando abortou: gate, teto de tempo, perda de contato.
    -- Aborto é RESULTADO, não erro (§5) — por isso tem campo próprio e não vive
    -- num `error TEXT` genérico.
    motivo_aborto TEXT,
    gates_aplicados JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- consentimento explícito é pré-condição de execução (§5, gates). Sem ele a
    -- escada não sai do pré-voo; o CHECK abaixo torna isso estrutural.
    consentimento_ref UUID,
    consentimento_em TIMESTAMPTZ,
    iniciado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    -- o que a escada estava tentando responder; opcional porque existe execução
    -- de validação pós-reparo, que não parte de status nenhum (§11.6).
    status_alvo TEXT REFERENCES negative_status(codigo) ON DELETE SET NULL,
    duracao_estimada_min INTEGER,
    duracao_estimada_max INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,

    CONSTRAINT stress_run_consentimento_antes_de_executar
        CHECK (estado = 'pre_voo' OR consentimento_ref IS NOT NULL),
    CONSTRAINT stress_run_aborto_tem_motivo
        CHECK (estado <> 'abortado' OR motivo_aborto IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_stress_run_device_time
    ON stress_run (device_id, created_at DESC);
-- Comparação antes × depois da mesma escada (§11.6) casa por perfil+versão.
CREATE INDEX IF NOT EXISTS idx_stress_run_perfil
    ON stress_run (device_id, perfil, perfil_versao, created_at DESC);

-- ---------------------------------------------------------------------------
-- stress_sample — a série bruta (§4, §5)
--
-- É a tabela que justifica o projeto inteiro: sem load_level no eixo X não
-- existe curva, e sem curva não existe limiar aprendível. Cresce rápido, e é
-- dado de treino — retenção permanente (§7.4).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stress_sample (
    run_id UUID NOT NULL REFERENCES stress_run(id) ON DELETE CASCADE,
    stage TEXT NOT NULL,
    -- percentual do teto medido no PRÓPRIO dispositivo (§5). Absoluto não
    -- compara máquinas desiguais.
    load_level SMALLINT NOT NULL CHECK (load_level BETWEEN 0 AND 100),
    t_ms INTEGER NOT NULL CHECK (t_ms >= 0),
    metrica TEXT NOT NULL,
    valor DOUBLE PRECISION NOT NULL,

    -- Idempotência exigida pelo contrato do agente (§5): reentrega após
    -- reconexão não pode duplicar amostra.
    PRIMARY KEY (run_id, stage, load_level, t_ms, metrica)
);

-- A leitura real é sempre "a curva desta execução, deste estágio, em ordem".
CREATE INDEX IF NOT EXISTS idx_stress_sample_curva
    ON stress_sample (run_id, stage, load_level, t_ms);

-- ---------------------------------------------------------------------------
-- stall_event — trava com origem dupla (§6)
--
-- Quem mede não pode ser quem trava. Por isso as duas origens são colunas
-- separadas e a duração conciliada é uma TERCEIRA coluna: em nenhum momento se
-- sobrescreve o que cada lado viu.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stall_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    -- nulo quando a trava aconteceu fora de escada (uso normal) — que é
    -- justamente o caso que dispara alerta ao cliente (§9).
    run_id UUID REFERENCES stress_run(id) ON DELETE CASCADE,
    inicio TIMESTAMPTZ NOT NULL,
    fim TIMESTAMPTZ,
    -- buraco de heartbeat visto pelo servidor: a verdade sobre início e duração.
    server_gap_ms INTEGER,
    -- ring buffer do agente, despejado DEPOIS do evento: contexto, não relógio.
    agent_ts JSONB,
    duracao_conciliada_ms INTEGER,
    confianca TEXT NOT NULL DEFAULT 'media'
        CHECK (confianca IN ('alta','media','baixa')),
    -- relógio local correu normal durante o buraco ⇒ foi rede, não trava (§6).
    -- Sem esta distinção, toda queda de link viraria falso positivo.
    origem TEXT NOT NULL DEFAULT 'trava'
        CHECK (origem IN ('trava','rede','indeterminado')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stall_event_device_time
    ON stall_event (device_id, inicio DESC);
-- "travou N vezes em 7 dias" (§9, §10.5.1) é contagem de travas de verdade.
CREATE INDEX IF NOT EXISTS idx_stall_event_reais
    ON stall_event (device_id, inicio DESC) WHERE origem = 'trava';

-- ---------------------------------------------------------------------------
-- stage_duration_stat — base da previsão de duração (§10.2)
--
-- Regressão simples sobre execuções anteriores, não rede. `n` existe para a
-- tela poder dizer "estimativa grosseira" em vez de esconder a incerteza.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stage_duration_stat (
    classe_dispositivo TEXT NOT NULL,
    estagio TEXT NOT NULL,
    p50_ms INTEGER NOT NULL,
    p90_ms INTEGER NOT NULL,
    n INTEGER NOT NULL DEFAULT 0,
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (classe_dispositivo, estagio)
);

-- ---------------------------------------------------------------------------
-- diagnosis — a saída do motor (§4)
--
-- Uma linha por diagnóstico, provocado (run_id) OU passivo (telemetry_window).
-- Nunca os dois, nunca nenhum: diagnóstico sem base é diagnóstico inventado.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS diagnosis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    run_id UUID REFERENCES stress_run(id) ON DELETE CASCADE,
    telemetry_window TSTZRANGE,
    status_codigo TEXT REFERENCES negative_status(codigo) ON DELETE SET NULL,
    -- top-3 com probabilidade e faixa. Máximo de 3 é regra de produto (§1),
    -- garantida pelo CHECK: lista longa é o jeito de não decidir nada.
    causas JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- abstenção é resposta de primeira classe (§10.7), não erro.
    abstain BOOLEAN NOT NULL DEFAULT false,
    proximos_testes JSONB NOT NULL DEFAULT '[]'::jsonb,
    motor TEXT NOT NULL CHECK (motor IN ('regra','modelo')),
    -- FK preenchida quando motor='modelo': diagnóstico não auditável
    -- retroativamente não deveria ter sido mostrado (§14.5).
    versao_modelo TEXT,
    nivel_alerta TEXT NOT NULL DEFAULT 'nenhum'
        CHECK (nivel_alerta IN ('nenhum','1','2')),
    -- rótulo de recidiva, preenchido depois pela telemetria (§13.5). NULL
    -- significa "janela ainda aberta", não "não houve".
    recidiva_7d BOOLEAN,
    recidiva_30d BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT diagnosis_tem_exatamente_uma_base
        CHECK ((run_id IS NOT NULL) <> (telemetry_window IS NOT NULL)),
    -- Faixa vazia NÃO é nula: sem esta linha, um diagnóstico "passivo" com
    -- janela vazia passaria no XOR acima e seria gravado sem base nenhuma.
    CONSTRAINT diagnosis_janela_nao_vazia
        CHECK (telemetry_window IS NULL OR NOT isempty(telemetry_window)),
    CONSTRAINT diagnosis_no_maximo_tres_causas
        CHECK (jsonb_array_length(causas) <= 3),
    -- Abstenção sem direção é abstenção inútil (§10.5.1).
    CONSTRAINT diagnosis_abstencao_tem_direcao
        CHECK (NOT abstain OR jsonb_array_length(proximos_testes) > 0)
);

CREATE INDEX IF NOT EXISTS idx_diagnosis_device_time
    ON diagnosis (device_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_diagnosis_run
    ON diagnosis (run_id) WHERE run_id IS NOT NULL;
-- Janela de recidiva ainda aberta: é o que o job de rotulagem varre (§13.5).
CREATE INDEX IF NOT EXISTS idx_diagnosis_recidiva_pendente
    ON diagnosis (created_at) WHERE recidiva_30d IS NULL;
