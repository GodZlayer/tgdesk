-- TGDesk: escopo de ordem de serviço derivado do diagnóstico.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §11. É a última tradução da
-- probabilidade em ação: o diagnóstico não termina em "causa provável", termina
-- em o que levar, com que ferramenta, quanto tempo e o que fazer se não
-- resolver.
--
-- A regra que organiza tudo aqui: o escopo deriva do TOP-3, não da causa
-- vencedora. O técnico de campo vai uma vez; se a hipótese 2 tem 25%, voltar
-- depois custa mais caro que levar a peça junto.

-- ---------------------------------------------------------------------------
-- tool_catalog — ferramentas, peças, insumos, credenciais, mídias (§11.7)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tool_catalog (
    codigo TEXT PRIMARY KEY,
    nome TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN (
        'ferramenta','peca','insumo','credencial','midia','software'
    )),
    portatil BOOLEAN NOT NULL DEFAULT true,
    -- escala 1..5. Entra na conta de levar/não levar (§11.1) junto com o custo
    -- de faltar — nunca sozinho.
    custo_relativo SMALLINT NOT NULL DEFAULT 1
        CHECK (custo_relativo BETWEEN 1 AND 5),
    -- item que exige aprovação NUNCA entra automaticamente no escopo, qualquer
    -- que seja a probabilidade. Vira sugestão pendente.
    requer_aprovacao BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- cause_requirement — o que cada (causa, ação) exige (§11.7)
--
-- É daqui que o nível de cada item é DERIVADO. Digitar nível à mão na OS seria
-- devolver ao humano a decisão que o dossiê já sabe tomar — e a exceção, quando
-- houver, fica registrada como exceção em os_scope.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cause_requirement (
    causa_codigo TEXT NOT NULL,
    acao TEXT NOT NULL,
    tool_codigo TEXT NOT NULL REFERENCES tool_catalog(codigo) ON DELETE CASCADE,
    nivel TEXT NOT NULL CHECK (nivel IN (
        'essencial','necessaria','facilitadora','dispensavel'
    )),
    quantidade SMALLINT NOT NULL DEFAULT 1,
    -- condição que liga o requisito: so_se_volume_criptografado, so_se_notebook.
    -- É o que faz a chave de recuperação aparecer ANTES de a máquina ser aberta.
    condicao TEXT,
    -- classe de risco da AÇÃO, não do item. Decide, junto com a probabilidade,
    -- se o escopo dispensa a escada (§11.5). Regra determinística: nunca
    -- decisão do modelo sozinho.
    risco_acao TEXT NOT NULL DEFAULT 'medio'
        CHECK (risco_acao IN ('baixo','medio','alto')),

    PRIMARY KEY (causa_codigo, acao, tool_codigo)
);

-- ---------------------------------------------------------------------------
-- os_scope — o escopo materializado (§11.7)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS os_scope (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chamado_id UUID,
    diagnosis_id UUID REFERENCES diagnosis(id) ON DELETE SET NULL,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    -- itens com nível JÁ RESOLVIDO sobre a união das hipóteses plausíveis: um
    -- item facilitador para a causa 1 e essencial para a causa 2 sobe para
    -- essencial (§11.2).
    itens JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- o que o dossiê calculou sozinho: tamanho de backup, mídia necessária,
    -- peça de reposição, se é notebook, estado de criptografia (§11.3).
    derivados JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- 'cego' = máquina desligada ou sem agente: escopo derivado do ÚLTIMO
    -- dossiê conhecido mais o sintoma declarado. Nunca se apresenta com a
    -- mesma cara de escopo derivado (§11.4) — por isso é coluna, não nuance.
    modo TEXT NOT NULL DEFAULT 'derivado' CHECK (modo IN ('derivado','cego')),
    dispensa_escada BOOLEAN NOT NULL DEFAULT false,
    dispensa_motivo TEXT,
    janela_estimada_min INTEGER,
    janela_estimada_max INTEGER,
    -- item digitado à mão é EXCEÇÃO, e exceção fica registrada como tal.
    itens_manuais JSONB NOT NULL DEFAULT '[]'::jsonb,
    liberado_em TIMESTAMPTZ,
    liberado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Dispensar a escada é decisão de consequência: sem motivo escrito, não
    -- dispensa (§11.5).
    CONSTRAINT os_scope_dispensa_tem_motivo
        CHECK (NOT dispensa_escada OR dispensa_motivo IS NOT NULL),
    -- Escopo cego não pode se disfarçar de derivado: se não há observação
    -- atual, não há diagnóstico corrente para apontar.
    CONSTRAINT os_scope_derivado_tem_diagnostico
        CHECK (modo <> 'derivado' OR diagnosis_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_os_scope_device
    ON os_scope (device_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- os_validation — validação é RETESTE, não relato (§11.6)
--
-- "Trocado e testado" não é evidência. Evidência é o limiar ter se movido na
-- MESMA escada: quebrava no degrau 3, agora atravessa inteira.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS os_validation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    os_scope_id UUID NOT NULL REFERENCES os_scope(id) ON DELETE CASCADE,
    stress_run_antes UUID REFERENCES stress_run(id) ON DELETE SET NULL,
    stress_run_depois UUID REFERENCES stress_run(id) ON DELETE SET NULL,
    limiar_antes INTEGER,
    limiar_depois INTEGER,
    veredito TEXT NOT NULL CHECK (veredito IN (
        'resolvido','nao_resolvido','causa_reclassificada'
    )),
    validado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Fechar como resolvido exige as DUAS execuções. Sem o par não há
    -- comparação, e sem comparação é relato — que é exatamente o que §11.6
    -- recusa.
    CONSTRAINT os_validation_resolvido_exige_par
        CHECK (veredito <> 'resolvido'
               OR (stress_run_antes IS NOT NULL AND stress_run_depois IS NOT NULL)),
    -- E exige que o limiar tenha REALMENTE se movido. Um par de execuções com o
    -- mesmo limiar significa que o problema continua lá.
    CONSTRAINT os_validation_resolvido_exige_limiar_movido
        CHECK (veredito <> 'resolvido'
               OR (limiar_antes IS NOT NULL AND limiar_depois IS NOT NULL
                   AND limiar_depois > limiar_antes))
);

CREATE INDEX IF NOT EXISTS idx_os_validation_escopo
    ON os_validation (os_scope_id, created_at DESC);
