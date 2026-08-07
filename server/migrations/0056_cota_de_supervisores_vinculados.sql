-- TGDesk: quantos vinculados cada um pode ter é decisão do admin.
--
-- O supervisor emite a chave, mas quem define o teto é o dono do produto —
-- porque isso vai ser cobrado. Enquanto não existe sistema financeiro, a cota
-- já mora onde o financeiro vai olhar: uma linha por organização, editável na
-- tela do admin como os percentuais e os limites de preço.
--
-- Fica em pricing_rules? Não. Lá é dinheiro; aqui é direito de uso, e misturar
-- os dois obrigaria toda leitura de preço a saber sobre cota. São dois assuntos
-- que mudam por motivos diferentes.

CREATE TABLE IF NOT EXISTS organization_quotas (
    organization_id UUID PRIMARY KEY
        REFERENCES organizations(id) ON DELETE CASCADE,

    -- Quantos supervisores vinculados esta organização pode ter ao mesmo
    -- tempo. Zero é um valor legítimo e significa "não pode nenhum" — é
    -- diferente de não ter linha, que cai no padrão.
    max_affiliated_supervisors INTEGER NOT NULL DEFAULT 0
        CHECK (max_affiliated_supervisors >= 0),

    -- Espaço para o resto do que será cobrado, sem exigir migration nova a
    -- cada item. Nulo em qualquer um deles significa "sem teto".
    max_technicians INTEGER CHECK (max_technicians IS NULL OR max_technicians >= 0),
    max_devices     INTEGER CHECK (max_devices     IS NULL OR max_devices     >= 0),

    note       TEXT NOT NULL DEFAULT '',
    updated_by UUID REFERENCES technicians(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- O padrão do produto, para organização que ainda não tem linha própria.
--
-- Uma linha só, com organization_id nulo, na mesma tabela? Não: a chave
-- primária é a organização, e abrir exceção para nulo transformaria toda
-- consulta em "a minha ou a global". Uma tabela de um registro é mais honesta
-- sobre o que é — configuração do produto, não de ninguém.
CREATE TABLE IF NOT EXISTS product_defaults (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
    max_affiliated_supervisors INTEGER NOT NULL DEFAULT 0
        CHECK (max_affiliated_supervisors >= 0),
    updated_by UUID REFERENCES technicians(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO product_defaults(singleton, max_affiliated_supervisors)
VALUES (true, 0)
ON CONFLICT (singleton) DO NOTHING;

-- Quantos vinculados uma organização já tem. Conta as chaves vinculadas ainda
-- vivas junto dos técnicos já afiliados: uma chave emitida e não consumida já
-- é uma vaga comprometida, senão emitir dez chaves de uma vez furaria o teto.
CREATE OR REPLACE FUNCTION affiliated_supervisors_used(org UUID)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT (
        SELECT count(*) FROM technicians
        WHERE affiliated_organization_id = org AND status = 'ativo'
    ) + (
        SELECT count(*) FROM technician_enrollment_keys
        WHERE affiliated_organization_id = org
          AND consumed_at IS NULL
          AND (expires_at IS NULL OR expires_at > now())
    );
$$;
