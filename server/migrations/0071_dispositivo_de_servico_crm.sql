-- TGDesk: dispositivo de serviço (tier 'crm').
--
-- devices.role diz a FUNÇÃO DA MÁQUINA, não o papel do usuário (0026):
--   'host'       -> máquina atendida
--   'supervisor' -> máquina de controle do supervisor
--   'crm'        -> máquina-SERVIDOR de um produto que vive dentro da VPN
--
-- Por que um tier e não uma permissão de usuário: o alcance de rede no TGDesk
-- nunca dependeu de papel — quem decide é a subrede compartilhada, e o firewall
-- do hub não consulta credencial nenhuma (wg/hub.go). Aqui continua igual: o
-- tier 'crm' não dá poder, não vê nada a mais e não administra ninguém. Ele só
-- marca que aquela máquina é um serviço da organização, sem operador humano, e
-- por isso é legítimo qualquer dispositivo da VPN pedir para alcançá-la.
--
-- Marcar a máquina de trabalho de uma pessoa como 'crm' a tornaria alcançável
-- por todo dispositivo que pedisse — nos dois sentidos, porque ApplySessionPairs
-- libera o par nas duas direções. O CHECK abaixo não consegue impedir isso
-- sozinho; quem impede é CRMJoin, que recusa alvo com control_technician_id.
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_role_check;

ALTER TABLE devices ADD CONSTRAINT devices_role_check
    CHECK (role IN ('host', 'supervisor', 'crm'));

-- Uma máquina de serviço não é máquina de controle de ninguém. Se fosse, o
-- dispositivo teria dono humano e o registro aberto viraria exposição do
-- computador dessa pessoa.
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_crm_sem_dono;

ALTER TABLE devices ADD CONSTRAINT devices_crm_sem_dono
    CHECK (role <> 'crm' OR control_technician_id IS NULL);
