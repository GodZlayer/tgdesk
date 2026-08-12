-- TGDesk: corpus externo de casos resolvidos.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §13.7. É o material de
-- CONSTRUÇÃO da ontologia — não é dado operacional e não é lido em runtime pelo
-- caminho do diagnóstico. Por isso vive em schema próprio: a separação física
-- é o que impede que uma consulta de diagnóstico acabe, por descuido, buscando
-- veredito em texto de fórum.
--
-- O que sai daqui alimenta `negative_status`, `text_template`, `log_signature` e
-- `corpus_prior` em etapa de construção, sempre com revisão humana no meio.
--
-- Licença: o dump do Stack Exchange é CC BY-SA. `corpus_thread.licenca` e `url`
-- existem para que a atribuição sobreviva ao processamento — perder a origem
-- tornaria o corpus inutilizável na prática.

CREATE SCHEMA IF NOT EXISTS corpus;

-- ---------------------------------------------------------------------------
-- corpus_thread — uma discussão
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.corpus_thread (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fonte TEXT NOT NULL,
    -- id da thread na fonte. É o que torna a ingestão reexecutável sem
    -- duplicar: dump novo sobre dump velho tem que convergir, não somar.
    fonte_id TEXT NOT NULL,
    url TEXT,
    titulo TEXT NOT NULL,
    licenca TEXT NOT NULL,
    data TIMESTAMPTZ,
    hash TEXT,
    autor_id_criador TEXT,
    total_mensagens INTEGER NOT NULL DEFAULT 0,
    -- quando a fonte tem resposta aceita, o rótulo é NATIVO e não precisa da
    -- heurística primeira/última (§13.3). É a razão de o dump do Stack Exchange
    -- ser a fonte preferida.
    resolvido_nativo BOOLEAN,
    ingerido_em TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (fonte, fonte_id)
);

-- ---------------------------------------------------------------------------
-- corpus_post — uma mensagem
--
-- A granularidade que permite a filtragem por tópico ser CONSULTA e não
-- heurística sobre texto corrido: só o criador, primeira e última do criador,
-- um participante específico, a mensagem que a última do criador cita.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.corpus_post (
    thread_id UUID NOT NULL REFERENCES corpus.corpus_thread(id) ON DELETE CASCADE,
    seq INTEGER NOT NULL,
    autor_id TEXT,
    is_criador BOOLEAN NOT NULL DEFAULT false,
    is_primeira_do_autor BOOLEAN NOT NULL DEFAULT false,
    is_ultima_do_autor BOOLEAN NOT NULL DEFAULT false,
    responde_a_seq INTEGER,
    cita_seq INTEGER,
    data TIMESTAMPTZ,
    -- corpo já limpo de marcação. Somente texto: sem imagens, sem anexos.
    corpo_txt TEXT NOT NULL,
    tem_bloco_log BOOLEAN NOT NULL DEFAULT false,
    -- blocos de log separados — matéria-prima de log_signature (§8). É o que o
    -- corpus entrega de graça: a linha que um humano usou para decidir.
    logs_extraidos JSONB NOT NULL DEFAULT '[]'::jsonb,

    PRIMARY KEY (thread_id, seq)
);

-- "primeira e última do criador" é a consulta da heurística de desfecho (§13.3).
CREATE INDEX IF NOT EXISTS idx_corpus_post_criador
    ON corpus.corpus_post (thread_id, seq) WHERE is_criador;
-- Threads com log são as que rendem assinatura.
CREATE INDEX IF NOT EXISTS idx_corpus_post_com_log
    ON corpus.corpus_post (thread_id) WHERE tem_bloco_log;

-- ---------------------------------------------------------------------------
-- corpus_case — uma thread ÚTIL, já rotulada
--
-- Nem toda thread vira caso. O que não tem informação causal fica só como
-- vocabulário de sintoma (§13.3, filtros de descarte).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.corpus_case (
    thread_id UUID PRIMARY KEY REFERENCES corpus.corpus_thread(id) ON DELETE CASCADE,
    sintoma_normalizado TEXT,
    desfecho TEXT NOT NULL CHECK (desfecho IN (
        'resolvido','nao_resolvido','abandonado','inconclusivo'
    )),
    -- aponta para o corpus_post que carrega a SOLUÇÃO — que quase nunca é a
    -- última mensagem do autor (§13.3). Sem seguir a citação, o corpus vira
    -- milhares de "obrigado, funcionou" sem causa nenhuma.
    seq_da_causa INTEGER,
    causa_extraida TEXT,
    testes_citados JSONB NOT NULL DEFAULT '[]'::jsonb,
    ferramentas_citadas JSONB NOT NULL DEFAULT '[]'::jsonb,
    sinais_citados JSONB NOT NULL DEFAULT '[]'::jsonb,
    classe_problema TEXT,
    confianca_extracao REAL,
    -- por que a thread foi descartada como fonte causal, quando foi
    motivo_descarte TEXT,
    revisado_por UUID,
    revisado_em TIMESTAMPTZ,

    -- Desfecho resolvido sem apontar de onde veio a causa é exatamente o
    -- "obrigado, funcionou" que §13.3 manda recusar.
    CONSTRAINT corpus_case_resolvido_aponta_causa
        CHECK (desfecho <> 'resolvido' OR seq_da_causa IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_corpus_case_classe
    ON corpus.corpus_case (classe_problema, desfecho);

-- ---------------------------------------------------------------------------
-- corpus_prior — frequência causa|status, com peso que DECAI (§13.4)
--
-- peso_atual = k / (k + n_interno), k = 20 por padrão. Com 0 casos internos o
-- prior externo vale 1,0; com 20, meio; com 100, 0,17. Nunca chega a zero,
-- porque causa rara continua precisando de prior.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.corpus_prior (
    status_codigo TEXT NOT NULL,
    causa_codigo TEXT NOT NULL,
    frequencia REAL NOT NULL,
    n INTEGER NOT NULL DEFAULT 0,
    -- k por causa: fonte notoriamente enviesada para aquela causa entra com k
    -- menor e sai de cena mais rápido.
    k INTEGER NOT NULL DEFAULT 20,
    n_interno INTEGER NOT NULL DEFAULT 0,
    peso_atual REAL NOT NULL DEFAULT 1.0,
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (status_codigo, causa_codigo)
);

-- ---------------------------------------------------------------------------
-- coverage_report — o critério de aceite da missão (§13.6)
--
-- "Detectamos todos os tipos de problema?" vira número: fração dos casos
-- resolvidos que o catálogo atual CONSEGUIRIA ter discriminado. Medido por
-- CLASSE, nunca em agregado — média alta esconde classe inteira em zero.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.coverage_report (
    classe TEXT NOT NULL,
    versao_catalogo TEXT NOT NULL,
    casos_total INTEGER NOT NULL,
    casos_discriminaveis INTEGER NOT NULL,
    cobertura REAL NOT NULL,
    lacunas JSONB NOT NULL DEFAULT '[]'::jsonb,
    medido_em TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (classe, versao_catalogo)
);

-- ---------------------------------------------------------------------------
-- corpus_signal_demand — a derivação de §13.6, passagem 3 (viabilidade)
--
-- Cada sinal que os casos reais exigiram, com o veredito de viabilidade. É
-- desta tabela que sai o backlog do agente e a lista de lacunas declaradas —
-- e é ela que inverte a ordem causal do projeto: o corpus define o catálogo,
-- não o contrário.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS corpus.corpus_signal_demand (
    sinal TEXT PRIMARY KEY,
    casos_que_exigiram INTEGER NOT NULL DEFAULT 0,
    causas_que_consomem JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- poder de separação entre causas: é o que distingue sinal essencial de
    -- sinal que aparece muito e não decide nada.
    ganho_informacao REAL,
    veredito TEXT CHECK (veredito IN ('existe','adaptar','construir','inviavel')),
    -- para 'existe': a que teste do agente corresponde hoje
    teste_atual TEXT,
    -- para 'inviavel': vira negative_status.limitacoes e aparece na tela como
    -- "esta causa não é separável à distância". Lacuna não some.
    motivo_inviavel TEXT,
    revisado_por UUID,
    revisado_em TIMESTAMPTZ,

    CONSTRAINT corpus_signal_inviavel_tem_motivo
        CHECK (veredito <> 'inviavel' OR motivo_inviavel IS NOT NULL)
);
