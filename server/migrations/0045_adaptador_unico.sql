-- TGDesk: um adaptador por máquina.
--
-- O papel — cliente, técnico, supervisor, admin — é decidido pelo servidor a
-- partir da credencial apresentada, NUNCA pela rede. Logo não faz sentido o
-- papel Técnico ter identidade de rede própria: existe um dispositivo, um
-- adaptador ("tgdesk0") e um endereço.
--
-- Antes a máquina do técnico subia um segundo adaptador ("TGDesk-Tech", pool
-- 10.70.1.x), deixando DUAS rotas para 10.70.0.0/16 no mesmo Windows,
-- resolvidas por métrica. Isso tornava imprevisível qual endereço originava o
-- tráfego — e o isolamento por subrede depende exatamente de saber isso.
--
-- Os endereços liberados voltam ao pool (0041) em vez de serem descartados.

-- 1) Devolve ao pool os endereços que os técnicos ocupavam. Só entram os que
--    pertencem a uma rede conhecida; endereços do /24 legado 10.70.1.x ficam
--    simplesmente livres, já que aquele pool não é mais consultado.
INSERT INTO network_free_ips(network_id, virtual_ip)
SELECT p.network_id, t.wg_virtual_ip
FROM technicians t
JOIN network_pools p
  ON p.cidr_octet = split_part(t.wg_virtual_ip, '.', 3)::int
WHERE coalesce(t.wg_virtual_ip,'') <> ''
ON CONFLICT (virtual_ip) DO NOTHING;

-- 2) Libera a identidade de rede do técnico. A conta segue intacta: some
--    apenas o endereço e a chave do adaptador que deixou de existir.
UPDATE technicians
SET wg_virtual_ip = NULL, wg_pubkey = NULL
WHERE coalesce(wg_virtual_ip,'') <> '' OR coalesce(wg_pubkey,'') <> '';

-- 3) A sequência do /24 reservado de técnicos não é mais usada.
DROP SEQUENCE IF EXISTS technician_host_octet_seq;
