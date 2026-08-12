package main

import (
	"context"
	"fmt"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
	"tgdesk/api-core/internal/corpus"
)

func main() {
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, "postgres://postgres:corpus@localhost:55433/tgdesk?sslmode=disable")
	if err != nil {
		panic(err)
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
		panic(err)
	}
	defer rows.Close()

	var todos []corpus.CasoReal
	porCampo := map[string]int{}
	porChave := map[string]int{}
	comMedida, total := 0, 0
	classeComMedida := map[string]int{}

	for rows.Next() {
		var id, classe, titulo, logs string
		if rows.Scan(&id, &classe, &titulo, &logs) != nil {
			continue
		}
		total++
		c := corpus.CasoReal{ThreadID: id, Sintoma: titulo, Classe: classe,
			Medidas: corpus.ExtrairMedidas(logs)}
		if !c.TemMedida() {
			continue
		}
		todos = append(todos, c)
		comMedida++
		classeComMedida[classe]++
		for _, campo := range c.CamposDoDossie() {
			porCampo[campo]++
		}
		for _, m := range c.Medidas {
			porChave[m.Campo+"/"+m.Chave]++
		}
	}

	fmt.Printf("casos reais lidos: %d\ncom medida extraida: %d (%.0f%%)\n\n", total, comMedida, float64(comMedida)/float64(total)*100)
	fmt.Println("-- campos de dossie que os casos exigem (= a telemetria necessaria):")
	tipo := ordenar(porCampo)
	for _, k := range tipo {
		fmt.Printf("  %-18s %d casos\n", k, porCampo[k])
	}
	fmt.Println("\n-- medidas mais frequentes:")
	ch := ordenar(porChave)
	for i, k := range ch {
		if i >= 18 {
			break
		}
		fmt.Printf("  %-46s %d\n", k, porChave[k])
	}
	fmt.Println("\n-- casos com medida, por classe:")
	for _, k := range ordenar(classeComMedida) {
		fmt.Printf("  %-12s %d\n", k, classeComMedida[k])
	}

	// Conjunto de treino por simulação (§19.3).
	conj := corpus.Montar(todos)
	fmt.Printf("\n=== CONJUNTO DE TREINO POR SIMULACAO ===\n")
	fmt.Printf("exemplos utilizaveis: %d (descartados por nao render evidencia: %d)\n\n",
		len(conj.Exemplos), conj.SemExemplo)

	fmt.Println("-- exemplos por rotulo (o desfecho a que os humanos chegaram):")
	for _, k := range ordenar(conj.PorRotulo) {
		fmt.Printf("  %-12s %d\n", k, conj.PorRotulo[k])
	}
	fmt.Println("\n-- sinais presentes nos exemplos:")
	for _, k := range ordenar(conj.PorSinal) {
		fmt.Printf("  %-20s %d\n", k, conj.PorSinal[k])
	}
	fmt.Printf("\nrotulos com >=10 exemplos (treinaveis hoje): %v\n",
		conj.RotulosComVolumeMinimo(10))

	if len(conj.Exemplos) > 0 {
		e := conj.Exemplos[0]
		fmt.Printf("\n-- um dossie sintetico, para conferir a forma:\n")
		fmt.Printf("  sintoma : %s\n  rotulo  : %s   simulado=%v  tem_curva=%v\n",
			e.Sintoma, e.Rotulo, e.Simulado, e.TemCurva)
		for _, ev := range e.Evidencias {
			valor := "ausente"
			if ev.Valor != nil {
				valor = fmt.Sprintf("%.0f", *ev.Valor)
			}
			lit := ev.Literal
			if len(lit) > 64 {
				lit = lit[:64] + "…"
			}
			fmt.Printf("    %-18s valor=%-9s %s\n", ev.Sinal, valor, lit)
		}
	}
}

func ordenar(m map[string]int) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Slice(ks, func(a, b int) bool { return m[ks[a]] > m[ks[b]] })
	return ks
}
