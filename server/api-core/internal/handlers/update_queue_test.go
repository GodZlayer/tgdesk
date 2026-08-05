package handlers

import (
	"strings"
	"testing"
)

// A fila existe para proteger a banda do próprio servidor. Se o limite deixar
// de valer acima do parque de referência, o produto volta a saturar o link
// justamente quando há mais gente para atender.
func TestFilaGrandeLimitaVelocidade(t *testing.T) {
	if throttleForQueue(largeQueueThreshold) != 0 {
		t.Error("fila dentro do limite não deve reduzir velocidade")
	}
	if throttleForQueue(largeQueueThreshold+1) != throttledKbps {
		t.Error("acima do parque de referência o download precisa ser limitado")
	}
	if largeQueueThreshold != 30 {
		t.Errorf("o parque de referência do produto é 30, e não %d", largeQueueThreshold)
	}
}

// Versão ilegível não vira ordem de atualização: empurrar uma instalação para
// uma máquina cuja versão não se consegue ler é agir no escuro.
func TestComparacaoDeVersaoNaoAdivinha(t *testing.T) {
	casos := []struct {
		current, target string
		older           bool
	}{
		{"1.1.36", "1.1.37", true},
		{"1.1.37", "1.1.37", false},
		{"1.1.38", "1.1.37", false},
		{"1.2", "1.10", true},
		{"", "1.1.37", false},
		{"beta", "1.1.37", false},
		{"1.1.37", "", false},
	}
	for _, caso := range casos {
		if got := versionIsOlder(caso.current, caso.target); got != caso.older {
			t.Errorf("versionIsOlder(%q,%q)=%v, esperado %v",
				caso.current, caso.target, got, caso.older)
		}
	}
}

// Um dispositivo por vez é a regra, e ela é resolvida no banco para continuar
// valendo se um dia houver mais de um processo servindo.
func TestVagaDeAtualizacaoEExclusiva(t *testing.T) {
	source := functionSource(t, "update_queue.go",
		"func (s *Server) claimUpdateSlot", "func nullableThrottle")
	if !strings.Contains(source, "state='em_andamento' AND device_id<>$1") {
		t.Error("a vaga precisa ser recusada quando outro dispositivo já atualiza")
	}
	if !strings.Contains(source, "FOR UPDATE SKIP LOCKED") {
		t.Error("a tomada da vaga precisa ser exclusiva no banco")
	}
	if !strings.Contains(source, "s.reclaimStaleUpdates") {
		t.Error("sem retomar entradas presas, um cliente que caiu trava a fila")
	}
}

// O cliente que cai no meio não pode deixar a fila parada para sempre, e
// tentar infinitas vezes também não resolve — depois do teto a entrada falha
// e a fila anda.
func TestEntradaPresaVoltaParaFila(t *testing.T) {
	source := functionSource(t, "update_queue.go",
		"func (s *Server) reclaimStaleUpdates", "func (s *Server) pendingUpdateCount")
	for _, regra := range []string{"'falhou'", "'pendente'", "started_at < now()"} {
		if !strings.Contains(source, regra) {
			t.Errorf("a retomada precisa considerar %q", regra)
		}
	}
	if maxUpdateAttempts < 1 {
		t.Error("é preciso ao menos uma tentativa")
	}
}
