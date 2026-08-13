package diagnostico

import (
	"fmt"
	"math"
	"sort"
)

// A camada de regra (§3, camada 1).
//
// É de propósito que ela seja legível de cabo a rabo: enquanto for ela quem
// responde — e é, até alguma causa passar no gate de calibração — precisa ser
// auditável por quem atende o chamado.
//
// O que este arquivo NUNCA faz:
//
//   - escrever prosa: devolve chave de template e valores (§12.4);
//   - decidir gate de segurança do stress: isso é regra pura no fluxo da
//     escada, nunca decisão de motor (§17);
//   - falar com o cliente: quem tem canal é o api-core.

const (
	// Teto de hipóteses na tela (§1). Não é preferência de layout: lista longa
	// é o jeito de não decidir nada.
	MaxCausas = 3
	// Teto da probabilidade sem intervenção (§10.5.1). Sem escada não existe
	// limiar, então não existe veredito — por mais que os sinais apontem.
	TetoSemEscada = 0.85
	// Abaixo disto, nada domina, e a resposta honesta é abstenção com direção.
	LimiarDeDominancia = 0.40
)

// Dossie é a entrada da inferência.
type Dossie struct {
	DeviceID     string
	StatusCodigo string
	Evidencias   map[string]Evidencia
	// True quando veio de stress_run: existe curva, existe limiar.
	TemCurva     bool
	DegrauQuebra *int
}

// Causa é uma hipótese com o que a sustenta.
type Causa struct {
	Codigo     string
	Prob       float64
	FaixaMin   float64
	FaixaMax   float64
	Template   string
	Evidencias []string
}

// Resposta é o schema que as DUAS camadas compartilham. A tela não sabe qual
// respondeu — e é por isso que promover uma causa não exige mexer no front.
type Resposta struct {
	Status         string
	Causas         []Causa
	Abstain        bool
	ProximosTestes []string
	Motor          string
	VersaoModelo   string
	// Sombra: o que a rede achou quando ela ainda não decide (§14.1). Fica
	// registrado para o laço RAT comparar depois, e não aparece na tela.
	Sombra *Sombra
}

// Sombra é a suposição da rede rodando no escuro.
type Sombra struct {
	VersaoModelo string             `json:"versao_modelo"`
	Estado       string             `json:"estado"`
	Abstain      bool               `json:"abstain"`
	Causas       map[string]float64 `json:"causas"`
}

// InferirPorRegra: prior externo + evidência observada.
//
// `pesosSinalCausa[sinal+"|"+causa]` vem de `log_signature.peso` e da
// frequência do corpus. `priors` já chega com o decaimento de §13.4 aplicado —
// o peso do fórum cai à medida que o dado interno cresce, e isso é explícito na
// configuração, não implícito aqui.
func InferirPorRegra(
	d Dossie,
	causasDoStatus []string,
	priors map[string]float64,
	pesosSinalCausa map[string]float64,
	nCasosPorCausa map[string]int,
) Resposta {
	if len(causasDoStatus) == 0 {
		// Status sem causas cadastradas: não há domínio sobre o qual
		// distribuir. Abster é a única resposta honesta.
		return Resposta{
			Status: d.StatusCodigo, Abstain: true, Motor: "regra",
			ProximosTestes: []string{"catalogo_de_status_ainda_nao_revisado"},
		}
	}

	pesos := map[string]float64{}
	sustentando := map[string][]string{}
	for _, c := range causasDoStatus {
		p, ok := priors[c]
		if !ok {
			p = 0.01
		}
		pesos[c] = p
	}

	for sinal, ev := range d.Evidencias {
		for _, causa := range causasDoStatus {
			peso, ok := pesosSinalCausa[sinal+"|"+causa]
			if !ok || peso == 0 {
				continue
			}
			pesos[causa] *= 1.0 + peso
			sustentando[causa] = append(sustentando[causa], ev.Literal)
		}
	}

	dist := normalizar(pesos)
	if deveAbster(dist) {
		return Resposta{
			Status: d.StatusCodigo, Abstain: true, Motor: "regra",
			ProximosTestes: proximosTestesUteis(d),
		}
	}

	return Resposta{
		Status: d.StatusCodigo,
		Causas: montarCausas(dist, d, sustentando, nCasosPorCausa),
		Motor:  "regra",
	}
}

// InferirPorRede: camada 2, mesma saída.
func InferirPorRede(c *Cabecote, d Dossie, estado string) Resposta {
	p := c.Probabilidades(d.Evidencias)
	dist := map[string]float64{}
	for i, causa := range c.Causas {
		dist[causa] = p[i]
	}

	abstain := DeveAbsterPorEntropia(p)
	versao := fmt.Sprintf("%s.mlp.%s", c.Status, c.HashPesos())

	r := Resposta{
		Status: d.StatusCodigo, Abstain: abstain,
		Motor: "modelo", VersaoModelo: versao,
	}
	if abstain {
		r.ProximosTestes = proximosTestesUteis(d)
	} else {
		r.Causas = montarCausas(dist, d, nil, nil)
	}
	r.Sombra = &Sombra{
		VersaoModelo: versao, Estado: estado, Abstain: abstain, Causas: dist,
	}
	return r
}

func montarCausas(
	dist map[string]float64,
	d Dossie,
	sustentando map[string][]string,
	nCasos map[string]int,
) []Causa {
	tipo := make([]Causa, 0, len(dist))
	for codigo, prob := range dist {
		tipo = append(tipo, Causa{Codigo: codigo, Prob: prob})
	}
	sort.Slice(tipo, func(i, j int) bool {
		if tipo[i].Prob != tipo[j].Prob {
			return tipo[i].Prob > tipo[j].Prob
		}
		return tipo[i].Codigo < tipo[j].Codigo
	})
	if len(tipo) > MaxCausas {
		tipo = tipo[:MaxCausas]
	}

	for i := range tipo {
		p := aplicarTeto(tipo[i].Prob, d.TemCurva)
		min, max := faixaDeConfianca(p, nCasos[tipo[i].Codigo])
		tipo[i].Prob = arredondar(p)
		tipo[i].FaixaMin, tipo[i].FaixaMax = arredondar(min), arredondar(max)
		tipo[i].Template = fmt.Sprintf("%s.%s.v1", d.StatusCodigo, tipo[i].Codigo)
		if sustentando != nil {
			tipo[i].Evidencias = sustentando[tipo[i].Codigo]
		}
	}
	return tipo
}

func normalizar(pesos map[string]float64) map[string]float64 {
	total := 0.0
	for _, p := range pesos {
		if p > 0 {
			total += p
		}
	}
	if total <= 0 {
		return nil
	}
	saida := make(map[string]float64, len(pesos))
	for c, p := range pesos {
		if p < 0 {
			p = 0
		}
		saida[c] = p / total
	}
	return saida
}

// aplicarTeto: sem intervenção, a probabilidade tem teto (§10.5.1). Não é
// pessimismo — é que nada foi forçado ainda.
func aplicarTeto(prob float64, temCurva bool) float64 {
	if temCurva {
		return prob
	}
	return math.Min(prob, TetoSemEscada)
}

// faixaDeConfianca: mais larga quanto menos histórico. Com pouco caso a faixa é
// quase toda a régua — e isso é honesto, não inútil.
func faixaDeConfianca(prob float64, nCasos int) (float64, float64) {
	margem := 0.35
	if nCasos > 0 {
		margem = math.Min(0.35, 1.0/math.Sqrt(float64(nCasos)))
	}
	return math.Max(0, prob-margem), math.Min(1, prob+margem)
}

// deveAbster: abstenção é resposta de primeira classe (§10.7), não erro.
func deveAbster(dist map[string]float64) bool {
	if len(dist) == 0 {
		return true
	}
	maior := 0.0
	for _, p := range dist {
		if p > maior {
			maior = p
		}
	}
	return maior < LimiarDeDominancia
}

// proximosTestesUteis: o teste que mais SEPARA as hipóteses, não o mais rápido
// nem o mais completo (§10.5.1).
//
// Sem curva, o que separa é rodar a escada. Com curva e ainda sem dominância, o
// problema é outro: a escada já rodou e não decidiu, então o próximo passo é
// humano.
func proximosTestesUteis(d Dossie) []string {
	if !d.TemCurva {
		return []string{"escada_completa"}
	}
	return []string{"inspecao_presencial"}
}

func arredondar(v float64) float64 { return math.Round(v*10000) / 10000 }
