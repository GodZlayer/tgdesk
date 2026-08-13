package main

import (
	"sync"
	"time"
)

// Ring buffer de alta resolução para contexto de trava (§6 da arquitetura).
//
// A divisão de trabalho com o servidor é a regra central do capítulo: QUEM MEDE
// O TRAVAMENTO NÃO PODE SER QUEM TRAVA. O servidor é o relógio — ele vê o buraco
// no heartbeat e é a verdade sobre início e duração. Este arquivo NÃO mede
// trava; ele guarda o que estava acontecendo em volta e entrega depois.
//
// A única coisa que o agente afirma sobre o tempo é se o PRÓPRIO relógio saltou.
// Isso não serve para medir a trava: serve para distinguir trava de queda de
// rede. Se o processo continuou amostrando normalmente durante o buraco, a
// máquina não travou — o link caiu. Sem essa distinção, todo Wi-Fi instável
// viraria "travou 40 vezes" no dossiê.

const (
	// 60 s a 10 Hz (§18: trava.ring_buffer_s / trava.ring_buffer_hz).
	ringBufferHz       = 10
	ringBufferSegundos = 60
	ringBufferCap      = ringBufferHz * ringBufferSegundos

	// Um salto é uma amostra que demorou MUITO mais que o período. 1s contra um
	// período de 100ms é folgado de propósito: escalonamento de SO atrasa
	// amostra o tempo todo, e chamar isso de trava encheria o dossiê de ruído.
	saltoDeRelogio = 1 * time.Second
)

// amostraDeContexto é um ponto do buffer. Fica deliberadamente pequeno: a 10 Hz,
// carregar payload gordo em memória o tempo todo custaria mais que o valor de
// diagnóstico que ele traz.
type amostraDeContexto struct {
	T     int64   `json:"t"`               // epoch ms
	CPU   float64 `json:"cpu,omitempty"`   // % de uso
	RAM   float64 `json:"ram,omitempty"`   // % em uso
	Disco float64 `json:"disco,omitempty"` // % de tempo ocupado
}

// contextoPendente é o despejo pronto para subir no próximo ciclo do canal.
type contextoPendente struct {
	// Autoteste: prova que o CANAL funciona, sem afirmar que houve trava.
	//
	// A transmissão do contexto só é exercitada quando há congelamento — ou
	// seja, o caminho crítico do detector ficaria sem prova até o dia em que
	// precisa funcionar, que é o pior dia para descobrir que não funciona.
	// Aqui ele é exercitado na conexão, quando não custa nada.
	//
	// O servidor trata esta mensagem à parte: carimba que o canal está de pé e
	// NUNCA cria evento de trava com ela.
	Autoteste bool `json:"autoteste,omitempty"`

	DuracaoMs     int64               `json:"duracao_ms"`
	RelogioSaltou bool                `json:"relogio_saltou"`
	Buffer        []amostraDeContexto `json:"buffer"`
}

type ringBufferTrava struct {
	mu       sync.Mutex
	amostras []amostraDeContexto
	proximo  int
	cheio    bool

	ultima   time.Time
	pendente *contextoPendente

	parar chan struct{}
	uma   sync.Once
}

var (
	ringTravaUma    sync.Once
	ringTravaGlobal *ringBufferTrava
)

// ringBufferDeTrava devolve o buffer do processo. É deliberadamente global e
// não por conexão: o congelamento normalmente DERRUBA a conexão, e um buffer
// que morresse junto perderia exatamente o contexto do evento que existe para
// registrar.
func ringBufferDeTrava() *ringBufferTrava {
	ringTravaUma.Do(func() {
		ringTravaGlobal = novoRingBufferTrava()
		// Com coletor: o buffer passa a guardar CPU e memória a 10 Hz, além da
		// linha do tempo.
		//
		// Sem isso, o despejo de uma trava chegava vazio — dizia QUANDO
		// congelou e nada sobre o que a máquina estava fazendo. O contexto é
		// justamente a única coisa que o servidor não tem: ele mede a duração
		// pelo relógio externo, mas não enxerga dentro da máquina congelada.
		//
		// `amostrarRapido` é syscall direta, de propósito. A 10 Hz, qualquer
		// coisa mais cara transformaria o buffer na causa do travamento que ele
		// existe para explicar — foi assim que a coleta de telemetria acabou
		// registrando 250 travas falsas por hora.
		ringTravaGlobal.iniciar(amostrarRapido)
	})
	return ringTravaGlobal
}

func novoRingBufferTrava() *ringBufferTrava {
	return &ringBufferTrava{
		amostras: make([]amostraDeContexto, ringBufferCap),
		ultima:   time.Now(),
		parar:    make(chan struct{}),
	}
}

// iniciar liga a amostragem. `coletar` é injetado para que o buffer não dependa
// de como as métricas são obtidas — e para que dê para testar sem tocar em
// hardware nenhum.
func (r *ringBufferTrava) iniciar(coletar func() amostraDeContexto) {
	go func() {
		t := time.NewTicker(time.Second / ringBufferHz)
		defer t.Stop()
		for {
			select {
			case <-r.parar:
				return
			case <-t.C:
				r.registrar(coletar)
			}
		}
	}()
}

func (r *ringBufferTrava) encerrar() {
	r.uma.Do(func() { close(r.parar) })
}

func (r *ringBufferTrava) registrar(coletar func() amostraDeContexto) {
	agora := time.Now()

	r.mu.Lock()
	desde := agora.Sub(r.ultima)
	r.ultima = agora
	r.mu.Unlock()

	// O processo ficou parado tempo demais entre duas amostras: ou a máquina
	// congelou, ou o SO suspendeu. De qualquer forma o relógio saltou, e é isso
	// — e só isso — que o agente tem autoridade para afirmar.
	if desde >= saltoDeRelogio {
		r.marcarSalto(desde)
	}

	var amostra amostraDeContexto
	if coletar != nil {
		amostra = coletar()
	}
	amostra.T = agora.UnixMilli()

	r.mu.Lock()
	r.amostras[r.proximo] = amostra
	r.proximo = (r.proximo + 1) % ringBufferCap
	if r.proximo == 0 {
		r.cheio = true
	}
	r.mu.Unlock()
}

func (r *ringBufferTrava) marcarSalto(duracao time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	// Se já havia um despejo pendente, prevalece o salto MAIOR: o buraco maior
	// é o que o servidor também terá visto, e é o que interessa conciliar.
	if r.pendente != nil && r.pendente.DuracaoMs >= duracao.Milliseconds() {
		return
	}
	r.pendente = &contextoPendente{
		DuracaoMs:     duracao.Milliseconds(),
		RelogioSaltou: true,
	}
}

// despejar entrega o contexto pendente, se houver, e limpa. O buffer vai junto
// porque é justamente o que o servidor não tem: o que acontecia em volta.
//
// Devolve nil quando não há nada — o caminho normal, chamado a cada ciclo do
// canal sem custo.
func (r *ringBufferTrava) despejar() *contextoPendente {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.pendente == nil {
		return nil
	}
	saida := r.pendente
	r.pendente = nil
	saida.Buffer = r.instantaneoLocked()
	return saida
}

// registrarBuracoDeRede é chamado quando a reconexão do canal aconteceu SEM que
// o relógio local tivesse saltado. É o outro lado da distinção: houve buraco
// para o servidor, mas o agente estava vivo o tempo todo.
func (r *ringBufferTrava) registrarBuracoDeRede(duracao time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.pendente != nil {
		return
	}
	r.pendente = &contextoPendente{
		DuracaoMs:     duracao.Milliseconds(),
		RelogioSaltou: false,
	}
}

// instantaneoLocked devolve as amostras em ordem cronológica. Exige o mutex.
func (r *ringBufferTrava) instantaneoLocked() []amostraDeContexto {
	if !r.cheio {
		saida := make([]amostraDeContexto, r.proximo)
		copy(saida, r.amostras[:r.proximo])
		return saida
	}
	saida := make([]amostraDeContexto, 0, ringBufferCap)
	saida = append(saida, r.amostras[r.proximo:]...)
	saida = append(saida, r.amostras[:r.proximo]...)
	return saida
}

// contextoDeAutoteste monta o despejo que prova o canal na conexão.
//
// Leva uma amostra real do buffer, não um payload vazio: se a serialização do
// contexto quebrar, é aqui que se descobre — e não durante o congelamento que
// a gente passou meses esperando registrar.
func (r *ringBufferTrava) contextoDeAutoteste() *contextoPendente {
	r.mu.Lock()
	defer r.mu.Unlock()

	// Reaproveita o mesmo instantâneo que uma trava real usaria: se a
	// serialização do contexto quebrar, é aqui que se descobre — e não durante
	// o congelamento que a gente passou meses esperando registrar.
	todas := r.instantaneoLocked()
	if n := len(todas); n > 5 {
		todas = todas[n-5:]
	}
	return &contextoPendente{
		Autoteste:     true,
		DuracaoMs:     0,
		RelogioSaltou: false,
		Buffer:        todas,
	}
}
