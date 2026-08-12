package main

import (
	"testing"
	"time"
)

// Testes do ring buffer de contexto de trava (§6).
//
// O ponto que estes testes protegem é a fronteira de autoridade: o agente só
// pode afirmar que o PRÓPRIO relógio saltou. Se ele começasse a afirmar duração
// de trava, o dado voltaria a carregar a incerteza do tamanho da própria trava
// — que é justamente o problema que o relógio externo resolve.

func TestBufferMantemOrdemCronologicaAposDarVolta(t *testing.T) {
	r := novoRingBufferTrava()
	// Uma volta e meia: é o caso em que um buffer circular mal escrito devolve
	// o histórico embaralhado, e histórico embaralhado é pior que nenhum.
	for i := 0; i < ringBufferCap+ringBufferCap/2; i++ {
		r.registrar(nil)
	}
	r.mu.Lock()
	amostras := r.instantaneoLocked()
	r.mu.Unlock()

	if len(amostras) != ringBufferCap {
		t.Fatalf("buffer devolveu %d amostras, esperado o teto de %d",
			len(amostras), ringBufferCap)
	}
	for i := 1; i < len(amostras); i++ {
		if amostras[i].T < amostras[i-1].T {
			t.Fatalf("amostra %d é anterior à %d: buffer devolveu fora de ordem", i, i-1)
		}
	}
}

func TestSemSaltoNaoHaDespejo(t *testing.T) {
	r := novoRingBufferTrava()
	for i := 0; i < 20; i++ {
		r.registrar(nil)
	}
	if r.despejar() != nil {
		t.Fatal("amostragem normal gerou despejo de trava; isso encheria o dossiê de ruído")
	}
}

func TestSaltoDeRelogioViraDespejoComBuffer(t *testing.T) {
	r := novoRingBufferTrava()
	for i := 0; i < 5; i++ {
		r.registrar(nil)
	}
	// Simula o congelamento: a última amostra ficou velha porque o processo não
	// rodou. É exatamente o que um freeze produz.
	r.mu.Lock()
	r.ultima = time.Now().Add(-4200 * time.Millisecond)
	r.mu.Unlock()
	r.registrar(nil)

	d := r.despejar()
	if d == nil {
		t.Fatal("salto de 4,2s não gerou despejo")
	}
	if !d.RelogioSaltou {
		t.Fatal("despejo por congelamento tem que marcar relogio_saltou; sem isso o servidor não separa trava de queda de rede")
	}
	if d.DuracaoMs < 4000 {
		t.Fatalf("duração relatada %dms, esperado ~4200ms", d.DuracaoMs)
	}
	if len(d.Buffer) == 0 {
		t.Fatal("despejo veio sem contexto; o contexto é a única coisa que o servidor não tem")
	}
	if r.despejar() != nil {
		t.Fatal("despejo repetiu: o mesmo evento seria contado duas vezes")
	}
}

func TestBuracoDeRedeNaoMarcaSaltoDeRelogio(t *testing.T) {
	// O outro lado da distinção: o servidor viu buraco, mas o agente estava
	// vivo o tempo todo. Isso é queda de link, não travamento.
	r := novoRingBufferTrava()
	r.registrar(nil)
	r.registrarBuracoDeRede(3 * time.Second)

	d := r.despejar()
	if d == nil {
		t.Fatal("buraco de rede não gerou despejo")
	}
	if d.RelogioSaltou {
		t.Fatal("buraco de rede marcado como salto de relógio: todo Wi-Fi instável viraria trava no dossiê")
	}
}

func TestSaltoMaiorPrevaleceSobrePendente(t *testing.T) {
	r := novoRingBufferTrava()
	r.marcarSalto(2 * time.Second)
	r.marcarSalto(9 * time.Second)
	r.marcarSalto(3 * time.Second)

	d := r.despejar()
	if d == nil || d.DuracaoMs < 9000 {
		t.Fatalf("prevaleceu o salto errado: %+v — o buraco maior é o que o servidor também viu", d)
	}
}
