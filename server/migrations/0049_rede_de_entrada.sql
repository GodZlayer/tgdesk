-- TGDesk: rede de entrada por organização.
--
-- O instalador passa a resolver o destino do cliente: empresarial escolhe o
-- técnico e o dispositivo se coloca sozinho na rede de entrada daquela
-- organização; particular continua indo para tgdevs.clientes_avulsos (0039).
-- Com isso a tela de bifurcação do primeiro início deixa de existir.
--
-- A rede de entrada é isolada por peer, como as redes de sistema TGDevs
-- (0035): quem chega ali ainda não foi vetado por ninguém, então não pode
-- enxergar os outros que chegaram. O técnico depois promove o dispositivo
-- para a rede real, e essa promoção é o PUT /devices/{id}/networks que já
-- existe — Bind continua sendo admissão por código de pareamento.
--
-- Não usa system_key porque o índice de system_key é único global (0035) e
-- aqui existe uma rede de entrada POR organização.

ALTER TABLE networks
    ADD COLUMN IF NOT EXISTS is_intake BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS networks_intake_unique_per_org
    ON networks(organization_id) WHERE is_intake;

-- Toda organização operacional ganha uma. A org TGDevs fica de fora: ela é o
-- plano de controle, e a entrada de cliente avulso já é tgdevs.clientes_avulsos.
INSERT INTO networks(organization_id,name,status,peer_isolation,is_intake)
SELECT o.id,'Entrada','ativa',true,true
FROM organizations o
WHERE NOT EXISTS (
        SELECT 1 FROM networks n
        WHERE n.organization_id=o.id AND n.is_intake)
  AND NOT EXISTS (
        SELECT 1 FROM networks n
        WHERE n.organization_id=o.id AND n.system_key IS NOT NULL)
ON CONFLICT (organization_id,name) DO NOTHING;

-- Sem subrede Principal o dispositivo entra na rede e fica fora de
-- device_subnetworks, ou seja, fora do modelo de visibilidade.
--
-- Ela nasce isolada porque desde 0042 quem decide contato direto é a SUBREDE,
-- não a rede: marcar só networks.peer_isolation deixaria os clientes da rede
-- de entrada se enxergando. A rede de entrada é o "sem rede/subrede" — o
-- dispositivo participa da VPN e não alcança ninguém. Enxergar os da própria
-- rede é consequência de ser movido para ela.
INSERT INTO subnetworks(network_id,name,peer_isolation)
SELECT n.id,'Principal',true FROM networks n WHERE n.is_intake
ON CONFLICT (network_id,name) DO NOTHING;

UPDATE subnetworks s SET peer_isolation=true
FROM networks n WHERE n.id=s.network_id AND n.is_intake AND NOT s.peer_isolation;

-- Apagar ou renomear a rede de entrada quebraria a instalação de clientes
-- daquela organização, que a resolve pelo flag e não por nome.
CREATE OR REPLACE FUNCTION protect_intake_networks()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' AND OLD.is_intake THEN
        RAISE EXCEPTION 'rede de entrada nao pode ser excluida';
    END IF;
    IF TG_OP='UPDATE' AND OLD.is_intake AND (
        NEW.is_intake IS DISTINCT FROM OLD.is_intake OR
        NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
        NEW.peer_isolation IS DISTINCT FROM OLD.peer_isolation
    ) THEN
        RAISE EXCEPTION 'rede de entrada nao pode ser reconfigurada';
    END IF;
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;

DROP TRIGGER IF EXISTS protect_intake_networks_trigger ON networks;
CREATE TRIGGER protect_intake_networks_trigger
BEFORE UPDATE OR DELETE ON networks
FOR EACH ROW EXECUTE FUNCTION protect_intake_networks();

-- Organização nova nasce com a sua. Cobre CreateTechnician (org pessoal do
-- supervisor) e CreateOrganization sem duplicar a regra nos dois handlers.
CREATE OR REPLACE FUNCTION ensure_intake_network()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE intake_id UUID;
BEGIN
    INSERT INTO networks(organization_id,name,status,peer_isolation,is_intake)
    VALUES(NEW.id,'Entrada','ativa',true,true)
    ON CONFLICT (organization_id,name) DO NOTHING
    RETURNING id INTO intake_id;
    IF intake_id IS NOT NULL THEN
        INSERT INTO subnetworks(network_id,name,peer_isolation)
        VALUES(intake_id,'Principal',true)
        ON CONFLICT (network_id,name) DO NOTHING;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS ensure_intake_network_trigger ON organizations;
CREATE TRIGGER ensure_intake_network_trigger
AFTER INSERT ON organizations
FOR EACH ROW EXECUTE FUNCTION ensure_intake_network();
