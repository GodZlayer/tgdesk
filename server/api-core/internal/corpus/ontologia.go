package corpus

import (
	"sort"
	"strings"
)

// Ontologia: do corpus para `negative_status` e `corpus_prior` (§4, §13.4).
//
// A derivação (derivacao.go) responde "quais SINAIS precisam existir". Este
// arquivo responde a outra pergunta, que é a que falta para o motor ter
// domínio sobre o qual distribuir probabilidade:
//
//	quais STATUS NEGATIVOS existem, e quais CAUSAS cada um admite.
//
// O par (status, causa) é o que sustenta tudo: é o domínio do softmax (§3), a
// chave do template (§12.2), o campo de fechamento do chamado (§10.3) e a
// linha de `corpus_prior`.
//
// A separação que o resto do documento pressupõe e que o corpus não trazia
// pronta:
//
//   - STATUS é o que se OBSERVA — "trava", "não liga", "desliga sozinho". Vem
//     do título/relato, que é o que o usuário escreveu antes de saber a causa.
//   - CAUSA é o que se CONCLUI — "disco degradado", "memória instável". Vem da
//     `classe_problema`, que a rotulagem extraiu da mensagem causal (§13.3).
//
// `sintoma_normalizado` no corpus é o título cru da thread, não uma
// normalização — então a classificação em status é feita aqui, pelo mesmo
// método de vocabulário do resto do pacote. É explicitamente uma heurística, e
// o caso que nenhum vocábulo casa fica em `indefinido` em vez de ser
// empurrado para o status mais próximo.

// Os status negativos. Catálogo FECHADO (§4): a lista não cresce em runtime, e
// causa que não está no conjunto do status não pode ser respondida.
var vocabularioDeStatus = map[string][]string{
	"trava_sob_carga": {
		"freeze", "frozen", "freezes", "hang", "hangs", "not responding",
		"unresponsive", "lock up", "locks up", "lockup", "stutter",
		"trava", "travando", "congela", "não responde", "nao responde",
	},
	"desligamento_inesperado": {
		"random reboot", "reboots", "restarts", "shuts down", "shutdown",
		"turns off", "powers off", "bsod", "blue screen", "crash", "crashes",
		"kernel panic", "reinicia", "desliga", "desligou", "tela azul",
	},
	"nao_inicializa": {
		"won't boot", "wont boot", "not booting", "no boot", "boot loop",
		"no post", "won't start", "wont start", "won't turn on", "black screen",
		"não liga", "nao liga", "não dá boot", "nao da boot", "não inicia",
	},
	// Lentidão é DOIS status, não um.
	//
	// A separação não veio do corpus — no fórum todo mundo escreve "slow" para
	// os dois casos, e foi assim que a primeira versão colapsou os dois num
	// `lentidao_persistente` só. Veio de quem convive com as máquinas: "o
	// Daniel tem lentidões ocasionais rápidas; a Dani tem momentos de lentidão
	// profunda". Sentimento diferente, causa diferente, solução diferente.
	//
	// E o dado do parque confirma, no histograma de `device_metric_rollup`:
	// Daniel tem 1,83% das amostras de CPU acima de 95% (429 em 23.402), a Dani
	// tem 0,19% (33 em 17.120) — dez vezes menos pico, e mesmo assim a lentidão
	// dela é a mais severa. São fenômenos distintos.
	//
	// O que separa os dois não é a INTENSIDADE, é a FORMA do episódio: pico
	// curto e frequente que se resolve sozinho, contra degradação sustentada
	// que não passa. Por isso o vocabulário abaixo insiste em duração.
	"lentidao_intermitente": {
		"stutter", "stuttering", "hitch", "hitches", "brief lag", "micro lag",
		"momentary", "occasional slowdown", "intermittent",
		"engasga", "engasgando", "travadinha", "lentidão ocasional",
		"lentidao ocasional", "lentidão rápida", "de vez em quando",
	},
	"lentidao_profunda": {
		"grinds to a halt", "unusable", "crawl", "crawling", "very slow",
		"extremely slow", "takes forever", "unresponsive for minutes",
		"lentidão profunda", "lentidao profunda", "fica impossível",
		"fica impossivel", "trava tudo", "demora muito",
	},
	// Fica como o caso em que se sabe que está lento e NÃO se sabe a forma.
	// Não é sinônimo dos dois acima: é a declaração de que a distinção não foi
	// estabelecida, e é ela que dispara "o teste que mais separa" em vez de um
	// palpite entre duas condutas opostas.
	"lentidao_nao_caracterizada": {
		"slow", "slowly", "sluggish", "performance", "lag", "laggy",
		"lento", "lentidão", "lentidao", "desempenho",
	},
	"superaquecimento": {
		"overheat", "overheating", "too hot", "high temperature", "thermal",
		"superaquec", "esquentando", "temperatura alta",
	},
	"corrupcao_de_dados": {
		"corrupt", "corrupted", "data loss", "bad sectors", "file system error",
		"corromp", "setores defeituosos", "perda de dados",
	},
	// O sistema operacional já ACUSOU a peça — erro de I/O, dispositivo não
	// reconhecido, volume em somente-leitura, SMART com falha declarada. É um
	// status distinto de `corrupcao_de_dados` porque muda a conduta: aqui não
	// se investiga se há problema, investiga-se qual peça e o que fazer.
	//
	// Vale a regra de §7.3: se o sistema já diz, não se adivinha. Este status é
	// o caso em que a classe do evento é FATO e a rede só distribui
	// probabilidade sobre a causa dentro dele.
	"erro_de_dispositivo": {
		"i/o error", "io error", "read error", "write error", "smart error",
		"smart errors", "drive error", "disk error", "not recognized",
		"not detected", "doesn't recognize", "don't recognized", "not mounting",
		"read only", "read-only", "no space left",
		"erro de leitura", "erro de escrita", "não reconhece", "nao reconhece",
		"somente leitura",
	},
}

// Descrição de cada status, em uma frase. É o que aparece na tela antes de
// qualquer probabilidade (§10.5.1, campo 1).
var descricaoDeStatus = map[string]string{
	"trava_sob_carga":            "O computador para de responder e volta sozinho, ou precisa ser reiniciado à força.",
	"desligamento_inesperado":    "O computador desliga ou reinicia sem aviso, incluindo tela azul.",
	"nao_inicializa":             "O computador não completa a inicialização do sistema.",
	"lentidao_intermitente":      "O computador engasga por segundos e volta ao normal sozinho, várias vezes ao dia.",
	"lentidao_profunda":          "O computador entra em períodos longos em que tudo fica lento, e não melhora sozinho.",
	"lentidao_nao_caracterizada": "O computador está lento, e ainda não se sabe se são engasgos curtos ou períodos longos.",
	"superaquecimento":           "O computador opera acima da faixa térmica segura.",
	"corrupcao_de_dados":         "Arquivos ou estruturas do sistema de arquivos estão sendo corrompidos.",
	"erro_de_dispositivo":        "O sistema operacional está reportando erro de acesso a um dispositivo.",
}

// classe do corpus -> código de causa do conjunto fechado.
//
// Nem toda classe vira causa: `trava` e `boot` são SINTOMAS que a rotulagem
// classificou como classe por falta de conclusão melhor, e `indefinido` é
// ausência de rótulo. Os três não entram como causa — inventar causa a partir
// deles seria exatamente o "chute vira rótulo de treino" que a arquitetura
// proíbe (§0 do roadmap).
var classeParaCausa = map[string]string{
	"disco":      "disco_degradado",
	"memoria":    "memoria_instavel",
	"termico":    "refrigeracao_insuficiente",
	"energia":    "alimentacao_instavel",
	"driver":     "driver_incompativel",
	"software":   "software_conflitante",
	"rede":       "rede_instavel",
	"desempenho": "recurso_saturado",
}

// Descrição de cada causa em nível técnico e em nível cliente (§12.2 exige os
// dois; o cliente lê uma frase, o técnico lê a curva).
var descricaoDeCausa = map[string][2]string{
	"disco_degradado":           {"Disco degradado — superfície, controladora ou interface falhando.", "O disco (onde ficam seus arquivos) está falhando."},
	"memoria_instavel":          {"Memória instável — erro de leitura/escrita em RAM sob carga.", "A memória do computador está com defeito."},
	"refrigeracao_insuficiente": {"Refrigeração insuficiente — dissipação abaixo do necessário para a carga.", "O computador está esquentando demais."},
	"alimentacao_instavel":      {"Alimentação instável — fonte, bateria ou rede elétrica fora da faixa.", "A energia que chega ao computador está oscilando."},
	"driver_incompativel":       {"Driver incompatível ou defeituoso para o hardware presente.", "Um programa de controle de peça está com defeito."},
	"software_conflitante":      {"Software conflitante — programa ou serviço interferindo no sistema.", "Um programa instalado está atrapalhando o sistema."},
	"rede_instavel":             {"Rede instável — perda, latência ou saturação do enlace.", "A conexão de rede está instável."},
	"recurso_saturado":          {"Recurso saturado — CPU, RAM ou I/O em uso pleno de forma sustentada.", "O computador está sem folga para o que você usa."},
}

// CausasDeclaradas cobre os status que o corpus NÃO consegue popular.
//
// A derivação tira causa candidata da frequência do corpus (§13.6). Isso não
// funciona para os dois status de lentidão: o fórum não distingue engasgo de
// degradação sustentada, então nenhum caso rotula um dos dois. Deixar a
// derivação decidir produziria um conjunto vazio — e status sem causa
// candidata abstém sempre, que seria um jeito elegante de nunca responder.
//
// Então a causa entra DECLARADA, com procedência de observação de campo em vez
// de frequência de fórum. É a mesma regra de §14.4 vista de outro ângulo: o
// prior externo só vale enquanto não houver coisa melhor, e conhecimento de
// quem convive com as máquinas é coisa melhor.
//
// A lista de cada um é curta de propósito. O ponto não é cobrir toda causa
// concebível: é que as causas de um NÃO SÃO as do outro, porque a conduta que
// elas geram é oposta — controlar um processo contra trocar uma peça.
var CausasDeclaradas = map[string][]string{
	// Engasgo: alguma coisa toma o recurso por segundos e devolve. A peça está
	// sã; o que está errado é a disputa.
	"lentidao_intermitente": {
		"software_conflitante",      // varredura, indexação, atualização em segundo plano
		"recurso_saturado",          // pico legítimo de uso, sem folga para o resto
		"refrigeracao_insuficiente", // throttle térmico curto, que passa ao esfriar
		"driver_incompativel",       // driver que trava o pipeline por instantes
	},
	// Degradação sustentada: entra num estado ruim e fica. Aqui a peça costuma
	// estar no limite ou falhando, e controlar processo não resolve.
	"lentidao_profunda": {
		"disco_degradado",      // I/O com retry, latência alta sustentada
		"recurso_saturado",     // RAM insuficiente para a carga, com paginação
		"memoria_instavel",     // erro de memória forçando recuperação constante
		"software_conflitante", // programa pesado que não devolve o recurso
	},
}

// DiscriminadorDeStatus diz QUAL MEDIDA separa um status dos seus vizinhos.
//
// Existe porque a pergunta "o que testar primeiro?" (§10.5.1, campo 5) precisa
// de uma resposta que não seja "roda tudo". Quando o dossiê não decide entre
// engasgo e degradação, o que falta não é mais um teste qualquer: é a medida
// que tem a forma do episódio.
var DiscriminadorDeStatus = map[string]string{
	"lentidao_intermitente": "duracao_do_episodio",
	"lentidao_profunda":     "duracao_do_episodio",
}

// ClassificarStatus mapeia o relato do usuário para um status negativo.
//
// Devolve "" quando nada casa. Ausência de status é informação — significa que
// aquele caso não sustenta prior nenhum — e nunca é substituída pelo status
// mais frequente.
func ClassificarStatus(relato string) string {
	casados := casarVocabulario(relato, vocabularioDeStatus)
	if len(casados) == 0 {
		return ""
	}
	// Mais de um status casa com frequência ("freezes and reboots"). A ordem do
	// vocabulário não pode decidir — o desempate é pela especificidade: o status
	// cujo vocábulo casado é mais longo é o mais específico do relato.
	melhor, melhorPeso := "", 0
	for _, st := range casados {
		peso := 0
		for _, termo := range vocabularioDeStatus[st] {
			if strings.Contains(strings.ToLower(relato), termo) && len(termo) > peso {
				peso = len(termo)
			}
		}
		if peso > melhorPeso {
			melhor, melhorPeso = st, peso
		}
	}
	return melhor
}

// CausaDaClasse traduz a classe do corpus em causa do conjunto fechado.
// Devolve "" para as classes que são sintoma, não causa.
func CausaDaClasse(classe string) string { return classeParaCausa[classe] }

// ParStatusCausa é uma linha de `corpus_prior`: quantos casos reais do fórum
// terminaram naquela causa, dado aquele status observado.
type ParStatusCausa struct {
	Status string
	Causa  string
	N      int
	// Frequência dentro do status. É o prior propriamente dito — P(causa|status)
	// segundo o fórum, antes de qualquer dado interno.
	Frequencia float64
}

// StatusDerivado é uma linha de `negative_status` pronta para gravar.
type StatusDerivado struct {
	Codigo           string
	Descricao        string
	CausasCandidatas []string
	Sinais           []string
	Testes           []string
	// Causas vistas no corpus mas com casos de menos para sustentar prior.
	// Não somem: viram limitação declarada (§13.6), porque uma causa que existe
	// e não é separável precisa aparecer na tela como lacuna.
	Limitacoes []string
	CasosTotal int
}

// CasoParaOntologia é o mínimo que a derivação de ontologia consome.
type CasoParaOntologia struct {
	Relato string
	Classe string
	Sinais []string
	Testes []string
}

// DerivarOntologia produz o catálogo de status e os priors a partir dos casos
// resolvidos.
//
// `minimoPorCausa` é o corte abaixo do qual uma causa não entra no conjunto
// candidato do status — entra como limitação declarada. Sem esse corte, uma
// causa vista uma vez num fórum viraria opção do softmax com peso real, que é
// como um corpus enviesado contamina o motor.
func DerivarOntologia(casos []CasoParaOntologia, minimoPorCausa int) ([]StatusDerivado, []ParStatusCausa) {
	type acumulador struct {
		porCausa map[string]int
		sinais   map[string]int
		testes   map[string]int
		total    int
	}
	porStatus := map[string]*acumulador{}

	for _, c := range casos {
		status := ClassificarStatus(c.Relato)
		if status == "" {
			continue
		}
		causa := CausaDaClasse(c.Classe)
		if causa == "" {
			continue
		}
		a, ok := porStatus[status]
		if !ok {
			a = &acumulador{porCausa: map[string]int{}, sinais: map[string]int{}, testes: map[string]int{}}
			porStatus[status] = a
		}
		a.porCausa[causa]++
		a.total++
		for _, s := range c.Sinais {
			a.sinais[s]++
		}
		for _, t := range c.Testes {
			a.testes[t]++
		}
	}

	var statuses []StatusDerivado
	var priors []ParStatusCausa

	for codigo, a := range porStatus {
		st := StatusDerivado{
			Codigo:     codigo,
			Descricao:  descricaoDeStatus[codigo],
			CasosTotal: a.total,
		}
		// Denominador do prior: só as causas que passam o corte. Incluir a cauda
		// no denominador diluiria as causas boas com ruído que não é ofertado.
		denominador := 0
		for causa, n := range a.porCausa {
			if n >= minimoPorCausa {
				denominador += n
			}
			_ = causa
		}
		for causa, n := range a.porCausa {
			if n < minimoPorCausa {
				st.Limitacoes = append(st.Limitacoes, causa)
				continue
			}
			st.CausasCandidatas = append(st.CausasCandidatas, causa)
			freq := 0.0
			if denominador > 0 {
				freq = float64(n) / float64(denominador)
			}
			priors = append(priors, ParStatusCausa{
				Status: codigo, Causa: causa, N: n, Frequencia: freq,
			})
		}
		st.Sinais = maisFrequentes(a.sinais, 8)
		st.Testes = maisFrequentes(a.testes, 6)
		sort.Strings(st.CausasCandidatas)
		sort.Strings(st.Limitacoes)
		statuses = append(statuses, st)
	}

	sort.Slice(statuses, func(i, j int) bool { return statuses[i].CasosTotal > statuses[j].CasosTotal })
	sort.Slice(priors, func(i, j int) bool {
		if priors[i].Status != priors[j].Status {
			return priors[i].Status < priors[j].Status
		}
		return priors[i].N > priors[j].N
	})
	return statuses, priors
}

func maisFrequentes(m map[string]int, limite int) []string {
	type kv struct {
		k string
		n int
	}
	var lista []kv
	for k, n := range m {
		lista = append(lista, kv{k, n})
	}
	sort.Slice(lista, func(i, j int) bool {
		if lista[i].n != lista[j].n {
			return lista[i].n > lista[j].n
		}
		return lista[i].k < lista[j].k
	})
	if len(lista) > limite {
		lista = lista[:limite]
	}
	out := make([]string, 0, len(lista))
	for _, e := range lista {
		out = append(out, e.k)
	}
	return out
}

// DescricaoDaCausa devolve (técnico, cliente). É a matéria-prima dos dois
// níveis obrigatórios de `text_template` (§12.2).
func DescricaoDaCausa(causa string) (string, string) {
	d, ok := descricaoDeCausa[causa]
	if !ok {
		return causa, causa
	}
	return d[0], d[1]
}

// CausasConhecidas devolve o conjunto fechado inteiro, em ordem estável.
func CausasConhecidas() []string {
	out := make([]string, 0, len(descricaoDeCausa))
	for c := range descricaoDeCausa {
		out = append(out, c)
	}
	sort.Strings(out)
	return out
}

// ComCausasDeclaradas acrescenta os status cujas causas vêm de observação de
// campo em vez de frequência de corpus.
//
// O prior desses status é UNIFORME, e é assim de propósito: declarar que uma
// causa é candidata é conhecimento; declarar que ela é 40% provável seria
// invenção. A distribuição só ganha forma quando houver caso interno fechado —
// que é exatamente o que §13.4 diz sobre o prior externo, aplicado a um prior
// que nem externo é.
func ComCausasDeclaradas(
	statuses []StatusDerivado, priors []ParStatusCausa,
) ([]StatusDerivado, []ParStatusCausa) {
	indice := map[string]int{}
	for i, st := range statuses {
		indice[st.Codigo] = i
	}

	codigos := make([]string, 0, len(CausasDeclaradas))
	for c := range CausasDeclaradas {
		codigos = append(codigos, c)
	}
	sort.Strings(codigos)

	for _, codigo := range codigos {
		declaradas := CausasDeclaradas[codigo]
		if len(declaradas) == 0 {
			continue
		}

		// UNIR, nunca substituir nem pular.
		//
		// O corpus classifica ALGUNS casos nesses status — "stutter", "takes
		// forever" casam com o vocabulário — mas poucos, e o conjunto que sai
		// dali fica pequeno demais para ser o domínio do softmax. A primeira
		// versão pulava o status quando o corpus já o tinha tocado, e o
		// resultado foi `lentidao_intermitente` com ZERO causa candidata: um
		// status que abstém sempre, o que é pior que não existir.
		i, existe := indice[codigo]
		if !existe {
			statuses = append(statuses, StatusDerivado{
				Codigo:    codigo,
				Descricao: descricaoDeStatus[codigo],
				Sinais:    []string{"uso_cpu", "uso_memoria", "processo_pesado", "forma_do_episodio"},
				Testes:    []string{"resource_pressure_series"},
			})
			i = len(statuses) - 1
			indice[codigo] = i
		}

		jaCandidata := map[string]bool{}
		for _, c := range statuses[i].CausasCandidatas {
			jaCandidata[c] = true
		}
		var novas []string
		for _, c := range declaradas {
			if !jaCandidata[c] {
				statuses[i].CausasCandidatas = append(statuses[i].CausasCandidatas, c)
				novas = append(novas, c)
			}
		}
		sort.Strings(statuses[i].CausasCandidatas)

		if d := DiscriminadorDeStatus[codigo]; d != "" {
			statuses[i].Testes = append(statuses[i].Testes, d)
		}

		// Prior só para as causas ACRESCENTADAS, e uniforme entre elas. Onde o
		// corpus tinha frequência, ela fica: dado medido não é substituído por
		// declaração. Onde não tinha, o uniforme diz "é candidata" sem afirmar
		// o quanto — declarar 40% seria invenção.
		// Causa candidata NÃO pode continuar listada como lacuna. As duas listas
		// dizem coisas opostas na tela — "posso responder isto" contra "isto não
		// é separável à distância" — e um item nas duas é o tipo de contradição
		// que faz o técnico parar de ler a tela inteira.
		if len(novas) > 0 {
			virouCandidata := map[string]bool{}
			for _, c := range novas {
				virouCandidata[c] = true
			}
			var restam []string
			for _, l := range statuses[i].Limitacoes {
				if !virouCandidata[l] {
					restam = append(restam, l)
				}
			}
			statuses[i].Limitacoes = restam
		}

		if len(novas) == 0 {
			continue
		}
		uniforme := 1.0 / float64(len(statuses[i].CausasCandidatas))
		for _, causa := range novas {
			priors = append(priors, ParStatusCausa{
				Status: codigo, Causa: causa, N: 0, Frequencia: uniforme,
			})
		}
	}

	// Renormalizar por status: prior é DISTRIBUIÇÃO, e tem que somar 1.
	//
	// Misturar frequência medida do corpus com uniforme declarado quebra a soma
	// — e um vetor que soma 1,5 não é probabilidade, é peso disfarçado de
	// probabilidade. O motor normaliza de novo antes de responder, mas gravar
	// errado no banco tornaria `corpus_prior` inútil para qualquer outra
	// leitura, inclusive a auditoria de "quanto disto ainda vem de fórum".
	total := map[string]float64{}
	for _, p := range priors {
		total[p.Status] += p.Frequencia
	}
	for i := range priors {
		if t := total[priors[i].Status]; t > 0 {
			priors[i].Frequencia /= t
		}
	}
	return statuses, priors
}
