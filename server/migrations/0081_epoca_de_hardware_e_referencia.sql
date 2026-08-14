-- Época de hardware e referência de fábrica.
--
-- A ordem correta do diagnóstico começa antes da telemetria: é preciso saber
-- QUAIS peças compõem a máquina, porque é a peça que define o que medir e o
-- que esperar. Sem isso, "lento" é adjetivo — não existe régua.
--
-- E existe uma armadilha que só aparece com o tempo: quando uma peça é
-- trocada, a máquina passa a ser outra. Comparar medições de antes com as de
-- depois é comparar dois computadores diferentes e chamar a diferença de
-- degradação. Por isso toda medida pertence a uma ÉPOCA.

-- ---------------------------------------------------------------------------
-- A época: o intervalo em que a máquina foi a MESMA máquina.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hardware_epoch (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id    uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    -- Impressão das peças ESTÁVEIS: modelo, capacidade, slot, identificador.
    -- Deliberadamente sem uso, temperatura ou espaço livre — o que muda a toda
    -- hora não identifica a máquina, apenas o estado dela.
    impressao    text NOT NULL,
    componentes  jsonb NOT NULL DEFAULT '{}'::jsonb,
    iniciou_em   timestamptz NOT NULL DEFAULT now(),
    encerrou_em  timestamptz,
    CONSTRAINT hardware_epoch_intervalo CHECK (encerrou_em IS NULL OR encerrou_em >= iniciou_em)
);

CREATE INDEX IF NOT EXISTS hardware_epoch_device_idx
    ON hardware_epoch (device_id, iniciou_em DESC);

-- Só UMA época aberta por dispositivo. Duas épocas abertas significam que a
-- reconciliação falhou no meio, e a partir daí nenhuma medida sabe a que
-- máquina pertence.
CREATE UNIQUE INDEX IF NOT EXISTS hardware_epoch_uma_aberta
    ON hardware_epoch (device_id) WHERE encerrou_em IS NULL;

-- ---------------------------------------------------------------------------
-- A troca: o momento em que "outro computador" começou.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hardware_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id      uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    ocorrido_em    timestamptz NOT NULL DEFAULT now(),
    epoca_anterior uuid REFERENCES hardware_epoch(id) ON DELETE SET NULL,
    epoca_nova     uuid NOT NULL REFERENCES hardware_epoch(id) ON DELETE CASCADE,
    -- [{classe, item, antes, depois, tipo}] — tipo em adicionada|removida|trocada
    alteracoes     jsonb NOT NULL DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS hardware_change_device_idx
    ON hardware_change (device_id, ocorrido_em DESC);

-- ---------------------------------------------------------------------------
-- Amarrar cada medida à época em que foi feita.
-- ---------------------------------------------------------------------------
ALTER TABLE telemetry_snapshots ADD COLUMN IF NOT EXISTS epoca_id uuid
    REFERENCES hardware_epoch(id) ON DELETE SET NULL;
ALTER TABLE diagnostic_runs ADD COLUMN IF NOT EXISTS epoca_id uuid
    REFERENCES hardware_epoch(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS telemetry_snapshots_epoca_idx
    ON telemetry_snapshots (epoca_id, coletado_em DESC) WHERE epoca_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- A referência: o que a peça DEVERIA entregar.
-- ---------------------------------------------------------------------------
--
-- É a régua que transforma "está lento" em "entrega 40% do que esta peça
-- entrega". Sem ela, todo laudo degenera em "compre mais", que é o conselho
-- que nunca erra e nunca ajuda.
--
-- As linhas iniciais são POR CLASSE, não por modelo, e isso é deliberado:
-- número por modelo exigiria fonte verificável para cada peça do mundo, e
-- inventar precisão é pior que assumir faixa. Linhas por modelo entram depois,
-- e vencem as de classe por serem mais específicas (especificidade maior).
CREATE TABLE IF NOT EXISTS component_reference (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    classe         text NOT NULL,           -- disco | memoria | cpu | gpu
    -- Critérios de casamento. NULL = não restringe.
    barramento     text,                    -- NVMe | SATA
    midia          text,                    -- SSD | HDD
    modelo_como    text,                    -- ILIKE sobre o modelo, quando por modelo
    metrica        text NOT NULL,           -- leitura_sequencial_mbs | latencia_ms | ...
    valor_esperado numeric NOT NULL,
    -- Abaixo de quanto do esperado a peça é considerada em DÉFICIT.
    piso_pct       numeric NOT NULL DEFAULT 50,
    -- Quanto mais específica, mais alta. Classe = 1, barramento+mídia = 2,
    -- modelo = 3. A consulta pega a de maior especificidade que casar.
    especificidade smallint NOT NULL DEFAULT 1,
    fonte          text NOT NULL,
    observacao     text NOT NULL DEFAULT '',
    created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS component_reference_busca_idx
    ON component_reference (classe, metrica, especificidade DESC);

-- Sementes por classe. Valores de faixa amplamente documentada para a
-- categoria, não medição nossa — o campo `fonte` diz exatamente isso, para que
-- ninguém os leia como precisão que não têm.
INSERT INTO component_reference
    (classe, barramento, midia, metrica, valor_esperado, piso_pct, especificidade, fonte, observacao)
VALUES
    ('disco','NVMe','SSD','leitura_sequencial_mbs', 2000, 40, 2,
     'faixa de classe (NVMe consumidor)',
     'NVMe de consumo entrega tipicamente entre 1.500 e 3.500 MB/s em leitura sequencial'),
    ('disco','NVMe','SSD','latencia_ociosa_ms', 1, 100, 2,
     'faixa de classe (NVMe consumidor)',
     'acima de 1 ms com o disco ocioso já indica disputa ou controlador sem folga'),
    ('disco','SATA','SSD','leitura_sequencial_mbs', 500, 40, 2,
     'limite do barramento SATA III',
     'SATA III satura em ~550 MB/s; SSD de consumo fica perto disso quando saudável'),
    ('disco','SATA','SSD','latencia_ociosa_ms', 3, 100, 2,
     'faixa de classe (SATA SSD)',
     'SSD SATA ocioso responde em poucos milissegundos; dezenas indicam controlador em apuros'),
    ('disco','SATA','HDD','leitura_sequencial_mbs', 120, 40, 2,
     'faixa de classe (disco mecânico 5400-7200 rpm)', ''),
    ('disco',NULL,NULL,'ocupacao_maxima_pct', 85, 100, 1,
     'prática de fabricantes de SSD',
     'acima de ~85% o controlador perde espaço de manobra para reorganizar blocos'),
    ('memoria',NULL,NULL,'commit_maximo_pct', 80, 100, 1,
     'comportamento do gerenciador de memória do Windows',
     'acima disso a máquina passa a depender do arquivo de paginação para operar')
ON CONFLICT DO NOTHING;
