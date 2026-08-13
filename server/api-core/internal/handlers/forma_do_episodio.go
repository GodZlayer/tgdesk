package handlers

import (
	"context"
	"fmt"
	"time"
)

// A forma do episódio — o que separa engasgo de degradação sustentada.
//
// A primeira versão do dossiê tinha um status só, `lentidao_persistente`, e
// estava errada para as duas máquinas do parque. Quem convive com elas
// descreveu a diferença: "o Daniel tem lentidões ocasionais rápidas; a Dani tem
// momentos de lentidão profunda" — e observou que sentimento diferente implica
// causa e solução diferentes.
//
// O histograma de `device_metric_rollup` confirma, e com folga:
//
//	Daniel  1,83% das amostras de CPU acima de 95%  (429 de 23.402)
//	Dani    0,19%                                     (33 de 17.120)
//
// Dez vezes mais pico no Daniel — e a lentidão MAIS SEVERA é a da Dani. Não é
// intensidade, é FORMA. Pico curto e frequente que se resolve sozinho não é o
// mesmo fenômeno que degradação que entra e fica.
//
// O que este arquivo faz é ler essa forma do histograma que já existe. O que
// ele NÃO faz é fingir que consegue ler a forma quando o sinal não está lá —
// e é isso que produz a lacuna declarada abaixo.

// FormaDoEpisodio é o veredito sobre o formato da lentidão.
type FormaDoEpisodio struct {
	// Status resolvido, ou `lentidao_nao_caracterizada` quando não se separa.
	Status string
	// A evidência numérica que sustentou a escolha, para a tela citar.
	Evidencia string
	// Preenchido quando a forma NÃO pôde ser determinada: diz qual medida
	// faltou. É o "próximo teste que mais separa" de §10.5.1.
	MedidaQueFalta string
}

// Limiares da forma. Vivem aqui e não em `diag_param` ainda porque nasceram
// agora, de uma única observação de campo com duas máquinas — promovê-los a
// parâmetro versionado antes de valerem para mais gente daria a eles uma
// autoridade que não têm.
const (
	// Fração de amostras em pico acima da qual o comportamento é "engasgo
	// frequente". Daniel está em 1,8%; a Dani, em 0,2%.
	fracaoDePicoParaIntermitente = 0.01
	// Média sustentada acima da qual o recurso está preso, não oscilando.
	mediaParaDegradacaoSustentada = 60.0
	// Janela de observação. Curta demais confunde um dia atípico com padrão.
	janelaDeObservacao = 7 * 24 * time.Hour
)

// formaDaLentidao decide entre engasgo e degradação a partir do histograma.
//
// Devolve `lentidao_nao_caracterizada` quando nenhum dos dois padrões aparece —
// e esse é o caso da Dani hoje, que é justamente o caso interessante: ela tem a
// lentidão mais severa do parque e nenhum sinal coletado a explica. A resposta
// honesta é dizer isso e apontar a medida que falta, não escolher o status
// menos improvável.
func (s *Server) formaDaLentidao(ctx context.Context, deviceID string) FormaDoEpisodio {
	type agregado struct {
		amostras int
		acima95  int
		acima85  int
		media    float64
	}
	porMetrica := map[string]agregado{}

	rows, err := s.Pool.Query(ctx, `
		SELECT metrica, sum(samples), sum(acima_95), sum(acima_85),
		       sum(soma) / nullif(sum(samples), 0)
		FROM device_metric_rollup
		WHERE device_id = $1 AND bucket_hora > now() - $2::interval
		GROUP BY metrica`, deviceID, janelaDeObservacao.String())
	if err != nil {
		return FormaDoEpisodio{Status: "lentidao_nao_caracterizada",
			MedidaQueFalta: "historico_de_pressao"}
	}
	defer rows.Close()

	for rows.Next() {
		var m string
		var a agregado
		var media *float64
		if rows.Scan(&m, &a.amostras, &a.acima95, &a.acima85, &media) != nil {
			continue
		}
		if media != nil {
			a.media = *media
		}
		porMetrica[m] = a
	}

	cpu := porMetrica["processing"]
	mem := porMetrica["memory"]
	latencia := porMetrica["disk_latency_ms"]
	discoOcupado := porMetrica["disk_busy"]

	// 0. O disco primeiro, e antes de CPU e memória.
	//
	// A ordem não é arbitrária. A máquina do parque com a lentidão mais severa
	// tinha CPU e memória tranquilas — se o disco fosse avaliado por último,
	// ela cairia em "não caracterizada" mesmo com a latência gritando. Quem
	// tem a medida direta do gargalo decide antes de quem tem indício.
	//
	// `acima_75` sobre latência conta amostras acima de 75 na ESCALA DA
	// MÉTRICA, que aqui é milissegundo: são as amostras em que uma operação
	// levou mais de 75 ms. Isso é episódio, não pico instantâneo.
	if latencia.amostras >= 30 {
		fracaoLenta := float64(latencia.acima85) / float64(latencia.amostras)
		if fracaoLenta > 0 || latencia.media >= 20 {
			return FormaDoEpisodio{
				Status: "lentidao_profunda",
				Evidencia: fmt.Sprintf(
					"disco com latência média de %.1f ms na janela, e %d amostras acima de 85 ms (de %d)",
					latencia.media, latencia.acima85, latencia.amostras),
			}
		}
	}
	if discoOcupado.amostras >= 30 && discoOcupado.media >= 70 {
		return FormaDoEpisodio{
			Status: "lentidao_profunda",
			Evidencia: fmt.Sprintf("disco ocupado %.0f%% do tempo, em média, na janela",
				discoOcupado.media),
		}
	}

	// 1. Engasgo: muita amostra em pico, mas média baixa. O recurso é tomado e
	//    devolvido — é a assinatura de disputa, não de esgotamento.
	if cpu.amostras > 0 {
		fracao := float64(cpu.acima95) / float64(cpu.amostras)
		if fracao >= fracaoDePicoParaIntermitente && cpu.media < mediaParaDegradacaoSustentada {
			return FormaDoEpisodio{
				Status: "lentidao_intermitente",
				Evidencia: fmt.Sprintf(
					"CPU passou de 95%% em %.2f%% das amostras (%d de %d), com média de apenas %.0f%%",
					fracao*100, cpu.acima95, cpu.amostras, cpu.media),
			}
		}
	}

	// 2. Degradação sustentada: média alta, recurso preso.
	if cpu.media >= mediaParaDegradacaoSustentada {
		return FormaDoEpisodio{
			Status:    "lentidao_profunda",
			Evidencia: fmt.Sprintf("CPU com média sustentada de %.0f%% na janela", cpu.media),
		}
	}
	if mem.amostras > 0 && mem.media >= 85 {
		return FormaDoEpisodio{
			Status:    "lentidao_profunda",
			Evidencia: fmt.Sprintf("memória com média sustentada de %.0f%%", mem.media),
		}
	}

	// 3. Nem um nem outro. A lentidão existe (o chamado veio, ou a ocupação
	//    está no limite), e os sinais que temos não a explicam.
	//
	//    O que falta é nomeado, não genérico: o que caracteriza degradação
	//    profunda é o disco OCUPADO e a latência de I/O — e a métrica
	//    `storage` que coletamos é OCUPAÇÃO, não atividade. Disco cheio e
	//    disco lento são coisas diferentes, e hoje só medimos o primeiro.
	// Se a latência JÁ está sendo medida e está normal, a lacuna deixa de ser
	// "não medimos" e passa a ser "não sabemos ainda" — que é outra coisa, e a
	// tela precisa dizer a certa. Confundir as duas faria o técnico procurar um
	// sinal que já existe.
	falta := "tempo_de_disco_ocupado_e_latencia_io"
	if latencia.amostras > 0 || discoOcupado.amostras > 0 {
		falta = "historico_de_episodios"
	}
	return FormaDoEpisodio{
		Status:         "lentidao_nao_caracterizada",
		MedidaQueFalta: falta,
		Evidencia: fmt.Sprintf(
			"CPU e memória dentro do normal na janela (CPU média %.0f%%, pico em %.2f%% das amostras)",
			cpu.media, fracaoSegura(cpu.acima95, cpu.amostras)*100),
	}
}

func fracaoSegura(parte, total int) float64 {
	if total == 0 {
		return 0
	}
	return float64(parte) / float64(total)
}
