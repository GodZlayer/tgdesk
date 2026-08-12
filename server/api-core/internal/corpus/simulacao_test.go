package corpus

import "testing"

// Testes da simulação (§19.3).
//
// A regra em jogo é a que separa este projeto de um gerador de dados: o que se
// sintetiza é o FORMATO, nunca o número. Um exemplo com valor inventado deixa de
// ser evidência e vira nossa opinião com aparência de dado — e a rede aprende a
// nossa opinião.

func num(v float64) *float64 { return &v }

func TestValorAusenteContinuaAusente(t *testing.T) {
	// Kernel panic não tem número. Se a simulação preenchesse com zero, a rede
	// aprenderia que "não medido" e "medido zero" são a mesma coisa.
	c := CasoReal{
		ThreadID: "t1", Classe: "trava", Sintoma: "trava sob carga",
		Medidas: []Medida{{Campo: "kernel_panic", Chave: "panic", Literal: "panic(cpu 0..."}},
	}
	d, ok := Sintetizar(c)
	if !ok {
		t.Fatal("caso com panic não virou exemplo")
	}
	if d.Evidencias[0].Valor != nil {
		t.Fatal("simulação inventou valor para medida categórica")
	}
}

func TestValorVemDoLogEhCopiadoIntacto(t *testing.T) {
	c := CasoReal{
		ThreadID: "t1", Classe: "disco",
		Medidas: []Medida{{Campo: "smart", Chave: "reallocated", Valor: num(12)}},
	}
	d, _ := Sintetizar(c)
	if d.Evidencias[0].Valor == nil || *d.Evidencias[0].Valor != 12 {
		t.Fatalf("valor do log não sobreviveu à simulação: %+v", d.Evidencias[0])
	}
	if d.Evidencias[0].Sinal != "smart_reallocated" {
		t.Fatalf("sinal traduzido errado: %q", d.Evidencias[0].Sinal)
	}
}

func TestExemploNasceMarcadoComoSimulado(t *testing.T) {
	// Sem esta marca, um exemplo de fórum entraria no cálculo de calibração e
	// o produto passaria a afirmar acurácia que nunca mediu em campo.
	c := CasoReal{ThreadID: "t", Classe: "disco",
		Medidas: []Medida{{Campo: "smart", Chave: "reallocated", Valor: num(1)}}}
	d, _ := Sintetizar(c)
	if !d.Simulado {
		t.Fatal("exemplo simulado não foi marcado como tal")
	}
	// Caso de fórum não tem escada: sem curva, o motor tem que aplicar o teto
	// de probabilidade e nunca produzir veredito.
	if d.TemCurva {
		t.Fatal("exemplo de fórum declarou ter curva; ele nunca teve escada")
	}
	if d.ThreadID == "" {
		t.Fatal("exemplo sem origem não pode ser auditado nem removido depois")
	}
}

func TestIdadeDoDiscoNaoViraSinalDeFalha(t *testing.T) {
	// Horas ligadas e desgaste dizem IDADE. Mapeá-los para sinal de defeito
	// ensinaria a rede que disco velho é disco quebrado — o erro que o técnico
	// já comete sozinho.
	c := CasoReal{ThreadID: "t", Classe: "disco",
		Medidas: []Medida{{Campo: "smart", Chave: "horas_ligado", Valor: num(40000)}}}
	d, _ := Sintetizar(c)
	if d.Evidencias[0].Sinal == "smart_reallocated" || d.Evidencias[0].Sinal == "erro_io_log" {
		t.Fatalf("idade virou sinal de falha: %q", d.Evidencias[0].Sinal)
	}
}

func TestEventoInformativoNaoEhEvidenciaDeFalha(t *testing.T) {
	// O nível vem do próprio sistema. "Information" não é falha, e contá-lo
	// como tal encheria o treino de ruído rotulado.
	c := CasoReal{ThreadID: "t", Classe: "boot",
		Medidas: []Medida{{Campo: "evento_sistema", Chave: "BROWSER:8033", Nivel: "Information"}}}
	if _, ok := Sintetizar(c); ok {
		t.Fatal("evento informativo sozinho virou exemplo de treino")
	}
}

func TestEventoDeErroEhEvidencia(t *testing.T) {
	c := CasoReal{ThreadID: "t", Classe: "energia",
		Medidas: []Medida{{Campo: "evento_sistema", Chave: "Kernel-Power:41", Nivel: "Error", Valor: num(41)}}}
	d, ok := Sintetizar(c)
	if !ok || d.Evidencias[0].Sinal != "erro_sistema_log" {
		t.Fatalf("evento de erro não virou evidência: %+v", d)
	}
}

func TestCasoSemEvidenciaTraduzivelNaoViraExemplo(t *testing.T) {
	// Forçar todo caso a virar exemplo encheria o treino de linhas vazias
	// rotuladas — a forma mais eficiente de ensinar uma rede a chutar.
	c := CasoReal{ThreadID: "t", Classe: "disco",
		Medidas: []Medida{{Campo: "campo_desconhecido", Chave: "x"}}}
	if _, ok := Sintetizar(c); ok {
		t.Fatal("caso sem evidência traduzível virou exemplo")
	}
}

func TestRotuloIndefinidoNaoTreina(t *testing.T) {
	c := CasoReal{ThreadID: "t", Classe: "indefinido",
		Medidas: []Medida{{Campo: "smart", Chave: "reallocated", Valor: num(9)}}}
	if _, ok := Sintetizar(c); ok {
		t.Fatal("caso sem classe utilizável virou exemplo rotulado")
	}
}

func TestVolumeMinimoPorRotulo(t *testing.T) {
	// Treinar uma classe com 2 exemplos não produz modelo: produz memorização
	// com aparência de aprendizado.
	conj := ConjuntoDeTreino{PorRotulo: map[string]int{"disco": 57, "termico": 2}}
	rotulos := conj.RotulosComVolumeMinimo(10)
	if len(rotulos) != 1 || rotulos[0] != "disco" {
		t.Fatalf("piso de volume não aplicado: %v", rotulos)
	}
}

func TestMontarAgregaSemPerderCaso(t *testing.T) {
	casos := []CasoReal{
		{ThreadID: "a", Classe: "disco", Medidas: []Medida{{Campo: "smart", Chave: "reallocated", Valor: num(3)}}},
		{ThreadID: "b", Classe: "trava", Medidas: []Medida{{Campo: "bugcheck", Chave: "0x0000009F"}}},
		{ThreadID: "c", Classe: "disco", Medidas: []Medida{{Campo: "nada", Chave: "x"}}},
	}
	conj := Montar(casos)
	if len(conj.Exemplos) != 2 {
		t.Fatalf("exemplos: %d", len(conj.Exemplos))
	}
	if conj.SemExemplo != 1 {
		t.Fatal("caso descartado não foi contado; a perda ficaria invisível")
	}
	if conj.PorRotulo["disco"] != 1 || conj.PorSinal["bugcheck"] != 1 {
		t.Fatalf("agregação errada: %+v %+v", conj.PorRotulo, conj.PorSinal)
	}
}
