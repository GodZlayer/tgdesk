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

// O par (evidência, causa) só existe no fechamento do atendimento: as medidas
// vêm do dossiê e do exame, o rótulo vem do técnico que abriu a máquina.
// Nenhum dos dois sozinho é exemplo de treino.
//
// Sem isto, o conjunto de treino continua 100% simulado de fórum — e um modelo
// que só viu fórum aprende o fórum.
func TestCasoFechadoViraExemploDeTreino(t *testing.T) {
	fonte := lerFonte(t, "rat_laco.go")
	if !contemTodos(fonte, []string{"gravarExemploDeTreino", "'interno_rat'"}) {
		t.Fatal("o atendimento fechado não está virando exemplo de treino")
	}
	// A característica tem que ser a MESMA que o motor viu ao diagnosticar.
	// Um conjunto diferente treinaria a rede num mundo que ela não encontra.
	if !contemTodos(fonte, []string{"s.evidenciasDoDispositivo(ctx, deviceID)"}) {
		t.Fatal("o exemplo precisa usar a mesma evidência que o motor usou")
	}
}

// Rótulo sem medida ensina a rede a chutar aquela causa sempre que não souber
// de nada — exatamente o oposto do que se quer.
func TestRotuloSemMedidaNaoViraExemplo(t *testing.T) {
	fonte := lerFonte(t, "rat_laco.go")
	if !contemTodos(fonte, []string{"if len(d.Evidencias) == 0 {"}) {
		t.Fatal("exemplo com vetor vazio precisa ser recusado")
	}
}
