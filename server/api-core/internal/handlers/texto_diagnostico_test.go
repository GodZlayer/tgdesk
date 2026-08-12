package handlers

import (
	"strings"
	"testing"
)

// Testes da camada de texto (§12).
//
// O que se protege aqui é a fronteira que separa este projeto de um chatbot:
// nenhuma frase é escrita em runtime, e nenhuma frase incompleta chega à tela.

func templateDeTeste() Template {
	return Template{
		Chave:  "trava_sob_carga_io.disco_degradado.v1",
		Idioma: "pt-BR",
		Nivel:  "tecnico",
		Titulo: "Disco degradado",
		Corpo: "Parou de responder por {duracao_trava} sob carga de {peca} no degrau " +
			"{degrau_quebra}. O esperado nessa carga seria {limiar_esperado}; " +
			"medimos {valor_medido}.",
		Versao:      1,
		RevisadoPor: "tecnico-123",
	}
}

func valoresCompletos() map[string]string {
	return map[string]string{
		"duracao_trava":   "4,2s",
		"peca":            "disco",
		"degrau_quebra":   "3",
		"limiar_esperado": "<40ms p99",
		"valor_medido":    "310ms p99",
	}
}

func TestRenderizaComTodosOsValores(t *testing.T) {
	titulo, corpo, err := Renderizar(templateDeTeste(), valoresCompletos())
	if err != nil {
		t.Fatalf("render falhou: %v", err)
	}
	if titulo != "Disco degradado" {
		t.Fatalf("título %q", titulo)
	}
	if !strings.Contains(corpo, "4,2s") || !strings.Contains(corpo, "degrau 3") {
		t.Fatalf("valores não entraram: %q", corpo)
	}
	if strings.Contains(corpo, "{") {
		t.Fatalf("sobrou slot sem preencher: %q", corpo)
	}
}

func TestSlotSemValorFalhaAltoEmVezDeMostrarBuraco(t *testing.T) {
	// "Parou de responder por  sob carga de  no degrau " é pior que erro:
	// parece resposta.
	valores := valoresCompletos()
	delete(valores, "duracao_trava")

	_, _, err := Renderizar(templateDeTeste(), valores)
	if err == nil {
		t.Fatal("renderizou com slot faltando")
	}
	erroSlot, ok := err.(*ErroDeSlot)
	if !ok {
		t.Fatalf("erro de tipo errado: %T", err)
	}
	if len(erroSlot.Faltando) != 1 || erroSlot.Faltando[0] != "duracao_trava" {
		t.Fatalf("erro não diz o que faltou: %v", erroSlot.Faltando)
	}
}

func TestSlotVazioContaComoAusente(t *testing.T) {
	// Valor em branco produziria exatamente o mesmo buraco de um valor ausente.
	valores := valoresCompletos()
	valores["valor_medido"] = "   "
	if _, _, err := Renderizar(templateDeTeste(), valores); err == nil {
		t.Fatal("string vazia passou como valor válido")
	}
}

func TestTemplateNaoRevisadoNaoEhServido(t *testing.T) {
	// O modelo generativo propõe rascunho a partir do corpus; gente aprova.
	// Servir rascunho seria deixar o modelo escrever para o técnico por uma
	// porta lateral.
	rascunho := templateDeTeste()
	rascunho.RevisadoPor = ""

	if _, _, err := Renderizar(rascunho, valoresCompletos()); err == nil {
		t.Fatal("rascunho não revisado foi servido ao técnico")
	}
}

func TestSlotsSaemDoCorpoNaoDaColunaDeclarada(t *testing.T) {
	// A fonte da verdade é o texto: um template editado não pode divergir da
	// própria declaração e silenciosamente parar de exigir um valor.
	tpl := templateDeTeste()
	tpl.Titulo = "Disco degradado no degrau {degrau_quebra}"
	slots := SlotsExigidos(tpl)

	if len(slots) != 5 {
		t.Fatalf("slots detectados: %v", slots)
	}
	// Ordenado e sem repetição, mesmo aparecendo no título e no corpo.
	for i := 1; i < len(slots); i++ {
		if slots[i] == slots[i-1] {
			t.Fatalf("slot repetido: %v", slots)
		}
	}
}

func TestChaveSegueOFormatoDaArquitetura(t *testing.T) {
	if got := ChaveDeTemplate("trava_sob_carga_io", "disco_degradado", "v1"); got != "trava_sob_carga_io.disco_degradado.v1" {
		t.Fatalf("chave %q", got)
	}
	if got := ChaveDeTemplate("s", "c", ""); got != "s.c.v1" {
		t.Fatalf("variante padrão errada: %q", got)
	}
}

func TestNivelDoLeitorSeparaTecnicoDeCliente(t *testing.T) {
	if NivelDoLeitor(true) != "tecnico" || NivelDoLeitor(false) != "cliente" {
		t.Fatal("nível trocado: mostraria jargão de supervisor para o cliente")
	}
}
