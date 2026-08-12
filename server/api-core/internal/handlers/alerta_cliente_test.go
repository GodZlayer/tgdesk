package handlers

import (
	"testing"
	"time"
)

// Testes dos alertas (§9) e da recidiva (§13.5).
//
// A coisa que estes testes protegem é a confiança do cliente no produto. Um
// alerta que nomeia causa errada, ou que repete sem parar, ensina a pessoa a
// ignorar o aviso — e aí o produto perde exatamente o que ele tinha de valor.

func limiaresPadrao() LimiaresDeAlerta {
	// Os valores da §18, que em produção vêm de `diag_param`.
	return LimiaresDeAlerta{
		Nivel2Prob:            0.90,
		Nivel2CasosMin:        30,
		SomeAbaixoDe:          0.50,
		MaxSimultaneos:        2,
		AntiRepeticao:         14 * 24 * time.Hour,
		SilencioAposDescartar: 30 * 24 * time.Hour,
	}
}

func TestCausaNaoPromovidaNaoViraNivel2MesmoComProbabilidadeAlta(t *testing.T) {
	// Probabilidade alta de uma causa que nunca foi validada é confiança
	// emprestada, não medida.
	c := EstadoDaCausa{Codigo: "disco_degradado", Prob: 0.97, Promovida: false, CasosInternos: 3}
	if got := NivelDoAlerta(c, limiaresPadrao()); got != AlertaNivel1 {
		t.Fatalf("nível %q: 97%% sem validação virou causa nomeada ao cliente", got)
	}
}

func TestCausaPromovidaComProbabilidadeAltaViraNivel2(t *testing.T) {
	c := EstadoDaCausa{Codigo: "disco_degradado", Prob: 0.93, Promovida: true}
	if got := NivelDoAlerta(c, limiaresPadrao()); got != AlertaNivel2 {
		t.Fatalf("nível %q, esperado 2", got)
	}
}

func TestHistoricoInternoSubstituiAPromocao(t *testing.T) {
	// A camada de regra também pode nomear causa — desde que tenha histórico
	// próprio. Exigir rede treinada travaria o produto até o parque crescer.
	c := EstadoDaCausa{Codigo: "memoria_instavel", Prob: 0.91, Promovida: false, CasosInternos: 30}
	if got := NivelDoAlerta(c, limiaresPadrao()); got != AlertaNivel2 {
		t.Fatalf("nível %q: 30 casos internos deveriam bastar", got)
	}
}

func TestProbabilidadeBaixaFazOAlertaDesaparecer(t *testing.T) {
	c := EstadoDaCausa{Codigo: "x", Prob: 0.49, Promovida: true}
	if got := NivelDoAlerta(c, limiaresPadrao()); got != AlertaNenhum {
		t.Fatalf("nível %q: alerta ficou preso na tela abaixo do piso", got)
	}
}

func TestRebaixamentoDeNivel2ParaNivel1(t *testing.T) {
	// Se a confiança cai, o alerta volta a descrever sintoma — não continua
	// afirmando causa.
	lim := limiaresPadrao()
	antes := EstadoDaCausa{Codigo: "x", Prob: 0.95, Promovida: true}
	depois := EstadoDaCausa{Codigo: "x", Prob: 0.72, Promovida: true}
	if NivelDoAlerta(antes, lim) != AlertaNivel2 || NivelDoAlerta(depois, lim) != AlertaNivel1 {
		t.Fatal("rebaixamento automático não aconteceu")
	}
}

func TestChamadoAbertoSilenciaOAlerta(t *testing.T) {
	agora := time.Now()
	h := AlertaHistorico{ChamadoAberto: true}
	if ok, motivo := PodeEnviar(h, agora, limiaresPadrao()); ok || motivo == "" {
		t.Fatal("alertou alguém que já abriu chamado: ruído em cima de quem já agiu")
	}
}

func TestAntiRepeticaoRespeitaAJanela(t *testing.T) {
	agora := time.Now()
	lim := limiaresPadrao()

	recente := AlertaHistorico{UltimoEnviadoEm: agora.Add(-3 * 24 * time.Hour)}
	if ok, _ := PodeEnviar(recente, agora, lim); ok {
		t.Fatal("repetiu o alerta 3 dias depois; a janela é de 14")
	}

	antigo := AlertaHistorico{UltimoEnviadoEm: agora.Add(-20 * 24 * time.Hour)}
	if ok, _ := PodeEnviar(antigo, agora, lim); !ok {
		t.Fatal("não realertou depois da janela")
	}
}

func TestDescarteDoClienteSilenciaPorMaisTempo(t *testing.T) {
	agora := time.Now()
	h := AlertaHistorico{DescartadoEm: agora.Add(-20 * 24 * time.Hour)}
	if ok, _ := PodeEnviar(h, agora, limiaresPadrao()); ok {
		t.Fatal("reapareceu 20 dias após o cliente descartar; o silêncio é de 30")
	}
}

func TestTetoDeDoisAlertasSimultaneos(t *testing.T) {
	candidatos := []AlertaCandidato{
		{"a", AlertaNivel1, 0.60},
		{"b", AlertaNivel2, 0.95},
		{"c", AlertaNivel1, 0.75},
		{"d", AlertaNenhum, 0.10},
	}
	sel := SelecionarAlertas(candidatos, limiaresPadrao())
	if len(sel) != 2 {
		t.Fatalf("selecionou %d alertas; três avisos de uma vez treinam o cliente a ignorar", len(sel))
	}
	if sel[0].StatusCodigo != "b" || sel[1].StatusCodigo != "c" {
		t.Fatalf("selecionou os errados: %+v", sel)
	}
}

func TestAlertaNenhumNuncaEhSelecionado(t *testing.T) {
	sel := SelecionarAlertas([]AlertaCandidato{{"a", AlertaNenhum, 0.99}}, limiaresPadrao())
	if len(sel) != 0 {
		t.Fatal("alerta de nível 'nenhum' foi enviado")
	}
}

// --- recidiva ---

func TestSintomaQueVoltouEmSeteDiasEhPaliativo(t *testing.T) {
	fechado := time.Now().Add(-40 * 24 * time.Hour)
	oc := []Ocorrencia{{Em: fechado.Add(3 * 24 * time.Hour)}}

	r7, r30, aberta := AvaliarRecidiva(fechado, oc, time.Now(), 7*24*time.Hour, 30*24*time.Hour)
	if !r7 || !r30 {
		t.Fatalf("recidiva de 3 dias não foi marcada: r7=%v r30=%v", r7, r30)
	}
	if aberta {
		t.Fatal("janela de 30 dias deveria estar fechada após 40 dias")
	}
}

func TestSintomaAnteriorAoReparoNaoEhRecidiva(t *testing.T) {
	// É o problema original, não a volta dele. Contá-lo marcaria como paliativo
	// todo reparo que funcionou.
	fechado := time.Now().Add(-40 * 24 * time.Hour)
	oc := []Ocorrencia{{Em: fechado.Add(-2 * 24 * time.Hour)}}

	r7, r30, _ := AvaliarRecidiva(fechado, oc, time.Now(), 7*24*time.Hour, 30*24*time.Hour)
	if r7 || r30 {
		t.Fatal("sintoma anterior ao reparo contou como recidiva")
	}
}

func TestVoltaEntreSeteETrintaDiasSoMarcaALonga(t *testing.T) {
	fechado := time.Now().Add(-40 * 24 * time.Hour)
	oc := []Ocorrencia{{Em: fechado.Add(20 * 24 * time.Hour)}}

	r7, r30, _ := AvaliarRecidiva(fechado, oc, time.Now(), 7*24*time.Hour, 30*24*time.Hour)
	if r7 {
		t.Fatal("volta em 20 dias marcou recidiva de 7")
	}
	if !r30 {
		t.Fatal("volta em 20 dias não marcou recidiva de 30")
	}
}

func TestJanelaAindaAbertaNaoEhConclusao(t *testing.T) {
	// "Ainda não voltou" não é "não vai voltar". Gravar isso como conclusão
	// contaminaria o treino com otimismo.
	fechado := time.Now().Add(-5 * 24 * time.Hour)

	_, r30, aberta := AvaliarRecidiva(fechado, nil, time.Now(), 7*24*time.Hour, 30*24*time.Hour)
	if r30 {
		t.Fatal("marcou ausência de recidiva com a janela ainda aberta")
	}
	if !aberta {
		t.Fatal("janela de 30 dias deveria estar aberta após 5 dias")
	}
}
