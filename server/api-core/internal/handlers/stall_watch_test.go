package handlers

import (
	"encoding/json"
	"sync"
	"testing"
	"time"
)

// Testes da detecção de trava por relógio externo (§6).
//
// O que se verifica aqui é COMPORTAMENTO NO TEMPO: quando abre, quando não
// abre, que duração registra e de onde ela vem. Por isso o watcher é montado à
// mão, com persistência de mentira e um buraco curto — esperar 1,5s reais em
// teste seria trocar verificação por paciência.

type registroDeTrava struct {
	mu        sync.Mutex
	aberturas []time.Time
	fechado   []time.Duration
	confianca []string
	origem    []string
}

func novoWatcherDeTeste(buraco time.Duration) (*stallWatcher, *registroDeTrava) {
	reg := &registroDeTrava{}
	w := &stallWatcher{
		deviceID:  "dispositivo-de-teste",
		ultimoHB:  time.Now(),
		buracoDur: buraco,
		tolerDur:  500 * time.Millisecond,
		parar:     make(chan struct{}),
	}
	w.persistAbrir = func(inicio time.Time) string {
		reg.mu.Lock()
		defer reg.mu.Unlock()
		reg.aberturas = append(reg.aberturas, inicio)
		return "trava-1"
	}
	w.persistFechar = func(_ string, inicio, fim time.Time, confianca, origem string) {
		reg.mu.Lock()
		defer reg.mu.Unlock()
		reg.fechado = append(reg.fechado, fim.Sub(inicio))
		reg.confianca = append(reg.confianca, confianca)
		reg.origem = append(reg.origem, origem)
	}
	go w.varrer()
	return w, reg
}

func (r *registroDeTrava) contagem() (int, int) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.aberturas), len(r.fechado)
}

func TestBatidaRegularNaoAbreTrava(t *testing.T) {
	w, reg := novoWatcherDeTeste(600 * time.Millisecond)
	defer w.encerrar()

	// Batendo bem mais rápido que o buraco, como faz o heartbeat de 2 Hz.
	for i := 0; i < 12; i++ {
		w.tick()
		time.Sleep(100 * time.Millisecond)
	}
	if abertas, _ := reg.contagem(); abertas != 0 {
		t.Fatalf("heartbeat regular abriu %d trava(s); não deveria abrir nenhuma", abertas)
	}
}

func TestBuracoAbreEVoltaFecha(t *testing.T) {
	w, reg := novoWatcherDeTeste(400 * time.Millisecond)
	defer w.encerrar()

	w.tick()
	time.Sleep(900 * time.Millisecond) // silêncio maior que o buraco
	abertas, fechadas := reg.contagem()
	if abertas != 1 {
		t.Fatalf("silêncio de 900ms com buraco de 400ms abriu %d trava(s), esperado 1", abertas)
	}
	if fechadas != 0 {
		t.Fatalf("trava fechou antes de o heartbeat voltar")
	}

	w.tick() // heartbeat voltou
	abertas, fechadas = reg.contagem()
	if fechadas != 1 {
		t.Fatalf("volta do heartbeat não fechou a trava (fechadas=%d)", fechadas)
	}
	if abertas != 1 {
		t.Fatalf("abriu trava a mais: %d", abertas)
	}

	// A duração medida tem que ser o buraco INTEIRO — do último heartbeat até a
	// volta — e não o tempo desde que a varredura percebeu. Medir a partir da
	// percepção embutiria o intervalo de varredura na duração.
	reg.mu.Lock()
	dur := reg.fechado[0]
	reg.mu.Unlock()
	if dur < 850*time.Millisecond {
		t.Fatalf("duração medida (%v) é menor que o buraco real (~900ms): "+
			"a varredura está sendo descontada da trava", dur)
	}
}

func TestBuracoUnicoNaoAbreDuasTravas(t *testing.T) {
	w, reg := novoWatcherDeTeste(300 * time.Millisecond)
	defer w.encerrar()

	w.tick()
	time.Sleep(1500 * time.Millisecond) // várias varreduras dentro do mesmo buraco
	if abertas, _ := reg.contagem(); abertas != 1 {
		t.Fatalf("um único buraco gerou %d travas; a varredura está reabrindo o mesmo evento", abertas)
	}
}

func TestEncerrarFechaTravaAbertaComConfiancaBaixa(t *testing.T) {
	w, reg := novoWatcherDeTeste(300 * time.Millisecond)

	w.tick()
	time.Sleep(700 * time.Millisecond)
	if abertas, _ := reg.contagem(); abertas != 1 {
		t.Fatalf("esperava trava aberta antes de encerrar")
	}

	// Conexão caiu com a trava em aberto: o dispositivo sumiu e não voltou para
	// contar por quê. Ficar aberta para sempre seria pior que não registrar.
	w.encerrar()
	reg.mu.Lock()
	defer reg.mu.Unlock()
	if len(reg.fechado) != 1 {
		t.Fatalf("encerrar deixou trava aberta no banco")
	}
	if reg.confianca[0] != "baixa" {
		t.Fatalf("trava sem volta do dispositivo ficou com confiança %q; deveria ser baixa",
			reg.confianca[0])
	}
	if reg.origem[0] != "indeterminado" {
		t.Fatalf("origem %q; sem o agente voltar não há como saber se foi trava ou rede",
			reg.origem[0])
	}
}

func TestOrigemDistingueRedeDeTrava(t *testing.T) {
	// A distinção que impede que toda queda de link vire falso positivo.
	if got := origemDaTrava(true); got != "trava" {
		t.Fatalf("relógio saltou ⇒ trava; got %q", got)
	}
	if got := origemDaTrava(false); got != "rede" {
		t.Fatalf("relógio correu normal ⇒ rede; got %q", got)
	}
}

func TestConfiancaDaConciliacao(t *testing.T) {
	const tol = 500
	cases := []struct {
		nome             string
		servidor, agente int64
		quer             string
	}{
		{"os dois concordam", 4200, 4100, "alta"},
		{"na borda da tolerância", 4200, 3700, "alta"},
		{"divergem além da tolerância", 4200, 2000, "media"},
		{"só o servidor viu", 4200, 0, "media"},
	}
	for _, c := range cases {
		if got := confiancaConciliada(c.servidor, c.agente, tol); got != c.quer {
			t.Fatalf("%s: got %q, want %q", c.nome, got, c.quer)
		}
	}
}

func TestContextoDeTravaAceitaBufferDoAgente(t *testing.T) {
	// O despejo do ring buffer é opcional e chega DEPOIS do evento; sua
	// ausência não pode quebrar a leitura do resto.
	var c contextoDeTrava
	if err := json.Unmarshal([]byte(`{"duracao_ms":4200,"relogio_saltou":true}`), &c); err != nil {
		t.Fatalf("contexto sem buffer não deveria falhar: %v", err)
	}
	if c.DuracaoMs != 4200 || !c.RelogioSaltou {
		t.Fatalf("contexto lido errado: %+v", c)
	}
}
