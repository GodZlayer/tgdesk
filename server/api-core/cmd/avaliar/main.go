// Avaliação do motor de regra contra os casos reais (§19.3).
//
// Responde a pergunta que nenhum teste unitário responde: **o motor chega ao
// mesmo desfecho a que o grupo de humanos chegou?**
//
// Duas honestidades obrigatórias, sem as quais o número seria propaganda:
//
//  1. SEPARAÇÃO TREINO/TESTE. Os pesos são aprendidos numa parte dos casos e
//     medidos na outra. Aprender e medir no mesmo conjunto produziria acerto
//     alto e falso — o motor teria decorado, não aprendido.
//  2. O MOTOR AVALIADO É O DE VERDADE. As chamadas vão por HTTP para o
//     container do tgdesk-brain, não para uma reimplementação em Go. Avaliar
//     uma cópia mediria a cópia.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"hash/fnv"
	"log"
	"net/http"
	"os"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/corpus"
)

func main() {
	var (
		dbURL    = flag.String("db", os.Getenv("DATABASE_URL"), "Postgres do corpus")
		brainURL = flag.String("brain", "http://localhost:58101", "URL do tgdesk-brain")
		fracao   = flag.Int("treino-pct", 70, "percentual dos casos usado para aprender")
	)
	flag.Parse()

	casos, err := carregar(context.Background(), *dbURL)
	if err != nil {
		log.Fatalf("carregando casos: %v", err)
	}
	conj := corpus.Montar(casos)
	log.Printf("exemplos: %d", len(conj.Exemplos))

	// A divisão é por hash do thread_id, não aleatória: rodar duas vezes tem
	// que dar o mesmo resultado, senão o número muda a cada execução e não
	// serve para comparar versões do motor.
	var treino, teste []corpus.DossieSintetico
	for _, e := range conj.Exemplos {
		if int(hash(e.ThreadID)%100) < *fracao {
			treino = append(treino, e)
		} else {
			teste = append(teste, e)
		}
	}
	log.Printf("treino: %d   teste: %d", len(treino), len(teste))

	priors, pesos, nPorRotulo := aprender(treino)
	rotulos := chaves(nPorRotulo)
	log.Printf("rótulos aprendidos: %v", rotulos)

	avaliar(*brainURL, teste, rotulos, priors, pesos)
}

func carregar(ctx context.Context, url string) ([]corpus.CasoReal, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
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
		return nil, err
	}
	defer rows.Close()

	var casos []corpus.CasoReal
	for rows.Next() {
		var id, classe, titulo, logs string
		if rows.Scan(&id, &classe, &titulo, &logs) != nil {
			continue
		}
		casos = append(casos, corpus.CasoReal{
			ThreadID: id, Classe: classe, Sintoma: titulo,
			Medidas: corpus.ExtrairMedidas(logs),
		})
	}
	return casos, rows.Err()
}

// aprender calcula prior por rótulo e o peso de cada sinal para cada rótulo.
//
// O peso é LIFT: quantas vezes mais provável o sinal é naquele rótulo do que no
// conjunto todo. Frequência pura premiaria o sinal que aparece em tudo — que é
// justamente o que não decide nada (§13.6).
func aprender(treino []corpus.DossieSintetico) (map[string]float64, map[string]map[string]float64, map[string]int) {
	nPorRotulo := map[string]int{}
	nSinalRotulo := map[string]map[string]int{}
	nSinal := map[string]int{}

	for _, e := range treino {
		nPorRotulo[e.Rotulo]++
		for _, ev := range e.Evidencias {
			if nSinalRotulo[ev.Sinal] == nil {
				nSinalRotulo[ev.Sinal] = map[string]int{}
			}
			nSinalRotulo[ev.Sinal][e.Rotulo]++
			nSinal[ev.Sinal]++
		}
	}

	priors := map[string]float64{}
	for r, n := range nPorRotulo {
		priors[r] = float64(n) / float64(len(treino))
	}

	pesos := map[string]map[string]float64{}
	for sinal, porRotulo := range nSinalRotulo {
		pesos[sinal] = map[string]float64{}
		for rotulo, n := range porRotulo {
			pSinalDadoRotulo := float64(n) / float64(nPorRotulo[rotulo])
			pSinal := float64(nSinal[sinal]) / float64(len(treino))
			if pSinal <= 0 {
				continue
			}
			lift := pSinalDadoRotulo/pSinal - 1
			if lift > 0 {
				pesos[sinal][rotulo] = lift
			}
		}
	}
	return priors, pesos, nPorRotulo
}

func avaliar(brainURL string, teste []corpus.DossieSintetico, rotulos []string,
	priors map[string]float64, pesos map[string]map[string]float64) {

	acertosTop1, acertosTop3, abstencoes, erros := 0, 0, 0, 0
	porRotulo := map[string][2]int{} // [acertos, total]

	for _, e := range teste {
		evid := make([]map[string]any, 0, len(e.Evidencias))
		for _, ev := range e.Evidencias {
			m := map[string]any{"sinal": ev.Sinal, "literal": ev.Literal}
			if ev.Valor != nil {
				m["valor"] = *ev.Valor
			}
			evid = append(evid, m)
		}
		achatado := map[string]float64{}
		for sinal, porRot := range pesos {
			for rot, p := range porRot {
				achatado[sinal+"|"+rot] = p
			}
		}

		corpo, _ := json.Marshal(map[string]any{
			"device_id":         e.ThreadID,
			"status_codigo":     "caso_de_corpus",
			"causas_candidatas": rotulos,
			"priors":            priors,
			"pesos_sinal_causa": achatado,
			"evidencias":        evid,
			"tem_curva":         false,
		})
		resp, err := http.Post(brainURL+"/infer", "application/json", bytes.NewReader(corpo))
		if err != nil {
			log.Fatalf("brain indisponível: %v", err)
		}
		var out struct {
			Abstain bool `json:"abstain"`
			Causas  []struct {
				Codigo string `json:"codigo"`
			} `json:"causas"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&out)
		resp.Body.Close()

		st := porRotulo[e.Rotulo]
		st[1]++

		switch {
		case out.Abstain || len(out.Causas) == 0:
			abstencoes++
		case out.Causas[0].Codigo == e.Rotulo:
			acertosTop1++
			acertosTop3++
			st[0]++
		default:
			erros++
			for _, c := range out.Causas {
				if c.Codigo == e.Rotulo {
					acertosTop3++
					break
				}
			}
		}
		porRotulo[e.Rotulo] = st
	}

	n := len(teste)
	fmt.Printf("\n=== MOTOR DE REGRA CONTRA CASOS REAIS (conjunto de teste) ===\n")
	fmt.Printf("casos avaliados     : %d\n", n)
	fmt.Printf("acerto na 1a hipótese: %d (%.1f%%)\n", acertosTop1, pct(acertosTop1, n))
	fmt.Printf("acerto no top-3      : %d (%.1f%%)\n", acertosTop3, pct(acertosTop3, n))
	fmt.Printf("abstenções           : %d (%.1f%%)\n", abstencoes, pct(abstencoes, n))
	fmt.Printf("erros                : %d (%.1f%%)\n", erros, pct(erros, n))

	// Sem abstenção no denominador: dos casos em que o motor ARRISCOU, quanto
	// ele acertou. É o número que diz se o técnico pode confiar quando ele fala.
	arriscou := n - abstencoes
	if arriscou > 0 {
		fmt.Printf("\nquando NÃO se absteve: %.1f%% de acerto na 1a (%d de %d)\n",
			pct(acertosTop1, arriscou), acertosTop1, arriscou)
	}

	fmt.Println("\n-- por classe:")
	for _, r := range chavesPar(porRotulo) {
		st := porRotulo[r]
		fmt.Printf("  %-12s %d/%d  (%.0f%%)\n", r, st[0], st[1], pct(st[0], st[1]))
	}
}

func pct(a, b int) float64 {
	if b == 0 {
		return 0
	}
	return float64(a) / float64(b) * 100
}

func hash(s string) uint32 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(s))
	return h.Sum32()
}

func chaves(m map[string]int) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

func chavesPar(m map[string][2]int) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}
