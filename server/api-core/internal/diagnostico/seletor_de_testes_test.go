package diagnostico

import "testing"

// A pergunta que o seletor responde não é "qual é a causa?", é "o que eu meço
// agora para descobrir?". É a pergunta que o técnico tem na mão — e ela precisa
// de muito menos dado rotulado que a primeira.

func TestEscolheOTesteQueMaisSepara(t *testing.T) {
	// Duas hipóteses empatadas: incerteza máxima. Um teste que distingue as
	// duas vale muito; um que só toca numa delas vale pouco.
	dist := map[string]float64{"disco_lento": 0.5, "memoria_insuficiente": 0.5}
	pesos := map[string]float64{
		"latencia_disco|disco_lento":       4.0,
		"uso_memoria|memoria_insuficiente": 4.0,
		"temperatura|disco_lento":          0.1,
	}
	candidatos := []TesteCandidato{
		{Codigo: "termico", Sinais: []string{"temperatura"}, DuracaoS: 5},
		{Codigo: "disco", Sinais: []string{"latencia_disco"}, DuracaoS: 10},
	}

	s := SelecionarTestes(dist, candidatos, pesos, nil)
	if len(s) == 0 {
		t.Fatal("nenhuma sugestão com duas hipóteses empatadas")
	}
	if s[0].Codigo != "disco" {
		t.Fatalf("escolheu %q; o teste térmico quase não separa estas duas hipóteses", s[0].Codigo)
	}
}

func TestNaoSugereTesteQuandoNaoHaDuvida(t *testing.T) {
	// Com certeza praticamente absoluta, rodar teste é gastar a máquina do
	// cliente para confirmar o que já se sabe.
	dist := map[string]float64{"disco_degradado": 0.99, "outra": 0.01}
	candidatos := []TesteCandidato{{Codigo: "disco", Sinais: []string{"latencia_disco"}}}
	pesos := map[string]float64{"latencia_disco|disco_degradado": 3.0}

	if s := SelecionarTestes(dist, candidatos, pesos, nil); len(s) > 0 && s[0].ReducaoPct > 30 {
		t.Fatalf("sugeriu teste caro sobre dúvida quase inexistente: %+v", s[0])
	}
}

func TestSinalJaObservadoNaoRendeTeste(t *testing.T) {
	// Rodar de novo para rever o que já se sabe é desperdício puro.
	dist := map[string]float64{"a": 0.5, "b": 0.5}
	pesos := map[string]float64{"latencia_disco|a": 4.0}
	candidatos := []TesteCandidato{{Codigo: "disco", Sinais: []string{"latencia_disco"}}}

	if s := SelecionarTestes(dist, candidatos, pesos, map[string]bool{"latencia_disco": true}); len(s) != 0 {
		t.Fatalf("sugeriu teste para um sinal já medido: %+v", s)
	}
}

func TestPresencialSoVenceSeSepararMuitoMais(t *testing.T) {
	// Teste presencial custa deslocamento, não tempo de máquina. Ele não pode
	// vencer um remoto que separa quase igual.
	dist := map[string]float64{"a": 0.5, "b": 0.5}
	pesos := map[string]float64{"mau_contato|a": 4.0, "latencia_disco|a": 3.6}
	candidatos := []TesteCandidato{
		{Codigo: "inspecao", Sinais: []string{"mau_contato"}, Presencial: true},
		{Codigo: "disco", Sinais: []string{"latencia_disco"}, DuracaoS: 10},
	}

	s := SelecionarTestes(dist, candidatos, pesos, nil)
	if len(s) == 0 || s[0].Codigo != "disco" {
		t.Fatalf("o presencial venceu um remoto que separa quase igual: %+v", s)
	}
}

func TestAusenciaDeSinalTambemInforma(t *testing.T) {
	// Metade que a maioria dos diagnósticos esquece: se um sinal ESPERADO não
	// aparece, isso enfraquece a causa que o produziria. Um seletor que só
	// considera o mundo em que o sinal aparece subestima todo teste.
	dist := map[string]float64{"a": 0.5, "b": 0.5}
	pesos := map[string]float64{"sinal_de_a|a": 5.0}
	candidatos := []TesteCandidato{{Codigo: "t", Sinais: []string{"sinal_de_a"}, DuracaoS: 1}}

	s := SelecionarTestes(dist, candidatos, pesos, nil)
	if len(s) == 0 || s[0].Ganho <= 0 {
		t.Fatal("teste que confirma OU descarta uma hipótese precisa ter ganho positivo")
	}
}

func TestSugestaoExplicaOQueEspera(t *testing.T) {
	// Número sozinho é oráculo. A recomendação precisa dizer o que ela compra.
	dist := map[string]float64{"disco_lento": 0.5, "memoria_insuficiente": 0.5}
	pesos := map[string]float64{"latencia_disco|disco_lento": 4.0}
	candidatos := []TesteCandidato{{Codigo: "disco", Sinais: []string{"latencia_disco"}, DuracaoS: 10}}

	s := SelecionarTestes(dist, candidatos, pesos, nil)
	if len(s) == 0 || s[0].Porque == "" {
		t.Fatal("sugestão sem explicação: o técnico não tem como julgar se vale a hora dele")
	}
	if s[0].ReducaoPct <= 0 {
		t.Fatal("a redução precisa vir em porcentagem: 'resolve 62% da dúvida' diz mais que '0,84 bits'")
	}
}
