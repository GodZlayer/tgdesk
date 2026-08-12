package corpus

import "testing"

// Testes da rotulagem do corpus (§13.3).
//
// A qualidade destes rótulos é o teto de qualidade de tudo que vem depois:
// ontologia, priors e templates saem daqui. Um falso "resolvido" não fica
// contido — vira prior errado, que vira probabilidade errada na tela do
// técnico.

func thread(posts ...Post) Thread {
	for i := range posts {
		if posts[i].Seq == 0 {
			posts[i].Seq = i + 1
		}
	}
	return Thread{Posts: posts}
}

func TestAutorQueNuncaVoltouEhAbandonado(t *testing.T) {
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "meu pc trava do nada"},
		Post{AutorID: "b", CorpoTxt: "roda o memtest"},
	))
	if r.Desfecho != DesfechoAbandonado {
		t.Fatalf("desfecho %q, esperado abandonado", r.Desfecho)
	}
	if r.MotivoDescarte == "" {
		t.Fatal("descarte sem motivo registrado: a thread ainda vale como vocabulário de sintoma")
	}
	if r.SeqDaCausa != 0 {
		t.Fatal("thread abandonada apontou causa; não há causa a apontar")
	}
}

func TestSolucaoEstaNaMensagemDeOutro(t *testing.T) {
	// O caso central de §13.3: a última do autor é só "valeu"; a causa está na
	// mensagem de outra pessoa.
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "trava sob carga"},
		Post{AutorID: "b", CorpoTxt: "seu SMART tem 12 setores realocados, o disco está morrendo"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "troquei o disco, resolveu, obrigado!", CitaSeq: 2},
	))
	if r.Desfecho != DesfechoResolvido {
		t.Fatalf("desfecho %q, esperado resolvido", r.Desfecho)
	}
	if r.SeqDaCausa != 2 {
		t.Fatalf("causa apontada para seq %d; a solução está na mensagem 2", r.SeqDaCausa)
	}
}

func TestRespostaAceitaTemPrecedenciaSobreCitacao(t *testing.T) {
	// Rótulo nativo é humano e explícito — vence qualquer heurística nossa.
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "não liga"},
		Post{AutorID: "b", CorpoTxt: "tenta outro cabo"},
		Post{AutorID: "c", CorpoTxt: "a fonte está fora de especificação", AceitaNativa: true},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "funcionou, obrigado", CitaSeq: 2},
	))
	if r.SeqDaCausa != 3 {
		t.Fatalf("causa em seq %d; a resposta aceita (3) tem precedência", r.SeqDaCausa)
	}
}

func TestObrigadoFuncionouSemCausaNaoViraCaso(t *testing.T) {
	// Sem ninguém mais na thread, "resolveu" não tem de onde tirar causa.
	// Aceitar isso encheria o corpus de agradecimentos sem informação.
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "trava às vezes"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "resolveu sozinho, obrigado"},
	))
	if r.Desfecho == DesfechoResolvido {
		t.Fatal("virou caso resolvido sem mensagem causal: é o 'obrigado, funcionou' que §13.3 recusa")
	}
	if r.MotivoDescarte == "" {
		t.Fatal("descarte sem motivo")
	}
}

func TestReinstalacaoTemInformacaoCausalNula(t *testing.T) {
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "lentidão extrema"},
		Post{AutorID: "b", CorpoTxt: "olha o antivírus"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "formatei e resolveu", CitaSeq: 2},
	))
	if r.Desfecho == DesfechoResolvido {
		t.Fatal("'formatei e resolveu' virou caso: isso ensinaria ao modelo que formatar é a causa")
	}
	if r.SeqDaCausa != 0 {
		t.Fatal("apontou causa para um desfecho sem informação causal")
	}
}

func TestNaoResolvidoEhReconhecido(t *testing.T) {
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "reinicia sozinho"},
		Post{AutorID: "b", CorpoTxt: "troca a RAM"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "troquei, continua travando"},
	))
	if r.Desfecho != DesfechoNaoResolvido {
		t.Fatalf("desfecho %q, esperado nao_resolvido", r.Desfecho)
	}
}

func TestPrimeiraEUltimaDoAutor(t *testing.T) {
	posts := []Post{
		{Seq: 1, AutorID: "a"}, {Seq: 2, AutorID: "b"},
		{Seq: 3, AutorID: "a"}, {Seq: 4, AutorID: "a"},
	}
	primeira, ultima := PrimeiraEUltima(posts, "a")
	if primeira != 1 || ultima != 4 {
		t.Fatalf("primeira=%d ultima=%d; esperado 1 e 4", primeira, ultima)
	}
}

func TestExtracaoDeLogExigeSinalDiagnostico(t *testing.T) {
	// Instrução não é evidência: um comando que o respondente mandou rodar não
	// pode virar assinatura diagnóstica.
	if got := ExtrairBlocosDeLog(`<pre><code>sudo apt update</code></pre>`); len(got) != 0 {
		t.Fatalf("comando virou log: %q", got)
	}

	logReal := `<pre><code>2024-03-11 04:12:07 Error disk 0x0000007A ` +
		`The device \Device\Harddisk0\DR0 has a bad block. Event ID 51</code></pre>`
	blocos := ExtrairBlocosDeLog(logReal)
	if len(blocos) != 1 {
		t.Fatalf("log real não foi extraído: %d blocos", len(blocos))
	}
	if !TemBlocoDeLog(logReal) {
		t.Fatal("TemBlocoDeLog discorda de ExtrairBlocosDeLog")
	}
}

func TestLimpezaDeHTMLPreservaTextoEDesescapa(t *testing.T) {
	got := LimparHTML(`<p>o disco <b>&quot;morreu&quot;</b></p><p>de novo</p>`)
	want := "o disco \"morreu\"\n\nde novo"
	if got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestBlocoDuplicadoNaoEntraDuasVezes(t *testing.T) {
	// <pre><code> é a forma normal do dump; contar os dois duplicaria o log.
	corpo := `<pre><code>CRITICAL_PROCESS_DIED 0x000000EF bugcheck no boot de hoje</code></pre>`
	if got := ExtrairBlocosDeLog(corpo); len(got) != 1 {
		t.Fatalf("%d blocos para um único log", len(got))
	}
}

// O corpus preferido é o Superuser, que é em inglês. Rotulagem que só entende
// português classificaria a fonte inteira como "inconclusivo" — e o corpus
// nasceria vazio sem ninguém perceber, porque nada falharia.
func TestRotulagemEmIngles(t *testing.T) {
	resolvido := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "pc freezes copying files"},
		Post{AutorID: "b", CorpoTxt: "your SMART shows 12 reallocated sectors"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "replaced the disk, it worked, thanks!", CitaSeq: 2},
	))
	if resolvido.Desfecho != DesfechoResolvido || resolvido.SeqDaCausa != 2 {
		t.Fatalf("inglês resolvido: %+v", resolvido)
	}

	naoResolvido := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "random bsod"},
		Post{AutorID: "b", CorpoTxt: "swap the ram"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "did that, still crashing"},
	))
	if naoResolvido.Desfecho != DesfechoNaoResolvido {
		t.Fatalf("inglês não resolvido: %+v", naoResolvido)
	}

	semCausa := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "very slow"},
		Post{AutorID: "b", CorpoTxt: "check the antivirus"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "I formatted the machine and it resolved"},
	))
	if semCausa.Desfecho == DesfechoResolvido {
		t.Fatal("'formatted and resolved' virou caso resolvido em inglês")
	}
	if semCausa.MotivoDescarte == "" {
		t.Fatal("descarte por reinstalação em inglês ficou sem motivo registrado")
	}
}

// Regressão do primeiro ensaio contra o dump real: 3000 threads renderam só 24
// casos. No Stack Exchange o autor escreve só a pergunta — as voltas dele são
// COMENTÁRIOS, que não estão no Posts.xml. A heurística primeira/última não
// tinha segunda mensagem para comparar e marcava tudo como abandonado, sem
// nunca olhar a resposta aceita.
func TestRespostaAceitaValeMesmoSemOAutorVoltar(t *testing.T) {
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "pc freezes copying large files"},
		Post{AutorID: "b", CorpoTxt: "check your cables"},
		Post{AutorID: "c", CorpoTxt: "SMART shows reallocated sectors, the disk is failing", AceitaNativa: true},
	))
	if r.Desfecho != DesfechoResolvido {
		t.Fatalf("desfecho %q: com resposta aceita, o rótulo é nativo e não depende do autor voltar", r.Desfecho)
	}
	if r.SeqDaCausa != 3 {
		t.Fatalf("causa em seq %d, esperado 3 (a resposta aceita)", r.SeqDaCausa)
	}
}

func TestSemRespostaAceitaAHeuristicaContinuaValendo(t *testing.T) {
	// O rótulo nativo tem precedência, mas não substitui a heurística: fontes
	// sem resposta aceita continuam dependendo dela.
	r := Rotular(thread(
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "pc travando"},
		Post{AutorID: "b", CorpoTxt: "olha o SMART do disco"},
		Post{IsCriador: true, AutorID: "a", CorpoTxt: "era o disco mesmo, resolveu", CitaSeq: 2},
	))
	if r.Desfecho != DesfechoResolvido || r.SeqDaCausa != 2 {
		t.Fatalf("heurística parou de funcionar sem rótulo nativo: %+v", r)
	}
}
