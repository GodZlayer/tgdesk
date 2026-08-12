package diagnostico

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Treino em batch a partir do Postgres (§14, §19.3).
//
// O alvo é explícito: a rede tem que chegar ao mesmo desfecho a que o grupo de
// humanos chegou naquele caso.
//
// Ordem das operações, cada uma respondendo a uma armadilha conhecida:
//
//  1. lê `training_example` pela PARTIÇÃO já gravada — nunca sorteia aqui, que
//     vazaria o mesmo caso para os dois lados;
//  2. treina um cabeçote POR STATUS, e só para status com volume;
//  3. calibra a temperatura na validação;
//  4. mede ECE, log-loss e acurácia, e compara com o baseline da REGRA — rede
//     que empata com a regra não entra (§14.2);
//  5. grava `model_version` em SOMBRA, com `n_simulado`.
//
// Nenhum caminho aqui grava 'promovido'. E mesmo que gravasse, o CHECK da 0078
// recusaria enquanto n_simulado = n_treino: código esquece, constraint não.

const (
	// Piso de exemplos para um status render modelo. Abaixo disso o que se
	// produz é memorização com aparência de aprendizado.
	MinimoPorStatus = 12
	// Piso por causa: causa com 1 exemplo não é aprendida, é decorada — e ainda
	// rouba massa de probabilidade das outras.
	MinimoPorCausa = 2
)

// ResultadoDoTreino é o relatório de uma rodada.
type ResultadoDoTreino struct {
	Treinados []CabecoteTreinado `json:"treinados"`
	Recusados []Recusa           `json:"recusados"`
}

type CabecoteTreinado struct {
	Status          string   `json:"status"`
	Causas          []string `json:"causas"`
	NTreino         int      `json:"n_treino"`
	NValidacao      int      `json:"n_validacao"`
	NSimulado       int      `json:"n_simulado"`
	Temperatura     float64  `json:"temperatura"`
	PerdaInicial    float64  `json:"perda_inicial"`
	PerdaFinal      float64  `json:"perda_final"`
	HashPesos       string   `json:"hash_pesos"`
	Metricas        Metricas `json:"metricas"`
	LogLossRegra    float64  `json:"log_loss_regra"`
	MelhorQueARegra bool     `json:"melhor_que_a_regra"`
	cabecote        *Cabecote
}

type Recusa struct {
	Status string `json:"status"`
	N      int    `json:"n"`
	Motivo string `json:"motivo"`
}

// CarregarExemplos lê o conjunto de treino.
func CarregarExemplos(ctx context.Context, pool *pgxpool.Pool) ([]Exemplo, error) {
	rows, err := pool.Query(ctx, `
		SELECT status_codigo, causa_verdadeira, evidencias, peso, particao, origem
		FROM training_example`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var saida []Exemplo
	for rows.Next() {
		var e Exemplo
		var bruto []byte
		if err := rows.Scan(&e.Status, &e.Causa, &bruto, &e.Peso, &e.Particao, &e.Origem); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(bruto, &e.Evidencias); err != nil {
			e.Evidencias = map[string]Evidencia{}
		}
		saida = append(saida, e)
	}
	return saida, rows.Err()
}

// Treinar roda uma rodada completa sobre todos os status.
func Treinar(exemplos []Exemplo) ResultadoDoTreino {
	porStatus := map[string][]Exemplo{}
	for _, e := range exemplos {
		porStatus[e.Status] = append(porStatus[e.Status], e)
	}

	var res ResultadoDoTreino
	statuses := make([]string, 0, len(porStatus))
	for s := range porStatus {
		statuses = append(statuses, s)
	}
	sort.Strings(statuses)

	for _, status := range statuses {
		grupo := porStatus[status]
		if len(grupo) < MinimoPorStatus {
			res.Recusados = append(res.Recusados, Recusa{status, len(grupo),
				fmt.Sprintf("abaixo do piso de %d exemplos", MinimoPorStatus)})
			continue
		}

		contagem := map[string]int{}
		for _, e := range grupo {
			contagem[e.Causa]++
		}
		var causas []string
		for c, n := range contagem {
			if n >= MinimoPorCausa {
				causas = append(causas, c)
			}
		}
		sort.Strings(causas)
		if len(causas) < 2 {
			res.Recusados = append(res.Recusados, Recusa{status, len(grupo),
				"menos de 2 causas com volume — softmax de uma classe responderia " +
					"100% sempre, que nao e diagnostico"})
			continue
		}

		valido := map[string]bool{}
		for _, c := range causas {
			valido[c] = true
		}
		var filtrado []Exemplo
		sinaisVistos := map[string]bool{}
		for _, e := range grupo {
			if !valido[e.Causa] {
				continue
			}
			filtrado = append(filtrado, e)
			for s := range e.Evidencias {
				sinaisVistos[s] = true
			}
		}
		if len(sinaisVistos) == 0 {
			res.Recusados = append(res.Recusados, Recusa{status, len(filtrado), "nenhum sinal observado"})
			continue
		}
		sinais := make([]string, 0, len(sinaisVistos))
		for s := range sinaisVistos {
			sinais = append(sinais, s)
		}
		sort.Strings(sinais)

		vet := Vetorizador{Sinais: sinais}
		vet.Ajustar(filtrado)

		idx := map[string]int{}
		for i, c := range causas {
			idx[c] = i
		}

		var Xt, Xv [][]float64
		var yt, yv []int
		var wt []float64
		nSimulado := 0
		for _, e := range filtrado {
			if e.Origem == "simulado_corpus" {
				nSimulado++
			}
			x := vet.Transformar(e.Evidencias)
			if e.Particao == "validacao" {
				Xv = append(Xv, x)
				yv = append(yv, idx[e.Causa])
				continue
			}
			Xt = append(Xt, x)
			yt = append(yt, idx[e.Causa])
			wt = append(wt, e.Peso)
		}
		if len(Xt) == 0 {
			res.Recusados = append(res.Recusados, Recusa{status, len(filtrado), "particao de treino vazia"})
			continue
		}

		cab := NovoCabecote(status, causas, vet, 16)
		hist := cab.Treinar(Xt, yt, wt, 400, 0.05, 1e-3)
		cab.Calibrar(Xv, yv)
		metricas := cab.Avaliar(Xv, yv)

		// O baseline honesto é a frequência das causas no treino — é
		// literalmente o que o prior faz sem evidência nenhuma (§14.2:
		// "não pior que a regra que substitui").
		logLossRegra := 0.0
		if len(yv) > 0 {
			base := make([]float64, len(causas))
			for _, c := range yt {
				base[c]++
			}
			for i := range base {
				base[i] = maxF(base[i]/float64(len(yt)), 1e-6)
			}
			for _, c := range yv {
				logLossRegra += -logF(base[c])
			}
			logLossRegra /= float64(len(yv))
		}

		res.Treinados = append(res.Treinados, CabecoteTreinado{
			Status: status, Causas: causas,
			NTreino: len(Xt), NValidacao: len(Xv), NSimulado: nSimulado,
			Temperatura:  cab.Temperatura,
			PerdaInicial: hist[0], PerdaFinal: hist[len(hist)-1],
			HashPesos: cab.HashPesos(), Metricas: metricas,
			LogLossRegra:    logLossRegra,
			MelhorQueARegra: len(yv) > 0 && metricas.LogLoss < logLossRegra,
			cabecote:        cab,
		})
	}
	return res
}

// Gravar persiste cada cabeçote como versão em SOMBRA, com os pesos no banco.
func Gravar(ctx context.Context, pool *pgxpool.Pool, res ResultadoDoTreino) error {
	for _, t := range res.Treinados {
		pesos, err := json.Marshal(t.cabecote)
		if err != nil {
			return err
		}
		codigo := fmt.Sprintf("%s.mlp.%s", t.Status, t.HashPesos)
		if _, err := pool.Exec(ctx, `
			INSERT INTO model_version
			  (codigo, status_codigo, causa_codigo, estado, n_treino, n_validacao,
			   n_simulado, ece, log_loss, log_loss_regra, acuracia, hash_pesos, pesos)
			VALUES ($1,$2,NULL,'sombra',$3,$4,$5,$6,$7,$8,$9,$10,$11)
			ON CONFLICT (codigo) DO UPDATE SET
			  n_treino=EXCLUDED.n_treino, n_validacao=EXCLUDED.n_validacao,
			  n_simulado=EXCLUDED.n_simulado, ece=EXCLUDED.ece,
			  log_loss=EXCLUDED.log_loss, log_loss_regra=EXCLUDED.log_loss_regra,
			  acuracia=EXCLUDED.acuracia, pesos=EXCLUDED.pesos, treinado_em=now()`,
			codigo, t.Status, t.NTreino, t.NValidacao, t.NSimulado,
			t.Metricas.ECE, t.Metricas.LogLoss, t.LogLossRegra, t.Metricas.Acuracia,
			t.HashPesos, pesos); err != nil {
			return err
		}
	}
	return nil
}

// CarregarCabecotes lê do banco os modelos que existem, por status.
//
// Vazio é estado NORMAL, não erro: significa que nenhum status atingiu volume
// de treino, e a regra responde sozinha — que é o comportamento correto de
// §14.4, onde nenhuma faixa é um estado degradado.
func CarregarCabecotes(ctx context.Context, pool *pgxpool.Pool) (map[string]*Cabecote, map[string]string, error) {
	rows, err := pool.Query(ctx, `
		SELECT DISTINCT ON (status_codigo) status_codigo, estado, pesos
		FROM model_version
		WHERE pesos IS NOT NULL AND estado <> 'rebaixado'
		ORDER BY status_codigo, (estado = 'promovido') DESC, treinado_em DESC`)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	cabecotes := map[string]*Cabecote{}
	estados := map[string]string{}
	for rows.Next() {
		var status, estado string
		var bruto []byte
		if err := rows.Scan(&status, &estado, &bruto); err != nil {
			return nil, nil, err
		}
		var c Cabecote
		if err := json.Unmarshal(bruto, &c); err != nil {
			// Modelo ilegível não derruba nada: a regra continua respondendo.
			continue
		}
		cabecotes[status] = &c
		estados[status] = estado
	}
	return cabecotes, estados, rows.Err()
}

func maxF(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func logF(v float64) float64 {
	if v <= 0 {
		return -27.6 // ln(1e-12)
	}
	return math.Log(v)
}
