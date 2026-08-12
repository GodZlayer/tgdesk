package corpus

import (
	"html"
	"regexp"
	"strings"
)

// Limpeza de texto e extração de blocos de log.
//
// O corpus é SOMENTE TEXTO — sem imagens, sem anexos (§13.2). E o que ele
// entrega de mais valioso não é a prosa: são os blocos de log que o humano
// olhou para decidir. Eles saem separados aqui e viram a matéria-prima de
// `log_signature` (§8), onde a evidência deixa de ser texto solto e passa a ser
// evidência NOMEADA e citável.

var (
	rePre    = regexp.MustCompile(`(?is)<pre[^>]*>(.*?)</pre>`)
	reCode   = regexp.MustCompile(`(?is)<code[^>]*>(.*?)</code>`)
	reTag    = regexp.MustCompile(`(?s)<[^>]+>`)
	reEspaco = regexp.MustCompile(`[ \t]+`)
	reLinhas = regexp.MustCompile(`\n{3,}`)

	// O que faz um bloco parecer log de verdade, e não um comando de uma linha
	// ou um nome de arquivo entre crases. Ser exigente aqui é o que evita
	// encher `logs_extraidos` de ruído que depois vira assinatura inútil.
	reSinalDeLog = regexp.MustCompile(`(?i)(0x[0-9a-f]{6,}|` + // código de erro / bugcheck
		`\b(error|erro|fail(ed|ure)?|warning|critical|exception|bugcheck|panic)\b|` +
		`\bevent\s*id\b|` +
		`\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}|` + // timestamp
		`\b(smart|reallocated|pending sector|crc)\b)`)
)

// LimparHTML transforma o corpo da fonte em texto plano legível, preservando as
// quebras que separam blocos. Não é sanitização de segurança: é redução de
// ruído para que o texto sirva de vocabulário.
func LimparHTML(corpo string) string {
	t := corpo
	t = strings.ReplaceAll(t, "</p>", "\n\n")
	t = strings.ReplaceAll(t, "<br>", "\n")
	t = strings.ReplaceAll(t, "<br/>", "\n")
	t = strings.ReplaceAll(t, "<br />", "\n")
	t = reTag.ReplaceAllString(t, "")
	t = html.UnescapeString(t)
	t = reEspaco.ReplaceAllString(t, " ")
	t = reLinhas.ReplaceAllString(t, "\n\n")
	return strings.TrimSpace(t)
}

// ExtrairBlocosDeLog devolve os blocos que parecem log de verdade, já em texto
// plano. Blocos de código sem nenhum sinal diagnóstico são descartados: um
// comando que o respondente mandou rodar não é evidência, é instrução.
func ExtrairBlocosDeLog(corpoHTML string) []string {
	var blocos []string
	vistos := map[string]bool{}

	adicionar := func(bruto string) {
		texto := LimparHTML(bruto)
		if len(texto) < 40 || !reSinalDeLog.MatchString(texto) {
			return
		}
		if vistos[texto] {
			return
		}
		vistos[texto] = true
		blocos = append(blocos, texto)
	}

	for _, m := range rePre.FindAllStringSubmatch(corpoHTML, -1) {
		adicionar(m[1])
	}
	// <code> solto só entra se o <pre> não pegou nada: em quase todo dump o
	// bloco vem como <pre><code>, e contar os dois duplicaria o mesmo log.
	if len(blocos) == 0 {
		for _, m := range reCode.FindAllStringSubmatch(corpoHTML, -1) {
			adicionar(m[1])
		}
	}
	return blocos
}

// TemBlocoDeLog é o predicado que vira a coluna `tem_bloco_log`. Existe
// separado porque a consulta "quais threads rendem assinatura" é feita por essa
// coluna, e não relendo o corpo de milhões de mensagens.
func TemBlocoDeLog(corpoHTML string) bool {
	return len(ExtrairBlocosDeLog(corpoHTML)) > 0
}
