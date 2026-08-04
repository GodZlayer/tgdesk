-- TGDesk: o cliente avulso passa a viver na rede de sistema
-- tgdevs.clientes_avulsos (criada em 0035, com peer_isolation=true), em vez da
-- org/rede paralela "Atendimento Avulso TGDesk"/"Pública isolada" criada por
-- ensureStandaloneScope antes de existir o plano de controle TGDevs.
--
-- Ver .godzmind/MODELO-PRODUTO.md, "Rede pública da VPN": a rede-base é
-- interna à VPN, sem peer-to-peer entre os membros e invisível fora do
-- super_admin. A rede legada não tinha peer_isolation, ou seja, os avulsos
-- ficavam sem o isolamento que o modelo exige.

-- 1) Move os dispositivos da rede avulsa legada para a rede de sistema.
WITH legacy AS (
    SELECT network_id FROM standalone_scope WHERE singleton=true
), target AS (
    SELECT id FROM networks WHERE system_key='tgdevs.clientes_avulsos'
)
UPDATE devices d SET network_id=(SELECT id FROM target), updated_at=now()
FROM legacy
WHERE d.network_id=legacy.network_id
  AND EXISTS (SELECT 1 FROM target);

-- 2) Reaponta a associação em device_networks, que é o que as listagens e o
--    Authorizer de fato consultam.
WITH legacy AS (
    SELECT network_id FROM standalone_scope WHERE singleton=true
), target AS (
    SELECT id FROM networks WHERE system_key='tgdevs.clientes_avulsos'
)
INSERT INTO device_networks(device_id,network_id)
SELECT dn.device_id, (SELECT id FROM target)
FROM device_networks dn, legacy
WHERE dn.network_id=legacy.network_id
  AND EXISTS (SELECT 1 FROM target)
ON CONFLICT DO NOTHING;

WITH legacy AS (
    SELECT network_id FROM standalone_scope WHERE singleton=true
)
DELETE FROM device_networks dn USING legacy
WHERE dn.network_id=legacy.network_id;

-- 3) Chamados já abertos apontando para a org/rede legada seguem o dispositivo,
--    para não ficarem órfãos de escopo depois da migração.
WITH legacy AS (
    SELECT organization_id, network_id FROM standalone_scope WHERE singleton=true
), target AS (
    SELECT organization_id, id AS network_id FROM networks
    WHERE system_key='tgdevs.clientes_avulsos'
)
UPDATE support_tickets t
SET organization_id=(SELECT organization_id FROM target),
    network_id=(SELECT network_id FROM target),
    updated_at=now()
FROM legacy
WHERE t.network_id=legacy.network_id
  AND EXISTS (SELECT 1 FROM target);

-- 4) Reaponta o singleton para a rede correta, para que qualquer caminho ainda
--    não migrado no código passe a resolver para a rede de sistema.
WITH target AS (
    SELECT organization_id, id FROM networks
    WHERE system_key='tgdevs.clientes_avulsos'
)
UPDATE standalone_scope SET organization_id=target.organization_id,
                            network_id=target.id
FROM target WHERE singleton=true;
