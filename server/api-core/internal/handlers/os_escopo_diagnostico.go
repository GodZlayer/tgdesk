package handlers

import "sort"

// Derivação do escopo de OS a partir do diagnóstico (§11 da arquitetura).
//
// Não confundir com `os_builder.go`: aquele é o lado COMERCIAL da ordem de
// serviço (catálogo de peças, preço, orçamento). Este é o lado DIAGNÓSTICO —
// o que precisa ir junto para que o técnico consiga executar o reparo de uma
// vez só. Os dois se encontram na OS, mas não compartilham regra.
//
// A regra central: o escopo deriva do TOP-3, não da causa vencedora. O técnico
// de campo vai uma vez. Se a hipótese 2 tem 25%, voltar depois custa mais caro
// que ter levado a peça junto.

// Níveis de item (§11.2), do mais forte ao mais fraco.
const (
	NivelEssencial    = "essencial"
	NivelNecessaria   = "necessaria"
	NivelFacilitadora = "facilitadora"
	NivelDispensavel  = "dispensavel"
)

// forcaDoNivel permite comparar dois níveis. Existe porque a união sobre as
// hipóteses precisa saber qual vence: um item facilitador para a causa 1 e
// essencial para a causa 2 sobe para essencial (§11.2).
var forcaDoNivel = map[string]int{
	NivelDispensavel:  0,
	NivelFacilitadora: 1,
	NivelNecessaria:   2,
	NivelEssencial:    3,
}

// CausaProvavel é uma hipótese do top-3, com a probabilidade que a sustenta.
type CausaProvavel struct {
	Codigo string
	Prob   float64
}

// Requisito é uma linha de `cause_requirement` já cruzada com `tool_catalog`.
type Requisito struct {
	CausaCodigo     string
	Acao            string
	ToolCodigo      string
	Nivel           string
	Quantidade      int
	Condicao        string
	Portatil        bool
	CustoRelativo   int
	RequerAprovacao bool
}

// ItemDeEscopo é o que sai para a tela e para `os_scope.itens`.
type ItemDeEscopo struct {
	ToolCodigo string `json:"tool_codigo"`
	Nivel      string `json:"nivel"`
	Quantidade int    `json:"quantidade"`
	// Por que este item está aqui: as causas que o exigiram, com a
	// probabilidade de cada uma. Item sem justificativa visível é item que o
	// técnico vai ignorar.
	PorCausa []string `json:"por_causa"`
	Pendente bool     `json:"pendente,omitempty"`
	// SobDemanda: plausível, mas caro/volumoso demais para ir por 20% de
	// chance. O técnico é avisado de que pode haver segunda visita.
	SobDemanda bool `json:"sob_demanda,omitempty"`
}

// custoDeFaltar traduz o nível em quanto dói não ter o item em campo (§11.1).
func custoDeFaltar(nivel string) float64 {
	switch nivel {
	case NivelEssencial:
		return 5
	case NivelNecessaria:
		return 3
	case NivelFacilitadora:
		return 1
	}
	return 0
}

// custoDeLevar soma o peso logístico ao custo do item, numa escala que começa
// em ZERO — e essa é uma correção deliberada sobre §11.1.
//
// O documento descreve `custo_relativo` de 1 a 5 e, no mesmo parágrafo, dá o
// exemplo "item barato e leve com 20% de chance de ser necessário entra". Os
// dois não se sustentam juntos: com o mínimo valendo 1, um item trivial exigido
// por hipótese de 20% dá 0,2 × 3 = 0,6 e fica de fora. A escala 1..5 do
// catálogo é a de CADASTRO (não existe item de custo zero para quem digita); a
// da conta é a de INCÔMODO, e o incômodo de levar uma chave de fenda é zero.
//
// Com o deslocamento, os dois exemplos do documento passam a valer: o item
// trivial entra por 20%, e o disco de 2 TB (custo 5, não portátil) só entra
// perto de 100% — ou por ser essencial.
func custoDeLevar(r Requisito) float64 {
	c := float64(r.CustoRelativo) - 1
	if c < 0 {
		c = 0
	}
	if !r.Portatil {
		c++
	}
	return c
}

// DerivarEscopo aplica §11.1 e §11.2 sobre as hipóteses plausíveis.
//
// `condicoesAtivas` são as condições do dispositivo já conhecidas pelo dossiê
// — `so_se_volume_criptografado`, `so_se_notebook`. Requisito com condição que
// não está ativa simplesmente não se aplica; requisito com condição ATIVA entra
// com o nível que tiver. É assim que a chave de recuperação vira item essencial
// ANTES de a máquina ser aberta, e não depois.
func DerivarEscopo(
	causas []CausaProvavel,
	requisitos []Requisito,
	condicoesAtivas map[string]bool,
) []ItemDeEscopo {
	prob := map[string]float64{}
	for _, c := range causas {
		prob[c.Codigo] = c.Prob
	}

	acumulado := map[string]*ItemDeEscopo{}
	// levaAlgum lembra se QUALQUER requisito daquele item passou no teste de
	// levar. Um item pode ser exigido por duas causas, e basta uma delas
	// justificar a viagem.
	levaAlgum := map[string]bool{}

	for _, r := range requisitos {
		p, plausivel := prob[r.CausaCodigo]
		if !plausivel {
			// Causa fora do top-3 não gera escopo. Levar item por hipótese que
			// o modelo já descartou é encher a mala de medo, não de método.
			continue
		}
		if r.Condicao != "" && !condicoesAtivas[r.Condicao] {
			continue
		}

		item, existe := acumulado[r.ToolCodigo]
		if !existe {
			item = &ItemDeEscopo{
				ToolCodigo: r.ToolCodigo,
				Nivel:      r.Nivel,
				Quantidade: r.Quantidade,
			}
			acumulado[r.ToolCodigo] = item
		}
		// União: vence o nível mais forte entre as hipóteses plausíveis.
		if forcaDoNivel[r.Nivel] > forcaDoNivel[item.Nivel] {
			item.Nivel = r.Nivel
		}
		if r.Quantidade > item.Quantidade {
			item.Quantidade = r.Quantidade
		}
		item.PorCausa = append(item.PorCausa, r.CausaCodigo)
		// Item que exige aprovação nunca entra automático, qualquer que seja a
		// probabilidade (§11.1).
		if r.RequerAprovacao {
			item.Pendente = true
		}

		if p*custoDeFaltar(r.Nivel) >= custoDeLevar(r) {
			levaAlgum[r.ToolCodigo] = true
		}
	}

	saida := make([]ItemDeEscopo, 0, len(acumulado))
	for codigo, item := range acumulado {
		// Essencial vai SEMPRE. Se qualquer hipótese plausível exigir o item
		// para começar o trabalho, a conta de custo não se aplica — sem ele a
		// OS não é liberada (§11.2).
		if item.Nivel != NivelEssencial && !levaAlgum[codigo] {
			item.SobDemanda = true
		}
		saida = append(saida, *item)
	}

	// Ordem estável e útil na tela: mais forte primeiro, depois alfabética.
	sort.Slice(saida, func(a, b int) bool {
		if forcaDoNivel[saida[a].Nivel] != forcaDoNivel[saida[b].Nivel] {
			return forcaDoNivel[saida[a].Nivel] > forcaDoNivel[saida[b].Nivel]
		}
		return saida[a].ToolCodigo < saida[b].ToolCodigo
	})
	return saida
}

// EscopoBloqueado diz se a OS pode ser liberada. Item essencial pendente de
// aprovação bloqueia: liberar a OS sabendo que falta o que a destrava seria
// mandar o técnico para uma viagem perdida.
func EscopoBloqueado(itens []ItemDeEscopo) (bool, []string) {
	var motivos []string
	for _, i := range itens {
		if i.Nivel == NivelEssencial && (i.Pendente || i.SobDemanda) {
			motivos = append(motivos, i.ToolCodigo)
		}
	}
	return len(motivos) > 0, motivos
}

// DispensaEscada aplica §11.5. É regra determinística de propósito: limiar de
// probabilidade mais classe de risco da ação, nunca decisão do modelo sozinho.
func DispensaEscada(causas []CausaProvavel, riscoDaAcao string, limiar float64) (bool, string) {
	if len(causas) == 0 {
		return false, ""
	}
	dominante := causas[0]
	for _, c := range causas {
		if c.Prob > dominante.Prob {
			dominante = c
		}
	}
	if dominante.Prob < limiar {
		return false, ""
	}
	if riscoDaAcao != "baixo" {
		return false, ""
	}
	return true, "causa dominante acima do limiar com ação de baixo risco: " +
		"forçar uma máquina que já se explicou é desgaste sem ganho de informação"
}
