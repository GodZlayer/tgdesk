package handlers

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

// Renderizador da camada de texto (§12 da arquitetura).
//
// O caminho é sempre `classificador → chave de template → render`. O motor
// devolve chave e valores; nunca prosa. Isto aqui é a última etapa, e é
// deliberadamente burra: substituição de slot, sem lógica de diagnóstico.
//
// A decisão de projeto que mais importa está em `Renderizar`: ele FALHA ALTO
// quando um slot exigido não tem valor. Melhor não mostrar frase do que mostrar
// frase com buraco — "Parou de responder por  sob carga de  no degrau " é pior
// que erro, porque parece resposta.

var reSlot = regexp.MustCompile(`\{([a-z_][a-z0-9_]*)\}`)

// Template é uma linha de `text_template` já carregada.
type Template struct {
	Chave  string
	Idioma string
	Nivel  string
	Titulo string
	Corpo  string
	Versao int
	// RevisadoPor vazio = rascunho. Rascunho não é servido (§12.3).
	RevisadoPor string
}

// ErroDeSlot diz exatamente o que faltou. É erro de programação, não de
// usuário: alguém mudou o template ou o motor parou de emitir um valor.
type ErroDeSlot struct {
	Chave    string
	Faltando []string
}

func (e *ErroDeSlot) Error() string {
	return fmt.Sprintf("template %q: sem valor para %s",
		e.Chave, strings.Join(e.Faltando, ", "))
}

// SlotsExigidos lê do próprio corpo quais slots precisam de valor. A fonte da
// verdade é o texto, não a coluna `slots` — assim um template editado não pode
// divergir da sua própria declaração.
func SlotsExigidos(t Template) []string {
	vistos := map[string]bool{}
	for _, texto := range []string{t.Titulo, t.Corpo} {
		for _, m := range reSlot.FindAllStringSubmatch(texto, -1) {
			vistos[m[1]] = true
		}
	}
	saida := make([]string, 0, len(vistos))
	for s := range vistos {
		saida = append(saida, s)
	}
	sort.Strings(saida)
	return saida
}

// Renderizar preenche o template. Falha se o template não foi revisado ou se
// falta valor para qualquer slot.
func Renderizar(t Template, valores map[string]string) (titulo, corpo string, err error) {
	// Rascunho não chega ao técnico. O modelo generativo propõe; gente aprova.
	if strings.TrimSpace(t.RevisadoPor) == "" {
		return "", "", fmt.Errorf("template %q não revisado: rascunho não é servido", t.Chave)
	}

	var faltando []string
	for _, s := range SlotsExigidos(t) {
		if v, ok := valores[s]; !ok || strings.TrimSpace(v) == "" {
			faltando = append(faltando, s)
		}
	}
	if len(faltando) > 0 {
		// Falha alto, de propósito (§12.2). Frase com buraco parece resposta.
		return "", "", &ErroDeSlot{Chave: t.Chave, Faltando: faltando}
	}

	substituir := func(texto string) string {
		return reSlot.ReplaceAllStringFunc(texto, func(m string) string {
			return valores[reSlot.FindStringSubmatch(m)[1]]
		})
	}
	return substituir(t.Titulo), substituir(t.Corpo), nil
}

// ChaveDeTemplate monta a chave no formato de §12.2: 'status.causa.variante'.
// A variante existe para o mesmo par (status, causa) ter redações diferentes
// conforme a faixa de evidência — "quebrou no degrau 1" e "quebrou no degrau 5"
// merecem ênfase diferente.
func ChaveDeTemplate(status, causa, variante string) string {
	if variante == "" {
		variante = "v1"
	}
	return status + "." + causa + "." + variante
}

// NivelDoLeitor traduz quem está olhando para o nível de texto. Existe como
// função, e não como string solta no chamador, porque errar isto significa
// mostrar jargão de supervisor para o cliente — o oposto do que §9 exige.
func NivelDoLeitor(ehTecnico bool) string {
	if ehTecnico {
		return "tecnico"
	}
	return "cliente"
}
