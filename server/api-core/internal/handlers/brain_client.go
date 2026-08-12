package handlers

import (
	"context"
	"strconv"
	"sync"

	"tgdesk/api-core/internal/diagnostico"
)

// O motor de diagnóstico, chamado em processo (§3, adaptado).
//
// A arquitetura desenhou o `tgdesk-brain` como serviço separado no compose, e
// este arquivo era o cliente HTTP dele. O projeto tem uma regra que vale mais —
// UM CONTAINER POR PROJETO — então a rede passou a morar em
// `internal/diagnostico`, e o que sobrou aqui é a mesma fronteira sem o salto
// de rede.
//
// A fronteira dura de §3 continua valendo, e fica mais forte: o motor não tem
// rota própria, não abre canal, não conhece RBAC nem organização. Ele recebe
// dossiê e devolve distribuição. Quem tem WebSocket, escopo e gate continua
// sendo o api-core — só que agora não existe um segundo processo para ficar
// fora do ar.
//
// O contrato (`PedidoDeInferencia` / `RespostaDeInferencia`) não mudou de
// propósito: quem chama não precisou saber da mudança, e o dia em que o modelo
// crescer a ponto de exigir runtime próprio, o caminho de volta é trocar esta
// implementação de novo, sem tocar em chamador nenhum.

// PedidoDeInferencia é a entrada do motor.
type PedidoDeInferencia struct {
	DeviceID     string              `json:"device_id"`
	StatusCodigo string              `json:"status_codigo"`
	Evidencias   []EvidenciaDoDossie `json:"evidencias"`
	TemCurva     bool                `json:"tem_curva"`
	DegrauQuebra *int                `json:"degrau_quebra,omitempty"`

	CausasCandidatas []string           `json:"causas_candidatas"`
	Priors           map[string]float64 `json:"priors"`
	// Chave achatada "sinal|causa" porque JSON não tem chave composta.
	PesosSinalCausa map[string]float64 `json:"pesos_sinal_causa"`
	NCasosPorCausa  map[string]int     `json:"n_casos_por_causa"`
}

type EvidenciaDoDossie struct {
	Sinal   string   `json:"sinal"`
	Literal string   `json:"literal"`
	Valor   *float64 `json:"valor,omitempty"`
}

// RespostaDeInferencia é o schema que as duas camadas — regra e rede —
// compartilham. A tela não sabe qual respondeu (§3).
type RespostaDeInferencia struct {
	Status         string          `json:"status"`
	Abstain        bool            `json:"abstain"`
	Motor          string          `json:"motor"`
	VersaoModelo   *string         `json:"versao_modelo"`
	ProximosTestes []string        `json:"proximos_testes"`
	Causas         []CausaInferida `json:"causas"`
	// A suposição da rede quando ela ainda roda no escuro (§14.1). Não vai para
	// a tela; vai para `rat_comparacao`, que é onde ela é medida contra a
	// realidade.
	Sombra *diagnostico.Sombra `json:"sombra,omitempty"`
}

type CausaInferida struct {
	Codigo     string         `json:"codigo"`
	Prob       float64        `json:"prob"`
	Faixa      []float64      `json:"faixa"`
	Template   string         `json:"template"`
	Slots      map[string]any `json:"slots"`
	Evidencias []string       `json:"evidencias"`
}

// motorDeDiagnostico guarda os cabeçotes carregados do banco.
//
// Os pesos moram em `model_version.pesos` (0079), não em volume: sem container
// separado não há volume de modelo, e inventar um diretório no host criaria
// estado fora do banco — mais uma coisa para versionar, sincronizar e perder
// num restore.
type motorDeDiagnostico struct {
	mu        sync.RWMutex
	cabecotes map[string]*diagnostico.Cabecote
	estados   map[string]string
}

var motor = &motorDeDiagnostico{
	cabecotes: map[string]*diagnostico.Cabecote{},
	estados:   map[string]string{},
}

// RecarregarModelos relê os cabeçotes do banco.
//
// Chamado na subida e depois de cada treino. Falha aqui não é fatal: sem
// cabeçote, a regra responde sozinha, que é o comportamento correto de §14.4 —
// nenhuma faixa é estado degradado.
func (s *Server) RecarregarModelos(ctx context.Context) error {
	cabecotes, estados, err := diagnostico.CarregarCabecotes(ctx, s.Pool)
	if err != nil {
		return err
	}
	motor.mu.Lock()
	motor.cabecotes, motor.estados = cabecotes, estados
	motor.mu.Unlock()
	return nil
}

// Inferir roda as duas camadas.
//
// A rede roda SEMPRE que existe cabeçote para o status — inclusive quando a
// regra já respondeu. É isso que "sombra" significa (§14.1): ela é medida
// contra a realidade sem custo de erro. Só substitui a regra quando o gate de
// calibração promoveu aquele status, o que exige caso interno — simulação
// treina, realidade promove (§19.3).
func (s *Server) Inferir(ctx context.Context, p PedidoDeInferencia) RespostaDeInferencia {
	evidencias := make(map[string]diagnostico.Evidencia, len(p.Evidencias))
	for _, e := range p.Evidencias {
		evidencias[e.Sinal] = diagnostico.Evidencia{Literal: e.Literal, Valor: e.Valor}
	}
	d := diagnostico.Dossie{
		DeviceID: p.DeviceID, StatusCodigo: p.StatusCodigo,
		Evidencias: evidencias, TemCurva: p.TemCurva, DegrauQuebra: p.DegrauQuebra,
	}

	r := diagnostico.InferirPorRegra(d, p.CausasCandidatas, p.Priors,
		p.PesosSinalCausa, p.NCasosPorCausa)

	motor.mu.RLock()
	cab := motor.cabecotes[p.StatusCodigo]
	estado := motor.estados[p.StatusCodigo]
	motor.mu.RUnlock()

	var sombra *diagnostico.Sombra
	if cab != nil {
		rede := diagnostico.InferirPorRede(cab, d, estado)
		sombra = rede.Sombra
		if estado == "promovido" {
			r = rede
		}
	}

	return traduzir(r, sombra)
}

func traduzir(r diagnostico.Resposta, sombra *diagnostico.Sombra) RespostaDeInferencia {
	out := RespostaDeInferencia{
		Status: r.Status, Abstain: r.Abstain, Motor: r.Motor,
		ProximosTestes: r.ProximosTestes, Sombra: sombra,
	}
	if r.VersaoModelo != "" {
		v := r.VersaoModelo
		out.VersaoModelo = &v
	}
	for _, c := range r.Causas {
		out.Causas = append(out.Causas, CausaInferida{
			Codigo: c.Codigo, Prob: c.Prob,
			Faixa:      []float64{c.FaixaMin, c.FaixaMax},
			Template:   c.Template,
			Slots:      map[string]any{"probabilidade": porcento(c.Prob)},
			Evidencias: c.Evidencias,
		})
	}

	// Cintos de segurança, mantidos da versão HTTP porque continuam valendo:
	// a tela nunca recebe mais de três causas (§1), e abstenção sem direção é
	// abstenção inútil (§10.5.1).
	if len(out.Causas) > 3 {
		out.Causas = out.Causas[:3]
	}
	if out.Abstain && len(out.ProximosTestes) == 0 {
		out.ProximosTestes = []string{"escada_completa"}
	}
	return out
}

func porcento(p float64) string {
	return strconv.Itoa(int(p*100+0.5)) + "%"
}

// MontarPedido achata a chave composta (sinal, causa) para o formato do
// contrato e garante que nenhum mapa chegue nulo ao motor.
//
// A chave composta existe porque o peso é de um PAR: o mesmo sinal empurra
// causas diferentes com forças diferentes — SMART realocado vale muito para
// disco e quase nada para driver. Achatar aqui, e não no motor, mantém o
// formato de transporte estável mesmo que o motor mude de implementação.
//
// Mapa nulo vira vazio de propósito: catálogo vazio é o estado real enquanto
// um status não tiver causas cadastradas, e o pedido tem que sair mesmo assim.
// Quem responde "não sei" é o motor, com abstenção — não um panic aqui.
func MontarPedido(
	deviceID, status string,
	causasCandidatas []string,
	priors map[string]float64,
	pesos map[string]map[string]float64,
	nCasos map[string]int,
	evidencias []EvidenciaDoDossie,
	temCurva bool,
) PedidoDeInferencia {
	achatado := map[string]float64{}
	for sinal, porCausa := range pesos {
		for causa, peso := range porCausa {
			achatado[sinal+"|"+causa] = peso
		}
	}
	if priors == nil {
		priors = map[string]float64{}
	}
	if nCasos == nil {
		nCasos = map[string]int{}
	}
	return PedidoDeInferencia{
		DeviceID: deviceID, StatusCodigo: status,
		Evidencias: evidencias, TemCurva: temCurva,
		CausasCandidatas: causasCandidatas,
		Priors:           priors,
		PesosSinalCausa:  achatado,
		NCasosPorCausa:   nCasos,
	}
}
