-- TGDesk: nunca pode existir mais de um administrador no sistema.
--
-- É metodologia de segurança: o tier admin tem os mesmos direitos do
-- supervisor e alguns a mais, e concentrar isso numa única conta é o que
-- limita o alcance de um comprometimento. Dois administradores é estado
-- inválido, não caso raro.
--
-- A garantia vive no banco para que nenhum caminho a contorne — nem seed, nem
-- promoção de papel, nem correção manual.

-- Índice único sobre expressão constante com predicado parcial: no máximo uma
-- linha em technicians pode ter role='super_admin'.
CREATE UNIQUE INDEX IF NOT EXISTS technicians_um_super_admin
    ON technicians((true)) WHERE role = 'super_admin';
