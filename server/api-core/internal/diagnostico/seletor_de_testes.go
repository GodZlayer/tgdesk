package diagnostico

import (
	"fmt"
	"math"
	"sort"
)

// O seletor de testes: qual medida fazer em seguida.
//
// Esta é uma mudança de papel do motor, e ela vem de uma observação de campo:
// a pergunta útil não é "qual é a causa?", é "o que eu meço agora para
// descobrir?".
//
// A diferença importa por dois motivos, e o segundo é o que destrava o produto:
//
//  1. É a pergunta que o técnico realmente tem na mão. Diante de uma máquina
//     lenta, ele não precisa de um palpite entre oito causas — precisa saber
//     qual dos trinta testes vale a hora dele.
//
//  2. ESCOLHER TESTE PRECISA DE MUITO MENOS DADO QUE CLASSIFICAR CAUSA.
//     Classificar exige rótulo confirmado por alguém que abriu a máquina, e o
//     parque tem quase nenhum. Escolher teste depende de quanto cada medida
//     SEPARA as hipóteses — e isso se calcula da distribuição corrente, que
//     existe desde o primeiro dia.
//
// O critério é ganho de informação: o teste que mais reduz a incerteza sobre
// qual causa é a verdadeira. Formalmente, a redução esperada da entropia da
// distribuição de causas ao observar o resultado daquele teste.
//
// O que este arquivo NÃO faz: escolher o teste mais rápido, o mais barato ou o
// mais completo. Rapidez entra só como desempate — porque entre dois testes
// que separam igual, o que custa menos tempo da máquina do cliente é
// estritamente melhor.

// TesteCandidato é um exame que pode ser executado, com o que ele custa e o
// que ele consegue distinguir.
type TesteCandidato struct {
	Codigo string
	// Sinais que este teste produz. É por eles que ele separa causas: um teste
	// que só produz sinais que todas as causas compartilham não separa nada,
	// por mais caro que seja.
	Sinais []string
	// Segundos típicos. Entra como DESEMPATE, nunca como critério primário —
	// escolher pelo mais rápido levaria a rodar sempre o teste inútil.
	DuracaoS int
	// Se ele exige que alguém esteja na máquina. Um teste presencial não
	// compete com um remoto: ele é a última opção, não a mais informativa.
	Presencial bool
}

// SugestaoDeTeste é uma recomendação com o porquê.
type SugestaoDeTeste struct {
	Codigo string  `json:"codigo"`
	Ganho  float64 `json:"ganho_de_informacao"`
	// Quanto da incerteza atual este teste resolve, em porcentagem. É o número
	// que a tela mostra — "resolve 62% da dúvida" diz mais ao técnico que
	// "ganho de 0,84 bits".
	ReducaoPct float64 `json:"reducao_pct"`
	DuracaoS   int     `json:"duracao_s"`
	// As causas que este teste consegue separar entre si. É a explicação da
	// recomendação, e sem ela o número é oráculo.
	Separa []string `json:"separa"`
	Porque string   `json:"porque"`
}

// entropia mede a incerteza de uma distribuição, em bits.
//
// Zero significa certeza absoluta; o máximo, ignorância completa. É a régua do
// seletor: um teste vale o que ele reduz daqui.
func entropia(dist map[string]float64) float64 {
	h := 0.0
	for _, p := range dist {
		if p > 0 {
			h -= p * math.Log2(p)
		}
	}
	return h
}

// SelecionarTestes ordena os candidatos por ganho de informação.
//
// `pesosSinalCausa[sinal|causa]` é o mesmo mapa que o motor de regra usa: o
// quanto observar aquele sinal empurra aquela causa. Reaproveitá-lo é
// deliberado — se o seletor usasse outra fonte, ele recomendaria testes que o
// motor não sabe interpretar, e o exame voltaria sem mudar o diagnóstico.
func SelecionarTestes(
	dist map[string]float64,
	candidatos []TesteCandidato,
	pesosSinalCausa map[string]float64,
	jaObservados map[string]bool,
) []SugestaoDeTeste {
	h0 := entropia(dist)
	if h0 <= 0 || len(dist) < 2 {
		// Sem incerteza não há o que reduzir. Recomendar teste aqui seria
		// gastar a máquina do cliente para confirmar o que já se sabe.
		return nil
	}
	// PISO DE DÚVIDA. Abaixo dele, nenhum teste é recomendado — nem o que
	// "resolve 90%".
	//
	// A armadilha que isto fecha: porcentagem de um número minúsculo engana.
	// Com uma causa em 99%, a entropia total é 0,08 bit; um teste que ganha
	// 0,04 aparece como "resolve 55% da dúvida" e manda o técnico gastar a
	// máquina do cliente para confirmar o que já estava decidido.
	//
	// 0,3 bit é aproximadamente a incerteza de uma hipótese em ~95% contra o
	// resto. Acima disso ainda vale medir; abaixo, o dossiê já respondeu.
	const duvidaMinimaEmBits = 0.3
	if h0 < duvidaMinimaEmBits {
		return nil
	}

	var sugestoes []SugestaoDeTeste
	for _, t := range candidatos {
		ganho, separa := ganhoDoTeste(dist, t, pesosSinalCausa, jaObservados)
		// Ganho ABSOLUTO, não relativo. Um teste precisa mover a agulha de
		// verdade, e não apenas uma fração de uma incerteza pequena.
		if ganho <= 0.05 {
			// Teste que não move a distribuição não entra na lista. Uma lista
			// longa com itens inúteis é pior que uma curta: ela transfere para
			// o técnico a decisão que o seletor existe para tomar.
			continue
		}
		sugestoes = append(sugestoes, SugestaoDeTeste{
			Codigo:     t.Codigo,
			Ganho:      arredonda(ganho),
			ReducaoPct: arredonda(ganho / h0 * 100),
			DuracaoS:   t.DuracaoS,
			Separa:     separa,
			Porque:     explicar(separa, ganho/h0),
		})
	}

	sort.Slice(sugestoes, func(i, j int) bool {
		// Ganho primeiro. Duração só desempata — e desempatar pelo mais rápido
		// entre iguais é ganho puro para o cliente.
		if math.Abs(sugestoes[i].Ganho-sugestoes[j].Ganho) > 0.01 {
			return sugestoes[i].Ganho > sugestoes[j].Ganho
		}
		return sugestoes[i].DuracaoS < sugestoes[j].DuracaoS
	})
	return sugestoes
}

// ganhoDoTeste calcula a redução esperada de entropia.
//
// O modelo é deliberadamente simples, e a simplicidade é defensável: para cada
// sinal que o teste produz, considera-se o mundo em que ele aparece e o mundo
// em que não aparece. A distribuição é reponderada em cada mundo pelos pesos
// que o motor já usa, e o ganho é a entropia atual menos a média das entropias
// dos dois mundos, ponderada pela chance de cada um.
//
// Um modelo mais fino exigiria saber P(sinal|causa) medido — que é justamente
// o que o parque ainda não tem. Quando tiver, esta função troca de miolo sem
// mudar de assinatura.
func ganhoDoTeste(
	dist map[string]float64,
	t TesteCandidato,
	pesos map[string]float64,
	jaObservados map[string]bool,
) (float64, []string) {
	h0 := entropia(dist)
	melhorGanho := 0.0
	separaSet := map[string]bool{}

	for _, sinal := range t.Sinais {
		// Sinal já observado não traz informação nova. Rodar o teste de novo
		// para revê-lo é desperdício de máquina do cliente.
		if jaObservados[sinal] {
			continue
		}

		// Mundo A: o sinal aparece. Cada causa é reponderada pelo peso do par.
		presente := map[string]float64{}
		ausente := map[string]float64{}
		var massaPresente float64
		envolvidas := []string{}
		for causa, p := range dist {
			peso := pesos[sinal+"|"+causa]
			if peso > 0 {
				envolvidas = append(envolvidas, causa)
			}
			presente[causa] = p * (1 + peso)
			massaPresente += p * peso
			// Mundo B: o sinal NÃO aparece. Causas que o produziriam perdem
			// força — e é essa metade que a maioria dos diagnósticos esquece:
			// a ausência de uma evidência esperada também informa.
			ausente[causa] = p / (1 + peso)
		}
		if len(envolvidas) == 0 {
			continue
		}

		normalizarNoLugar(presente)
		normalizarNoLugar(ausente)

		// Probabilidade de o sinal aparecer, dada a distribuição atual.
		pPresente := math.Min(0.95, math.Max(0.05, massaPresente))
		esperada := pPresente*entropia(presente) + (1-pPresente)*entropia(ausente)
		if g := h0 - esperada; g > melhorGanho {
			melhorGanho = g
			for _, c := range envolvidas {
				separaSet[c] = true
			}
		}
	}

	// Teste presencial paga uma penalidade: ele exige alguém na máquina, e o
	// custo disso não é tempo, é deslocamento. Só deve vencer quando separa
	// MUITO mais que qualquer alternativa remota.
	if t.Presencial {
		melhorGanho *= 0.5
	}

	separa := make([]string, 0, len(separaSet))
	for c := range separaSet {
		separa = append(separa, c)
	}
	sort.Strings(separa)
	return melhorGanho, separa
}

func normalizarNoLugar(m map[string]float64) {
	total := 0.0
	for _, v := range m {
		total += v
	}
	if total <= 0 {
		return
	}
	for k := range m {
		m[k] /= total
	}
}

// explicar traduz o ganho em uma frase que o técnico usa para decidir.
//
// O número sozinho é oráculo; a frase diz o que ele compra. É a mesma regra do
// resto do produto — nenhuma probabilidade aparece sem o que a sustenta.
func explicar(separa []string, fracao float64) string {
	switch {
	case len(separa) == 0:
		return "não separa nenhuma hipótese"
	case fracao >= 0.5:
		return fmt.Sprintf("resolve a maior parte da dúvida, separando %s",
			listar(separa))
	case fracao >= 0.2:
		return fmt.Sprintf("estreita bastante, separando %s", listar(separa))
	default:
		return fmt.Sprintf("ajuda pouco; separa apenas %s", listar(separa))
	}
}

func listar(itens []string) string {
	switch len(itens) {
	case 1:
		return itens[0]
	case 2:
		return itens[0] + " de " + itens[1]
	default:
		return fmt.Sprintf("%s e mais %d hipóteses", itens[0], len(itens)-1)
	}
}

func arredonda(v float64) float64 { return math.Round(v*100) / 100 }
