-- Os pesos do modelo passam a morar no Postgres, não em volume.
--
-- Consequência de uma regra do projeto: UM CONTAINER POR PROJETO. A rede não
-- tem serviço próprio — vive dentro do api-core, em `internal/diagnostico`. Sem
-- container separado, não há volume de modelo compartilhado, e inventar um
-- diretório no host para guardar pesos criaria estado fora do banco: mais uma
-- coisa para versionar, sincronizar e perder num restore.
--
-- Guardar aqui resolve os três de uma vez. O backup do banco já leva o modelo
-- junto, `hash_pesos` continua provando qual modelo produziu qual diagnóstico,
-- e restaurar um dump restaura o cérebro junto com o dado.
--
-- A fronteira dura de §3 não se perde ao juntar os processos, e fica mais
-- forte: a rede não tem rota, não abre canal, não conhece RBAC nem cliente. É
-- uma função chamada pelo api-core, não um serviço com endereço próprio.

ALTER TABLE model_version ADD COLUMN IF NOT EXISTS pesos JSONB;

COMMENT ON COLUMN model_version.pesos IS
    'Estado serializado do cabecote: camadas, escala do vetorizador e temperatura de calibracao. Ver internal/diagnostico/rede.go.';

-- Só uma versão por status pode estar servindo. O índice parcial garante isso
-- no banco: duas versões promovidas para o mesmo status seria ambiguidade sobre
-- quem respondeu, e diagnóstico ambíguo não é auditável.
CREATE UNIQUE INDEX IF NOT EXISTS idx_model_version_uma_promovida
    ON model_version (status_codigo, coalesce(causa_codigo, ''))
    WHERE estado = 'promovido';
