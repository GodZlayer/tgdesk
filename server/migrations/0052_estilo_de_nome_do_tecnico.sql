-- TGDesk: o nome do técnico deixa de ser só o apelido e vira um rótulo
-- montado por um "estilo" do catálogo.
--
-- Até aqui o técnico aparecia com o username cru — "nome". O supervisor quer
-- poder escolher, por técnico, como esse nome é apresentado: "nome",
-- "nomeDesk", "nome - assistência", "nomeassist" etc. Cada uma dessas formas
-- é um estilo do catálogo, uma template que aplica um sufixo/decoração em
-- cima do username com o placeholder {nome}. Acrescentar um estilo novo é
-- cadastro pela tela do admin — não release — o mesmo princípio dos tipos de
-- chamado e da precificação.

-- ---------------------------------------------------------------------------
-- 1) Catálogo de estilos.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS technician_name_styles (
    key         TEXT PRIMARY KEY,
    label       TEXT NOT NULL,
    -- Template que monta o nome de exibição. O placeholder é literalmente
    -- {nome} e é substituído pelo username na hora de exibir.
    template    TEXT NOT NULL,
    -- Ordem de exibição, para o supervisor ver os mais comuns primeiro.
    position    INTEGER NOT NULL DEFAULT 100,
    active      BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2) Defaults. 'nome' puro vem primeiro (comportamento atual); as demais são
--    as formas comuns que o produto já grava em prosa nas telas.
-- ---------------------------------------------------------------------------
INSERT INTO technician_name_styles(key,label,template,position) VALUES
    ('nome',        'Só o nome',         '{nome}',                      10),
    ('desk',        'Nome + Desk',        '{nome}Desk',                 20),
    ('assistencia', 'Nome - assistência', '{nome} - assistência',       30),
    ('assist',      'Nome + assist',      '{nome}assist',               40)
ON CONFLICT (key) DO NOTHING;

-- O parque atual é todo "só o nome": o default backfilla sem tocar em nada.
ALTER TABLE technicians
    ADD COLUMN IF NOT EXISTS name_style TEXT;

COMMENT ON COLUMN technicians.name_style IS
    'Chave de technician_name_styles escolhida pelo supervisor para exibir; NULL = só o nome.';