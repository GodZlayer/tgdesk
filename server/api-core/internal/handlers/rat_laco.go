package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

// O laço RAT × suposição (§19.4).
//
// É a peça que faltava para o aprendizado não parar no primeiro treino. Hoje o
// técnico já produz uma RAT — o relatório de atendimento, com o que ele
// encontrou e o que fez. Ela é a REALIDADE. A suposição da rede é o que o
// sistema achou ANTES.
//
//	a cada atendimento fechado: suposição da rede × RAT do técnico,
//	comparadas campo a campo, com o supervisor avaliando
//
// Disso saem três coisas que não existiam:
//
//   - o rótulo de treino de melhor qualidade que o produto consegue — não é
//     "resolvido/não resolvido", é a causa que a rede apontou contra a causa que
//     o técnico encontrou com a máquina na mão;
//   - a calibração medida em CAMPO, que é a evidência que §14.2 e §10.5.3
//     exigem e que nenhum corpus de fórum produz;
//   - a resposta parcial melhorando por estágio: como a rede vê a suposição
//     sendo corrigida, ela passa a acertar mais cedo.
//
// Regras que impedem o laço de virar teatro, todas aplicadas aqui:
//
//   - a causa encontrada vem do CONJUNTO FECHADO, nunca texto livre (§10.3);
//   - o supervisor avalia em DUAS dimensões — acertar a causa e sugerir o teste
//     certo são erros diferentes;
//   - divergência NÃO é erro do técnico: o que se ajusta é a rede, e o caso
//     entra no treino com peso maior (o trigger da 0078 faz isso no banco);
//   - a RAT continua sendo documento do atendimento, não formulário de treino.
//     O que o treino consome é o que ela JÁ registra — pedir campo a mais só
//     para alimentar modelo transformaria o técnico em rotulador.

// RegistroDeRAT é o que o técnico envia ao fechar o atendimento.
type RegistroDeRAT struct {
	TicketID string `json:"ticket_id"`
	DeviceID string `json:"device_id"`
	// Do conjunto fechado de `negative_status.causas_candidatas`. O handler
	// recusa qualquer coisa fora dele — é a diferença entre rótulo e opinião.
	CausaEncontrada string `json:"causa_encontrada"`
	AcaoExecutada   string `json:"acao_executada"`
	Observacao      string `json:"observacao"`
}

// AvaliacaoDoSupervisor fecha o laço.
type AvaliacaoDoSupervisor struct {
	// acertou | errou | abstencao_correta | abstencao_indevida
	AvaliacaoCausa string `json:"avaliacao_causa"`
	// ajudou | atrapalhou | indiferente
	AvaliacaoUtilidade string `json:"avaliacao_utilidade"`
}

var avaliacoesDeCausa = map[string]bool{
	"acertou": true, "errou": true,
	"abstencao_correta": true, "abstencao_indevida": true,
}

var avaliacoesDeUtilidade = map[string]bool{
	"ajudou": true, "atrapalhou": true, "indiferente": true,
}

// RegistrarRAT grava o que o técnico encontrou, junto com a suposição que o
// sistema tinha feito — congelada, não referenciada.
//
// Congelar importa: a suposição precisa sobreviver ao expurgo do `diagnosis`
// que a gerou (§7.4), senão a calibração histórica se apaga sozinha quando a
// retenção rodar.
func (s *Server) RegistrarRAT(w http.ResponseWriter, r *http.Request) {
	var in RegistroDeRAT
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErrCode(w, http.StatusBadRequest, "corpo_invalido", "corpo inválido")
		return
	}
	if in.DeviceID == "" || in.CausaEncontrada == "" {
		writeErrCode(w, http.StatusBadRequest, "campos_obrigatorios",
			"device_id e causa_encontrada são obrigatórios")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	// A suposição vigente para este dispositivo, se houver. LEFT JOIN de
	// propósito: atendimento sem diagnóstico prévio é caso legítimo — e é
	// justamente o caso que mede se a rede teria ajudado.
	var (
		diagID, supStatus, supCausa, supMotor, modelo *string
		supProb                                       *float64
	)
	err := s.Pool.QueryRow(ctx, `
		SELECT d.id::text, d.status_codigo,
		       (d.causas->0->>'codigo'), (d.causas->0->>'prob')::float8,
		       d.motor, d.model_version_codigo
		FROM diagnosis d
		WHERE d.device_id = $1
		ORDER BY d.created_at DESC
		LIMIT 1`, in.DeviceID).
		Scan(&diagID, &supStatus, &supCausa, &supProb, &supMotor, &modelo)
	if err != nil {
		// Sem diagnóstico anterior. Não é erro: grava a realidade sozinha, e a
		// comparação fica com suposição nula — que já é a informação de que o
		// sistema não tinha o que dizer.
		diagID, supStatus, supCausa, supMotor, modelo, supProb = nil, nil, nil, nil, nil, nil
	}

	// A causa tem que pertencer ao conjunto fechado do status. Fora dele, é
	// texto livre com aparência de código — e viraria rótulo de treino inválido.
	if supStatus != nil {
		var pertence bool
		if err := s.Pool.QueryRow(ctx, `
			SELECT EXISTS(
				SELECT 1 FROM negative_status
				WHERE codigo = $1 AND causas_candidatas ? $2)`,
			*supStatus, in.CausaEncontrada).Scan(&pertence); err == nil && !pertence {
			writeErrCode(w, http.StatusBadRequest, "causa_fora_do_conjunto",
				"causa_encontrada não pertence ao conjunto fechado do status "+*supStatus)
			return
		}
	}

	var id string
	if err := s.Pool.QueryRow(ctx, `
		INSERT INTO rat_comparacao
		  (ticket_id, device_id, diagnosis_id, suposicao_status, suposicao_causa,
		   suposicao_prob, suposicao_motor, model_version_codigo,
		   causa_encontrada, acao_executada, observacao)
		VALUES (nullif($1,'')::uuid, $2::uuid, nullif($3,'')::uuid, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id::text`,
		in.TicketID, in.DeviceID, strOuVazio(diagID), supStatus, supCausa,
		supProb, supMotor, modelo, in.CausaEncontrada, in.AcaoExecutada, in.Observacao,
	).Scan(&id); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "gravacao_falhou", err.Error())
		return
	}

	// A comparação já sai calculada — é o que o supervisor vai avaliar, e ele
	// não deveria ter que descobrir sozinho se a rede acertou.
	divergiu := supCausa == nil || *supCausa != in.CausaEncontrada
	writeJSON(w, http.StatusCreated, map[string]any{
		"id":               id,
		"suposicao_causa":  supCausa,
		"causa_encontrada": in.CausaEncontrada,
		"divergiu":         divergiu,
		"tinha_suposicao":  supCausa != nil,
	})
}

// AvaliarRAT registra o julgamento do supervisor sobre a suposição.
//
// O peso de treino NÃO é decidido aqui: quem decide é o trigger da 0078,
// porque é propriedade do dado e não do handler — qualquer caminho futuro que
// grave nesta tabela herda o comportamento certo.
func (s *Server) AvaliarRAT(w http.ResponseWriter, r *http.Request, id string) {
	var in AvaliacaoDoSupervisor
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeErrCode(w, http.StatusBadRequest, "corpo_invalido", "corpo inválido")
		return
	}
	if !avaliacoesDeCausa[in.AvaliacaoCausa] {
		writeErrCode(w, http.StatusBadRequest, "avaliacao_invalida",
			"avaliacao_causa deve ser acertou, errou, abstencao_correta ou abstencao_indevida")
		return
	}
	if !avaliacoesDeUtilidade[in.AvaliacaoUtilidade] {
		writeErrCode(w, http.StatusBadRequest, "utilidade_invalida",
			"avaliacao_utilidade deve ser ajudou, atrapalhou ou indiferente")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	tag, err := s.Pool.Exec(ctx, `
		UPDATE rat_comparacao
		SET avaliacao_causa = $2, avaliacao_utilidade = $3, avaliado_em = now()
		WHERE id = $1::uuid`, id, in.AvaliacaoCausa, in.AvaliacaoUtilidade)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "gravacao_falhou", err.Error())
		return
	}
	if tag.RowsAffected() == 0 {
		writeErrCode(w, http.StatusNotFound, "nao_encontrado", "comparação não encontrada")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "id": id})
}

// CalibracaoDeCampo devolve a tabela por trás de "quando dizemos 70–80%,
// acertamos 74% em 112 casos" (§10.5.3).
//
// É o número que transforma probabilidade em argumento em vez de oráculo. E é
// calculado SÓ sobre caso interno avaliado — nunca sobre simulado (§19.3).
// Faixa sem casos suficientes devolve `sem_historico`, jamais um número
// inventado.
func (s *Server) CalibracaoDeCampo(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	rows, err := s.Pool.Query(ctx, `
		SELECT width_bucket(suposicao_prob, 0, 1, 10) AS faixa,
		       count(*) AS n,
		       avg(suposicao_prob) AS confianca_media,
		       avg(CASE WHEN avaliacao_causa = 'acertou' THEN 1.0 ELSE 0.0 END) AS acerto_real
		FROM rat_comparacao
		WHERE avaliado_em IS NOT NULL AND suposicao_prob IS NOT NULL
		GROUP BY 1 ORDER BY 1`)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "consulta_falhou", err.Error())
		return
	}
	defer rows.Close()

	// Piso abaixo do qual a faixa não vira número. 20 é o ponto em que a
	// diferença entre 70% e 80% de acerto deixa de ser ruído de amostra.
	const minimoPorFaixa = 20

	var faixas []map[string]any
	total := 0
	for rows.Next() {
		var faixa, n int
		var conf, acerto float64
		if err := rows.Scan(&faixa, &n, &conf, &acerto); err != nil {
			continue
		}
		total += n
		item := map[string]any{
			"faixa":           []float64{float64(faixa-1) / 10, float64(faixa) / 10},
			"n":               n,
			"confianca_media": conf,
		}
		if n >= minimoPorFaixa {
			item["acerto_real"] = acerto
			item["desvio_pp"] = (acerto - conf) * 100
		} else {
			item["acerto_real"] = nil
			item["motivo"] = "sem_historico_suficiente"
		}
		faixas = append(faixas, item)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"faixas":           faixas,
		"total_avaliado":   total,
		"minimo_por_faixa": minimoPorFaixa,
		"origem":           "rat_comparacao (caso interno avaliado; simulado nunca entra)",
	})
}

func strOuVazio(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}
