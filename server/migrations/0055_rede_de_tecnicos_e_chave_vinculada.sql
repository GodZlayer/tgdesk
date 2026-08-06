-- TGDesk: cada organização passa a ter a sua rede de técnicos, e a chave de
-- inscrição passa a carregar o vínculo.
--
-- Duas coisas que faltavam, ligadas pelo mesmo fio: saber quais técnicos são de
-- quem, e conseguir criar um técnico que já nasce sendo de alguém.

-- ---------------------------------------------------------------------------
-- 1) A rede de técnicos da organização.
-- ---------------------------------------------------------------------------
--
-- Espelha a rede de entrada (0049): uma por organização, isolada por peer. A
-- diferença é quem mora nela — ali chegam os dispositivos dos clientes, aqui
-- ficam as máquinas dos técnicos vinculados àquele supervisor.
--
-- Isolada por peer porque o propósito é registro, não convívio: o supervisor
-- precisa saber quantos técnicos vinculou e quais são, e os técnicos não têm
-- nada a fazer com as máquinas uns dos outros. Estar nesta rede não concede
-- acesso remoto nem função de supervisão — o que cada um pode fazer continua
-- vindo da credencial que apresenta, como em todo o resto do produto.
--
-- Não usa system_key porque aquele índice é único global (0035) e aqui existe
-- uma rede de técnicos POR organização — o mesmo motivo da rede de entrada.
ALTER TABLE networks
    ADD COLUMN IF NOT EXISTS is_technicians BOOLEAN NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS networks_technicians_unique_per_org
    ON networks(organization_id) WHERE is_technicians;

-- Uma rede de técnicos para cada organização que ainda não tem. As de sistema
-- da TGDevs ficam de fora: lá já existem tgdevs.tecnicos e tgdevs.supervisores,
-- que são o destino de quem não tem supervisor.
INSERT INTO networks(organization_id, name, cidr_virtual, status,
                     peer_isolation, is_technicians)
SELECT o.id, 'Técnicos', '10.70.0.0/16', 'ativa', true, true
FROM organizations o
WHERE o.system_internal IS NOT TRUE
  AND NOT EXISTS (
      SELECT 1 FROM networks n WHERE n.organization_id = o.id AND n.is_technicians
  )
-- (organization_id, name) é único, e a TGDevs já tem uma rede chamada
-- "Técnicos" — a de sistema, criada em 0035. Deixar o banco recusar em vez de
-- eu tentar prever o conflito: comparar o nome aqui dependeria da codificação
-- do cliente psql bater com a do dado gravado, e é exatamente esse tipo de
-- suposição que falha em silêncio numa máquina diferente.
ON CONFLICT (organization_id, name) DO NOTHING;

-- Toda rede precisa da subrede Principal: é ela que device_subnetworks
-- referencia, e sem ela o dispositivo entra na rede e fica fora de qualquer
-- subrede — invisível para o modelo de visibilidade.
INSERT INTO subnetworks(network_id, name, peer_isolation)
SELECT n.id, 'Principal', true
FROM networks n
WHERE n.is_technicians
  AND NOT EXISTS (SELECT 1 FROM subnetworks s WHERE s.network_id = n.id);

-- ---------------------------------------------------------------------------
-- 2) O vínculo do técnico com a organização.
-- ---------------------------------------------------------------------------
--
-- Um técnico vinculado é de uma organização e só dela. Ele continua alcançando
-- a TGDevs, que é o plano de controle de todo mundo, mas não pode ser
-- acrescentado a uma terceira: é funcionário daquele supervisor, não um
-- prestador que circula.
--
-- Nulo é o que sempre existiu: técnico independente, sem organização natal.
ALTER TABLE technicians
    ADD COLUMN IF NOT EXISTS affiliated_organization_id UUID
        REFERENCES organizations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS technicians_affiliated_idx
    ON technicians(affiliated_organization_id)
    WHERE affiliated_organization_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3) A chave decide o vínculo.
-- ---------------------------------------------------------------------------
--
-- "É a chave quem determina tudo na vinculação, por isso ela tem uso único."
--
-- O instalador continua burro: ele entrega a chave e não sabe o que ela
-- significa. Quem lê o vínculo e o aplica é o servidor, no momento em que a
-- chave é consumida — e como o consumo é único, o vínculo é decidido uma vez
-- só e não pode ser reinterpretado depois.
--
-- Nulo mantém o comportamento atual: chave de inscrição de máquina para um
-- técnico que já existe, sem afiliar ninguém a nada.
ALTER TABLE technician_enrollment_keys
    ADD COLUMN IF NOT EXISTS affiliated_organization_id UUID
        REFERENCES organizations(id) ON DELETE CASCADE;

-- Quem emitiu a chave vinculada. Serve para o supervisor ver quais chaves ele
-- gerou e o que aconteceu com cada uma — a chave é de uso único, então o
-- histórico é a única forma de saber se foi usada e por quem.
COMMENT ON COLUMN technician_enrollment_keys.affiliated_organization_id IS
    'Organização à qual o técnico fica vinculado ao consumir esta chave. '
    'Nulo = chave comum, sem vínculo.';
