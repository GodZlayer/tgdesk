package corpus

import "testing"

// Testes da derivação (§13.6).
//
// O que se protege aqui é a inversão que dá nome ao capítulo: o corpus define o
// catálogo, não o contrário. Se estas funções mentirem, o produto vai medir o
// que é fácil de medir em vez do que os casos reais exigiram.

func TestExtracaoDeSinaisEmDuasLinguas(t *testing.T) {
	sinais := ExtrairSinais("your SMART shows 12 reallocated sectors and disk latency is high")
	if !contem(sinais, "smart_reallocated") {
		t.Fatalf("não extraiu smart_reallocated de %v", sinais)
	}
	pt := ExtrairSinais("o disco tem setores realocados e a temperatura passa de 90 °C")
	if !contem(pt, "smart_reallocated") || !contem(pt, "temperatura") {
		t.Fatalf("extração em português falhou: %v", pt)
	}
}

func TestExtracaoNaoRepeteSinal(t *testing.T) {
	// O mesmo sinal escrito de duas formas na mesma mensagem é um sinal, não
	// dois — senão a frequência infla e a poda decide errado.
	s := ExtrairSinais("memtest found a memory error, run memtest86 again")
	n := 0
	for _, x := range s {
		if x == "erro_memoria" {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("sinal contado %d vezes na mesma mensagem", n)
	}
}

func TestSinalExclusivoDeUmaClasseSeparaMelhor(t *testing.T) {
	casos := []CasoDerivado{
		// smart_reallocated só aparece em disco: separa perfeitamente.
		{Classe: "disco", Sinais: []string{"smart_reallocated", "erro_sistema_log"}},
		{Classe: "disco", Sinais: []string{"smart_reallocated", "erro_sistema_log"}},
		// erro_sistema_log aparece em todas: frequente e inútil.
		{Classe: "memoria", Sinais: []string{"erro_memoria", "erro_sistema_log"}},
		{Classe: "termico", Sinais: []string{"temperatura", "erro_sistema_log"}},
	}
	demanda := AgregarDemanda(casos)

	var smart, log DemandaDeSinal
	for _, d := range demanda {
		switch d.Sinal {
		case "smart_reallocated":
			smart = d
		case "erro_sistema_log":
			log = d
		}
	}
	if smart.GanhoDeInformacao <= log.GanhoDeInformacao {
		t.Fatalf("sinal exclusivo (%.2f) não separou melhor que o onipresente (%.2f): "+
			"o catálogo priorizaria o que aparece muito em vez do que decide",
			smart.GanhoDeInformacao, log.GanhoDeInformacao)
	}
	if log.CasosQueExigiram != 4 {
		t.Fatalf("frequência errada: %d", log.CasosQueExigiram)
	}
	// O mais discriminante tem que vir primeiro, que é a ordem de revisão.
	if demanda[0].Sinal != "smart_reallocated" && demanda[0].GanhoDeInformacao < 1 {
		t.Fatalf("ordem de revisão errada: primeiro é %q", demanda[0].Sinal)
	}
}

func TestCoberturaEhMedidaPorClasseNuncaEmAgregado(t *testing.T) {
	// O cenário que a §13.6 manda impedir: média alta escondendo uma classe
	// inteira em zero.
	casos := []CasoDerivado{
		{Classe: "disco", Sinais: []string{"smart_reallocated"}},
		{Classe: "disco", Sinais: []string{"smart_reallocated"}},
		{Classe: "disco", Sinais: []string{"smart_reallocated"}},
		{Classe: "energia", Sinais: []string{"tensao"}},
	}
	disponiveis := map[string]bool{"smart_reallocated": true} // não medimos tensão

	cob := MedirCobertura(casos, disponiveis)
	if len(cob) != 2 {
		t.Fatalf("esperava uma linha por classe, veio %d", len(cob))
	}
	// Pior primeiro: é onde está o trabalho.
	if cob[0].Classe != "energia" || cob[0].Cobertura != 0 {
		t.Fatalf("classe em zero não apareceu primeiro: %+v", cob[0])
	}
	if len(cob[0].Lacunas) == 0 || cob[0].Lacunas[0] != "tensao" {
		t.Fatalf("lacuna não foi nomeada: %+v", cob[0].Lacunas)
	}
	if cob[1].Cobertura != 1 {
		t.Fatalf("cobertura de disco deveria ser 1, veio %.2f", cob[1].Cobertura)
	}
}

func TestCasoSemSinalExtraidoContaContraACobertura(t *testing.T) {
	// Do ponto de vista do produto, um caso que não deixou sinal nenhum não
	// seria resolvido. Contá-lo como coberto seria mentir para nós mesmos.
	cob := MedirCobertura(
		[]CasoDerivado{{Classe: "disco", Sinais: nil}},
		map[string]bool{"smart_reallocated": true},
	)
	if cob[0].Cobertura != 0 {
		t.Fatalf("caso sem sinal virou coberto: %.2f", cob[0].Cobertura)
	}
}

func TestPodaSeparaOQueFicaDoQueSai(t *testing.T) {
	demanda := []DemandaDeSinal{
		{Sinal: "smart_reallocated", CasosQueExigiram: 40},
		{Sinal: "curiosidade", CasosQueExigiram: 1},
	}
	ficam, saem := Podar(demanda, 5)
	if len(ficam) != 1 || ficam[0].Sinal != "smart_reallocated" {
		t.Fatalf("poda manteve o errado: %+v", ficam)
	}
	if len(saem) != 1 {
		t.Fatal("a poda não registrou o que saiu; poda silenciosa não é revisável")
	}
}

func TestExtracaoDeTestesCitados(t *testing.T) {
	testes := ExtrairTestes("run memtest86 overnight and check crystaldiskinfo for smart status")
	if !contem(testes, "memtest") || !contem(testes, "smart_leitura") {
		t.Fatalf("testes citados não foram extraídos: %v", testes)
	}
}

func contem(lista []string, alvo string) bool {
	for _, s := range lista {
		if s == alvo {
			return true
		}
	}
	return false
}

func TestCoberturaSeparaLacunaDeProdutoDeLacunaDeExtracao(t *testing.T) {
	// Os dois derrubam a cobertura, mas pedem trabalho oposto: um é sensor que
	// falta no agente, o outro é vocabulário pobre do nosso extrator. Somados,
	// mandariam a equipe construir hardware para um problema de leitura de texto.
	casos := []CasoDerivado{
		{Classe: "disco", Sinais: []string{"smart_reallocated"}}, // medimos
		{Classe: "disco", Sinais: []string{"tensao"}},            // não medimos
		{Classe: "disco", Sinais: nil},                           // não entendemos
		{Classe: "disco", Sinais: nil},
	}
	cob := MedirCobertura(casos, map[string]bool{"smart_reallocated": true})[0]

	if cob.CasosSemSinal != 2 {
		t.Fatalf("casos sem sinal = %d, esperado 2", cob.CasosSemSinal)
	}
	if len(cob.Lacunas) != 1 || cob.Lacunas[0] != "tensao" {
		t.Fatalf("lacuna de produto contaminada pela de extração: %v", cob.Lacunas)
	}
	if cob.Cobertura != 0.25 {
		t.Fatalf("cobertura %.2f, esperado 0.25", cob.Cobertura)
	}
}

func TestCoberturaInstrumentadaIgnoraCasosSemMedicao(t *testing.T) {
	// A pergunta de §13.6 é "o catálogo conseguiria ter discriminado?". Um caso
	// resolvido sem nenhuma medição citada não tem como dizer qual instrumento
	// faltou — ele não é evidência contra o catálogo, é evidência de que aquele
	// problema não se resolve por telemetria.
	casos := []CasoDerivado{
		{Classe: "disco", Sinais: []string{"smart_reallocated"}}, // medimos
		{Classe: "disco", Sinais: []string{"tensao"}},            // não medimos
		{Classe: "disco", Sinais: nil},                           // sem medição
		{Classe: "disco", Sinais: nil},
		{Classe: "disco", Sinais: nil},
	}
	cob := MedirCobertura(casos, map[string]bool{"smart_reallocated": true})[0]

	if cob.Cobertura != 0.2 {
		t.Fatalf("cobertura crua %.2f, esperado 0.20", cob.Cobertura)
	}
	// 1 de 2 casos que citaram medição.
	if cob.CoberturaInstrumentada != 0.5 {
		t.Fatalf("cobertura instrumentada %.2f, esperado 0.50", cob.CoberturaInstrumentada)
	}
}
