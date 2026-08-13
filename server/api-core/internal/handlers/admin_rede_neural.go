package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"tgdesk/api-core/internal/diagnostico"
)

// A tela do admin sobre a rede neural (§10.5.3, §14).
//
// Por que isto precisa existir: a arquitetura inteira se apoia em CALIBRAÇÃO
// VISÍVEL — "quando dizemos 70–80%, acertamos 74% em 112 casos". Sem uma tela
// que mostre isso, o número na frente do técnico volta a ser oráculo, e o
// projeto perde a única defesa que tem contra um modelo que começou a mentir.
//
// A regra que organiza o que entra aqui: **tudo é resultado medido, nada é
// afirmação**. Cada bloco abaixo ou traz um número que saiu do banco, ou traz
// explicitamente a ausência dele. Em particular, `calibracao_de_campo` fica
// vazia enquanto não houver caso interno avaliado — porque calibração calculada
// sobre caso simulado é calibração do simulador (§19.3), e mostrá-la como se
// fosse de campo seria a mentira mais cara que esta tela pode contar.

// PainelDaRede é o retrato completo para o admin.
type PainelDaRede struct {
	// Quem responde HOJE, e por quê. É a primeira coisa que o admin precisa
	// saber, e a que mais gera mal-entendido: existir modelo treinado não
	// significa que ele está decidindo.
	MotorVigente  string `json:"motor_vigente"`
	MotivoDoMotor string `json:"motivo_do_motor"`

	Modelos          []ModeloNoPainel `json:"modelos"`
	ConjuntoDeTreino ConjuntoNoPainel `json:"conjunto_de_treino"`
	Ontologia        []StatusNoPainel `json:"ontologia"`
	LacoRAT          LacoNoPainel     `json:"laco_rat"`
	CalibracaoCampo  []FaixaDeAcerto  `json:"calibracao_de_campo"`
	GateDePromocao   GateNoPainel     `json:"gate_de_promocao"`
}

type ModeloNoPainel struct {
	Codigo       string    `json:"codigo"`
	Status       string    `json:"status_codigo"`
	Estado       string    `json:"estado"`
	Causas       []string  `json:"causas"`
	NTreino      int       `json:"n_treino"`
	NValidacao   int       `json:"n_validacao"`
	NSimulado    int       `json:"n_simulado"`
	Acuracia     *float64  `json:"acuracia"`
	ECE          *float64  `json:"ece"`
	LogLoss      *float64  `json:"log_loss"`
	LogLossRegra *float64  `json:"log_loss_regra"`
	Temperatura  *float64  `json:"temperatura"`
	TreinadoEm   time.Time `json:"treinado_em"`
	// Por que este modelo NÃO está promovido. Vazio quando está.
	BloqueiosParaPromover []string `json:"bloqueios_para_promover"`
}

type ConjuntoNoPainel struct {
	Total       int            `json:"total"`
	PorOrigem   map[string]int `json:"por_origem"`
	PorParticao map[string]int `json:"por_particao"`
	PorStatus   map[string]int `json:"por_status"`
	// Quantos exemplos vieram da realidade (RAT/escada) e não de simulação.
	// É o número que destrava a promoção, e por isso aparece sozinho.
	Reais int `json:"reais"`
}

type StatusNoPainel struct {
	Codigo     string          `json:"codigo"`
	Descricao  string          `json:"descricao"`
	Causas     []CausaNoPainel `json:"causas"`
	Limitacoes []string        `json:"limitacoes"`
	Revisor    string          `json:"revisor"`
}

type CausaNoPainel struct {
	Codigo   string  `json:"codigo"`
	Prior    float64 `json:"prior"`
	NCorpus  int     `json:"n_corpus"`
	NInterno int     `json:"n_interno"`
	// Peso do fórum que ainda sobra nesta causa: k/(k+n) de §13.4. Cai à
	// medida que o dado interno cresce, e é consultável de propósito — dá para
	// olhar uma probabilidade e saber quanto dela ainda vem de fórum.
	PesoExterno float64 `json:"peso_externo"`
}

type LacoNoPainel struct {
	Total             int `json:"total"`
	Avaliadas         int `json:"avaliadas"`
	PendentesAvaliar  int `json:"pendentes_avaliar"`
	Acertos           int `json:"acertos"`
	Erros             int `json:"erros"`
	AbstencoesCertas  int `json:"abstencoes_corretas"`
	AbstencoesErradas int `json:"abstencoes_indevidas"`
	Ajudou            int `json:"ajudou"`
	Atrapalhou        int `json:"atrapalhou"`
	Indiferente       int `json:"indiferente"`
	// Explicação do estado quando não há nada. Vazio não é erro: significa que
	// nenhum atendimento foi fechado ainda, e o laço só produz dado no
	// fechamento.
	Observacao string `json:"observacao"`
}

type FaixaDeAcerto struct {
	De             float64  `json:"de"`
	Ate            float64  `json:"ate"`
	N              int      `json:"n"`
	ConfiancaMedia float64  `json:"confianca_media"`
	AcertoReal     *float64 `json:"acerto_real"`
	Motivo         string   `json:"motivo,omitempty"`
}

type GateNoPainel struct {
	NMinimoPorCausa int     `json:"n_minimo_por_causa"`
	ECEMaximo       float64 `json:"ece_maximo"`
	DesvioMaximoPP  float64 `json:"desvio_maximo_pp"`
	ECERebaixamento float64 `json:"ece_rebaixamento"`
}

// PainelDaRedeNeural serve tudo o que o admin precisa para auditar o motor.
func (s *Server) PainelDaRedeNeural(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	p := PainelDaRede{
		GateDePromocao: GateNoPainel{
			NMinimoPorCausa: 150, ECEMaximo: 0.05,
			DesvioMaximoPP: 15, ECERebaixamento: 0.08,
		},
	}

	p.Modelos = s.modelosDoPainel(ctx)
	p.ConjuntoDeTreino = s.conjuntoDoPainel(ctx)
	p.Ontologia = s.ontologiaDoPainel(ctx)
	p.LacoRAT = s.lacoDoPainel(ctx)
	p.CalibracaoCampo = s.calibracaoDoPainel(ctx)

	// Quem responde hoje. A resposta honesta quase sempre é "a regra", e a tela
	// tem que dizer isso mesmo com um modelo treinado no banco — confundir
	// "existe modelo" com "o modelo decide" é o mal-entendido mais provável
	// desta tela inteira.
	promovido := false
	for _, m := range p.Modelos {
		if m.Estado == "promovido" {
			promovido = true
		}
	}
	if promovido {
		p.MotorVigente = "modelo"
		p.MotivoDoMotor = "há pelo menos um status com modelo promovido pelo gate de calibração"
	} else if len(p.Modelos) > 0 {
		p.MotorVigente = "regra"
		p.MotivoDoMotor = "existe modelo treinado, mas nenhum passou o gate — todos rodam em sombra, " +
			"medidos contra a realidade sem decidir nada"
	} else {
		p.MotorVigente = "regra"
		p.MotivoDoMotor = "nenhum status atingiu volume de treino; a camada de regra responde sozinha"
	}

	writeJSON(w, http.StatusOK, p)
}

func (s *Server) modelosDoPainel(ctx context.Context) []ModeloNoPainel {
	rows, err := s.Pool.Query(ctx, `
		SELECT codigo, status_codigo, estado, n_treino, n_validacao, n_simulado,
		       acuracia, ece, log_loss, log_loss_regra, treinado_em, pesos
		FROM model_version ORDER BY treinado_em DESC`)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var saida []ModeloNoPainel
	for rows.Next() {
		var m ModeloNoPainel
		var pesos []byte
		if rows.Scan(&m.Codigo, &m.Status, &m.Estado, &m.NTreino, &m.NValidacao,
			&m.NSimulado, &m.Acuracia, &m.ECE, &m.LogLoss, &m.LogLossRegra,
			&m.TreinadoEm, &pesos) != nil {
			continue
		}
		// As causas e a temperatura moram dentro dos pesos serializados. Ler
		// dali evita uma segunda fonte de verdade sobre o que o modelo aprendeu.
		var cab struct {
			Causas      []string `json:"causas"`
			Temperatura float64  `json:"temperatura"`
		}
		if json.Unmarshal(pesos, &cab) == nil {
			m.Causas = cab.Causas
			t := cab.Temperatura
			m.Temperatura = &t
		}
		m.BloqueiosParaPromover = bloqueiosParaPromover(m)
		saida = append(saida, m)
	}
	return saida
}

// bloqueiosParaPromover lista, em português, tudo que impede este modelo de
// substituir a regra.
//
// A lista é o valor desta tela: sem ela o admin vê "sombra" e não sabe se falta
// dado, calibração ou tempo. Cada item aqui é uma condição de §14.2, verificada
// contra o número que está no banco.
func bloqueiosParaPromover(m ModeloNoPainel) []string {
	if m.Estado == "promovido" {
		return nil
	}
	var b []string
	if m.NSimulado >= m.NTreino && m.NTreino > 0 {
		b = append(b, "treinado só com casos simulados do corpus — simulação treina, "+
			"realidade promove; o banco recusa a promoção enquanto isto valer")
	}
	if m.ECE != nil && *m.ECE > 0.05 {
		b = append(b, "erro de calibração (ECE) acima do gate: mede o quanto a "+
			"probabilidade que ele diz corresponde ao acerto real")
	}
	if m.LogLoss != nil && m.LogLossRegra != nil && *m.LogLoss >= *m.LogLossRegra {
		b = append(b, "não é melhor que a regra que substituiria — complexidade sem ganho")
	}
	if m.NValidacao < 30 {
		b = append(b, "conjunto de validação pequeno demais para estimar a faixa de confiança")
	}
	return b
}

func (s *Server) conjuntoDoPainel(ctx context.Context) ConjuntoNoPainel {
	c := ConjuntoNoPainel{
		PorOrigem: map[string]int{}, PorParticao: map[string]int{},
		PorStatus: map[string]int{},
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT origem, particao, status_codigo, count(*)
		FROM training_example GROUP BY 1,2,3`)
	if err != nil {
		return c
	}
	defer rows.Close()
	for rows.Next() {
		var origem, particao, status string
		var n int
		if rows.Scan(&origem, &particao, &status, &n) != nil {
			continue
		}
		c.Total += n
		c.PorOrigem[origem] += n
		c.PorParticao[particao] += n
		c.PorStatus[status] += n
		if origem != "simulado_corpus" {
			c.Reais += n
		}
	}
	return c
}

func (s *Server) ontologiaDoPainel(ctx context.Context) []StatusNoPainel {
	rows, err := s.Pool.Query(ctx, `
		SELECT codigo, descricao, causas_candidatas, limitacoes,
		       coalesce(revisado_por::text, revisado_por_automacao, 'nao revisado')
		FROM negative_status ORDER BY codigo`)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var saida []StatusNoPainel
	for rows.Next() {
		var st StatusNoPainel
		var causas, limitacoes []byte
		if rows.Scan(&st.Codigo, &st.Descricao, &causas, &limitacoes, &st.Revisor) != nil {
			continue
		}
		var codigos []string
		_ = json.Unmarshal(causas, &codigos)
		_ = json.Unmarshal(limitacoes, &st.Limitacoes)
		for _, c := range codigos {
			st.Causas = append(st.Causas, CausaNoPainel{Codigo: c})
		}
		saida = append(saida, st)
	}

	// Priors numa segunda passada: a tabela vive em outro schema, e juntá-las
	// numa consulta só amarraria a leitura da ontologia à do corpus.
	priors, err := s.Pool.Query(ctx, `
		SELECT status_codigo, causa_codigo, frequencia, n, n_interno, k
		FROM corpus.corpus_prior`)
	if err != nil {
		return saida
	}
	defer priors.Close()
	for priors.Next() {
		var status, causa string
		var freq float64
		var n, nInterno, k int
		if priors.Scan(&status, &causa, &freq, &n, &nInterno, &k) != nil {
			continue
		}
		for i := range saida {
			if saida[i].Codigo != status {
				continue
			}
			for j := range saida[i].Causas {
				if saida[i].Causas[j].Codigo != causa {
					continue
				}
				saida[i].Causas[j].Prior = freq
				saida[i].Causas[j].NCorpus = n
				saida[i].Causas[j].NInterno = nInterno
				if k+nInterno > 0 {
					saida[i].Causas[j].PesoExterno = float64(k) / float64(k+nInterno)
				}
			}
		}
	}
	return saida
}

func (s *Server) lacoDoPainel(ctx context.Context) LacoNoPainel {
	var l LacoNoPainel
	err := s.Pool.QueryRow(ctx, `
		SELECT count(*),
		       count(*) FILTER (WHERE avaliado_em IS NOT NULL),
		       count(*) FILTER (WHERE avaliado_em IS NULL),
		       count(*) FILTER (WHERE avaliacao_causa = 'acertou'),
		       count(*) FILTER (WHERE avaliacao_causa = 'errou'),
		       count(*) FILTER (WHERE avaliacao_causa = 'abstencao_correta'),
		       count(*) FILTER (WHERE avaliacao_causa = 'abstencao_indevida'),
		       count(*) FILTER (WHERE avaliacao_utilidade = 'ajudou'),
		       count(*) FILTER (WHERE avaliacao_utilidade = 'atrapalhou'),
		       count(*) FILTER (WHERE avaliacao_utilidade = 'indiferente')
		FROM rat_comparacao`).
		Scan(&l.Total, &l.Avaliadas, &l.PendentesAvaliar, &l.Acertos, &l.Erros,
			&l.AbstencoesCertas, &l.AbstencoesErradas,
			&l.Ajudou, &l.Atrapalhou, &l.Indiferente)
	if err != nil {
		l.Observacao = "não foi possível ler o laço"
		return l
	}
	if l.Total == 0 {
		l.Observacao = "nenhum atendimento fechado ainda. O laço só produz dado no " +
			"fechamento: é ali que a suposição da rede encontra o que o técnico achou."
	}
	return l
}

func (s *Server) calibracaoDoPainel(ctx context.Context) []FaixaDeAcerto {
	const minimoPorFaixa = 20
	rows, err := s.Pool.Query(ctx, `
		SELECT width_bucket(suposicao_prob, 0, 1, 10),
		       count(*), avg(suposicao_prob),
		       avg(CASE WHEN avaliacao_causa = 'acertou' THEN 1.0 ELSE 0.0 END)
		FROM rat_comparacao
		WHERE avaliado_em IS NOT NULL AND suposicao_prob IS NOT NULL
		GROUP BY 1 ORDER BY 1`)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var saida []FaixaDeAcerto
	for rows.Next() {
		var faixa, n int
		var conf, acerto float64
		if rows.Scan(&faixa, &n, &conf, &acerto) != nil {
			continue
		}
		f := FaixaDeAcerto{
			De: float64(faixa-1) / 10, Ate: float64(faixa) / 10,
			N: n, ConfiancaMedia: conf,
		}
		// Abaixo do piso a faixa não vira número. É a regra de §10.5.3: sem
		// histórico suficiente o rótulo é "sem histórico", nunca um número
		// inventado que pareceria calibração.
		if n >= minimoPorFaixa {
			a := acerto
			f.AcertoReal = &a
		} else {
			f.Motivo = "sem histórico suficiente"
		}
		saida = append(saida, f)
	}
	return saida
}

// TreinarRede dispara uma rodada de treino a partir da tela do admin.
//
// Expor o treino é o que torna a tela útil em vez de decorativa: o admin vê o
// conjunto crescer com o laço RAT e roda de novo, sem depender de alguém com
// acesso ao container. O treino sempre grava em SOMBRA — não existe caminho,
// nesta rota ou em qualquer outra, que promova um modelo sem o gate.
func (s *Server) TreinarRede(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 120*time.Second)
	defer cancel()

	exemplos, err := diagnostico.CarregarExemplos(ctx, s.Pool)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "leitura_falhou", err.Error())
		return
	}
	res := diagnostico.Treinar(exemplos)
	if err := diagnostico.Gravar(ctx, s.Pool, res); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "gravacao_falhou", err.Error())
		return
	}
	if err := s.RecarregarModelos(ctx); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "recarga_falhou", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, res)
}
