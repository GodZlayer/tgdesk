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
	// Congelamento BREVE e repetido: a máquina para por 1 a 5 s, fica inusável,
	// e volta inteira. É o que o usuário chama de "travadinha".
	//
	// Não é lentidão — em lentidão tudo responde devagar; aqui NADA responde e
	// depois volta como se nada tivesse acontecido. E não é `trava_sob_carga`,
	// que é o congelamento longo: um costuma ser disputa que se resolve
	// sozinha, o outro é esgotamento ou peça falhando. Condutas opostas.
	//
	// Quem mede é o relógio EXTERNO (§6): a máquina congelada não carimba a
	// hora do próprio congelamento.
	"congelamento_breve_repetido": {
		"micro freeze", "micro-freeze", "brief freeze", "freezes for a second",
		"freezes for a few seconds", "momentary freeze", "short hang",
		"travadinha", "trava um segundo", "congela por segundos",
		"congelamento breve", "para e volta",
	},
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
	"trava_sob_carga":             "O computador para de responder e volta sozinho, ou precisa ser reiniciado à força.",
	"desligamento_inesperado":     "O computador desliga ou reinicia sem aviso, incluindo tela azul.",
	"nao_inicializa":              "O computador não completa a inicialização do sistema.",
	"congelamento_breve_repetido": "O computador para totalmente por alguns segundos e volta sozinho, várias vezes.",
	"lentidao_intermitente":       "O computador engasga por segundos e volta ao normal sozinho, várias vezes ao dia.",
	"lentidao_profunda":           "O computador entra em períodos longos em que tudo fica lento, e não melhora sozinho.",
	"lentidao_nao_caracterizada":  "O computador está lento, e ainda não se sabe se são engasgos curtos ou períodos longos.",
	"superaquecimento":            "O computador opera acima da faixa térmica segura.",
	"corrupcao_de_dados":          "Arquivos ou estruturas do sistema de arquivos estão sendo corrompidos.",
	"erro_de_dispositivo":         "O sistema operacional está reportando erro de acesso a um dispositivo.",
}

// classe do corpus -> código de causa do conjunto fechado.
//
// Nem toda classe vira causa: `trava` e `boot` são SINTOMAS que a rotulagem
// classificou como classe por falta de conclusão melhor, e `indefinido` é
// ausência de rótulo. Os três não entram como causa — inventar causa a partir
// deles seria exatamente o "chute vira rótulo de treino" que a arquitetura
// proíbe (§0 do roadmap).
var classeParaCausa = map[string]string{
	// A classe do corpus é grossa e não separa as condutas — no fórum "disco"
	// cobre cheio, lento e falhando. Mapeia-se para a causa que o corpus
	// realmente descreve na maioria dos casos (thread de fórum resolvida quase
	// sempre termina em defeito, não em faxina), e as causas finas entram por
	// declaração no `Catalogo` de taxonomia.go, com o discriminador que as separa.
	"disco":      "disco_degradado",
	"memoria":    "memoria_instavel",
	"termico":    "refrigeracao_insuficiente",
	"energia":    "alimentacao_instavel",
	"driver":     "driver_incompativel",
	"software":   "software_conflitante",
	"rede":       "rede_instavel",
	"desempenho": "cpu_insuficiente",
}

// Descrição de cada causa em nível técnico e em nível cliente (§12.2 exige os
// dois; o cliente lê uma frase, o técnico lê a curva).
// Descrição de cada causa em nível técnico e em nível cliente (§12.2 exige os
// dois; o cliente lê uma frase, o técnico lê a curva).
//
// O CRITÉRIO DE EXISTÊNCIA DE UMA CAUSA É A CONDUTA QUE ELA GERA.
//
// A primeira versão tinha `recurso_saturado` engolindo "RAM cheia" e "CPU
// sobrecarregada", e `disco_degradado` engolindo "cheio", "lento" e "falhando".
// Cinco condutas opostas em duas causas — limpar, trocar por melhor, trocar
// urgente com backup, comprar RAM, achar um processo. Um softmax sobre causas
// grossas produz uma probabilidade que não diz o que fazer, e uma probabilidade
// que não diz o que fazer não vale nada para quem atende.
//
// Então causa se divide sempre que a AÇÃO se divide, e nunca só porque o nome
// soa diferente.

// AcaoDaCausa é o que fazer. Existe separado da descrição porque é O MOTIVO de
// a causa existir: se duas causas têm a mesma ação, elas são a mesma causa.
//
// Também é o que a tela mostra em "ação recomendada" (§10.5.2, campo 7) — e o
// que torna possível checar, no futuro, se a ação tomada bateu com a sugerida.

// DiscriminadorDeStatus diz QUAL MEDIDA separa um status dos seus vizinhos.
//
// Existe porque a pergunta "o que testar primeiro?" (§10.5.1, campo 5) precisa
// de uma resposta que não seja "roda tudo". Quando o dossiê não decide entre
// engasgo e degradação, o que falta não é mais um teste qualquer: é a medida
// que tem a forma do episódio.
var DiscriminadorDeStatus = map[string]string{
	// O que separa as causas de um congelamento breve NÃO é uso de recurso —
	// a máquina costuma estar folgada no instante. É a latência de tratamento
	// de interrupção: DPC e ISR altos significam que alguém segurou o
	// processador em IRQL alto, e é isso que congela vídeo e entrada juntos.
	"congelamento_breve_repetido": "latencia_dpc_isr",
	"lentidao_intermitente":       "duracao_do_episodio",
	"lentidao_profunda":           "duracao_do_episodio",
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

// DescricaoDaCausa devolve (técnico, cliente), lendo do catálogo.
func DescricaoDaCausa(causa string) (string, string) {
	p, ok := ProblemaPorCodigo(causa)
	if !ok {
		return causa, causa
	}
	return p.Tecnico, p.Cliente
}

// AcaoDaCausa devolve a conduta. É o motivo de a causa existir: dois problemas
// com a mesma conduta são o mesmo problema.
func AcaoDaCausa(causa string) string {
	p, _ := ProblemaPorCodigo(causa)
	return p.Acao
}

// CausasConhecidas devolve o conjunto fechado inteiro, em ordem estável.
func CausasConhecidas() []string {
	out := make([]string, 0, len(Catalogo))
	for _, p := range Catalogo {
		out = append(out, p.Codigo)
	}
	sort.Strings(out)
	return out
}

// ComTaxonomia reconcilia a derivação do corpus com o CATÁLOGO.
//
// O corpus dá frequência; o catálogo dá o conjunto. Onde o corpus mediu, a
// frequência dele vale — é dado, não opinião. Onde não mediu, entra uniforme,
// que declara "é candidata" sem afirmar o quanto. Declarar 40% sem contar caso
// nenhum seria invenção com cara de estatística.
//
// Todo status conhecido aparece, mesmo os que o corpus nunca tocou: o conjunto
// de causas é derivado da matriz `Produz` do catálogo, não escrito à mão. Era
// exatamente a duplicação de fonte que fazia `lentidao_intermitente` sair com
// zero causas candidatas — um status que abstém sempre.
func ComTaxonomia(
	statuses []StatusDerivado, priors []ParStatusCausa,
) ([]StatusDerivado, []ParStatusCausa) {
	indice := map[string]int{}
	for i, st := range statuses {
		indice[st.Codigo] = i
	}
	// Frequência já medida pelo corpus, por par.
	medido := map[string]float64{}
	for _, p := range priors {
		medido[p.Status+"|"+p.Causa] = p.Frequencia
	}

	var saidaPriors []ParStatusCausa
	contagemCorpus := map[string]int{}
	for _, p := range priors {
		contagemCorpus[p.Status+"|"+p.Causa] = p.N
	}

	for _, status := range StatusConhecidos() {
		causas := CausasDoStatus(status)
		if len(causas) == 0 {
			continue
		}

		i, existe := indice[status]
		if !existe {
			statuses = append(statuses, StatusDerivado{Codigo: status})
			i = len(statuses) - 1
			indice[status] = i
		}
		statuses[i].Descricao = descricaoDeStatus[status]
		statuses[i].CausasCandidatas = causas
		statuses[i].Sinais = SinaisDoStatus(status)
		statuses[i].Limitacoes = LacunasDoStatus(status)
		if len(statuses[i].Testes) == 0 {
			statuses[i].Testes = []string{"all_tests"}
		}

		// Massa que o corpus já mediu para este status, e quantas causas ficaram
		// sem medida. O restante é dividido igualmente entre elas.
		massaMedida, semMedida := 0.0, 0
		for _, c := range causas {
			if f, ok := medido[status+"|"+c]; ok {
				massaMedida += f
			} else {
				semMedida++
			}
		}
		sobra := 1.0 - massaMedida
		if sobra < 0 {
			sobra = 0
		}
		uniforme := 0.0
		if semMedida > 0 {
			uniforme = sobra / float64(semMedida)
		}

		// Piso de prior. Uma causa candidata com prior ZERO nunca pode ser
		// respondida, por mais evidência que apareça — o peso multiplica o
		// prior, e qualquer coisa vezes zero é zero. Ela estaria no conjunto
		// só de enfeite.
		//
		// Acontecia quando o corpus já tinha medido toda a massa do status:
		// não sobrava nada para as causas que ele não viu, e elas entravam
		// zeradas. O piso as mantém vivas sem afirmar frequência que ninguém
		// mediu.
		const pisoDePrior = 0.01

		for _, c := range causas {
			f, ok := medido[status+"|"+c]
			if !ok {
				f = uniforme
			}
			if f < pisoDePrior {
				f = pisoDePrior
			}
			saidaPriors = append(saidaPriors, ParStatusCausa{
				Status: status, Causa: c, N: contagemCorpus[status+"|"+c], Frequencia: f,
			})
		}
	}

	// Status que o corpus derivou mas que nenhum problema do catálogo produz
	// não deveria existir: sem causa candidata ele abstém sempre.
	var filtrados []StatusDerivado
	for _, st := range statuses {
		if len(st.CausasCandidatas) > 0 {
			filtrados = append(filtrados, st)
		}
	}

	// Renormaliza: prior é DISTRIBUIÇÃO, e um vetor que não soma 1 não é
	// probabilidade, é peso disfarçado de probabilidade.
	total := map[string]float64{}
	for _, p := range saidaPriors {
		total[p.Status] += p.Frequencia
	}
	for i := range saidaPriors {
		if t := total[saidaPriors[i].Status]; t > 0 {
			saidaPriors[i].Frequencia /= t
		}
	}
	return filtrados, saidaPriors
}
