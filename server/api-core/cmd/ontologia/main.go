// Deriva o catálogo de status negativos, os priors e os templates a partir do
// corpus (§4, §12.2, §13.4).
//
// A saída é um SCRIPT SQL, não uma escrita direta: o Postgres de produção não
// publica porta no host, e não publicar é a postura certa. O script é aplicado
// por psql dentro do container e fica versionado no repositório como o
// registro exato do que entrou no banco.
//
// Sobre revisão: a arquitetura exige que nada valha sem revisão (§8, §12.3), e
// o esquema modelava isso como `revisado_por -> technicians`, que admite
// apenas revisor humano. Forjar um técnico para assinar milhares de linhas
// destruiria a única pergunta que a coluna responde — quem aprovou. Por isso a
// 0078 declarou o segundo tipo de revisor, e é ele que este comando preenche:
// `revisado_por_automacao` guarda a procedência da derivação.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/corpus"
)

const origem = "corpusderiva/ontologia@superuser-dump"

func main() {
	corpusURL := flag.String("corpus", "postgres://postgres:corpus@localhost:55433/tgdesk?sslmode=disable", "banco do corpus")
	minimo := flag.Int("minimo", 8, "casos mínimos para uma causa entrar no conjunto candidato")
	sqlOut := flag.String("sql", "", "escreve o SQL neste arquivo")
	flag.Parse()

	ctx := context.Background()

	cpool, err := pgxpool.New(ctx, *corpusURL)
	if err != nil {
		log.Fatalf("corpus: %v", err)
	}
	defer cpool.Close()

	// O sinal vem da MENSAGEM CAUSAL; o status, do TÍTULO. O título é o relato
	// de quem ainda não sabe a causa — é o que o cliente escreve. Quem cita
	// SMART, memtest ou temperatura é quem respondeu (§13.3). Extrair status do
	// texto da solução seria vazamento de rótulo: o modelo aprenderia a ler a
	// resposta em vez da pergunta.
	rows, err := cpool.Query(ctx, `
		SELECT coalesce(c.sintoma_normalizado, t.titulo),
		       coalesce(c.classe_problema, ''),
		       coalesce(p.corpo_txt, '')
		FROM corpus.corpus_case c
		JOIN corpus.corpus_thread t ON t.id = c.thread_id
		LEFT JOIN corpus.corpus_post p
		       ON p.thread_id = c.thread_id AND p.seq = c.seq_da_causa
		WHERE c.desfecho = 'resolvido'`)
	if err != nil {
		log.Fatalf("consulta: %v", err)
	}

	var casos []corpus.CasoParaOntologia
	for rows.Next() {
		var c corpus.CasoParaOntologia
		var mensagemCausal string
		if err := rows.Scan(&c.Relato, &c.Classe, &mensagemCausal); err != nil {
			log.Fatalf("scan: %v", err)
		}
		c.Sinais = corpus.ExtrairSinais(mensagemCausal)
		c.Testes = corpus.ExtrairTestes(mensagemCausal)
		casos = append(casos, c)
	}
	rows.Close()

	statuses, priors := corpus.DerivarOntologia(casos, *minimo)

	fmt.Printf("casos resolvidos lidos: %d\n", len(casos))
	fmt.Printf("status negativos derivados: %d\n\n", len(statuses))
	for _, st := range statuses {
		fmt.Printf("%-24s %4d casos\n", st.Codigo, st.CasosTotal)
		for _, p := range priors {
			if p.Status != st.Codigo {
				continue
			}
			fmt.Printf("    %-28s prior %5.1f%%  n=%d\n", p.Causa, p.Frequencia*100, p.N)
		}
		if len(st.Limitacoes) > 0 {
			fmt.Printf("    (lacuna declarada: %v)\n", st.Limitacoes)
		}
		fmt.Printf("    sinais: %v\n\n", st.Sinais)
	}

	if *sqlOut == "" {
		fmt.Println("-- nada gravado (rode com -sql <arquivo>)")
		return
	}
	if err := emitirSQL(*sqlOut, statuses, priors); err != nil {
		log.Fatalf("sql: %v", err)
	}
	fmt.Printf("-- SQL escrito em %s\n", *sqlOut)
}

func emitirSQL(caminho string, statuses []corpus.StatusDerivado, priors []corpus.ParStatusCausa) error {
	var b strings.Builder
	b.WriteString("-- Ontologia derivada do corpus. GERADO por cmd/ontologia — nao editar a mao.\n")
	b.WriteString("-- Regerar: go run ./cmd/ontologia -sql <arquivo>\n\nBEGIN;\n\n")

	for _, st := range statuses {
		sinais := arrayJSON(st.Sinais)
		causas := arrayJSON(st.CausasCandidatas)
		testes := arrayJSON(st.Testes)
		limitacoes := arrayJSON(st.Limitacoes)
		b.WriteString("INSERT INTO negative_status\n")
		b.WriteString("  (codigo, descricao, sinais, causas_candidatas, testes_discriminantes,\n")
		b.WriteString("   limitacoes, origem_corpus, revisado_por_automacao, revisado_em)\n")
		fmt.Fprintf(&b, "VALUES (%s,%s,%s,%s,%s,%s,%s,%s, now())\n",
			lit(st.Codigo), lit(st.Descricao), lit(sinais), lit(causas),
			lit(testes), lit(limitacoes), lit(origem), lit(origem))
		b.WriteString("ON CONFLICT (codigo) DO UPDATE SET\n")
		b.WriteString("  descricao=EXCLUDED.descricao, sinais=EXCLUDED.sinais,\n")
		b.WriteString("  causas_candidatas=EXCLUDED.causas_candidatas,\n")
		b.WriteString("  testes_discriminantes=EXCLUDED.testes_discriminantes,\n")
		b.WriteString("  limitacoes=EXCLUDED.limitacoes, origem_corpus=EXCLUDED.origem_corpus,\n")
		b.WriteString("  revisado_por_automacao=EXCLUDED.revisado_por_automacao,\n")
		b.WriteString("  revisado_em=now(), updated_at=now();\n")
	}
	b.WriteString("\n")

	for _, p := range priors {
		b.WriteString("INSERT INTO corpus.corpus_prior (status_codigo, causa_codigo, frequencia, n, peso_atual)\n")
		fmt.Fprintf(&b, "VALUES (%s,%s,%.6f,%d,1.0)\n", lit(p.Status), lit(p.Causa), p.Frequencia, p.N)
		b.WriteString("ON CONFLICT (status_codigo, causa_codigo) DO UPDATE SET\n")
		b.WriteString("  frequencia=EXCLUDED.frequencia, n=EXCLUDED.n, atualizado_em=now();\n")
	}
	b.WriteString("\n")

	const slots = `'["valor_medido","limiar_esperado","probabilidade"]'`
	for _, p := range priors {
		tec, cli := corpus.DescricaoDaCausa(p.Causa)
		chave := fmt.Sprintf("%s.%s.v1", p.Status, p.Causa)
		niveis := [][2]string{
			{"tecnico", tec + " Medimos {valor_medido}; o esperado para esta classe seria {limiar_esperado}. Probabilidade {probabilidade}."},
			{"cliente", cli + " Fale com um tecnico."},
		}
		for _, n := range niveis {
			b.WriteString("INSERT INTO text_template (chave, idioma, nivel, titulo, corpo, slots, versao, origem_corpus, revisado_por_automacao, revisado_em)\n")
			fmt.Fprintf(&b, "VALUES (%s,'pt-BR',%s,%s,%s,%s,1,%s,%s, now())\n",
				lit(chave), lit(n[0]), lit(tec), lit(n[1]), slots, lit(origem), lit(origem))
			b.WriteString("ON CONFLICT (chave, idioma, nivel, versao) DO UPDATE SET\n")
			b.WriteString("  titulo=EXCLUDED.titulo, corpo=EXCLUDED.corpo, slots=EXCLUDED.slots,\n")
			b.WriteString("  revisado_por_automacao=EXCLUDED.revisado_por_automacao, revisado_em=now();\n")
		}
	}

	b.WriteString("\nCOMMIT;\n")
	return os.WriteFile(caminho, []byte(b.String()), 0o644)
}

// arrayJSON garante ARRAY vazio, nunca `null`.
//
// Slice nil em Go vira `null` em JSON, e `null` num jsonb quebra todo consumidor
// que trate a coluna como lista — `jsonb_array_length` de um escalar é erro, nao
// zero. O default da coluna e '[]', mas insert explicito passa por cima dele.
func arrayJSON(v []string) string {
	if v == nil {
		return "[]"
	}
	b, _ := json.Marshal(v)
	return string(b)
}

// lit escapa um literal de texto para SQL. O dado vem de titulo de forum —
// assumir que nao tem aspas seria ingenuo.
func lit(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
