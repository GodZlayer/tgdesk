package handlers

import (
	"context"
	"fmt"
)

// Déficit: a distância entre o que a peça entrega e o que ela deveria entregar.
//
// É a última etapa da ordem correta do diagnóstico — e a que transforma
// adjetivo em medida. Sem referência, "o computador está lento" é opinião;
// com ela, vira "o disco responde a 1% do esperado para a classe dele".
//
// A diferença prática aparece na conduta. Peça que entrega o esperado e o
// usuário reclama não tem defeito: o que falta é capacidade para aquele uso, e
// a resposta é otimizar ou crescer. Peça abaixo do piso da própria classe é
// outra história, e aí trocar faz sentido. Sem a régua, os dois casos viram o
// mesmo conselho — "compre mais" —, que nunca erra e nunca ajuda.

// Deficit é uma medida confrontada com a referência da classe da peça.
type Deficit struct {
	Classe     string  `json:"classe"`
	Peca       string  `json:"peca"`
	Metrica    string  `json:"metrica"`
	Medido     float64 `json:"medido"`
	Esperado   float64 `json:"esperado"`
	EntregaPct float64 `json:"entrega_pct"`
	EmDeficit  bool    `json:"em_deficit"`
	Fonte      string  `json:"fonte"`
	Leitura    string  `json:"leitura"`
}

// AvaliarContraReferencia confronta o estado atual do dispositivo com a régua.
//
// Trabalha sobre a ÚLTIMA amostra da época vigente: comparar com medidas de
// antes de uma troca de peça compararia dois computadores diferentes.
func (s *Server) AvaliarContraReferencia(ctx context.Context, deviceID string) ([]Deficit, error) {
	linhas, err := s.Pool.Query(ctx, `
		WITH ultima AS (
		    SELECT hardware
		      FROM telemetry_snapshots
		     WHERE device_id = $1
		     ORDER BY coletado_em DESC
		     LIMIT 1
		),
		disco AS (
		    SELECT d->>'model'        AS modelo,
		           d->>'bus_type'     AS barramento,
		           d->>'media_type'   AS midia,
		           (d->>'used_pct')::numeric AS ocupacao
		      FROM ultima, jsonb_array_elements(hardware->'storage') d
		),
		memoria AS (
		    SELECT 100 * (hardware->'memory_summary'->>'commit_used_bytes')::numeric
		             / NULLIF((hardware->'memory_summary'->>'commit_limit_bytes')::numeric, 0) AS commit_pct
		      FROM ultima
		)
		SELECT 'disco', disco.modelo, r.metrica, disco.ocupacao, r.valor_esperado, r.fonte
		  FROM disco
		  -- LATERAL com ORDER BY especificidade: a linha mais específica que
		  -- casar vence. Um limite único de ocupação para todo disco do mundo
		  -- é falso — e o próprio parque desmente: uma máquina a 98,3% responde
		  -- em 0,73 ms sob carga enquanto outra a 93,7% desaba para 577 ms. O
		  -- que tolera ocupação é o controlador, não a porcentagem.
		  JOIN LATERAL (
		      SELECT valor_esperado, metrica, fonte
		        FROM component_reference r
		       WHERE r.classe = 'disco'
		         AND r.metrica = 'ocupacao_maxima_pct'
		         AND (r.modelo_como IS NULL OR disco.modelo ILIKE r.modelo_como)
		         AND (r.barramento IS NULL OR r.barramento = disco.barramento)
		         AND (r.midia IS NULL OR r.midia = disco.midia)
		       ORDER BY r.especificidade DESC
		       LIMIT 1
		  ) r ON true
		 WHERE disco.ocupacao IS NOT NULL
		UNION ALL
		SELECT 'memoria', 'memória do sistema', r.metrica, memoria.commit_pct, r.valor_esperado, r.fonte
		  FROM memoria
		  JOIN component_reference r
		    ON r.classe = 'memoria' AND r.metrica = 'commit_maximo_pct'
		 WHERE memoria.commit_pct IS NOT NULL`, deviceID)
	if err != nil {
		return nil, err
	}
	defer linhas.Close()

	var saida []Deficit
	for linhas.Next() {
		var d Deficit
		if err := linhas.Scan(&d.Classe, &d.Peca, &d.Metrica, &d.Medido, &d.Esperado, &d.Fonte); err != nil {
			continue
		}
		// Métricas de TETO: aqui o número medido deve ficar ABAIXO do esperado.
		// Ocupação de disco e uso de memória são assim, e tratá-las como
		// "quanto mais melhor" inverteria o diagnóstico — foi esse tipo de
		// inversão que já classificou disco cheio como disco defeituoso.
		d.EmDeficit = d.Medido > d.Esperado
		if d.Esperado > 0 {
			d.EntregaPct = arredondarPct(d.Medido / d.Esperado * 100)
		}
		d.Leitura = leituraDoDeficit(d)
		saida = append(saida, d)
	}
	return saida, linhas.Err()
}

func leituraDoDeficit(d Deficit) string {
	if !d.EmDeficit {
		return fmt.Sprintf("dentro do esperado (%.0f de no máximo %.0f)", d.Medido, d.Esperado)
	}
	return fmt.Sprintf("acima do limite: %.1f contra %.0f recomendado", d.Medido, d.Esperado)
}

func arredondarPct(v float64) float64 {
	return float64(int(v*10+0.5)) / 10
}
