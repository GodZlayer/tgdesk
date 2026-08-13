package handlers

import "testing"

// A regra que faz a entrega diferida valer alguma coisa: o carimbo é o da
// COLETA. Um lote que subiu depois de um dia offline descreve um DIA — usar a
// hora de chegada comprimiria o dia inteiro no instante da reconexão, e todo
// histograma de pressão, janela de episódio e correlação com trava ficariam
// errados de um jeito invisível na tela.
func TestCarimboEODaColetaNaoODaChegada(t *testing.T) {
	fonte := lerFonte(t, "telemetria_local.go")

	// `roll_metric` tem que receber o instante da amostra, não now().
	if !contemTodos(fonte, []string{"roll_metric($1,$2,$3,$4)", "deviceID, metrica, valor, em"}) {
		t.Fatal("o histograma precisa receber o instante da COLETA")
	}
	if contemTodos(fonte, []string{"roll_metric($1,$2,$3,now())"}) {
		t.Fatal("a hora do servidor está sendo usada: um dia offline viraria um instante")
	}
}

// Amostra sem hora não pode ser situada, e amostra do futuro é relógio local
// errado. As duas precisam ser descartadas em vez de carimbadas na marra.
func TestAmostraSemHoraOuDoFuturoNaoEntra(t *testing.T) {
	fonte := lerFonte(t, "telemetria_local.go")
	if !contemTodos(fonte, []string{"a.Em.IsZero()", "a.Em.After(time.Now()"}) {
		t.Fatal("amostra sem hora ou do futuro precisa ser descartada")
	}
}
