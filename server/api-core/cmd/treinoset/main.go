// Monta o conjunto de treino por simulação e o grava em `training_example`
// (§19.3).
//
//	caso real -> medidas extraídas -> dossiê sintético no formato da escada ->
//	exemplo de treino rotulado com a causa que os humanos confirmaram
//
// Duas traduções acontecem aqui, e nenhuma delas é cosmética:
//
//  1. `classe_problema` -> CAUSA do conjunto fechado. Classe que é sintoma
//     (`trava`, `boot`) não vira causa — o exemplo é descartado em vez de
//     receber um rótulo inventado.
//  2. título do caso -> STATUS negativo. É o mesmo classificador que a
//     ontologia usa, pelo mesmo motivo: o status tem que sair do relato, não da
//     solução.
//
// Exemplo cujo status ou causa não resolve é DESCARTADO e contado. Um conjunto
// de treino menor e honesto vale mais que um grande com rótulo forçado.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/corpus"
)

func main() {
	corpusURL := flag.String("corpus", "postgres://postgres:corpus@localhost:55433/tgdesk?sslmode=disable", "banco do corpus")
	sqlOut := flag.String("sql", "", "escreve o SQL neste arquivo")
	fracaoValidacao := flag.Float64("validacao", 0.25, "fração do conjunto reservada para validação")
	flag.Parse()

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, *corpusURL)
	if err != nil {
		log.Fatalf("corpus: %v", err)
	}
	defer pool.Close()

	rows, err := pool.Query(ctx, `
		SELECT c.thread_id::text, coalesce(c.classe_problema,'indefinido'), t.titulo,
		       coalesce(string_agg(l.bloco, E'\n'), '')
		FROM corpus.corpus_case c
		JOIN corpus.corpus_thread t ON t.id=c.thread_id
		JOIN corpus.corpus_post p ON p.thread_id=c.thread_id AND p.tem_bloco_log
		CROSS JOIN LATERAL jsonb_array_elements_text(p.logs_extraidos) AS l(bloco)
		WHERE c.desfecho='resolvido' AND t.resolvido_nativo
		GROUP BY c.thread_id, c.classe_problema, t.titulo`)
	if err != nil {
		log.Fatalf("consulta: %v", err)
	}

	var casos []corpus.CasoReal
	for rows.Next() {
		var c corpus.CasoReal
		var blocos string
		if err := rows.Scan(&c.ThreadID, &c.Classe, &c.Sintoma, &blocos); err != nil {
			log.Fatalf("scan: %v", err)
		}
		c.Medidas = corpus.ExtrairMedidas(blocos)
		casos = append(casos, c)
	}
	rows.Close()

	conjunto := corpus.Montar(casos)

	type exemplo struct {
		threadID  string
		status    string
		causa     string
		evidencia map[string]any
	}
	var exemplos []exemplo
	descartadoSemStatus, descartadoSemCausa := 0, 0

	for _, d := range conjunto.Exemplos {
		status := corpus.ClassificarStatus(d.Sintoma)
		if status == "" {
			descartadoSemStatus++
			continue
		}
		causa := corpus.CausaDaClasse(d.Rotulo)
		if causa == "" {
			descartadoSemCausa++
			continue
		}
		ev := map[string]any{}
		for _, e := range d.Evidencias {
			item := map[string]any{"literal": e.Literal}
			// Valor ausente fica AUSENTE da chave (§19.3). Nunca zero.
			if e.Valor != nil {
				item["valor"] = *e.Valor
			}
			ev[e.Sinal] = item
		}
		exemplos = append(exemplos, exemplo{d.ThreadID, status, causa, ev})
	}

	fmt.Printf("casos reais lidos: %d\n", len(casos))
	fmt.Printf("dossiês sintetizados: %d\n", len(conjunto.Exemplos))
	fmt.Printf("exemplos utilizáveis: %d  (descartados: %d sem status, %d sem causa)\n\n",
		len(exemplos), descartadoSemStatus, descartadoSemCausa)

	porPar := map[string]int{}
	porStatus := map[string]int{}
	for _, e := range exemplos {
		porPar[e.status+" / "+e.causa]++
		porStatus[e.status]++
	}
	chaves := make([]string, 0, len(porPar))
	for k := range porPar {
		chaves = append(chaves, k)
	}
	sort.Slice(chaves, func(i, j int) bool { return porPar[chaves[i]] > porPar[chaves[j]] })
	fmt.Println("-- exemplos por (status / causa):")
	for _, k := range chaves {
		fmt.Printf("  %-52s %d\n", k, porPar[k])
	}
	fmt.Println("\n-- por status (é por status que a rede tem cabeçote, §3):")
	for st, n := range porStatus {
		fmt.Printf("  %-26s %d\n", st, n)
	}

	if *sqlOut == "" {
		fmt.Println("\n-- nada gravado (rode com -sql <arquivo>)")
		return
	}

	// Partição por hash estável do thread_id, não aleatória por execução: o
	// mesmo caso cai sempre do mesmo lado, e regerar o conjunto não embaralha a
	// separação treino/validação — que é o que tornaria a métrica incomparável
	// entre duas rodadas.
	var b strings.Builder
	b.WriteString("-- Conjunto de treino por simulacao. GERADO por cmd/treinoset.\n")
	b.WriteString("BEGIN;\nDELETE FROM training_example WHERE origem='simulado_corpus';\n\n")
	nValidacao := 0
	for _, e := range exemplos {
		particao := "treino"
		if hashEstavel(e.threadID) < *fracaoValidacao {
			particao = "validacao"
			nValidacao++
		}
		evJSON, _ := json.Marshal(e.evidencia)
		b.WriteString("INSERT INTO training_example (origem, corpus_thread_id, status_codigo, causa_verdadeira, evidencias, tem_curva, particao)\n")
		fmt.Fprintf(&b, "VALUES ('simulado_corpus',%s,%s,%s,%s,false,%s);\n",
			lit(e.threadID), lit(e.status), lit(e.causa), lit(string(evJSON)), lit(particao))
	}
	b.WriteString("\nCOMMIT;\n")
	if err := os.WriteFile(*sqlOut, []byte(b.String()), 0o644); err != nil {
		log.Fatalf("escrita: %v", err)
	}
	fmt.Printf("\n-- SQL escrito em %s (%d treino, %d validação)\n",
		*sqlOut, len(exemplos)-nValidacao, nValidacao)
}

// hashEstavel devolve um número em [0,1) determinístico para a string.
func hashEstavel(s string) float64 {
	var h uint32 = 2166136261
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return float64(h%10000) / 10000.0
}

func lit(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }
