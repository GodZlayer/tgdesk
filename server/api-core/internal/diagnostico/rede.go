// Package diagnostico é o motor de causa provável do TGDesk (§3, §14, §19.3).
//
// Duas camadas, MESMA saída, e a tela não sabe qual respondeu:
//
//  1. regra determinística sobre prior + evidência observada;
//  2. rede neural, um cabeçote por status negativo.
//
// Sobre morar aqui dentro: a arquitetura desenhou o `tgdesk-brain` como serviço
// separado no compose. O projeto tem uma regra que vale mais — UM CONTAINER POR
// PROJETO — e ela ganha. A fronteira dura de §3 não se perde com a junção; ela
// fica mais forte, porque a rede deixa de ter endereço próprio: não tem rota,
// não abre canal, não conhece RBAC nem cliente. É função chamada pelo api-core.
//
// O que se perde é o isolamento de processo, e o que se ganha é não ter um
// segundo runtime, um segundo deploy, um segundo ponto de falha e um volume de
// pesos para sincronizar. Para um MLP de dezenas de exemplos, a troca não é
// próxima.
//
// A rede é um MLP de uma camada oculta: ReLU, softmax, cross-entropy, backprop,
// calibração por temperatura. É a mesma matemática que a arquitetura pede em
// PyTorch — e o ponto de troca fica declarado: quando a entrada deixar de ser
// um vetor de sinais e passar a ser a curva inteira como série, isto aqui não
// serve mais e vira treino externo com pesos importados.
package diagnostico

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"math/rand"
	"sort"
)

// Semente fixa: treino que não reproduz não é auditável. Dois treinos com o
// mesmo dado precisam dar o mesmo peso, senão não dá para saber se uma métrica
// mudou por causa do dado ou do sorteio.
const semente = 20260812

// Vetorizador traduz evidências do dossiê em vetor numérico.
//
// DUAS features por sinal, e é aí que mora a regra de ausência (§19.3):
//
//	presente[i]  1 se o sinal foi observado, 0 se não
//	valor[i]     o valor medido normalizado, 0 quando ausente
//
// A segunda sozinha seria ambígua — "temperatura 0" e "temperatura não medida"
// colapsariam no mesmo número. A primeira desfaz a ambiguidade, e é por isso
// que ausência continua sendo informação em vez de virar zero.
type Vetorizador struct {
	Sinais []string `json:"sinais"`
	// Escala por sinal, aprendida do treino (mediana dos valores observados).
	// Normalizar por constante de código faria a rede depender de uma unidade
	// que ninguém revisou.
	Escala map[string]float64 `json:"escala"`
}

func (v Vetorizador) Dimensao() int { return len(v.Sinais) * 2 }

// Ajustar calcula a escala de cada sinal a partir dos exemplos.
func (v *Vetorizador) Ajustar(exemplos []Exemplo) {
	if v.Escala == nil {
		v.Escala = map[string]float64{}
	}
	for _, sinal := range v.Sinais {
		var valores []float64
		for _, ex := range exemplos {
			if e, ok := ex.Evidencias[sinal]; ok && e.Valor != nil {
				valores = append(valores, math.Abs(*e.Valor))
			}
		}
		escala := 1.0
		if len(valores) > 0 {
			sort.Float64s(valores)
			escala = valores[len(valores)/2]
		}
		if escala <= 0 {
			escala = 1.0
		}
		v.Escala[sinal] = escala
	}
}

func (v Vetorizador) Transformar(evidencias map[string]Evidencia) []float64 {
	x := make([]float64, v.Dimensao())
	for i, sinal := range v.Sinais {
		e, ok := evidencias[sinal]
		if !ok {
			continue
		}
		x[i*2] = 1.0
		if e.Valor != nil {
			escala := v.Escala[sinal]
			if escala == 0 {
				escala = 1
			}
			x[i*2+1] = *e.Valor / escala
		}
	}
	return x
}

// Evidencia é um sinal observado com o valor que o sustenta.
type Evidencia struct {
	// Literal é o que aparece na tela: a linha de log, o contador, o valor
	// medido. Nunca "indícios sugerem" (§10.5.1).
	Literal string `json:"literal"`
	// Nulo quando a medida é categórica. Nulo ≠ zero.
	Valor *float64 `json:"valor,omitempty"`
}

// Exemplo é uma linha de `training_example`.
type Exemplo struct {
	Status     string
	Causa      string
	Evidencias map[string]Evidencia
	Peso       float64
	Particao   string
	Origem     string
}

// Cabecote é o modelo de UM status: MLP sobre as causas dele.
//
// Um cabeçote por status, nunca um modelo universal: status diferente tem
// domínio de causas diferente, e um softmax único distribuiria massa sobre
// causas que não pertencem ao problema.
type Cabecote struct {
	Status string      `json:"status"`
	Causas []string    `json:"causas"`
	Vetor  Vetorizador `json:"vetorizador"`
	Oculta int         `json:"oculta"`
	W1     [][]float64 `json:"w1"`
	B1     []float64   `json:"b1"`
	W2     [][]float64 `json:"w2"`
	B2     []float64   `json:"b2"`
	// Temperatura de calibração. 1 = sem ajuste; >1 achata a distribuição, que
	// é o conserto típico de uma rede confiante demais.
	Temperatura float64 `json:"temperatura"`
}

func NovoCabecote(status string, causas []string, v Vetorizador, oculta int) *Cabecote {
	r := rand.New(rand.NewSource(semente))
	d, k := v.Dimensao(), len(causas)
	c := &Cabecote{
		Status: status, Causas: causas, Vetor: v, Oculta: oculta,
		Temperatura: 1.0,
		W1:          make([][]float64, d), B1: make([]float64, oculta),
		W2: make([][]float64, oculta), B2: make([]float64, k),
	}
	// He: mantém a variância estável através da ReLU.
	dpEntrada := math.Sqrt(2.0 / float64(d))
	for i := range c.W1 {
		c.W1[i] = make([]float64, oculta)
		for j := range c.W1[i] {
			c.W1[i][j] = r.NormFloat64() * dpEntrada
		}
	}
	dpOculta := math.Sqrt(2.0 / float64(oculta))
	for i := range c.W2 {
		c.W2[i] = make([]float64, k)
		for j := range c.W2[i] {
			c.W2[i][j] = r.NormFloat64() * dpOculta
		}
	}
	return c
}

func (c *Cabecote) frente(x []float64) (oculta, logits []float64) {
	oculta = make([]float64, c.Oculta)
	for j := 0; j < c.Oculta; j++ {
		soma := c.B1[j]
		for i, xi := range x {
			soma += xi * c.W1[i][j]
		}
		if soma < 0 {
			soma = 0 // ReLU
		}
		oculta[j] = soma
	}
	logits = make([]float64, len(c.Causas))
	for k := range logits {
		soma := c.B2[k]
		for j, h := range oculta {
			soma += h * c.W2[j][k]
		}
		logits[k] = soma
	}
	return oculta, logits
}

func softmax(z []float64, temperatura float64) []float64 {
	if temperatura <= 0 {
		temperatura = 1
	}
	maxZ := math.Inf(-1)
	for _, v := range z {
		if v/temperatura > maxZ {
			maxZ = v / temperatura
		}
	}
	saida := make([]float64, len(z))
	soma := 0.0
	for i, v := range z {
		saida[i] = math.Exp(v/temperatura - maxZ)
		soma += saida[i]
	}
	for i := range saida {
		saida[i] /= soma
	}
	return saida
}

// Probabilidades roda a inferência já calibrada.
func (c *Cabecote) Probabilidades(evidencias map[string]Evidencia) []float64 {
	_, z := c.frente(c.Vetor.Transformar(evidencias))
	return softmax(z, c.Temperatura)
}

// Treinar ajusta os pesos por cross-entropy com peso por exemplo e L2.
//
// O peso por exemplo é o que carrega a regra de §19.4: o caso em que a rede
// errou contra a RAT do técnico entra valendo mais, porque é exatamente onde
// ela precisa mudar.
//
// L2 não é enfeite: com dezenas de exemplos e dezenas de features a rede
// memoriza sem ele — e memorização com aparência de aprendizado é o modo de
// falha que este projeto inteiro tenta evitar.
func (c *Cabecote) Treinar(X [][]float64, y []int, pesos []float64, epocas int, taxa, l2 float64) []float64 {
	n, k := len(X), len(c.Causas)
	somaPesos := 0.0
	for _, p := range pesos {
		somaPesos += p
	}
	if somaPesos == 0 {
		somaPesos = 1
	}

	historico := make([]float64, 0, epocas)
	for e := 0; e < epocas; e++ {
		gW1 := zeros2(len(c.W1), c.Oculta)
		gB1 := make([]float64, c.Oculta)
		gW2 := zeros2(c.Oculta, k)
		gB2 := make([]float64, k)
		perda := 0.0

		for i := 0; i < n; i++ {
			oculta, z := c.frente(X[i])
			p := softmax(z, 1.0)
			w := pesos[i] / somaPesos
			perda += -w * math.Log(math.Max(p[y[i]], 1e-12))

			dz := make([]float64, k)
			for j := range dz {
				alvo := 0.0
				if j == y[i] {
					alvo = 1.0
				}
				dz[j] = (p[j] - alvo) * w
			}
			dh := make([]float64, c.Oculta)
			for j := 0; j < c.Oculta; j++ {
				for m := 0; m < k; m++ {
					gW2[j][m] += oculta[j] * dz[m]
					dh[j] += c.W2[j][m] * dz[m]
				}
				if oculta[j] <= 0 {
					dh[j] = 0 // derivada da ReLU
				}
			}
			for m := 0; m < k; m++ {
				gB2[m] += dz[m]
			}
			for a := range X[i] {
				if X[i][a] == 0 {
					continue // esparso: a maioria dos sinais está ausente
				}
				for j := 0; j < c.Oculta; j++ {
					gW1[a][j] += X[i][a] * dh[j]
				}
			}
			for j := 0; j < c.Oculta; j++ {
				gB1[j] += dh[j]
			}
		}

		for a := range c.W1 {
			for j := range c.W1[a] {
				c.W1[a][j] -= taxa * (gW1[a][j] + l2*c.W1[a][j])
			}
		}
		for j := range c.W2 {
			for m := range c.W2[j] {
				c.W2[j][m] -= taxa * (gW2[j][m] + l2*c.W2[j][m])
			}
		}
		for j := range c.B1 {
			c.B1[j] -= taxa * gB1[j]
		}
		for m := range c.B2 {
			c.B2[m] -= taxa * gB2[m]
		}
		historico = append(historico, perda)
	}
	return historico
}

// Calibrar ajusta a temperatura minimizando log-loss na validação.
//
// Busca em grade, não por gradiente: é UM parâmetro, e a grade é auditável —
// dá para olhar a curva inteira e ver que o mínimo não foi acidente.
func (c *Cabecote) Calibrar(X [][]float64, y []int) float64 {
	if len(y) == 0 {
		c.Temperatura = 1.0
		return 1.0
	}
	logits := make([][]float64, len(X))
	for i := range X {
		_, logits[i] = c.frente(X[i])
	}
	melhorT, melhorPerda := 1.0, math.Inf(1)
	for t := 0.5; t <= 5.0001; t += 0.05 {
		perda := 0.0
		for i := range logits {
			p := softmax(logits[i], t)
			perda += -math.Log(math.Max(p[y[i]], 1e-12))
		}
		perda /= float64(len(y))
		if perda < melhorPerda {
			melhorT, melhorPerda = t, perda
		}
	}
	c.Temperatura = melhorT
	return melhorT
}

// Metricas é o que o gate de calibração lê (§14.2).
type Metricas struct {
	N        int     `json:"n"`
	Acuracia float64 `json:"acuracia"`
	LogLoss  float64 `json:"log_loss"`
	ECE      float64 `json:"ece"`
	PorFaixa []Faixa `json:"por_faixa"`
}

// Faixa é uma linha de "quando dizemos 70–80%, acertamos 74% em 112 casos"
// (§10.5.3). Sem ela a probabilidade é oráculo; com ela é argumento.
type Faixa struct {
	De             float64 `json:"de"`
	Ate            float64 `json:"ate"`
	N              int     `json:"n"`
	ConfiancaMedia float64 `json:"confianca_media"`
	AcertoReal     float64 `json:"acerto_real"`
	DesvioPP       float64 `json:"desvio_pp"`
}

func (c *Cabecote) Avaliar(X [][]float64, y []int) Metricas {
	if len(y) == 0 {
		return Metricas{}
	}
	acertos, logloss := 0, 0.0
	confianca := make([]float64, len(y))
	certo := make([]bool, len(y))
	for i := range X {
		_, z := c.frente(X[i])
		p := softmax(z, c.Temperatura)
		melhor := 0
		for j := range p {
			if p[j] > p[melhor] {
				melhor = j
			}
		}
		confianca[i] = p[melhor]
		certo[i] = melhor == y[i]
		if certo[i] {
			acertos++
		}
		logloss += -math.Log(math.Max(p[y[i]], 1e-12))
	}
	m := Metricas{
		N:        len(y),
		Acuracia: float64(acertos) / float64(len(y)),
		LogLoss:  logloss / float64(len(y)),
	}
	m.PorFaixa, m.ECE = calibracao(confianca, certo)
	return m
}

// calibracao devolve as faixas e o ECE.
//
// ECE é o requisito de engenharia do projeto — não acurácia. Um modelo que
// acerta 85% e diz "99%" é pior que inútil, porque o técnico aprende a confiar
// num número que mente.
func calibracao(confianca []float64, certo []bool) ([]Faixa, float64) {
	const nf = 10
	var faixas []Faixa
	ece := 0.0
	total := float64(len(confianca))
	for b := 0; b < nf; b++ {
		lo, hi := float64(b)/nf, float64(b+1)/nf
		var somaConf, somaAcerto float64
		n := 0
		for i, c := range confianca {
			dentro := c > lo && c <= hi
			if b == 0 {
				dentro = c >= lo && c <= hi
			}
			if !dentro {
				continue
			}
			n++
			somaConf += c
			if certo[i] {
				somaAcerto++
			}
		}
		if n == 0 {
			continue
		}
		mediaConf, mediaAcerto := somaConf/float64(n), somaAcerto/float64(n)
		ece += (float64(n) / total) * math.Abs(mediaAcerto-mediaConf)
		faixas = append(faixas, Faixa{
			De: lo, Ate: hi, N: n,
			ConfiancaMedia: mediaConf, AcertoReal: mediaAcerto,
			DesvioPP: math.Abs(mediaAcerto-mediaConf) * 100,
		})
	}
	return faixas, ece
}

// FracaoEntropiaAbstencao: acima disso, o cabeçote abstém.
//
// Expresso como fração da entropia MÁXIMA do domínio, não valor absoluto: um
// status com 3 causas e outro com 8 têm tetos diferentes, e um limiar absoluto
// trataria os dois igual.
const FracaoEntropiaAbstencao = 0.85

func DeveAbsterPorEntropia(p []float64) bool {
	if len(p) <= 1 {
		return false
	}
	h := 0.0
	for _, v := range p {
		if v > 0 {
			h += -v * math.Log(v)
		}
	}
	return h/math.Log(float64(len(p))) > FracaoEntropiaAbstencao
}

// HashPesos identifica os pesos. É o que permite provar, depois, que um
// diagnóstico veio DAQUELE modelo e não de outro com o mesmo nome.
func (c *Cabecote) HashPesos() string {
	b, _ := json.Marshal(struct {
		W1 [][]float64 `json:"w1"`
		W2 [][]float64 `json:"w2"`
		B1 []float64   `json:"b1"`
		B2 []float64   `json:"b2"`
		T  float64     `json:"t"`
	}{c.W1, c.W2, c.B1, c.B2, c.Temperatura})
	return fmt.Sprintf("%x", sha256.Sum256(b))[:16]
}

func zeros2(a, b int) [][]float64 {
	m := make([][]float64, a)
	for i := range m {
		m[i] = make([]float64, b)
	}
	return m
}
