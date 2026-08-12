package corpus

import (
	"strings"
	"testing"
)

// Fixture pequeno no formato real do dump. Existe para que o parser seja
// verificável sem os 10+ GB do arquivo verdadeiro — e para que continue
// verificável quando o dump não estiver na máquina.
const dumpDeExemplo = `<?xml version="1.0" encoding="utf-8"?>
<posts>
  <row Id="1" PostTypeId="1" AcceptedAnswerId="3" CreationDate="2021-04-02T10:00:00.000"
       Score="7" Title="PC freezes under heavy disk load"
       Body="&lt;p&gt;My pc freezes when copying big files&lt;/p&gt;"
       OwnerUserId="100" Tags="&lt;hard-drive&gt;&lt;freeze&gt;" AnswerCount="2" />
  <row Id="2" PostTypeId="2" ParentId="1" CreationDate="2021-04-02T11:00:00.000"
       Score="0" Body="&lt;p&gt;try another cable&lt;/p&gt;" OwnerUserId="200" />
  <row Id="3" PostTypeId="2" ParentId="1" CreationDate="2021-04-02T12:00:00.000"
       Score="12" Body="&lt;p&gt;Your SMART shows 12 reallocated sectors&lt;/p&gt;
       &lt;pre&gt;&lt;code&gt;2021-04-01 03:11:02 Error disk 0x0000007A bad block Event ID 51&lt;/code&gt;&lt;/pre&gt;"
       OwnerUserId="300" />
  <row Id="4" PostTypeId="1" CreationDate="2021-05-02T10:00:00.000"
       Title="How to change the wallpaper" Body="&lt;p&gt;where is the setting&lt;/p&gt;"
       OwnerUserId="400" Tags="&lt;windows&gt;&lt;customization&gt;" />
</posts>`

func TestLeituraEmFluxoDoDump(t *testing.T) {
	var lidos []SEPost
	if err := LerPosts(strings.NewReader(dumpDeExemplo), func(p SEPost) error {
		lidos = append(lidos, p)
		return nil
	}); err != nil {
		t.Fatalf("leitura falhou: %v", err)
	}
	if len(lidos) != 4 {
		t.Fatalf("leu %d linhas, esperado 4", len(lidos))
	}

	pergunta := lidos[0]
	if pergunta.PostTypeID != 1 || pergunta.AcceptedAnswerID != 3 {
		t.Fatalf("pergunta lida errado: %+v", pergunta)
	}
	if pergunta.CreationDate.IsZero() {
		t.Fatal("data não foi parseada; sem data não dá para ordenar a thread")
	}
	if lidos[1].ParentID != 1 {
		t.Fatal("resposta perdeu o vínculo com a pergunta")
	}
}

func TestCorpoVemDesescapadoEComLogSeparado(t *testing.T) {
	var respostaBoa SEPost
	_ = LerPosts(strings.NewReader(dumpDeExemplo), func(p SEPost) error {
		if p.ID == 3 {
			respostaBoa = p
		}
		return nil
	})

	texto := LimparHTML(respostaBoa.Body)
	if !strings.Contains(texto, "12 reallocated sectors") {
		t.Fatalf("corpo limpo perdeu o conteúdo: %q", texto)
	}
	logs := ExtrairBlocosDeLog(respostaBoa.Body)
	if len(logs) != 1 {
		t.Fatalf("bloco de log não foi separado: %d blocos", len(logs))
	}
	if !strings.Contains(logs[0], "Event ID 51") {
		t.Fatalf("log extraído sem a linha diagnóstica: %q", logs[0])
	}
}

func TestFiltroDeDominioDescartaOForaDeEscopo(t *testing.T) {
	if !InteressaAoDominio("<hard-drive><freeze>", "PC freezes under heavy disk load") {
		t.Fatal("pergunta de disco ficou de fora do corpus")
	}
	if InteressaAoDominio("<windows><customization>", "How to change the wallpaper") {
		t.Fatal("pergunta de papel de parede entrou: sinal que nenhuma causa consome é custo puro")
	}
}

func TestClassePorTagsSeparaPorClasseDeProblema(t *testing.T) {
	cases := []struct{ tags, titulo, quer string }{
		{"<hard-drive>", "freezes copying files", "disco"},
		{"<memory>", "random bsod", "memoria"},
		{"<overheating>", "laptop shuts down", "termico"},
		{"<power-supply>", "pc não liga", "energia"},
		{"<driver>", "code 43 on gpu", "driver"},
		{"<windows>", "how to rename a folder", "indefinido"},
	}
	for _, c := range cases {
		if got := ClassePorTags(c.tags, c.titulo); got != c.quer {
			t.Fatalf("%q → classe %q, esperado %q", c.titulo, got, c.quer)
		}
	}
}

func TestSSDComLentidaoEhDiscoNaoDesempenho(t *testing.T) {
	// A ordem das classes importa: cobertura é medida por classe, e classificar
	// falha de SSD como "desempenho" esconderia a classe disco em zero.
	if got := ClassePorTags("<ssd><performance>", "ssd getting slow and freezing"); got != "disco" {
		t.Fatalf("classe %q, esperado disco", got)
	}
}

func TestLinhaCorrompidaNaoDerrubaAIngestao(t *testing.T) {
	// Dump de vários GB tem lixo. Abortar tudo por causa de uma linha seria
	// descartar milhares de casos bons.
	xmlRuim := `<posts><row Id="" PostTypeId="1" /><row Id="9" PostTypeId="1" Title="ok" /></posts>`
	var n int
	if err := LerPosts(strings.NewReader(xmlRuim), func(SEPost) error { n++; return nil }); err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	if n != 1 {
		t.Fatalf("aceitou %d linhas, esperado 1 (a linha sem Id é lixo)", n)
	}
}

func TestSubstringNaoContaComoTag(t *testing.T) {
	// Regressão: "cHANGe" contém "hang" e "sCANner" contém "can". Casamento por
	// substring solta traria toda pergunta de interface para dentro do corpus
	// de hardware, e o viés entraria pela porta da frente.
	if InteressaAoDominio("<windows>", "how to change the wallpaper") {
		t.Fatal("'change' casou com a tag 'hang'")
	}
	if !InteressaAoDominio("<windows>", "my pc hangs every morning") {
		t.Fatal("'hangs' deveria casar com 'hang' por fronteira de palavra")
	}
	if ClassePorTags("<windows>", "how to rename a scanner") != "indefinido" {
		t.Fatal("'scanner' casou com algum termo por substring")
	}
}

// O Superuser é, em boa parte, um site de "como faço". Ingerir configuração
// como caso resolvido envenenaria os priors: o modelo aprenderia que a causa de
// "não dá boot" é "particionar o disco".
func TestPerguntaDeConfiguracaoNaoEhCasoDeFalha(t *testing.T) {
	naoSaoCasos := []struct{ titulo, corpo string }{
		{"How to dual boot Windows and Linux", "I want to install both on the same disk"},
		{"What is the difference between UEFI and BIOS", "just curious about the boot process"},
		{"Best way to partition a new hard drive", "setting up a fresh machine"},
		{"Can I install Windows from a USB stick", "no dvd drive here"},
		{"Como faço para configurar dois monitores", "quero usar os dois ao mesmo tempo"},
	}
	for _, c := range naoSaoCasos {
		if EhCasoDeFalha(c.titulo, c.corpo) {
			t.Fatalf("pergunta de configuração entrou como caso: %q", c.titulo)
		}
	}

	saoCasos := []struct{ titulo, corpo string }{
		{"PC freezes under heavy disk load", "it stops responding for seconds"},
		{"Laptop won't boot after update", "black screen, no post"},
		{"How to fix random BSOD after installing new RAM", "it crashes every hour"},
		{"Computador travando e desligando sozinho", "acontece depois de uns minutos"},
		{"Machine reboots itself randomly", "no pattern that I can see"},
	}
	for _, c := range saoCasos {
		if !EhCasoDeFalha(c.titulo, c.corpo) {
			t.Fatalf("caso de defeito foi descartado: %q", c.titulo)
		}
	}
}

func TestComoFazerComFalhaExplicitaContinuaSendoCaso(t *testing.T) {
	// A regra é assimétrica: "how to" só é recusado quando NÃO há falha
	// descrita. Recusar "how to fix the crash" perderia caso bom.
	if !EhCasoDeFalha("How do I fix the disk error on boot", "it fails with a read error") {
		t.Fatal("'how to fix' com falha explícita foi descartado")
	}
}
