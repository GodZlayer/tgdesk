-- TGDesk: a atualização passa a ser empurrada pelo servidor.
--
-- O cliente não clica em nada: publicar uma versão coloca todo dispositivo
-- ativo na fila, e o servidor decide quando é a vez de cada um. Antes o
-- dispositivo é que decidia, a partir de um aviso de versão nova, e todos
-- baixavam ao mesmo tempo.
--
-- A fila é persistida porque um cliente que cai no meio da atualização não
-- pode travar os outros: o estado sobrevive à queda do dispositivo e à
-- reinicialização do servidor, e uma entrada em andamento tempo demais é
-- retomada em vez de ficar pendurada.

CREATE TABLE IF NOT EXISTS device_update_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    version TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'pendente'
        CHECK (state IN ('pendente','em_andamento','concluido','falhou')),
    attempts INT NOT NULL DEFAULT 0,
    throttle_kbps INT,
    error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    UNIQUE (device_id, version)
);

-- Um dispositivo por vez é a regra, então a busca quente é "a entrada mais
-- antiga que ainda espera" e "existe alguma em andamento?".
CREATE INDEX IF NOT EXISTS idx_device_update_queue_pendentes
    ON device_update_queue(created_at) WHERE state = 'pendente';

CREATE INDEX IF NOT EXISTS idx_device_update_queue_andamento
    ON device_update_queue(started_at) WHERE state = 'em_andamento';
