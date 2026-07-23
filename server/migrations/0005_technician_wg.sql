-- Túnel WireGuard próprio do Técnico (Hub), independente do device Host.
-- Reserva o octeto 1 (10.70.1.x) para técnicos, distinto das redes de
-- cliente (10.70.2.x em diante, ver 0002_wireguard.sql) — assim o mesmo
-- computador pode ter o Host e o Hub instalados ao mesmo tempo, cada um
-- com seu próprio adaptador/túnel, sem disputar o mesmo vínculo de rede.
CREATE SEQUENCE technician_host_octet_seq START 2;

ALTER TABLE technicians ADD COLUMN wg_pubkey TEXT;
ALTER TABLE technicians ADD COLUMN wg_virtual_ip TEXT;
