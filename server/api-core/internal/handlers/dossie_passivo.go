package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// O dossiê passivo (§7, §10.4) — o exame de rotina.
//
// A escada é o exame PROVOCADO; isto aqui é o que o servidor sabe do computador
// sem ter forçado nada. É o que pré-carrega a tela do técnico antes de qualquer
// chamado, e é o que sustenta os alertas ao cliente.
//
// Este arquivo é a ponte entre a telemetria que o agente JÁ manda e o
// vocabulário de sinais que o motor consome. Enquanto a telemetria contínua em
// duas velocidades (B4) não existir, a fonte é `telemetry_snapshots` +
// `device_health_state` — que é menos do que §7 pede, e por isso cada tradução
// abaixo é explícita, item a item, em vez de uma regra genérica que
// disfarçaria a lacuna.
//
// INVARIANTE: nada aqui é calculado quando a tela abre. O retrato é produzido
// no servidor e empurrado pelo canal (§10.4). O cliente desenha o que recebeu.

// dossiePassivo é o que o produtor extrai de um dispositivo.
type dossiePassivo struct {
	StatusProvavel string
	Evidencias     []EvidenciaDoDossie
}

// evidenciasDoDispositivo traduz a telemetria em sinais do vocabulário.
//
// Cada `case` é uma AFIRMAÇÃO de que aquela medida é aquele sinal — e afirmação
// implícita é a que ninguém revisa. Medida ausente não vira zero: o sinal
// simplesmente não entra, porque ausência é informação (§19.3).
func (s *Server) evidenciasDoDispositivo(ctx context.Context, deviceID string) dossiePassivo {
	var d dossiePassivo

	var hardware []byte
	err := s.Pool.QueryRow(ctx, `
		SELECT hardware FROM telemetry_snapshots
		WHERE device_id = $1 ORDER BY coletado_em DESC LIMIT 1`, deviceID).Scan(&hardware)
	if err == nil {
		d.Evidencias = append(d.Evidencias, sinaisDoHardware(hardware)...)
	}

	// `device_health_state` é o veredito por categoria que o produto já
	// calcula. Ele não substitui a medida — entra como sinal próprio, porque
	// "storage crítico" é uma observação do sistema, e §7.3 manda usar o que o
	// sistema já diz em vez de readivinhar.
	rows, err := s.Pool.Query(ctx, `
		SELECT categoria, level FROM device_health_state
		WHERE device_id = $1 AND level <> 'normal'`, deviceID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var categoria, level string
			if rows.Scan(&categoria, &level) != nil {
				continue
			}
			sinal := sinalDaCategoria(categoria)
			if sinal == "" {
				continue
			}
			d.Evidencias = append(d.Evidencias, EvidenciaDoDossie{
				Sinal:   sinal,
				Literal: fmt.Sprintf("estado de %s: %s", categoria, level),
			})
		}
	}

	d.StatusProvavel = statusProvavel(d.Evidencias)
	return d
}

// sinalDaCategoria traduz a categoria de `device_health_state` em sinal.
//
// `storage` é o caso que exige cuidado, e errar aqui custa caro: a categoria
// fica crítica por disco CHEIO, não por disco com defeito. As três máquinas do
// parque estão em `storage=critical` com SMART `Healthy` e 95–97% de ocupação —
// mapear isso para `erro_io_log` produziria "erro de dispositivo" em três
// computadores sadios, e mandaria trocar disco que só precisa de faxina.
//
// Então `storage` vira SATURAÇÃO. Quem afirma defeito de disco é a medida
// direta — SMART fora de `Healthy` ou desgaste abaixo do gate — extraída em
// `sinaisDoHardware`, e só ela.
func sinalDaCategoria(categoria string) string {
	switch categoria {
	case "storage":
		return "processo_pesado"
	case "memory":
		return "uso_memoria"
	case "processing":
		return "uso_cpu"
	case "thermal":
		return "temperatura"
	default:
		return ""
	}
}

// sinaisDoHardware extrai medidas literais do snapshot de hardware.
func sinaisDoHardware(bruto []byte) []EvidenciaDoDossie {
	var hw struct {
		Storage []struct {
			Model       string   `json:"model"`
			SmartStatus string   `json:"smart_status"`
			LifePct     *float64 `json:"life_pct"`
			Temperature *float64 `json:"temperature"`
			UsedPct     *float64 `json:"used_pct"`
			MediaType   string   `json:"media_type"`
		} `json:"storage"`
		MemorySummary struct {
			UsedPct *float64 `json:"used_pct"`
		} `json:"memory_summary"`
		CPU struct {
			UsedPct     *float64 `json:"used_pct"`
			Temperature *float64 `json:"temperature"`
		} `json:"cpu"`
	}
	if json.Unmarshal(bruto, &hw) != nil {
		return nil
	}

	var ev []EvidenciaDoDossie
	for _, disco := range hw.Storage {
		// SMART que não está saudável é a evidência mais forte que existe sem
		// escada — e é literal, citável na tela.
		if disco.SmartStatus != "" && disco.SmartStatus != "Healthy" {
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_geral",
				Literal: fmt.Sprintf("%s: SMART %s", disco.Model, disco.SmartStatus),
			})
		}
		// Desgaste de SSD. O limiar de 10% é o mesmo gate de segurança de §5,
		// que já trata desgaste abaixo disso como disco degradado.
		if disco.LifePct != nil && *disco.LifePct < 10 {
			v := *disco.LifePct
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_desgaste",
				Literal: fmt.Sprintf("%s: vida útil restante %.0f%%", disco.Model, v),
				Valor:   &v,
			})
		}
		if disco.Temperature != nil && *disco.Temperature >= 60 {
			v := *disco.Temperature
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "temperatura",
				Literal: fmt.Sprintf("%s: %.0f °C", disco.Model, v),
				Valor:   &v,
			})
		}
		// Disco cheio não é falha de disco — é recurso saturado, e a diferença
		// muda a conduta inteira: um se troca, o outro se limpa.
		if disco.UsedPct != nil && *disco.UsedPct >= 90 {
			v := *disco.UsedPct
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "processo_pesado",
				Literal: fmt.Sprintf("%s: %.0f%% ocupado", disco.Model, v),
				Valor:   &v,
			})
		}
	}
	if p := hw.MemorySummary.UsedPct; p != nil && *p >= 85 {
		v := *p
		ev = append(ev, EvidenciaDoDossie{
			Sinal: "uso_memoria", Literal: fmt.Sprintf("memória em %.0f%% de uso", v), Valor: &v,
		})
	}
	if p := hw.CPU.UsedPct; p != nil && *p >= 90 {
		v := *p
		ev = append(ev, EvidenciaDoDossie{
			Sinal: "uso_cpu", Literal: fmt.Sprintf("CPU em %.0f%% de uso", v), Valor: &v,
		})
	}
	if t := hw.CPU.Temperature; t != nil && *t >= 85 {
		v := *t
		ev = append(ev, EvidenciaDoDossie{
			Sinal: "temperatura", Literal: fmt.Sprintf("CPU a %.0f °C", v), Valor: &v,
		})
	}
	return ev
}

// statusProvavel escolhe o status a partir dos sinais observados.
//
// Sem histórico de travas ou desligamentos — que só a telemetria contínua (B4)
// vai trazer — o que dá para afirmar honestamente é limitado, e a ordem abaixo
// reflete isso: só se declara status quando um sinal o implica diretamente.
// Nenhum sinal implicando nada devolve "", e "" vira dossiê sem diagnóstico em
// vez de um palpite.
func statusProvavel(evidencias []EvidenciaDoDossie) string {
	tem := map[string]bool{}
	for _, e := range evidencias {
		tem[e.Sinal] = true
	}
	switch {
	case tem["smart_geral"] || tem["smart_desgaste"] || tem["erro_io_log"]:
		// O sistema já acusou a peça. §7.3: se o sistema diz, não se adivinha.
		return "erro_de_dispositivo"
	case tem["temperatura"]:
		return "superaquecimento"
	case tem["uso_memoria"] || tem["uso_cpu"] || tem["processo_pesado"]:
		return "lentidao_persistente"
	default:
		return ""
	}
}

// catalogoDoStatus lê a ontologia revisada para um status.
//
// Só linha SERVÍVEL entra: revisada por gente ou derivada por automação
// identificada (0078). Rascunho sem nenhum dos dois não diagnostica ninguém.
func (s *Server) catalogoDoStatus(ctx context.Context, status string) (
	causas []string, priors map[string]float64, nCasos map[string]int,
) {
	var bruto []byte
	err := s.Pool.QueryRow(ctx, `
		SELECT causas_candidatas FROM negative_status
		WHERE codigo = $1
		  AND (revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL)`,
		status).Scan(&bruto)
	if err != nil {
		return nil, nil, nil
	}
	_ = json.Unmarshal(bruto, &causas)

	priors = map[string]float64{}
	nCasos = map[string]int{}
	rows, err := s.Pool.Query(ctx, `
		SELECT causa_codigo, frequencia, n_interno
		FROM corpus.corpus_prior WHERE status_codigo = $1`, status)
	if err != nil {
		return causas, priors, nCasos
	}
	defer rows.Close()
	for rows.Next() {
		var causa string
		var freq float64
		var nInterno int
		if rows.Scan(&causa, &freq, &nInterno) != nil {
			continue
		}
		priors[causa] = freq
		nCasos[causa] = nInterno
	}
	return causas, priors, nCasos
}

// pesosDeSinal lê `log_signature` no formato (sinal, causa) -> peso.
func (s *Server) pesosDeSinal(ctx context.Context, status string) map[string]map[string]float64 {
	rows, err := s.Pool.Query(ctx, `
		SELECT padrao, causas_implicadas, peso FROM log_signature
		WHERE status_implicado = $1
		  AND (revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL)`, status)
	if err != nil {
		return nil
	}
	defer rows.Close()

	pesos := map[string]map[string]float64{}
	for rows.Next() {
		var sinal string
		var causasBruto []byte
		var peso float64
		if rows.Scan(&sinal, &causasBruto, &peso) != nil {
			continue
		}
		var causas []string
		_ = json.Unmarshal(causasBruto, &causas)
		for _, c := range causas {
			if pesos[sinal] == nil {
				pesos[sinal] = map[string]float64{}
			}
			pesos[sinal][c] = peso
		}
	}
	return pesos
}

// DiagnosticoDoDispositivo é o retrato que vai no snapshot do canal.
//
// É o "diagnóstico inicial" de §10.5.1: linguagem de HIPÓTESE, nunca veredito.
// Sem intervenção não existe limiar, e o teto de 0,85 já é aplicado pelo motor.
type DiagnosticoDoDispositivo struct {
	DeviceID string `json:"device_id"`
	// Vazio quando nenhum sinal implica status. Vazio é resposta: significa
	// "nada observado", e é diferente de "não sei o que é".
	Status          string              `json:"status"`
	StatusDescricao string              `json:"status_descricao"`
	Causas          []CausaInferida     `json:"causas"`
	Abstain         bool                `json:"abstain"`
	Motor           string              `json:"motor"`
	ProximosTestes  []string            `json:"proximos_testes"`
	Evidencias      []EvidenciaDoDossie `json:"evidencias"`
	// A suposição da rede quando ela roda no escuro. Vai para a tela do
	// SUPERVISOR como comparação, e para `rat_comparacao` como rótulo — nunca
	// como veredito (§14.1).
	Sombra any `json:"sombra,omitempty"`
	// Momento em que este retrato foi produzido. É a origem que permite
	// invalidá-lo (§10.4) em vez de substituí-lo às cegas.
	ProduzidoEm time.Time `json:"produzido_em"`
}

// diagnosticosParaSnapshot produz o dossiê passivo de cada dispositivo visível.
//
// Roda no servidor, no momento em que o canal abre — nunca quando a tela monta.
func (s *Server) diagnosticosParaSnapshot(ctx context.Context, deviceIDs []string) []DiagnosticoDoDispositivo {
	saida := make([]DiagnosticoDoDispositivo, 0, len(deviceIDs))
	for _, id := range deviceIDs {
		d := s.evidenciasDoDispositivo(ctx, id)
		retrato := DiagnosticoDoDispositivo{
			DeviceID: id, Status: d.StatusProvavel,
			Evidencias: d.Evidencias, ProduzidoEm: time.Now().UTC(),
		}
		if d.StatusProvavel == "" {
			// Nada observado. Não se chama o motor para ele responder sobre
			// coisa nenhuma — abstenção aqui seria ruído, não informação.
			retrato.Motor = "nenhum"
			saida = append(saida, retrato)
			continue
		}

		causas, priors, nCasos := s.catalogoDoStatus(ctx, d.StatusProvavel)
		_ = s.Pool.QueryRow(ctx, `SELECT descricao FROM negative_status WHERE codigo=$1`,
			d.StatusProvavel).Scan(&retrato.StatusDescricao)

		r := s.Inferir(ctx, MontarPedido(
			id, d.StatusProvavel, causas, priors,
			s.pesosDeSinal(ctx, d.StatusProvavel), nCasos, d.Evidencias, false,
		))
		s.renderizarCausas(ctx, r.Causas, d.Evidencias)
		retrato.Causas = r.Causas
		retrato.Abstain = r.Abstain
		retrato.Motor = r.Motor
		retrato.ProximosTestes = r.ProximosTestes
		if r.Sombra != nil {
			retrato.Sombra = r.Sombra
		}
		saida = append(saida, retrato)
	}
	return saida
}

// renderizarCausas preenche o título de cada causa a partir de `text_template`.
//
// É a regra dura de §12.1 em vigor: NENHUMA frase mostrada ao técnico é
// composta no cliente nem gerada por modelo em runtime. O motor devolve chave
// de template e valores; o texto sai daqui, determinístico e revisado.
//
// Slot sem valor faz o render FALHAR, e falhar é o comportamento certo: melhor
// não mostrar frase do que mostrar frase com buraco. Quando falha, a causa fica
// com o título vazio e a tela cai no código da causa — visivelmente cru, em vez
// de silenciosamente errado.
func (s *Server) renderizarCausas(ctx context.Context, causas []CausaInferida, evidencias []EvidenciaDoDossie) {
	if len(causas) == 0 {
		return
	}
	// O valor medido que sustenta a causa. Sem escada não existe limiar
	// esperado, então o slot recebe a marca explícita de ausência — nunca um
	// número inventado para o template fechar.
	literal := "—"
	if len(evidencias) > 0 {
		literal = evidencias[0].Literal
	}

	for i := range causas {
		var t Template
		err := s.Pool.QueryRow(ctx, `
			SELECT chave, idioma, nivel, titulo, corpo, versao,
			       coalesce(revisado_por::text, revisado_por_automacao, '')
			FROM text_template
			WHERE chave = $1 AND nivel = 'tecnico'
			  AND (revisado_por IS NOT NULL OR revisado_por_automacao IS NOT NULL)
			ORDER BY versao DESC LIMIT 1`, causas[i].Template).
			Scan(&t.Chave, &t.Idioma, &t.Nivel, &t.Titulo, &t.Corpo, &t.Versao, &t.RevisadoPor)
		if err != nil {
			continue
		}
		valores := map[string]string{
			"probabilidade":   fmt.Sprintf("%.0f%%", causas[i].Prob*100),
			"valor_medido":    literal,
			"limiar_esperado": "sem escada executada",
		}
		titulo, _, err := Renderizar(t, valores)
		if err != nil {
			continue
		}
		if causas[i].Slots == nil {
			causas[i].Slots = map[string]any{}
		}
		causas[i].Slots["titulo"] = titulo
	}
}
