-- TGDesk: parâmetros versionados e perfil de escada.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §18 e a invariante que o
-- sustenta: NENHUM limiar mora no código. Todo número — degrau, temperatura de
-- parada, limiar de alerta, ECE de promoção — vive aqui, versionado, e a versão
-- vigente acompanha cada stress_run, diagnosis e alerta gravados.
--
-- Por que isso é estrutural e não conveniência: mudar um limiar muda o
-- significado de todo dado gravado depois dele. Se o valor estivesse em código,
-- um diagnóstico de março e um de agosto seriam incomparáveis sem ninguém
-- perceber. Com versão explícita, a comparação ou é válida ou é recusada.

-- ---------------------------------------------------------------------------
-- diag_param_set — um conjunto fechado e versionado de parâmetros
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS diag_param_set (
    versao TEXT PRIMARY KEY,
    descricao TEXT NOT NULL,
    -- vigente = o que o servidor usa agora. Só um de cada vez; o índice único
    -- parcial abaixo garante.
    vigente BOOLEAN NOT NULL DEFAULT false,
    criado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_diag_param_set_vigente
    ON diag_param_set ((true)) WHERE vigente;

CREATE TABLE IF NOT EXISTS diag_param (
    versao TEXT NOT NULL REFERENCES diag_param_set(versao) ON DELETE CASCADE,
    chave TEXT NOT NULL,
    valor DOUBLE PRECISION NOT NULL,
    unidade TEXT NOT NULL,
    -- seção do documento que justifica o valor. Parâmetro sem razão escrita é
    -- parâmetro que ninguém vai saber ajustar depois.
    referencia TEXT NOT NULL,
    PRIMARY KEY (versao, chave)
);

-- ---------------------------------------------------------------------------
-- stress_profile — a composição da escada, como DADO (§10.1)
--
-- "Composição é dado, não código": o servidor decide os estágios a partir do
-- dispositivo, do motivo do chamado e do dossiê passivo — mas a decisão fica
-- registrada e versionada, para que execuções continuem comparáveis.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stress_profile (
    codigo TEXT NOT NULL,
    versao INTEGER NOT NULL,
    descricao TEXT NOT NULL,
    -- ordem fixa dos estágios, com forma do degrau de cada um
    estagios JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- conjunto de parâmetros com que este perfil foi definido
    param_versao TEXT REFERENCES diag_param_set(versao) ON DELETE SET NULL,
    ativo BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (codigo, versao)
);

-- stress_run já carrega (perfil, perfil_versao) desde a 0072; a FK fecha o laço
-- agora que a tabela de perfis existe.
ALTER TABLE stress_run
    DROP CONSTRAINT IF EXISTS stress_run_perfil_fk;
ALTER TABLE stress_run
    ADD CONSTRAINT stress_run_perfil_fk
    FOREIGN KEY (perfil, perfil_versao)
    REFERENCES stress_profile(codigo, versao) ON DELETE RESTRICT;

-- ---------------------------------------------------------------------------
-- Semente: os valores de partida da §18.
--
-- Entram como v1 e vigente. Não são chute: cada um tem referência à seção que
-- o justifica, e mudar qualquer um exige v2 — nunca UPDATE no lugar, porque
-- isso apagaria a comparabilidade do histórico.
-- ---------------------------------------------------------------------------
INSERT INTO diag_param_set (versao, descricao, vigente)
VALUES ('v1', 'Valores de partida da arquitetura (§18)', true)
ON CONFLICT (versao) DO NOTHING;

INSERT INTO diag_param (versao, chave, valor, unidade, referencia) VALUES
    ('v1', 'escada.degraus_por_estagio',        5,    'degraus', '§5'),
    ('v1', 'escada.duracao_degrau_s',           90,   's',       '§5'),
    ('v1', 'escada.descarte_inicial_s',         15,   's',       '§5'),
    ('v1', 'escada.amostragem_hz',              1,    'Hz',      '§5'),
    ('v1', 'escada.combinado_duracao_s',        180,  's',       '§5'),
    ('v1', 'escada.repeticoes_degrau_quebra',   1,    'vezes',   '§5'),
    ('v1', 'escada.teto_execucao_min',          45,   'min',     '§5'),
    ('v1', 'gate.temp_parada_c',                95,   '°C',      '§5'),
    ('v1', 'gate.temp_sustentada_c',            90,   '°C',      '§5'),
    ('v1', 'gate.temp_sustentada_s',            10,   's',       '§5'),
    ('v1', 'gate.trava_parada_s',               5,    's',       '§5'),
    ('v1', 'gate.temp_repouso_bloqueia_c',      75,   '°C',      '§5'),
    ('v1', 'gate.espaco_livre_min_pct',         10,   '%',       '§5'),
    ('v1', 'gate.perda_contato_s',              30,   's',       '§5'),
    ('v1', 'trava.heartbeat_hz',                2,    'Hz',      '§6'),
    ('v1', 'trava.buraco_abre_ms',              1500, 'ms',      '§6'),
    ('v1', 'trava.ring_buffer_s',               60,   's',       '§6'),
    ('v1', 'trava.ring_buffer_hz',              10,   'Hz',      '§6'),
    ('v1', 'trava.tolerancia_conciliacao_ms',   500,  'ms',      '§6'),
    ('v1', 'telemetria.intervalo_amostra_s',    60,   's',       '§7.1'),
    ('v1', 'telemetria.lote_s',                 300,  's',       '§7.1'),
    ('v1', 'telemetria.top_n_processos',        5,    'itens',   '§7.1'),
    ('v1', 'rajada.pico_pct',                   90,   '%',       '§7.1'),
    ('v1', 'rajada.pico_duracao_s',             120,  's',       '§7.1'),
    ('v1', 'rajada.ram_livre_min_pct',          5,    '%',       '§7.1'),
    ('v1', 'rajada.recorte_antes_s',            60,   's',       '§7.1'),
    ('v1', 'rajada.recorte_depois_s',           30,   's',       '§7.1'),
    ('v1', 'rajada.teto_por_dia',               6,    'rajadas', '§7.1'),
    ('v1', 'retencao.telemetry_sample_dias',    90,   'dias',    '§7.4'),
    ('v1', 'retencao.agregado_diario_meses',    24,   'meses',   '§7.4'),
    ('v1', 'retencao.burst_sem_consent_dias',   7,    'dias',    '§7.4'),
    ('v1', 'retencao.burst_sensivel_h',         72,   'h',       '§7.4'),
    ('v1', 'alerta.nivel2_prob_min',            0.90, 'prob',    '§9'),
    ('v1', 'alerta.nivel2_casos_min',           30,   'casos',   '§9'),
    ('v1', 'alerta.some_abaixo_de',             0.50, 'prob',    '§9'),
    ('v1', 'alerta.anti_repeticao_dias',        14,   'dias',    '§9'),
    ('v1', 'alerta.descartado_silencia_dias',   30,   'dias',    '§9'),
    ('v1', 'alerta.max_simultaneos',            2,    'alertas', '§9'),
    ('v1', 'diagnostico.teto_prob_inicial',     0.85, 'prob',    '§10.5.1'),
    ('v1', 'diagnostico.max_causas',            3,    'causas',  '§1'),
    ('v1', 'escopo.dispensa_escada_prob',       0.80, 'prob',    '§11.5'),
    ('v1', 'prior.k_decaimento',                20,   'casos',   '§13.4'),
    ('v1', 'modelo.n_minimo_promocao',          150,  'casos',   '§14.2'),
    ('v1', 'modelo.n_minimo_sombra',            30,   'casos',   '§14.4'),
    ('v1', 'modelo.ece_max_promocao',           0.05, 'ece',     '§14.2'),
    ('v1', 'modelo.ece_max_manutencao',         0.08, 'ece',     '§14.3'),
    ('v1', 'modelo.desvio_faixa_max_pp',        15,   'pp',      '§14.2'),
    ('v1', 'modelo.desvio_faixa_rebaixa_pp',    20,   'pp',      '§14.3'),
    ('v1', 'recidiva.janela_curta_dias',        7,    'dias',    '§13.5'),
    ('v1', 'recidiva.janela_longa_dias',        30,   'dias',    '§13.5')
ON CONFLICT (versao, chave) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Perfil de escada v1 (§5, forma do degrau).
--
-- Os estágios entram como CANDIDATOS — é a derivação do corpus (A4/§13.6) que
-- confirma, adapta ou poda. Perfil podado vira v2; v1 não é editado, para que
-- as execuções feitas sob ele continuem interpretáveis.
-- ---------------------------------------------------------------------------
INSERT INTO stress_profile (codigo, versao, descricao, estagios, param_versao)
VALUES (
    'completa', 1,
    'Escada unificada v1 — peça por peça, combinado no fim (§5)',
    '[
      {"stage": "cpu",              "ordem": 1, "degraus": [20,40,60,80,100], "duracao_s": 90},
      {"stage": "ram",              "ordem": 2, "degraus": [20,40,60,80,100], "duracao_s": 90},
      {"stage": "disco_sequencial", "ordem": 3, "degraus": [20,40,60,80,100], "duracao_s": 90},
      {"stage": "disco_aleatorio",  "ordem": 4, "degraus": [20,40,60,80,100], "duracao_s": 90},
      {"stage": "rede",             "ordem": 5, "degraus": [20,40,60,80,100], "duracao_s": 90},
      {"stage": "combinado",        "ordem": 6, "degraus": [100],             "duracao_s": 180}
    ]'::jsonb,
    'v1'
)
ON CONFLICT (codigo, versao) DO NOTHING;
