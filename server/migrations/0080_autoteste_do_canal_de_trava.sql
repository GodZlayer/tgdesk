-- Prova, em produção, de que o canal de contexto de trava funciona.
--
-- O problema que isto resolve: a transmissão do `stall_context` — o agente
-- despejando o ring buffer depois de um congelamento — só é exercitada quando
-- há congelamento. Ou seja, o caminho crítico do detector fica sem prova até o
-- dia em que ele precisa funcionar, que é o pior dia para descobrir que não
-- funciona.
--
-- Foi assim que 2.275 travas falsas passaram despercebidas: cada peça tinha
-- teste, nenhuma tinha prova de que conversava com a seguinte.
--
-- A solução é um AUTOTESTE: ao conectar, o agente envia um contexto marcado
-- como autoteste. O servidor NÃO cria evento de trava com ele — só carimba
-- aqui que a mensagem chegou. É o mesmo princípio de um POST de hardware:
-- exercitar o caminho quando não custa nada, para saber que ele existe.
--
-- Carimbo VAZIO é informação: significa que aquele dispositivo nunca provou
-- que consegue reportar um congelamento, e qualquer ausência de travas no
-- histórico dele é inconclusiva em vez de tranquilizadora.

ALTER TABLE devices ADD COLUMN IF NOT EXISTS stall_canal_verificado_em TIMESTAMPTZ;

COMMENT ON COLUMN devices.stall_canal_verificado_em IS
    'Ultima vez que o agente provou, por autoteste, que consegue transmitir contexto de trava. NULL = nunca provou, e a ausencia de travas no historico e inconclusiva.';

CREATE INDEX IF NOT EXISTS idx_devices_stall_canal_nao_verificado
    ON devices (id) WHERE stall_canal_verificado_em IS NULL;
