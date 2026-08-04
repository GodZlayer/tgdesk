-- TGDesk: histórico total de telemetria por agregação incremental.
--
-- Problema que isto resolve: hardwareStatistics carregava TODOS os snapshots
-- de 30 dias e desserializava cada JSON em memória, a cada 30 segundos, por
-- dispositivo — ~86.400 linhas por varredura, mais uma segunda varredura em
-- recentHardwareHealth. Passa hoje porque a base é pequena; com histórico
-- longo, não escala de jeito nenhum. Agregação incremental é a fundação da
-- análise de longo prazo, não uma otimização opcional.
--
-- Cada telemetria atualiza APENAS o bucket da hora corrente, então o custo é
-- constante e independente do tamanho do histórico.

CREATE TABLE IF NOT EXISTS device_metric_rollup (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    metrica TEXT NOT NULL,
    bucket_hora TIMESTAMPTZ NOT NULL,
    samples INTEGER NOT NULL DEFAULT 0,
    soma DOUBLE PRECISION NOT NULL DEFAULT 0,
    minimo DOUBLE PRECISION,
    maximo DOUBLE PRECISION,
    -- Tempo de exposição: quantas amostras ficaram acima de cada limiar.
    --
    -- A média é a raiz do problema de instabilidade: qualquer período ocioso a
    -- destrói e ela apaga picos, então o nível oscila conforme o uso da
    -- máquina. "Passou 38% do tempo acima de 85%" é estável, verdadeiro, e é o
    -- que o usuário de fato sente.
    acima_75 INTEGER NOT NULL DEFAULT 0,
    acima_85 INTEGER NOT NULL DEFAULT 0,
    acima_95 INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (device_id, metrica, bucket_hora)
);

CREATE INDEX IF NOT EXISTS device_metric_rollup_janela_idx
    ON device_metric_rollup(device_id, metrica, bucket_hora DESC);

-- Acumula uma leitura no bucket da hora. Os limiares são fixos porque servem a
-- métricas percentuais (CPU, memória, ocupação de disco); temperatura usa os
-- campos de min/max/média e limiares próprios na análise.
CREATE OR REPLACE FUNCTION roll_metric(
    p_device UUID, p_metrica TEXT, p_valor DOUBLE PRECISION, p_em TIMESTAMPTZ
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_valor IS NULL THEN RETURN; END IF;
    INSERT INTO device_metric_rollup AS r
        (device_id, metrica, bucket_hora, samples, soma, minimo, maximo,
         acima_75, acima_85, acima_95)
    VALUES (
        p_device, p_metrica, date_trunc('hour', p_em), 1, p_valor, p_valor, p_valor,
        CASE WHEN p_valor >= 75 THEN 1 ELSE 0 END,
        CASE WHEN p_valor >= 85 THEN 1 ELSE 0 END,
        CASE WHEN p_valor >= 95 THEN 1 ELSE 0 END)
    ON CONFLICT (device_id, metrica, bucket_hora) DO UPDATE SET
        samples  = r.samples + 1,
        soma     = r.soma + excluded.soma,
        minimo   = least(r.minimo, excluded.minimo),
        maximo   = greatest(r.maximo, excluded.maximo),
        acima_75 = r.acima_75 + excluded.acima_75,
        acima_85 = r.acima_85 + excluded.acima_85,
        acima_95 = r.acima_95 + excluded.acima_95;
END $$;

-- Estado de saúde persistido, com histerese.
--
-- Hoje o nível é recalculado do zero a cada 30s sobre uma janela móvel de 15
-- minutos, sem memória: um limiar seco faz o nível alternar a cada passada, e
-- `samples < 3` derruba tudo para 'normal' quando a máquina dorme ou perde
-- conexão. É isso que faz um computador saudável "mudar de estado" várias
-- vezes ao dia. Aqui o nível só sobe após subidas_consecutivas avaliações
-- acima, só desce após descidas_consecutivas abaixo, e ausência de amostra
-- MANTÉM o último nível em vez de zerar.
CREATE TABLE IF NOT EXISTS device_health_state (
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    categoria TEXT NOT NULL,
    level TEXT NOT NULL DEFAULT 'normal',
    nivel_candidato TEXT,
    consecutivas INTEGER NOT NULL DEFAULT 0,
    desde TIMESTAMPTZ NOT NULL DEFAULT now(),
    ultima_mudanca TIMESTAMPTZ NOT NULL DEFAULT now(),
    avaliado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, categoria)
);

CREATE INDEX IF NOT EXISTS device_health_state_device_idx
    ON device_health_state(device_id);
