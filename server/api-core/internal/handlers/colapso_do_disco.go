package handlers

import (
	"context"
	"fmt"
)

// Colapso sob carga: medir o disco em vez de julgá-lo por tabela.
//
// A ocupação máxima tolerável não é propriedade da marca, nem do modelo, nem
// da classe. Duas unidades idênticas com históricos diferentes — quanto já foi
// escrito, versão de firmware, padrão de uso — toleram ocupações diferentes.
// Qualquer limite afirmado de fora é palpite com aparência de norma.
//
// O parque desmonta o limite único de forma direta: uma máquina a 98,3% de
// ocupação responde MELHOR sob carga do que ociosa, enquanto outra a 93,7%
// fica 116 vezes mais lenta. Pela regra de porcentagem, a primeira estaria
// pior. Ela é a saudável.
//
// O que separa as duas não é quanto está cheio, é o que acontece quando o
// disco é exigido. Isso se mede, e a medida não precisa saber de que peça se
// trata:
//
//	fator = latência mediana sob carga ÷ latência mediana ocioso
//
// A ocupação continua importando — mas como HIPÓTESE do porquê, não como o
// diagnóstico. Primeiro se constata o colapso; depois se procura a explicação.

// ColapsoDoDisco é o comportamento medido de um disco sob carga.
type ColapsoDoDisco struct {
	Amostras      int     `json:"amostras"`
	OciosoMs      float64 `json:"ocioso_ms"`
	CarregadoMs   float64 `json:"carregado_ms"`
	Fator         float64 `json:"fator"`
	TempoSobCarga float64 `json:"pct_tempo_sob_carga"`
	Regime        string  `json:"regime"`
	Leitura       string  `json:"leitura"`
}

// Limiar do regime de colapso.
//
// PROVISÓRIO, e declarado como tal. Ele não vem de teoria: vem da separação
// observada num parque de três máquinas, onde os fatores medidos foram 0,7 —
// 2,9 — 116,4. Entre 2,9 e 116 há uma lacuna de quarenta vezes, e é dela que
// sai o corte.
//
// Com mais máquinas isto deve ser recalibrado a partir da distribuição real, e
// não continuar sendo um número que eu escolhi. Enquanto for escolhido, o
// campo `regime` diz qual foi o critério, para que ninguém o leia como lei.
const fatorDeColapso = 10.0

// Abaixo disto o disco está praticamente parado, e latência de disco parado é
// dominada por cache, não pelo disco.
const cargaQueConta = 25.0

// MedirColapsoDoDisco calcula o comportamento sob carga a partir da telemetria.
//
// Usa a mediana, não a média: um único pico atrapalhado por outro processo
// desloca a média e transforma máquina sadia em doente — erro que já custou
// caro neste projeto.
func (s *Server) MedirColapsoDoDisco(ctx context.Context, deviceID string, horas int) (ColapsoDoDisco, error) {
	var c ColapsoDoDisco
	err := s.Pool.QueryRow(ctx, `
		WITH a AS (
		    SELECT (hardware->'disk_activity'->>'busy_pct')::numeric   AS carga,
		           (hardware->'disk_activity'->>'latency_ms')::numeric AS lat
		      FROM telemetry_snapshots
		     WHERE device_id = $1
		       AND coletado_em > now() - make_interval(hours => $2)
		       AND (hardware->'disk_activity'->>'latency_ms') IS NOT NULL
		)
		SELECT count(*),
		       coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY lat)
		                FILTER (WHERE carga < $3), 0),
		       coalesce(percentile_cont(0.5) WITHIN GROUP (ORDER BY lat)
		                FILTER (WHERE carga >= $3), 0),
		       coalesce(100.0 * count(*) FILTER (WHERE carga >= $3) / nullif(count(*), 0), 0)
		  FROM a`, deviceID, horas, cargaQueConta).
		Scan(&c.Amostras, &c.OciosoMs, &c.CarregadoMs, &c.TempoSobCarga)
	if err != nil {
		return c, err
	}
	if c.Amostras == 0 || c.OciosoMs <= 0 || c.CarregadoMs <= 0 {
		// Sem os dois lados da comparação não existe fator. Devolver 1 aqui
		// seria afirmar "não colapsa" sem ter medido — e ausência de dado não
		// é evidência de saúde.
		c.Regime = "indeterminado"
		c.Leitura = "sem amostras suficientes com o disco ocioso e sob carga para comparar"
		return c, nil
	}

	c.Fator = arredondarPct(c.CarregadoMs / c.OciosoMs)
	switch {
	case c.Fator >= fatorDeColapso:
		c.Regime = "colapsa sob carga"
		c.Leitura = fmt.Sprintf(
			"fica %.0f× mais lento quando exigido (%.2f ms ocioso, %.0f ms sob carga), "+
				"e isso acontece em %.0f%% do tempo",
			c.Fator, c.OciosoMs, c.CarregadoMs, c.TempoSobCarga)
	case c.Fator >= 3:
		c.Regime = "degrada sob carga"
		c.Leitura = fmt.Sprintf("fica %.1f× mais lento quando exigido, o que ainda é absorvível",
			c.Fator)
	default:
		c.Regime = "estável"
		c.Leitura = fmt.Sprintf("mantém a resposta sob carga (%.2f ms ocioso, %.2f ms carregado)",
			c.OciosoMs, c.CarregadoMs)
	}
	return c, nil
}
