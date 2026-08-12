package handlers

import (
	"context"
	"encoding/json"
	"sync"
	"time"
)

// Detecção de trava por relógio externo (§6 da arquitetura).
//
// A regra que este arquivo existe para cumprir: QUEM MEDE O TRAVAMENTO NÃO PODE
// SER QUEM TRAVA. O agente congelado não carimba a hora do próprio
// congelamento — acorda depois e só sabe que o relógio pulou, e mal. Então o
// servidor é a verdade sobre início e duração, e o que o agente manda depois é
// CONTEXTO, não relógio.
//
// Por isso `stall_event` guarda as duas origens em colunas separadas
// (`server_gap_ms` e `agent_ts`) e a conciliação numa terceira: em nenhum
// momento um lado sobrescreve o que o outro viu.
//
// Este detector vive por conexão. Não usa Redis: o buraco de heartbeat é um
// fato local da conexão, e roteá-lo por outro processo acrescentaria justamente
// a latência que estamos tentando medir.

type stallWatcher struct {
	s        *Server
	deviceID string

	mu        sync.Mutex
	ultimoHB  time.Time
	abertoID  string
	abertoEm  time.Time
	buracoDur time.Duration
	tolerDur  time.Duration

	pararUma sync.Once
	parar    chan struct{}

	// Persistência injetável. Não é enfeite de teste: o que decide se a
	// detecção está certa é o COMPORTAMENTO NO TEMPO (quando abre, quando
	// fecha, com que duração), e isso precisa ser verificável sem depender de
	// um Postgres de pé nem de esperar segundos reais.
	persistAbrir  func(inicio time.Time) string
	persistFechar func(id string, inicio, fim time.Time, confianca, origem string)
}

// origemDaTrava aplica a distinção de §6: se o relógio local do agente correu
// normalmente durante o buraco, o que houve foi queda de rede, não travamento.
// Sem esta regra, todo link instável viraria falso positivo de trava — e o
// dossiê acumularia "travou 40 vezes" para uma máquina que nunca travou.
func origemDaTrava(relogioSaltou bool) string {
	if relogioSaltou {
		return "trava"
	}
	return "rede"
}

// confiancaConciliada compara o que o servidor mediu com o que o agente
// relatou. O valor que prevalece é sempre o do servidor; o agente decide
// apenas o quanto se confia nele.
func confiancaConciliada(serverGapMs, agenteMs, toleranciaMs int64) string {
	if agenteMs <= 0 {
		// Só o servidor viu. Vale a medição dele, com confiança média (§6).
		return "media"
	}
	delta := serverGapMs - agenteMs
	if delta < 0 {
		delta = -delta
	}
	if delta <= toleranciaMs {
		return "alta"
	}
	return "media"
}

// Cadência de varredura. Precisa ser bem menor que o buraco que abre evento
// (1,5s por padrão), senão a granularidade da detecção seria maior que o
// fenômeno detectado.
const stallVarreduraIntervalo = 250 * time.Millisecond

func (s *Server) newStallWatcher(ctx context.Context, deviceID string) *stallWatcher {
	buracoMs := s.diagParam(ctx, "trava.buraco_abre_ms", 1500)
	tolerMs := s.diagParam(ctx, "trava.tolerancia_conciliacao_ms", 500)
	w := &stallWatcher{
		s:         s,
		deviceID:  deviceID,
		ultimoHB:  time.Now(),
		buracoDur: time.Duration(buracoMs) * time.Millisecond,
		tolerDur:  time.Duration(tolerMs) * time.Millisecond,
		parar:     make(chan struct{}),
	}
	w.persistAbrir = w.gravarAbertura
	w.persistFechar = w.gravarFechamento
	go w.varrer()
	return w
}

// tick é chamado a cada batida do heartbeat de alta frequência. É deliberado
// que ele não toque no banco: a 2 Hz por dispositivo, um UPDATE por batida
// transformaria presença em carga de escrita. O que persiste é o buraco, que é
// raro.
func (w *stallWatcher) tick() {
	w.mu.Lock()
	w.ultimoHB = time.Now()
	abertoID, abertoEm := w.abertoID, w.abertoEm
	w.abertoID, w.abertoEm = "", time.Time{}
	w.mu.Unlock()

	if abertoID != "" {
		w.fechar(abertoID, abertoEm)
	}
}

func (w *stallWatcher) varrer() {
	t := time.NewTicker(stallVarreduraIntervalo)
	defer t.Stop()
	for {
		select {
		case <-w.parar:
			return
		case <-t.C:
			w.mu.Lock()
			jaAberto := w.abertoID != ""
			desde := time.Since(w.ultimoHB)
			ultimo := w.ultimoHB
			w.mu.Unlock()
			if jaAberto || desde < w.buracoDur {
				continue
			}
			// O início da trava é a ÚLTIMA batida recebida, não o instante em
			// que percebemos. Usar o instante da percepção embutiria a
			// varredura na duração medida.
			w.abrir(ultimo)
		}
	}
}

func (w *stallWatcher) abrir(inicio time.Time) {
	id := w.persistAbrir(inicio)
	if id == "" {
		return
	}
	w.mu.Lock()
	w.abertoID, w.abertoEm = id, inicio
	w.mu.Unlock()
}

// fechar grava a duração vista pelo servidor. A confiança fica 'media' porque
// só um lado falou; sobe para 'alta' se o despejo do agente chegar e bater
// dentro da tolerância (conciliar).
func (w *stallWatcher) fechar(id string, inicio time.Time) {
	w.persistFechar(id, inicio, time.Now(), "media", "indeterminado")
}

func (w *stallWatcher) gravarAbertura(inicio time.Time) string {
	var id string
	if w.s.Pool.QueryRow(context.Background(), `
		INSERT INTO stall_event (device_id, inicio, confianca, origem)
		VALUES ($1, $2, 'media', 'indeterminado')
		RETURNING id`, w.deviceID, inicio).Scan(&id) != nil {
		return ""
	}
	return id
}

func (w *stallWatcher) gravarFechamento(id string, inicio, fim time.Time, confianca, origem string) {
	gap := fim.Sub(inicio).Milliseconds()
	_, _ = w.s.Pool.Exec(context.Background(), `
		UPDATE stall_event
		SET fim=$2, server_gap_ms=$3, duracao_conciliada_ms=$3,
		    confianca=$4, origem=$5
		WHERE id=$1`, id, fim, gap, confianca, origem)
}

// encerrar fecha o que estiver aberto quando a conexão cai. Uma trava que não
// terminou não pode ficar aberta para sempre no banco: viraria uma trava de
// duração infinita no dossiê, que é pior que não ter registro.
func (w *stallWatcher) encerrar() {
	w.pararUma.Do(func() { close(w.parar) })
	w.mu.Lock()
	id, em := w.abertoID, w.abertoEm
	w.abertoID = ""
	w.mu.Unlock()
	if id == "" {
		return
	}
	// Aqui a origem é honestamente desconhecida: o dispositivo sumiu e não
	// voltou para contar por quê. Fica 'indeterminado' e com confiança baixa —
	// não sustenta veredito (§6).
	w.persistFechar(id, em, time.Now(), "baixa", "indeterminado")
}

// contextoDeTrava é o despejo do ring buffer do agente, enviado DEPOIS do
// evento (§6). Nunca é usado como relógio.
type contextoDeTrava struct {
	// Quanto o agente acha que ficou parado. Serve só para conciliar.
	DuracaoMs int64 `json:"duracao_ms"`
	// O agente percebeu salto no próprio relógio? Se o relógio local correu
	// normal durante o buraco, foi REDE, não trava — sem essa distinção toda
	// queda de link viraria falso positivo de travamento.
	RelogioSaltou bool `json:"relogio_saltou"`
	// Recorte de alta resolução do que acontecia em volta.
	Buffer json.RawMessage `json:"buffer,omitempty"`
}

// receberContexto casa o despejo do agente com o último buraco fechado deste
// dispositivo e resolve confiança e origem.
func (w *stallWatcher) receberContexto(payload json.RawMessage) {
	var ctxTrava contextoDeTrava
	if json.Unmarshal(payload, &ctxTrava) != nil {
		return
	}

	// A decisão fica em Go, não no SQL: origem e confiança são regra de
	// diagnóstico, e regra de diagnóstico precisa ser lida e testada sem um
	// banco no meio.
	var buffer any = nil
	if len(ctxTrava.Buffer) > 0 {
		buffer = string(ctxTrava.Buffer)
	}

	var id string
	var serverGap int64
	if w.s.Pool.QueryRow(context.Background(), `
		SELECT id, coalesce(server_gap_ms, 0) FROM stall_event
		WHERE device_id=$1 AND fim IS NOT NULL AND agent_ts IS NULL
		ORDER BY inicio DESC LIMIT 1`, w.deviceID).Scan(&id, &serverGap) != nil {
		return
	}

	_, _ = w.s.Pool.Exec(context.Background(), `
		UPDATE stall_event
		SET agent_ts=$2::jsonb, origem=$3, confianca=$4
		WHERE id=$1`,
		id, buffer,
		origemDaTrava(ctxTrava.RelogioSaltou),
		confiancaConciliada(serverGap, ctxTrava.DuracaoMs, w.tolerDur.Milliseconds()),
	)
}
