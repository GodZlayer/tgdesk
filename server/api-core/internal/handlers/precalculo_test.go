package handlers

import "testing"

// Testes da camada de pré-cálculo (§10.4).
//
// A invariante em jogo: nenhuma tela busca dado ao montar. Para isso valer, o
// servidor tem que acertar duas coisas — empurrar quando mudou, e NÃO empurrar
// quando não mudou. Errar a segunda transforma push em polling ao contrário.

func origensBase() OrigensDoPreCalculo {
	return OrigensDoPreCalculo{
		VersaoModelo:     "regra",
		VersaoPerfil:     "completa/1",
		VersaoParametros: "v1",
		JanelaTelemetria: "29341",
		VersaoInventario: "inv-abc",
		VersaoCatalogo:   "cat-1",
	}
}

func TestClienteSemRetratoRecebeAPrimeiraEntrega(t *testing.T) {
	// É isto que substitui a busca ao montar a tela.
	p := PreCalculo{DeviceID: "d1", Origens: origensBase()}
	if !PrecisaEmpurrar(p, "") {
		t.Fatal("cliente sem retrato não receberia nada; a tela ficaria vazia para sempre")
	}
}

func TestNadaMudouNaoEmpurra(t *testing.T) {
	p := PreCalculo{DeviceID: "d1", Origens: origensBase()}.Selar()
	if PrecisaEmpurrar(p, p.Impressao) {
		t.Fatal("empurrou sem mudança: isso é polling com o servidor no papel de quem pergunta")
	}
}

func TestQualquerOrigemQueMudaDisparaEmpurrao(t *testing.T) {
	base := PreCalculo{DeviceID: "d1", Origens: origensBase()}.Selar()

	casos := map[string]func(*OrigensDoPreCalculo){
		"versão de modelo":     func(o *OrigensDoPreCalculo) { o.VersaoModelo = "rede-v2" },
		"perfil de escada":     func(o *OrigensDoPreCalculo) { o.VersaoPerfil = "completa/2" },
		"parâmetros":           func(o *OrigensDoPreCalculo) { o.VersaoParametros = "v2" },
		"janela de telemetria": func(o *OrigensDoPreCalculo) { o.JanelaTelemetria = "29342" },
		"inventário":           func(o *OrigensDoPreCalculo) { o.VersaoInventario = "inv-xyz" },
		"catálogo":             func(o *OrigensDoPreCalculo) { o.VersaoCatalogo = "cat-2" },
	}
	for nome, mudar := range casos {
		origens := origensBase()
		mudar(&origens)
		novo := PreCalculo{DeviceID: "d1", Origens: origens}
		if !PrecisaEmpurrar(novo, base.Impressao) {
			t.Fatalf("mudança em %s não invalidou o retrato: o cliente ficaria com dado velho", nome)
		}
	}
}

func TestImpressaoEhEstavelParaAsMesmasOrigens(t *testing.T) {
	// Instabilidade aqui faria o servidor empurrar sem parar, mesmo sem nada
	// ter mudado.
	a := PreCalculo{DeviceID: "d1", Origens: origensBase()}.Selar()
	b := PreCalculo{DeviceID: "d1", Origens: origensBase()}.Selar()
	if a.Impressao != b.Impressao {
		t.Fatalf("impressões diferentes para as mesmas origens: %q vs %q", a.Impressao, b.Impressao)
	}
	if a.Impressao == "" {
		t.Fatal("retrato foi selado sem impressão; não teria como ser invalidado")
	}
}

func TestJanelaTruncadaNaoMudaACadaSegundo(t *testing.T) {
	// Sem truncar, a impressão mudaria continuamente e o servidor empurraria
	// sem parar.
	const janela = 300 // 5 min
	// Ancorado no INÍCIO de uma janela. A primeira versão deste teste usou um
	// instante arbitrário e dois pontos separados por 120s caíram em janelas
	// diferentes por acaso — o teste acusava o código, e o errado era ele.
	const borda = 1_754_000_100 // múltiplo de 300
	inicio := VersaoDeJanela(borda, janela)
	poucoDepois := VersaoDeJanela(borda+120, janela)
	janelaSeguinte := VersaoDeJanela(borda+janela, janela)

	if inicio != poucoDepois {
		t.Fatal("dois segundos diferentes dentro da MESMA janela geraram versões diferentes")
	}
	if inicio == janelaSeguinte {
		t.Fatal("janela seguinte não gerou versão nova; o retrato nunca se atualizaria")
	}
}

func TestAbrirChamadoMaterializaSemRecalcular(t *testing.T) {
	// Abrir chamado não dispara inferência: congela o que já existia. O que
	// muda é o estado, não o cálculo.
	p := PreCalculo{
		DeviceID:       "d1",
		StatusProvavel: "trava_sob_carga_io",
		CausasPassivas: []CausaInferida{{Codigo: "disco_degradado", Prob: 0.62}},
		TipoDeChamado:  "hardware_disco",
		Origens:        origensBase(),
	}.Selar()

	congelado := MaterializarChamado(p)

	if congelado.Impressao != p.Impressao {
		t.Fatal("materializar mudou a impressão: houve recálculo onde deveria haver cópia")
	}
	if congelado.StatusProvavel != p.StatusProvavel ||
		len(congelado.CausasPassivas) != len(p.CausasPassivas) {
		t.Fatal("o chamado não partiu do dossiê que já existia")
	}
}

func TestGatePrevistoCarregaOMotivo(t *testing.T) {
	// O técnico precisa ver no pré-voo que o disco vai rodar só em leitura, e
	// por quê — não descobrir durante a execução.
	p := PreCalculo{
		DeviceID: "d1",
		GatesPrevistos: []GatePrevisto{
			{Codigo: "disco_somente_leitura", Motivo: "SMART com 12 setores realocados"},
		},
		Origens: origensBase(),
	}.Selar()

	if p.GatesPrevistos[0].Motivo == "" {
		t.Fatal("gate sem motivo: viraria uma limitação inexplicada na tela")
	}
}
