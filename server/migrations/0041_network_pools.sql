-- TGDesk: uma rede pode ocupar vários octetos, e IPs liberados voltam a ser
-- usados.
--
-- Antes cada rede era um único /24 (networks.cidr_octet UNIQUE) com
-- next_host_octet só crescendo — teto rígido de ~253 dispositivos por rede,
-- para sempre, e reinstalações queimavam endereços sem devolver. Para a rede
-- de clientes avulsos, que é compartilhada por todo dispositivo sem
-- organização, esse teto é atingido cedo.
--
-- O octeto NÃO carrega semântica de visibilidade: quem define quem enxerga
-- quem é o modelo lógico organização → rede → subrede, aplicado pelo
-- Authorizer e por networks.peer_isolation. Logo, uma rede ocupar 3 octetos
-- não afeta isolamento nenhum — é só espaço de endereçamento.

CREATE TABLE IF NOT EXISTS network_pools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    cidr_octet INTEGER NOT NULL UNIQUE,
    next_host_octet INTEGER NOT NULL DEFAULT 2,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS network_pools_network_idx
    ON network_pools(network_id, cidr_octet);

-- Endereços devolvidos por dispositivos inativos, reaproveitados antes de
-- consumir um endereço novo.
CREATE TABLE IF NOT EXISTS network_free_ips (
    network_id UUID NOT NULL REFERENCES networks(id) ON DELETE CASCADE,
    virtual_ip TEXT PRIMARY KEY,
    released_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS network_free_ips_network_idx
    ON network_free_ips(network_id, released_at);

-- Cada rede existente vira seu primeiro pool, preservando octeto e posição.
INSERT INTO network_pools(network_id, cidr_octet, next_host_octet)
SELECT id, cidr_octet, next_host_octet FROM networks
WHERE cidr_octet IS NOT NULL
ON CONFLICT (cidr_octet) DO NOTHING;

-- Alocação atômica: reaproveita endereço liberado; senão avança o pool com
-- espaço; senão abre um pool novo para a mesma rede.
CREATE OR REPLACE FUNCTION allocate_virtual_ip(p_network UUID)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_ip TEXT;
    v_pool network_pools%ROWTYPE;
BEGIN
    DELETE FROM network_free_ips
    WHERE virtual_ip = (
        SELECT virtual_ip FROM network_free_ips
        WHERE network_id = p_network
        ORDER BY released_at LIMIT 1 FOR UPDATE SKIP LOCKED
    )
    RETURNING virtual_ip INTO v_ip;
    IF v_ip IS NOT NULL THEN
        RETURN v_ip;
    END IF;

    SELECT * INTO v_pool FROM network_pools
    WHERE network_id = p_network AND next_host_octet <= 254
    ORDER BY cidr_octet LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        INSERT INTO network_pools(network_id, cidr_octet, next_host_octet)
        VALUES (p_network, nextval('network_cidr_octet_seq'), 2)
        RETURNING * INTO v_pool;
    END IF;

    UPDATE network_pools SET next_host_octet = next_host_octet + 1
    WHERE id = v_pool.id;

    -- v_pool guarda o valor anterior ao incremento, que é o host a entregar.
    RETURN '10.70.' || v_pool.cidr_octet || '.' || v_pool.next_host_octet;
END $$;

-- Devolve o endereço ao pool da rede. Idempotente: chamar duas vezes para o
-- mesmo IP não duplica a entrada.
CREATE OR REPLACE FUNCTION release_virtual_ip(p_network UUID, p_ip TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_ip IS NULL OR p_ip = '' OR p_network IS NULL THEN
        RETURN;
    END IF;
    INSERT INTO network_free_ips(network_id, virtual_ip)
    VALUES (p_network, p_ip)
    ON CONFLICT (virtual_ip) DO NOTHING;
END $$;
