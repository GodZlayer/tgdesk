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
	"lentidao_persistente": {
		"slow", "slowly", "sluggish", "performance", "lag", "laggy",
		"takes forever", "lento", "lentidão", "lentidao", "desempenho",
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
	"trava_sob_carga":         "O computador para de responder e volta sozinho, ou precisa ser reiniciado à força.",
	"desligamento_inesperado": "O computador desliga ou reinicia sem aviso, incluindo tela azul.",
	"nao_inicializa":          "O computador não completa a inicialização do sistema.",
	"lentidao_persistente":    "O computador está sistematicamente mais lento do que deveria para o seu hardware.",
	"superaquecimento":        "O computador opera acima da faixa térmica segura.",
	"corrupcao_de_dados":      "Arquivos ou estruturas do sistema de arquivos estão sendo corrompidos.",
	"erro_de_dispositivo":     "O sistema operacional está reportando erro de acesso a um dispositivo.",
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
