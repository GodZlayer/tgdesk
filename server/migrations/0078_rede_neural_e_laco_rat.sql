-- TGDesk: rede neural, versionamento de modelo e o laço RAT × suposição.
--
-- Fecha três buracos que impediam o pipeline de rodar ponta a ponta:
--
--  1. REVISÃO AUTOMATIZADA. A arquitetura exige que nada valha sem revisão
--     (§8, §12.3), e o esquema modelou isso como `revisado_por UUID ->
--     technicians`. Isso admite exatamente um tipo de revisor: uma pessoa. A
--     derivação do corpus produz milhares de linhas, e forjar um técnico para
--     assiná-las destruiria a única coisa que a coluna serve para responder —
--     QUEM aprovou. A saída é declarar o segundo tipo de revisor em vez de
--     disfarçá-lo: `revisado_por_automacao` guarda a procedência da derivação,
--     e a linha passa a ser servível por qualquer um dos dois caminhos. Fica
--     consultável para sempre o que humano aprovou e o que a máquina derivou.
--
--  2. `model_version` (§14.5). Sem ela, `diagnosis` não pode apontar para o
--     modelo que a produziu, e diagnóstico não auditável retroativamente não
--     deveria ter sido mostrado (§17).
--
--  3. O LAÇO RAT × SUPOSIÇÃO (§19.4). Era a única parte da cadeia que não
--     existia em lugar nenhum. É o que faz o aprendizado continuar depois do
--     treino inicial, e o que produz a calibração medida em campo.

-- ---------------------------------------------------------------------------
-- 1. Revisão automatizada, declarada
-- ---------------------------------------------------------------------------

ALTER TABLE negative_status ADD COLUMN IF NOT EXISTS revisado_por_automacao TEXT;
ALTER TABLE text_template   ADD COLUMN IF NOT EXISTS revisado_por_automacao TEXT;
ALTER TABLE log_signature   ADD COLUMN IF NOT EXISTS revisado_por_automacao TEXT;

-- Servível = revisado por gente OU derivado por automação identificada.
-- Rascunho sem nenhum dos dois continua não sendo servido, que é a regra
-- original e não muda.
DROP INDEX IF EXISTS idx_text_template_servivel;
CREATE INDEX idx_text_template_servivel
    ON text_template (chave, idioma, nivel, versao DESC)
    WHERE revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_negative_status_servivel
    ON negative_status (codigo)
    WHERE revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_log_signature_servivel
    ON log_signature (status_implicado)
    WHERE revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. model_version (§14.5)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS model_version (
    codigo TEXT PRIMARY KEY,
    status_codigo TEXT NOT NULL REFERENCES negative_status(codigo) ON DELETE CASCADE,
    -- NULL = o cabeçote inteiro do status. Preenchido = promoção causa a causa,
    -- que é como §14.1 exige que a promoção aconteça.
    causa_codigo TEXT,
    estado TEXT NOT NULL DEFAULT 'sombra'
        CHECK (estado IN ('sombra','promovido','rebaixado')),

    treinado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    n_treino INTEGER NOT NULL DEFAULT 0,
    n_validacao INTEGER NOT NULL DEFAULT 0,
    -- Quantos dos exemplos de treino são SIMULADOS a partir do corpus (§19.3).
    -- Existe para tornar impossível esquecer: uma versão com n_simulado = n_treino
    -- nunca viu um caso interno, e por isso não pode ser promovida.
    n_simulado INTEGER NOT NULL DEFAULT 0,

    ece REAL,
    log_loss REAL,
    log_loss_regra REAL,
    acuracia REAL,

    promovido_em TIMESTAMPTZ,
    promovido_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    rebaixado_em TIMESTAMPTZ,
    motivo_rebaixamento TEXT,
    hash_pesos TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A trava de §19.3 em DDL, não em disciplina: rede que só viu simulação roda em
-- sombra. Nenhum código consegue promovê-la por engano.
ALTER TABLE model_version DROP CONSTRAINT IF EXISTS model_version_simulado_nao_promove;
ALTER TABLE model_version ADD CONSTRAINT model_version_simulado_nao_promove
    CHECK (estado <> 'promovido' OR n_simulado < n_treino);

CREATE INDEX IF NOT EXISTS idx_model_version_vigente
    ON model_version (status_codigo, causa_codigo, estado);

-- ---------------------------------------------------------------------------
-- 3. O laço RAT × suposição (§19.4)
--
-- A suposição da rede é o que o sistema achou ANTES. A RAT é o que o técnico
-- encontrou com a máquina na mão. A comparação das duas é o melhor rótulo de
-- treino que o produto consegue produzir — e a única fonte de calibração
-- medida em campo.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS rat_comparacao (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES support_tickets(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,

    -- O que a rede supôs, congelado no momento em que foi mostrado. Não é FK
    -- para diagnosis à toa: a suposição precisa sobreviver ao expurgo do que a
    -- gerou, senão a calibração histórica se apaga sozinha.
    diagnosis_id UUID,
    suposicao_status TEXT,
    suposicao_causa TEXT,
    suposicao_prob REAL,
    suposicao_motor TEXT CHECK (suposicao_motor IN ('regra','modelo')),
    model_version_codigo TEXT REFERENCES model_version(codigo) ON DELETE SET NULL,

    -- A realidade. Vem do conjunto fechado, nunca texto livre (§10.3, §19.4):
    -- o técnico MARCA a causa encontrada. `observacao` existe para o que não
    -- cabe no conjunto, e não é lida pelo treino.
    causa_encontrada TEXT NOT NULL,
    acao_executada TEXT,
    observacao TEXT,
    preenchido_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    preenchido_em TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A avaliação do supervisor, nas DUAS dimensões que §19.4 exige: acertar a
    -- causa e sugerir o teste certo são erros diferentes, e uma rede que acerta
    -- a causa apontando o teste errado precisa ser corrigida assim mesmo.
    avaliacao_causa TEXT CHECK (avaliacao_causa IN ('acertou','errou','abstencao_correta','abstencao_indevida')),
    avaliacao_utilidade TEXT CHECK (avaliacao_utilidade IN ('ajudou','atrapalhou','indiferente')),
    avaliado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    avaliado_em TIMESTAMPTZ,

    -- Divergência não é erro do técnico: o que se ajusta é a rede, e o caso
    -- entra no treino com peso maior porque é onde ela estava errada (§19.4).
    peso_treino REAL NOT NULL DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rat_pendente_avaliacao
    ON rat_comparacao (preenchido_em) WHERE avaliado_em IS NULL;
CREATE INDEX IF NOT EXISTS idx_rat_calibracao
    ON rat_comparacao (suposicao_status, suposicao_causa, avaliado_em)
    WHERE avaliado_em IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rat_device ON rat_comparacao (device_id, created_at DESC);

-- Divergência recebe peso maior automaticamente. Regra no banco e não no
-- treinador porque é propriedade do dado, não do algoritmo — qualquer
-- treinador futuro herda o comportamento certo.
CREATE OR REPLACE FUNCTION rat_peso_por_divergencia() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.avaliacao_causa = 'errou' THEN
        NEW.peso_treino := 3.0;
    ELSIF NEW.avaliacao_causa = 'abstencao_indevida' THEN
        NEW.peso_treino := 2.0;
    ELSE
        NEW.peso_treino := 1.0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rat_peso ON rat_comparacao;
CREATE TRIGGER trg_rat_peso BEFORE INSERT OR UPDATE ON rat_comparacao
    FOR EACH ROW EXECUTE FUNCTION rat_peso_por_divergencia();

-- ---------------------------------------------------------------------------
-- 4. Exemplos de treino (§19.3)
--
-- Um lugar só para os dois tipos de exemplo, com a origem sempre explícita.
-- Misturá-los sem marca seria o modo de falha que §19.3 nomeia: métrica de
-- calibração calculada sobre caso simulado é métrica do simulador.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS training_example (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    origem TEXT NOT NULL CHECK (origem IN ('simulado_corpus','interno_rat','interno_escada')),
    -- Só para simulado: de qual thread do corpus este exemplo saiu. É o que
    -- permite refazer a extração quando o extrator melhorar.
    corpus_thread_id UUID,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,

    status_codigo TEXT NOT NULL,
    causa_verdadeira TEXT NOT NULL,
    -- Vetor de evidências no formato do dossiê. Campo sem valor no caso fica
    -- AUSENTE da chave, nunca zero (§19.3) — ausência é informação.
    evidencias JSONB NOT NULL DEFAULT '{}'::jsonb,
    tem_curva BOOLEAN NOT NULL DEFAULT false,
    degrau_quebra INTEGER,

    peso REAL NOT NULL DEFAULT 1.0,
    -- Partição temporal, nunca aleatória: treino no passado, validação no
    -- futuro (§14.2). Amostragem aleatória vazaria o mesmo dispositivo para os
    -- dois lados.
    particao TEXT NOT NULL DEFAULT 'treino' CHECK (particao IN ('treino','validacao')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_training_status ON training_example (status_codigo, particao);
CREATE INDEX IF NOT EXISTS idx_training_origem ON training_example (origem);

-- ---------------------------------------------------------------------------
-- 5. diagnosis aponta para a versão de modelo (§17)
-- ---------------------------------------------------------------------------

ALTER TABLE diagnosis ADD COLUMN IF NOT EXISTS model_version_codigo TEXT
    REFERENCES model_version(codigo) ON DELETE SET NULL;
