-- TGDesk: camada de texto do diagnóstico.
--
-- Implementa ARQUITETURA-DIAGNOSTICO-NEURAL.md §12. A regra dura que esta
-- tabela existe para tornar estrutural: NENHUMA FRASE MOSTRADA AO TÉCNICO É
-- GERADA EM RUNTIME POR MODELO GENERATIVO.
--
-- Se a rede escrevesse frase livre, tudo o que a arquitetura constrói se
-- perderia: probabilidade calibrada viraria parágrafo confiante, o técnico não
-- conseguiria auditar, e um erro de redação seria indistinguível de um erro de
-- diagnóstico. O motor devolve CHAVE e VALORES; o texto vem daqui.
--
-- O modelo generativo tem um lugar legítimo — offline, na construção, propondo
-- rascunho a partir do corpus. Por isso `revisado_por`: rascunho sem revisão
-- não é servido.

CREATE TABLE IF NOT EXISTS text_template (
    -- 'status.causa.variante' — a chave que o motor devolve.
    chave TEXT NOT NULL,
    idioma TEXT NOT NULL DEFAULT 'pt-BR',
    -- Dois níveis OBRIGATÓRIOS (§12.2): o supervisor lê probabilidade e curva;
    -- o cliente lê uma frase. Mesmo diagnóstico, duas linguagens.
    nivel TEXT NOT NULL CHECK (nivel IN ('tecnico', 'cliente')),
    titulo TEXT NOT NULL,
    corpo TEXT NOT NULL,
    -- Slots nomeados e tipados: {degrau_quebra}, {duracao_trava}, {metrica},
    -- {valor_medido}, {limiar_esperado}, {probabilidade}.
    slots JSONB NOT NULL DEFAULT '[]'::jsonb,
    versao INTEGER NOT NULL DEFAULT 1,
    origem_corpus TEXT,
    -- Sem isto preenchido, o renderizador recusa a servir (§12.3).
    revisado_por UUID REFERENCES technicians(id) ON DELETE SET NULL,
    revisado_em TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (chave, idioma, nivel, versao)
);

-- O cliente cacheia por versão (§12.4); esta é a consulta do renderizador.
CREATE INDEX IF NOT EXISTS idx_text_template_servivel
    ON text_template (chave, idioma, nivel, versao DESC)
    WHERE revisado_por IS NOT NULL;

-- Rascunhos aguardando revisão. É a fila de trabalho humano de A3.
CREATE INDEX IF NOT EXISTS idx_text_template_pendente
    ON text_template (created_at) WHERE revisado_por IS NULL;
