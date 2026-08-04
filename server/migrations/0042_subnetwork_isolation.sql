-- TGDesk: contato direto entre dispositivos passa a ser decidido por
-- co-pertencimento a uma subrede, e não por endereço IP.
--
-- Regra única: dois participantes da VPN só se alcançam diretamente quando
-- existe uma subrede que contém os dois E que não é isolada. Todo o resto fala
-- apenas com o hub. Não há caso especial para sessão de acesso remoto: a
-- "subrede temporária" do MODELO-PRODUTO.md é só mais uma subrede, criada no
-- aceite do chamado e apagada no fechamento.
--
-- Isso torna a revogação estrutural em vez de procedural: como o Authorizer já
-- decide por pertencimento, apagar a subrede corta o acesso na camada de
-- aplicação e na de rede pelo mesmo ato, sem risco de uma ficar
-- dessincronizada da outra. E ninguém precisa ser movido nem trocar de IP,
-- porque device_subnetworks (0034) já é M:N.

-- 1) Isolamento agora é atributo da subrede. Subrede isolada é aquela em que
--    nem os próprios membros se enxergam — o caso da subrede de clientes
--    avulsos, que existe só para o dispositivo participar da VPN.
ALTER TABLE subnetworks
    ADD COLUMN IF NOT EXISTS peer_isolation BOOLEAN NOT NULL DEFAULT false;

-- 2) Subrede temporária de sessão: some junto com o chamado.
ALTER TABLE subnetworks
    ADD COLUMN IF NOT EXISTS ticket_id UUID REFERENCES support_tickets(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_subnetworks_ticket
    ON subnetworks(ticket_id) WHERE ticket_id IS NOT NULL;

-- 3) Toda rede precisa de ao menos uma subrede, senão seus dispositivos ficam
--    sem nenhum par possível sob a regra nova. Herda o isolamento da rede.
INSERT INTO subnetworks(network_id, name, peer_isolation)
SELECT n.id, 'Principal', n.peer_isolation
FROM networks n
WHERE NOT EXISTS (SELECT 1 FROM subnetworks s WHERE s.network_id = n.id)
ON CONFLICT (network_id, name) DO NOTHING;

-- 4) Propaga o isolamento que hoje está na rede para as subredes dela. Redes
--    de sistema TGDevs (avulsos, técnicos, supervisores) têm peer_isolation
--    verdadeiro desde 0035 e continuam isoladas.
UPDATE subnetworks s SET peer_isolation = true
FROM networks n
WHERE n.id = s.network_id AND n.peer_isolation AND NOT s.peer_isolation;

-- 5) Todo dispositivo precisa estar em alguma subrede da sua rede. Sem isso
--    ele fica sem par possível e some da regra.
INSERT INTO device_subnetworks(device_id, subnetwork_id)
SELECT d.id, s.id
FROM devices d
JOIN subnetworks s ON s.network_id = d.network_id
WHERE d.network_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM device_subnetworks ds
      JOIN subnetworks s2 ON s2.id = ds.subnetwork_id
      WHERE ds.device_id = d.id AND s2.network_id = d.network_id
  )
  AND s.name = 'Principal'
ON CONFLICT DO NOTHING;
