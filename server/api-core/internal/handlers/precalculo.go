package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"sort"
	"strconv"
	"strings"
)

// Camada de pré-cálculo (§10.4 da arquitetura).
//
// A ação única só é honesta se o que ela mostra já estiver pronto ANTES de
// alguém clicar. Nada é calculado na abertura da tela.
//
// A consequência prática é que o servidor mantém, por dispositivo, um retrato
// pronto: status provável, tipo de chamado sugerido, perfil de escada, gates que
// vão disparar, faixa de duração e nível de alerta. Quando qualquer origem muda,
// o servidor empurra a nova versão pelo canal. **O cliente nunca reconsulta.**
//
// O que este arquivo resolve é o problema difícil disso: saber QUANDO o retrato
// ficou velho. Sem invalidação explícita, ou se empurra tudo o tempo todo — que
// é polling ao contrário — ou se serve dado velho sem ninguém perceber.

// OrigensDoPreCalculo são as coisas cuja mudança torna o retrato obsoleto.
//
// Cada campo é uma versão, não o dado em si. Comparar versões é barato e
// funciona mesmo quando o dado é grande; comparar o dado exigiria carregá-lo
// justamente para descobrir que não precisava.
type OrigensDoPreCalculo struct {
	VersaoModelo     string
	VersaoPerfil     string
	VersaoParametros string
	// Fim da janela de telemetria considerada. Muda a cada janela nova.
	JanelaTelemetria string
	// Muda quando o inventário ou o SMART mudam — o que altera gates e perfil.
	VersaoInventario string
	VersaoCatalogo   string
}

// Impressao devolve a assinatura das origens. É ela que vai junto do retrato e
// que o cliente ecoa de volta quando reconecta.
func (o OrigensDoPreCalculo) Impressao() string {
	partes := []string{
		"modelo=" + o.VersaoModelo,
		"perfil=" + o.VersaoPerfil,
		"param=" + o.VersaoParametros,
		"janela=" + o.JanelaTelemetria,
		"inv=" + o.VersaoInventario,
		"catalogo=" + o.VersaoCatalogo,
	}
	sort.Strings(partes)
	soma := sha256.Sum256([]byte(strings.Join(partes, ";")))
	return hex.EncodeToString(soma[:8])
}

// PreCalculo é o retrato completo que trafega pelo canal (§10.4).
//
// Tudo aqui é resultado, nunca insumo: o cliente desenha o que recebe e não
// recalcula nada. "O cálculo é do servidor, o desenho é do cliente."
type PreCalculo struct {
	DeviceID string `json:"device_id"`

	StatusProvavel string          `json:"status_provavel"`
	CausasPassivas []CausaInferida `json:"causas_passivas"`
	TipoDeChamado  string          `json:"tipo_chamado_sugerido"`

	PerfilEscada     string         `json:"perfil_escada"`
	PerfilVersao     int            `json:"perfil_versao"`
	GatesPrevistos   []GatePrevisto `json:"gates_previstos"`
	DuracaoMin       int            `json:"duracao_min"`
	DuracaoMax       int            `json:"duracao_max"`
	DuracaoGrosseira bool           `json:"duracao_grosseira"`

	NivelAlerta string `json:"nivel_alerta"`

	// Origens e impressão viajam JUNTO com o dado. Um retrato que não diz de
	// onde veio não pode ser invalidado, só substituído às cegas.
	Origens   OrigensDoPreCalculo `json:"origens"`
	Impressao string              `json:"impressao"`
}

// GatePrevisto é um gate que VAI disparar, com o motivo — o técnico precisa
// ver isso no pré-voo, não descobrir durante a execução (§10.6-A).
type GatePrevisto struct {
	Codigo string `json:"codigo"`
	Motivo string `json:"motivo"`
}

// Selar preenche a impressão a partir das origens. Todo retrato passa por aqui
// antes de ir para o canal.
func (p PreCalculo) Selar() PreCalculo {
	p.Impressao = p.Origens.Impressao()
	return p
}

// PrecisaEmpurrar decide se o cliente deve receber uma versão nova.
//
// A comparação é por IMPRESSÃO, não campo a campo: se qualquer origem mudou, o
// retrato inteiro é substituído. Empurrar diferenças parciais criaria estados
// intermediários no cliente — meio retrato novo, meio velho — que é a classe de
// bug mais difícil de reproduzir que existe numa tela viva.
func PrecisaEmpurrar(novo PreCalculo, impressaoNoCliente string) bool {
	if impressaoNoCliente == "" {
		// Cliente sem retrato nenhum: a primeira entrega é sempre necessária.
		// É isto que substitui a busca ao montar a tela.
		return true
	}
	return novo.Selar().Impressao != impressaoNoCliente
}

// MaterializarChamado congela o pré-cálculo como ponto de partida de um
// chamado (§10.4).
//
// Abrir chamado NÃO dispara inferência: apenas materializa o `diagnosis`
// passivo que já existia. O que muda é o estado, não o cálculo — e por isso
// esta função copia em vez de recalcular.
func MaterializarChamado(p PreCalculo) PreCalculo {
	congelado := p.Selar()
	// O tipo sugerido vira o tipo do chamado, mas continua corrigível pelo
	// supervisor (§10.3). Congelar não é decidir por ele.
	return congelado
}

// VersaoDeJanela produz um rótulo estável para a janela de telemetria.
//
// Truncar para o início da janela é o que impede o retrato de ser considerado
// obsoleto a cada segundo: sem isso, a impressão mudaria continuamente e o
// servidor empurraria sem parar — polling ao contrário, com o servidor no papel
// de quem não para de perguntar.
func VersaoDeJanela(epochSegundos int64, janelaSegundos int64) string {
	if janelaSegundos <= 0 {
		return strconv.FormatInt(epochSegundos, 10)
	}
	return strconv.FormatInt(epochSegundos/janelaSegundos, 10)
}
