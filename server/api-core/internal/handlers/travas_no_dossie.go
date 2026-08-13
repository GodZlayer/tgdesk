package handlers

import (
	"context"
	"fmt"
	"time"
)

// As travas confirmadas entram no dossiê (§6, §7.3).
//
// Este arquivo existe porque faltava o elo mais óbvio da cadeia: o detector de
// travas por relógio externo estava construído, gravando em `stall_event` — e o
// diagnóstico nunca olhava para ele. A máquina congelava, o servidor media, e o
// dossiê continuava falando de pico de CPU.
//
// A regra que evita repetir o erro que produziu 2.275 eventos falsos:
//
//	SÓ ENTRA `origem = 'trava'`.
//
// `indeterminado` significa que o agente NÃO confirmou salto de relógio — ou
// seja, provavelmente foi queda de rede. Contar isso como travamento é como
// dizer que o computador do cliente congela toda vez que o Wi-Fi oscila. E
// `rede` é o oposto: é a confirmação de que NÃO foi trava.

// PerfilDeTravas é o que o histórico de travas diz sobre uma máquina.
type PerfilDeTravas struct {
	// Confirmadas pelo agente (relógio saltou). Só estas contam.
	Confirmadas int
	// Buracos sem confirmação. Não viram diagnóstico, mas aparecem no dossiê
	// como qualidade do canal — 700 desconexões por dia é um problema, ainda
	// que não seja travamento.
	Indeterminadas int

	MaisLongaMs int
	MedianaMs   int
	// Congelamentos curtos, de 1 a 5 s: o "trava um segundo e volta" que o
	// usuário relata e que nenhuma média captura, porque a média some no meio
	// de um evento de 20 minutos.
	Curtas int
	Status string
	// Evidência literal para a tela (§10.5.1).
	Evidencia string
}

// Janela de observação. Uma semana pega o padrão sem deixar um dia ruim
// definir o perfil da máquina.
const janelaDeTravas = 7 * 24 * time.Hour

// Limiar de "curta". Acima de 5 s deixa de ser engasgo e passa a ser trava
// que o usuário percebe como travamento pleno.
const travaCurtaMaxMs = 5000

func (s *Server) perfilDeTravas(ctx context.Context, deviceID string) PerfilDeTravas {
	var p PerfilDeTravas
	err := s.Pool.QueryRow(ctx, `
		SELECT
		  count(*) FILTER (WHERE origem = 'trava'),
		  count(*) FILTER (WHERE origem = 'indeterminado'),
		  coalesce(max(duracao_conciliada_ms) FILTER (WHERE origem = 'trava'), 0),
		  coalesce(percentile_disc(0.5) WITHIN GROUP (
		      ORDER BY duracao_conciliada_ms) FILTER (WHERE origem = 'trava'), 0),
		  count(*) FILTER (WHERE origem = 'trava'
		      AND duracao_conciliada_ms BETWEEN 1 AND $2)
		FROM stall_event
		WHERE device_id = $1 AND inicio > now() - $3::interval`,
		deviceID, travaCurtaMaxMs, janelaDeTravas.String()).
		Scan(&p.Confirmadas, &p.Indeterminadas, &p.MaisLongaMs, &p.MedianaMs, &p.Curtas)
	if err != nil {
		return p
	}

	if p.Confirmadas == 0 {
		return p
	}

	// A distinção que o usuário faz e que o dossiê tem que fazer junto:
	// congelamento CURTO e repetido é um fenômeno; trava longa é outro.
	//
	// Curta e repetida costuma ser disputa por um recurso que volta sozinho —
	// driver segurando o pipeline, I/O momentâneo, throttle. Longa costuma ser
	// esgotamento ou peça falhando. A conduta muda, então o status muda.
	if p.Curtas >= 3 && p.Curtas*2 >= p.Confirmadas {
		p.Status = "congelamento_breve_repetido"
		p.Evidencia = fmt.Sprintf(
			"%d congelamentos confirmados em 7 dias, %d deles de até 5 s (mediana %.1f s)",
			p.Confirmadas, p.Curtas, float64(p.MedianaMs)/1000)
		return p
	}

	p.Status = "trava_sob_carga"
	p.Evidencia = fmt.Sprintf(
		"%d congelamentos confirmados em 7 dias; o mais longo de %.0f s",
		p.Confirmadas, float64(p.MaisLongaMs)/1000)
	return p
}
