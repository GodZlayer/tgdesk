package handlers

import (
	"context"
	"encoding/json"
	"log"
	"sync"

	"tgdesk/api-core/internal/hardware"
)

// Reconciliação da época de hardware.
//
// A ordem correta do diagnóstico começa antes da telemetria: é a peça que
// define o que medir e o que esperar. E quando uma peça é trocada, a máquina
// passa a ser OUTRA — comparar medições de antes com as de depois é comparar
// dois computadores e chamar a diferença de degradação.
//
// Aqui é onde isso é registrado. A cada inventário recebido, a impressão das
// peças estáveis é recalculada; se mudou, a época anterior é fechada, uma nova
// é aberta e o evento guarda o que entrou e o que saiu.
//
// Como o inventário chega a cada poucos segundos por máquina, comparar contra
// o banco toda vez seriam milhares de consultas por hora para responder
// "continua igual" — que é a resposta em praticamente todas. A impressão
// corrente fica em memória e o banco só é tocado quando ela muda, ou na
// primeira vez que a máquina aparece após o processo subir.
var (
	impressoesMu       sync.RWMutex
	impressoesCorrente = map[string]string{}
)

// ReconciliarEpoca atualiza a época de hardware do dispositivo.
//
// Devolve o id da época vigente, ou vazio quando não foi possível determiná-la
// — e nesse caso a medida fica sem época em vez de ser atribuída à errada.
func (s *Server) ReconciliarEpoca(ctx context.Context, deviceID string, inventario []byte) string {
	retrato, err := hardware.Retratar(inventario)
	if err != nil {
		// Inventário parcial acontece: coleta cara que falhou, agente antigo.
		// Não é motivo para inventar uma troca de peça.
		return ""
	}

	impressoesMu.RLock()
	conhecida := impressoesCorrente[deviceID]
	impressoesMu.RUnlock()

	var epocaID string
	if conhecida == retrato.Impressao {
		// Caminho quente: nada mudou. Uma leitura barata só para carimbar a
		// medida com a época a que ela pertence.
		if err := s.Pool.QueryRow(ctx,
			`SELECT id::text FROM hardware_epoch
			  WHERE device_id=$1 AND encerrou_em IS NULL`, deviceID).Scan(&epocaID); err != nil {
			return ""
		}
		return epocaID
	}

	var atualID, atualImpressao string
	err = s.Pool.QueryRow(ctx,
		`SELECT id::text, impressao FROM hardware_epoch
		  WHERE device_id=$1 AND encerrou_em IS NULL`, deviceID).Scan(&atualID, &atualImpressao)

	componentes, _ := json.Marshal(retrato.Componentes)

	if err != nil || atualID == "" {
		// Primeira época desta máquina. Não é troca de peça — é a primeira vez
		// que sabemos quais peças ela tem, e registrar isso como "alteração"
		// encheria o histórico de falsos eventos a cada dispositivo novo.
		if errIns := s.Pool.QueryRow(ctx,
			`INSERT INTO hardware_epoch (device_id, impressao, componentes)
			 VALUES ($1,$2,$3) RETURNING id::text`,
			deviceID, retrato.Impressao, componentes).Scan(&epocaID); errIns != nil {
			return ""
		}
		s.lembrarImpressao(deviceID, retrato.Impressao)
		return epocaID
	}

	if atualImpressao == retrato.Impressao {
		// A memória do processo estava fria (reinício do servidor); o banco já
		// sabia. Só realinha.
		s.lembrarImpressao(deviceID, retrato.Impressao)
		return atualID
	}

	// Mudou de verdade. Fecha a época anterior, abre a nova e registra o que
	// aconteceu — em transação, porque uma época fechada sem sucessora deixa a
	// máquina sem identidade e toda medida seguinte órfã.
	var anterior hardware.Retrato
	var brutoAnterior []byte
	_ = s.Pool.QueryRow(ctx,
		`SELECT componentes FROM hardware_epoch WHERE id=$1`, atualID).Scan(&brutoAnterior)
	_ = json.Unmarshal(brutoAnterior, &anterior.Componentes)
	alteracoes := hardware.Comparar(anterior, retrato)
	alteracoesJSON, _ := json.Marshal(alteracoes)
	if len(alteracoes) == 0 {
		alteracoesJSON = []byte("[]")
	}

	tx, txErr := s.Pool.Begin(ctx)
	if txErr != nil {
		return atualID
	}
	defer tx.Rollback(ctx)

	if _, e := tx.Exec(ctx,
		`UPDATE hardware_epoch SET encerrou_em=now() WHERE id=$1`, atualID); e != nil {
		return atualID
	}
	if e := tx.QueryRow(ctx,
		`INSERT INTO hardware_epoch (device_id, impressao, componentes)
		 VALUES ($1,$2,$3) RETURNING id::text`,
		deviceID, retrato.Impressao, componentes).Scan(&epocaID); e != nil {
		return atualID
	}
	if _, e := tx.Exec(ctx,
		`INSERT INTO hardware_change (device_id, epoca_anterior, epoca_nova, alteracoes)
		 VALUES ($1,$2,$3,$4)`,
		deviceID, atualID, epocaID, alteracoesJSON); e != nil {
		return atualID
	}
	if e := tx.Commit(ctx); e != nil {
		return atualID
	}

	s.lembrarImpressao(deviceID, retrato.Impressao)
	log.Printf("hardware: %s mudou de peça — %d alteração(ões); época %s encerrada, %s aberta",
		deviceID, len(alteracoes), atualID, epocaID)
	return epocaID
}

func (s *Server) lembrarImpressao(deviceID, impressao string) {
	impressoesMu.Lock()
	impressoesCorrente[deviceID] = impressao
	impressoesMu.Unlock()
}
