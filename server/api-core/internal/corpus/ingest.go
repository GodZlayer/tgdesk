// Package corpus faz a ingestão e a rotulagem do corpus externo de casos
// resolvidos (§13 da arquitetura ARQUITETURA-DIAGNOSTICO-NEURAL.md).
//
// Fronteira que este pacote não cruza: o corpus externo produz PRIOR e
// VOCABULÁRIO, nunca veredito. Nada aqui é lido em runtime pelo caminho do
// diagnóstico — a saída alimenta `negative_status`, `text_template`,
// `log_signature` e `corpus_prior` em etapa de construção, sempre com revisão
// humana no meio.
//
// Por que a lógica de rotulagem mora aqui, separada do streaming de XML: o que
// decide a qualidade do corpus é a rotulagem, não o parser. Rotulagem só é
// confiável se der para testá-la contra casos difíceis escritos à mão — e
// nenhum deles precisa de um dump de vários gigabytes para rodar.
package corpus

import (
	"regexp"
	"strings"
)

// Desfecho de uma thread (§13.3).
const (
	DesfechoResolvido    = "resolvido"
	DesfechoNaoResolvido = "nao_resolvido"
	DesfechoAbandonado   = "abandonado"
	DesfechoInconclusivo = "inconclusivo"
)

// Post é uma mensagem já normalizada, na ordem em que aparece na thread.
type Post struct {
	Seq          int
	AutorID      string
	IsCriador    bool
	CorpoTxt     string
	CitaSeq      int
	RespondeA    int
	AceitaNativa bool
}

// Thread é o material bruto de uma discussão.
type Thread struct {
	AutorCriador string
	Posts        []Post
}

// Rotulagem é o resultado da heurística primeira/última mais a busca pela
// mensagem que carrega a causa.
type Rotulagem struct {
	Desfecho   string
	SeqDaCausa int
	// MotivoDescarte explica por que a thread não rende informação causal.
	// Threads descartadas continuam valendo como vocabulário de sintoma —
	// por isso descarte é campo, não exclusão.
	MotivoDescarte string
}

var (
	// Sinais de que o autor voltou para dizer que resolveu. Deliberadamente
	// conservador: falso positivo aqui vira rótulo de treino errado, que é o
	// erro mais caro do projeto.
	// O corpus preferido (Superuser) é em inglês, mas o produto é em português
	// e outras fontes serão em português. As duas línguas convivem no mesmo
	// padrão de propósito: separar por idioma duplicaria a regra sem separar
	// nada de útil.
	reResolveu = regexp.MustCompile(`(?i)\b(resolv(eu|ido|i|ed)|funcionou|deu certo|era isso|` +
		`obrigad[oa].{0,40}(funcionou|resolveu)|solved|it worked|that (fixed|solved|did) it|` +
		`this (fixed|solved) (it|the (issue|problem))|(problem|issue) (is )?(gone|fixed)|` +
		`thanks.{0,40}(worked|fixed|solved)|worked (like a charm|perfectly))\b`)
	reNaoResolveu = regexp.MustCompile(`(?i)\b(não resolveu|nao resolveu|continua (igual|travando|o mesmo)|` +
		`mesmo problema|didn'?t (work|help|fix)|(still|same) (happens|happening|crashes|crashing|freezing|issue|problem)|` +
		`no (luck|change)|did not (work|help))\b`)

	// Desfechos que NÃO carregam informação causal (§13.3, filtros de descarte).
	// "Formatei e sumiu" não ensina qual era a causa — ensina que o autor
	// desistiu de descobrir.
	reSemCausa = regexp.MustCompile(`(?i)\b(reinstal(ei|ar|ação|acao|led|ling|l)|format(ei|ar|ted|ting)|troquei (o|a) (pc|computador|máquina|maquina|notebook)|comprei outro|sumiu sozinho|voltou ao normal sozinho|clean install|fresh install|bought a new (pc|computer|laptop|machine)|went away (on its own|by itself)|fixed itself)\b`)
)

// Rotular aplica §13.3: o desfecho vem da comparação entre a primeira e a
// última mensagem DO AUTOR; o conteúdo causal vem de outra mensagem.
//
// A segunda parte é a que costuma ser esquecida. Na maioria das threads
// resolvidas a solução está na mensagem de outra pessoa, e a última do autor é
// só "valeu, resolveu". Sem seguir a citação, o corpus vira milhares de
// agradecimentos sem causa nenhuma.
func Rotular(t Thread) Rotulagem {
	// RÓTULO NATIVO PRIMEIRO. §13.2 é explícito: quando a fonte tem resposta
	// aceita, o rótulo é nativo e a heurística não se aplica — ela existe
	// "para fóruns sem campo de resposta aceita" (§13.3).
	//
	// Sem esta ordem, o Stack Exchange inteiro cairia em "abandonado": lá o
	// autor escreve só a pergunta, e as voltas dele são COMENTÁRIOS, que não
	// existem no Posts.xml. A heurística primeira/última nunca teria segunda
	// mensagem para comparar. Foi exatamente o que aconteceu no primeiro ensaio
	// contra o dump real: 24 casos em 3000 threads.
	for _, p := range t.Posts {
		if p.AceitaNativa {
			return Rotulagem{Desfecho: DesfechoResolvido, SeqDaCausa: p.Seq}
		}
	}

	doAutor := postsDoAutor(t)

	// Autor nunca voltou: fora do conjunto de causas, mantido só para
	// vocabulário de sintoma.
	if len(doAutor) <= 1 {
		return Rotulagem{
			Desfecho:       DesfechoAbandonado,
			MotivoDescarte: "autor nunca retornou",
		}
	}

	ultima := doAutor[len(doAutor)-1]

	switch {
	case reNaoResolveu.MatchString(ultima.CorpoTxt):
		return Rotulagem{Desfecho: DesfechoNaoResolvido}

	case reSemCausa.MatchString(ultima.CorpoTxt):
		// Pode ter "resolvido" na frase, mas reinstalar o sistema não é causa.
		return Rotulagem{
			Desfecho:       DesfechoInconclusivo,
			MotivoDescarte: "desfecho por reinstalação/troca: informação causal nula",
		}

	case reResolveu.MatchString(ultima.CorpoTxt):
		seq := localizarCausa(t, ultima)
		if seq == 0 {
			// Resolveu, mas não dá para dizer o que resolveu. Vira sintoma, não
			// caso — é o "obrigado, funcionou" que §13.3 manda recusar.
			return Rotulagem{
				Desfecho:       DesfechoInconclusivo,
				MotivoDescarte: "solução declarada sem mensagem causal identificável",
			}
		}
		return Rotulagem{Desfecho: DesfechoResolvido, SeqDaCausa: seq}
	}

	return Rotulagem{Desfecho: DesfechoInconclusivo}
}

// localizarCausa segue, em ordem de confiança: a resposta aceita pela fonte, a
// citação explícita da última mensagem do autor, e por fim a mensagem anterior
// de outra pessoa.
func localizarCausa(t Thread, ultima Post) int {
	// 1. Rótulo nativo da fonte é o melhor que existe — é humano e explícito.
	for _, p := range t.Posts {
		if p.AceitaNativa {
			return p.Seq
		}
	}
	// 2. Citação/resposta explícita do autor ao agradecer.
	for _, ref := range []int{ultima.CitaSeq, ultima.RespondeA} {
		if ref > 0 {
			if p, ok := porSeq(t, ref); ok && !p.IsCriador {
				return p.Seq
			}
		}
	}
	// 3. Última mensagem de OUTRA pessoa antes do agradecimento. É o palpite
	// mais fraco dos três, e por isso fica por último.
	melhor := 0
	for _, p := range t.Posts {
		if p.Seq < ultima.Seq && !p.IsCriador && strings.TrimSpace(p.CorpoTxt) != "" {
			melhor = p.Seq
		}
	}
	return melhor
}

func postsDoAutor(t Thread) []Post {
	var saida []Post
	for _, p := range t.Posts {
		if p.IsCriador {
			saida = append(saida, p)
		}
	}
	return saida
}

func porSeq(t Thread, seq int) (Post, bool) {
	for _, p := range t.Posts {
		if p.Seq == seq {
			return p, true
		}
	}
	return Post{}, false
}

// PrimeiraEUltima devolve, para um autor, os seqs de primeira e última
// mensagem. São esses valores que viram `is_primeira_do_autor` /
// `is_ultima_do_autor` — as colunas que tornam a filtragem por tópico uma
// CONSULTA em vez de heurística sobre texto corrido (§13.7).
func PrimeiraEUltima(posts []Post, autorID string) (primeira, ultima int) {
	for _, p := range posts {
		if p.AutorID != autorID {
			continue
		}
		if primeira == 0 {
			primeira = p.Seq
		}
		ultima = p.Seq
	}
	return
}
