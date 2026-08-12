package handlers

import "time"

// Alertas ao cliente em dois níveis (§9 da arquitetura) e rótulo de recidiva
// (§13.5).
//
// O princípio que organiza este arquivo: com telemetria contínua e sem escada,
// as probabilidades são amplas. Isso não impede alertar; impede AFIRMAR. Daí os
// dois níveis, com barras de confiança diferentes.
//
// A barra do cliente é MAIS ALTA que a do técnico, e isso é contraintuitivo até
// se pensar em quem lê: o supervisor lê probabilidade e curva, e sabe descontar;
// o cliente lê uma frase. Frase exige mais certeza que gráfico.

// Níveis de alerta (§9).
const (
	AlertaNenhum = "nenhum"
	AlertaNivel1 = "1" // sintoma observado, causa NÃO nomeada
	AlertaNivel2 = "2" // causa nomeada, texto acionável
)

// EstadoDaCausa espelha §14.1: só causa promovida (ou com histórico interno
// suficiente) pode ser nomeada ao cliente.
type EstadoDaCausa struct {
	Codigo string
	Prob   float64
	// Promovida = a rede passou no gate de calibração para esta causa.
	Promovida bool
	// CasosInternos = fechamentos validados por reteste (§11.6).
	CasosInternos int
}

// LimiaresDeAlerta vem de `diag_param` (§18), nunca de constante no código.
type LimiaresDeAlerta struct {
	Nivel2Prob            float64 // 0,90
	Nivel2CasosMin        int     // 30
	SomeAbaixoDe          float64 // 0,50
	MaxSimultaneos        int     // 2
	AntiRepeticao         time.Duration
	SilencioAposDescartar time.Duration
}

// AlertaHistorico é o que já aconteceu com este (dispositivo, status).
type AlertaHistorico struct {
	UltimoEnviadoEm time.Time
	DescartadoEm    time.Time
	ChamadoAberto   bool
}

// NivelDoAlerta decide o nível de um único status. É determinística e sem
// acesso a banco: recebe o estado e os limiares, devolve a decisão.
func NivelDoAlerta(c EstadoDaCausa, lim LimiaresDeAlerta) string {
	// Abaixo do piso, o alerta desaparece — não fica preso na tela (§9).
	if c.Prob < lim.SomeAbaixoDe {
		return AlertaNenhum
	}
	// Nomear causa exige as DUAS condições. Probabilidade alta de uma causa que
	// nunca foi validada é confiança emprestada, não medida.
	if c.Prob >= lim.Nivel2Prob && (c.Promovida || c.CasosInternos >= lim.Nivel2CasosMin) {
		return AlertaNivel2
	}
	// Massa de probabilidade espalhada, ou causa sem histórico: descreve o
	// sintoma e pede verificação. Nunca nomeia causa — nomear causa com
	// probabilidade baixa é como o produto perde a confiança do cliente.
	return AlertaNivel1
}

// PodeEnviar aplica a anti-repetição (§9). Separado de NivelDoAlerta porque são
// perguntas diferentes: "que nível é este?" e "o cliente deveria ver isto
// agora?".
func PodeEnviar(h AlertaHistorico, agora time.Time, lim LimiaresDeAlerta) (bool, string) {
	// Chamado aberto para aquele status: o cliente já sabe, já pediu ajuda.
	// Repetir o aviso é ruído em cima de quem já agiu.
	if h.ChamadoAberto {
		return false, "chamado já aberto para este status"
	}
	if !h.DescartadoEm.IsZero() && agora.Sub(h.DescartadoEm) < lim.SilencioAposDescartar {
		return false, "cliente descartou este alerta recentemente"
	}
	if !h.UltimoEnviadoEm.IsZero() && agora.Sub(h.UltimoEnviadoEm) < lim.AntiRepeticao {
		return false, "dentro da janela de anti-repetição"
	}
	return true, ""
}

// AlertaCandidato é um alerta já decidido, esperando pela seleção final.
type AlertaCandidato struct {
	StatusCodigo string
	Nivel        string
	Prob         float64
}

// SelecionarAlertas aplica o teto de simultâneos (§9), mantendo os de maior
// probabilidade.
//
// Três avisos ao mesmo tempo é ruído, e ruído treina o cliente a ignorar o
// produto — que é o oposto do que a camada de alerta existe para fazer.
func SelecionarAlertas(candidatos []AlertaCandidato, lim LimiaresDeAlerta) []AlertaCandidato {
	uteis := make([]AlertaCandidato, 0, len(candidatos))
	for _, c := range candidatos {
		if c.Nivel != AlertaNenhum {
			uteis = append(uteis, c)
		}
	}
	// Ordena por probabilidade decrescente, com desempate estável pelo código
	// para que a mesma entrada produza sempre a mesma saída.
	for i := 1; i < len(uteis); i++ {
		for j := i; j > 0; j-- {
			trocar := uteis[j].Prob > uteis[j-1].Prob ||
				(uteis[j].Prob == uteis[j-1].Prob && uteis[j].StatusCodigo < uteis[j-1].StatusCodigo)
			if !trocar {
				break
			}
			uteis[j], uteis[j-1] = uteis[j-1], uteis[j]
		}
	}
	if lim.MaxSimultaneos > 0 && len(uteis) > lim.MaxSimultaneos {
		uteis = uteis[:lim.MaxSimultaneos]
	}
	return uteis
}

// --- Recidiva (§13.5) ------------------------------------------------------

// Ocorrencia é uma manifestação do status no dispositivo, depois do fechamento.
type Ocorrencia struct {
	Em time.Time
}

// AvaliarRecidiva devolve os rótulos de 7 e 30 dias.
//
// > Se o sintoma não voltou em 7/30 dias, foi solução. Se voltou, foi paliativo.
//
// Nenhum fórum consegue produzir este rótulo — é a vantagem estrutural do
// produto, e é o dado de treino que vale (§13.5).
//
// O terceiro retorno diz se a janela ainda está ABERTA. Isso importa: `false`
// com janela aberta significa "ainda não voltou", não "não vai voltar", e
// gravar isso como se fosse conclusão contaminaria o treino com otimismo.
func AvaliarRecidiva(
	fechadoEm time.Time,
	ocorrencias []Ocorrencia,
	agora time.Time,
	janelaCurta, janelaLonga time.Duration,
) (recidiva7 bool, recidiva30 bool, janelaLongaAberta bool) {
	for _, o := range ocorrencias {
		if o.Em.Before(fechadoEm) {
			// Sintoma anterior ao reparo não é recidiva; é o problema original.
			continue
		}
		desde := o.Em.Sub(fechadoEm)
		if desde <= janelaCurta {
			recidiva7 = true
		}
		if desde <= janelaLonga {
			recidiva30 = true
		}
	}
	janelaLongaAberta = agora.Sub(fechadoEm) < janelaLonga
	return recidiva7, recidiva30, janelaLongaAberta
}
