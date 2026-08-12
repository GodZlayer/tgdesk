package handlers

import (
	"testing"

	"tgdesk/api-core/internal/diagnostico"
)

// Os casos deste arquivo são os mesmos de quando o motor era um serviço HTTP —
// o que mudou foi a fachada, não o que precisa continuar verdadeiro. Cada teste
// aqui protege uma promessa feita ao técnico, não um detalhe de implementação.

func TestCatalogoVazioProduzAbstencaoComDirecao(t *testing.T) {
	// É o estado real de um status ainda sem causas cadastradas. A resposta
	// honesta é "não sei", e abstenção sem direção é abstenção inútil (§10.5.1).
	r := diagnostico.InferirPorRegra(
		diagnostico.Dossie{DeviceID: "d1", StatusCodigo: "trava_sob_carga"},
		nil, nil, nil, nil,
	)
	if !r.Abstain {
		t.Fatal("status sem causas candidatas devia abster")
	}
	if len(r.ProximosTestes) == 0 {
		t.Fatal("abstenção chegou à tela sem dizer o que fazer em seguida")
	}
}

func TestNuncaMaisDeTresCausasNaTela(t *testing.T) {
	// §1: lista longa é o jeito de não decidir nada.
	causas := []string{"a", "b", "c", "d", "e"}
	priors := map[string]float64{"a": 0.5, "b": 0.2, "c": 0.15, "d": 0.1, "e": 0.05}
	r := diagnostico.InferirPorRegra(
		diagnostico.Dossie{DeviceID: "d1", StatusCodigo: "s", TemCurva: true},
		causas, priors, nil, nil,
	)
	if len(r.Causas) > 3 {
		t.Fatalf("tela receberia %d causas", len(r.Causas))
	}
}

func TestSemCurvaAProbabilidadeTemTeto(t *testing.T) {
	// §10.5.1: sem escada não existe limiar, então não existe veredito — por
	// mais que os sinais apontem para um lado só.
	r := diagnostico.InferirPorRegra(
		diagnostico.Dossie{DeviceID: "d1", StatusCodigo: "s", TemCurva: false},
		[]string{"disco_degradado", "memoria_instavel"},
		map[string]float64{"disco_degradado": 0.999, "memoria_instavel": 0.001},
		nil, nil,
	)
	if len(r.Causas) == 0 {
		t.Fatal("esperava causa dominante")
	}
	if r.Causas[0].Prob > diagnostico.TetoSemEscada {
		t.Fatalf("probabilidade %v passou do teto sem intervenção", r.Causas[0].Prob)
	}
}

func TestEvidenciaEmpurraACausaCerta(t *testing.T) {
	// O prior favorece memória; a evidência de SMART é de disco. A evidência
	// tem que virar o jogo, senão o motor está só repetindo o fórum.
	valor := 12.0
	r := diagnostico.InferirPorRegra(
		diagnostico.Dossie{
			DeviceID: "d1", StatusCodigo: "s", TemCurva: true,
			Evidencias: map[string]diagnostico.Evidencia{
				"smart_reallocated": {Literal: "Reallocated_Sector_Ct 12", Valor: &valor},
			},
		},
		[]string{"disco_degradado", "memoria_instavel"},
		map[string]float64{"disco_degradado": 0.3, "memoria_instavel": 0.7},
		map[string]float64{"smart_reallocated|disco_degradado": 5.0},
		nil,
	)
	if len(r.Causas) == 0 || r.Causas[0].Codigo != "disco_degradado" {
		t.Fatalf("evidência literal não moveu a probabilidade: %+v", r.Causas)
	}
	if len(r.Causas[0].Evidencias) == 0 {
		t.Fatal("causa apareceu sem a evidência que a sustenta — §10.5.1 exige o literal")
	}
}

func TestMontarPedidoAchataAChaveComposta(t *testing.T) {
	p := MontarPedido(
		"d1", "trava_sob_carga",
		[]string{"disco_degradado"},
		map[string]float64{"disco_degradado": 0.4},
		map[string]map[string]float64{
			"smart_reallocated": {"disco_degradado": 3.0},
		},
		nil, nil, false,
	)
	if p.PesosSinalCausa["smart_reallocated|disco_degradado"] != 3.0 {
		t.Fatalf("chave composta não foi achatada: %+v", p.PesosSinalCausa)
	}
	// Mapa nulo não chega ao motor: um nil onde se espera objeto é panic no
	// pior momento possível, que é com o técnico olhando a tela.
	if p.Priors == nil || p.NCasosPorCausa == nil {
		t.Fatal("mapa nulo foi enviado ao motor")
	}
}

func TestCatalogoVazioContinuaSendoPedidoValido(t *testing.T) {
	p := MontarPedido("d1", "", nil, nil, nil, nil, nil, false)
	if len(p.CausasCandidatas) != 0 {
		t.Fatal("catálogo vazio virou lista com lixo")
	}
}
