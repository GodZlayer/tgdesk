package handlers

import (
	"context"
	"os"
	"strconv"
	"strings"
	"time"
)

// Fila de atualização. O servidor empurra; o dispositivo não decide nada.
//
// A banda é do próprio servidor e é limitada, então atualiza um dispositivo
// por vez. Com fila grande, a velocidade de cada download também é limitada:
// mesmo serializada, uma máquina baixando a plena carga tira banda do
// atendimento que está acontecendo ao vivo.

const (
	// Acima disto a fila é considerada grande e o download passa a ser
	// limitado. O número veio do parque de referência do produto.
	largeQueueThreshold  = 30
	throttledKbps        = 2048
	maxConcurrentUpdates = 2
	// Uma entrada em andamento tempo demais é um cliente que caiu no meio.
	// Sem isto a fila inteira ficaria parada esperando alguém que não volta.
	updateLeaseTimeout = 15 * time.Minute
	maxUpdateAttempts  = 3
)

func advertisedVersion() string {
	return os.Getenv("CLIENT_VERSION")
}

// versionIsOlder responde se "current" ficou para trás de "target". Versão
// ilegível responde falso: na dúvida não se empurra atualização para uma
// máquina cuja versão não se consegue ler.
func versionIsOlder(current, target string) bool {
	parse := func(version string) []int {
		parts := strings.Split(strings.TrimPrefix(strings.TrimSpace(version), "v"), ".")
		values := make([]int, len(parts))
		for index, part := range parts {
			value, err := strconv.Atoi(part)
			if err != nil || value < 0 {
				return nil
			}
			values[index] = value
		}
		return values
	}
	left, right := parse(current), parse(target)
	if left == nil || right == nil {
		return false
	}
	size := len(left)
	if len(right) > size {
		size = len(right)
	}
	for index := 0; index < size; index++ {
		var a, b int
		if index < len(left) {
			a = left[index]
		}
		if index < len(right) {
			b = right[index]
		}
		if a != b {
			return a < b
		}
	}
	return false
}

// enqueueDeviceUpdate coloca o dispositivo na fila quando a versão dele ficou
// para trás. Chamado quando o dispositivo aparece no canal de controle, que é
// o momento em que se sabe a versão dele — publicar uma release não precisa
// avisar ninguém: quem estiver ativo entra na fila ao se conectar, e quem
// estiver desligado entra quando voltar.
func (s *Server) enqueueDeviceUpdate(ctx context.Context, deviceID, deviceVersion string) {
	target := advertisedVersion()
	if target == "" || deviceID == "" {
		return
	}
	// Dispositivo que não informa a versão é dispositivo velho, e entra na fila.
	//
	// Antes o silêncio era lido como "não sei, então não mexo", e isso criou um
	// impasse: o heartbeat só passou a carregar client_version na 1.1.38, e o
	// agente publicado até a 1.1.52 era anterior a isso. Quem estava em campo
	// não informava a versão, então nunca era enfileirado, então nunca recebia
	// o agente que informaria — o caminho que entregaria o conserto era o
	// próprio caminho quebrado.
	//
	// Enfileirar quem não informa custa pouco e resolve: o cliente compara o
	// manifesto com a versão dele antes de aplicar, e desiste sozinho se já
	// estiver em dia (stageModularUpdate → updateIsNewer). O risco de mandar
	// atualizar quem já está atualizado é uma consulta a mais; o de não mandar
	// é uma frota inteira parada, que foi o que aconteceu.
	if deviceVersion != "" && !versionIsOlder(deviceVersion, target) {
		// Chegou na versão alvo: é aqui que a atualização se conclui de fato.
		// O dispositivo voltou dizendo a versão nova, e isso é a única prova
		// de que a troca de arquivos aconteceu — a palavra do agente no
		// update_result não serve, porque ele responde antes de aplicar.
		_, _ = s.Pool.Exec(ctx, `
			UPDATE device_update_queue
			SET state='concluido', finished_at=now(), error=NULL
			WHERE device_id=$1 AND version=$2 AND state<>'concluido'`,
			deviceID, target)
		return
	}
	// Entradas de versões antigas não interessam mais: o alvo é sempre a
	// versão corrente, e insistir numa anterior só gastaria banda.
	_, _ = s.Pool.Exec(ctx, `
		DELETE FROM device_update_queue
		WHERE device_id=$1 AND version<>$2 AND state IN ('pendente','em_andamento')`,
		deviceID, target)
	_, _ = s.Pool.Exec(ctx, `
		INSERT INTO device_update_queue(device_id,version) VALUES ($1,$2)
		ON CONFLICT (device_id,version) DO NOTHING`, deviceID, target)
}

// reclaimStaleUpdates devolve à fila quem ficou em andamento tempo demais.
// É o que impede um cliente que caiu de travar todos os outros.
func (s *Server) reclaimStaleUpdates(ctx context.Context) {
	_, _ = s.Pool.Exec(ctx, `
		UPDATE device_update_queue
		SET state=CASE WHEN attempts>=$2 THEN 'falhou' ELSE 'pendente' END,
		    error=CASE WHEN attempts>=$2 THEN 'sem resposta do dispositivo' ELSE error END,
		    finished_at=CASE WHEN attempts>=$2 THEN now() ELSE NULL END,
		    started_at=NULL
		WHERE state='em_andamento' AND started_at < now() - $1::interval`,
		updateLeaseTimeout.String(), maxUpdateAttempts)
}

// pendingUpdateCount alimenta a decisão de limitar velocidade e o texto que o
// cliente vê enquanto espera a vez dele.
func (s *Server) pendingUpdateCount(ctx context.Context) int {
	var total int
	_ = s.Pool.QueryRow(ctx, `
		SELECT count(*) FROM device_update_queue
		WHERE state IN ('pendente','em_andamento')`).Scan(&total)
	return total
}

func throttleForQueue(pending int) int {
	if pending > largeQueueThreshold {
		return throttledKbps
	}
	return 0
}

// claimUpdateSlot tenta dar a vez ao dispositivo. Devolve falso quando outro
// já está atualizando — um por vez é a regra, e ela é resolvida no banco para
// continuar valendo se um dia houver mais de um processo servindo.
func (s *Server) claimUpdateSlot(ctx context.Context, deviceID string) (bool, int, string) {
	s.reclaimStaleUpdates(ctx)
	var active int
	if s.Pool.QueryRow(ctx, `
		SELECT count(*) FROM device_update_queue
		WHERE state='em_andamento' AND device_id<>$1`, deviceID).Scan(&active) != nil || active >= maxConcurrentUpdates {
		return false, 0, ""
	}
	throttle := throttleForQueue(s.pendingUpdateCount(ctx))
	var version string
	err := s.Pool.QueryRow(ctx, `
		UPDATE device_update_queue
		SET state='em_andamento', started_at=now(), attempts=attempts+1,
		    throttle_kbps=$2
		WHERE id = (
		    SELECT id FROM device_update_queue
		    WHERE device_id=$1 AND state='pendente'
		    ORDER BY created_at LIMIT 1
		    FOR UPDATE SKIP LOCKED)
		RETURNING version`, deviceID, nullableThrottle(throttle)).Scan(&version)
	if err != nil {
		return false, 0, ""
	}
	return true, throttle, version
}

func nullableThrottle(kbps int) any {
	if kbps <= 0 {
		return nil
	}
	return kbps
}

// finishUpdate encerra a vez do dispositivo. Sucesso ou falha, a vaga é
// liberada aqui — o próximo da fila só anda quando esta linha sai de
// 'em_andamento'.
func (s *Server) finishUpdate(ctx context.Context, deviceID string, ok bool, failure string) {
	if ok {
		// "OK" do dispositivo NÃO conclui a linha.
		//
		// O que o agente responde é o retorno de RunUpdate, que vale 0 para
		// "já estava atualizado" e 10 para "download começou" — nenhum dos
		// dois significa "trocou os arquivos e voltou na versão nova". A
		// aplicação acontece depois, no atualizador elevado, que pode falhar e
		// reverter sem ninguém avisar o servidor.
		//
		// Era assim que a fila mentia: a Dani apareceu 'concluido' na 1.1.55
		// enquanto rodava 1.1.48. Quem conclui agora é o heartbeat, quando o
		// dispositivo volta dizendo a versão nova — o único sinal que prova
		// que a troca aconteceu. Se não voltar, o lease devolve para a fila.
		_, _ = s.Pool.Exec(ctx, `
			UPDATE device_update_queue SET error=NULL
			WHERE device_id=$1 AND state='em_andamento'`, deviceID)
		return
	}
	_, _ = s.Pool.Exec(ctx, `
		UPDATE device_update_queue
		SET state=CASE WHEN attempts>=$3 THEN 'falhou' ELSE 'pendente' END,
		    error=$2,
		    finished_at=CASE WHEN attempts>=$3 THEN now() ELSE NULL END,
		    started_at=NULL
		WHERE device_id=$1 AND state='em_andamento'`,
		deviceID, failure, maxUpdateAttempts)
}
