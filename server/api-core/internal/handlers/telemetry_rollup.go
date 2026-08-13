package handlers

import (
	"context"
	"encoding/json"
	"time"
)

// rollHardwareJSON decodifica o snapshot cru e o acumula nos buckets. Aceita o
// JSON direto porque os dois caminhos de entrada (HTTP e WebSocket) recebem a
// telemetria assim.
func (s *Server) rollHardwareJSON(ctx context.Context, deviceID string, raw []byte) {
	var h hardwareSample
	if json.Unmarshal(raw, &h) != nil {
		return
	}
	s.rollTelemetry(ctx, deviceID, h)
}

// Categorias de saúde. Mantidas iguais às que a tela do cliente já consome
// (statistics.health.metrics), para não quebrar o contrato existente.
const (
	catProcessing  = "processing"
	catMemory      = "memory"
	catStorage     = "storage"
	catTemperature = "temperature"
)

// Histerese assimétrica: sobe rápido para não atrasar um problema real, desce
// devagar para não piscar. A 30s por amostra, 3 subidas ≈ 1,5 min e 20 descidas
// ≈ 10 min.
const (
	subidasParaConfirmar  = 3
	descidasParaConfirmar = 20
)

// rollTelemetry acumula o snapshot recém-recebido nos buckets horários. Custo
// constante: escreve só na hora corrente, independente do tamanho do histórico.
func (s *Server) rollTelemetry(ctx context.Context, deviceID string, h hardwareSample) {
	at := time.Now().UTC()
	roll := func(metrica string, valor *float64) {
		if valor == nil {
			return
		}
		_, _ = s.Pool.Exec(ctx, `SELECT roll_metric($1,$2,$3,$4)`,
			deviceID, metrica, *valor, at)
	}
	roll(catProcessing, h.CPU.Usage)
	roll(catMemory, h.MemorySummary.Usage)
	roll("cpu_temperature", h.CPU.Temperature)
	for _, gpu := range h.GPUs {
		roll("gpu_temperature", gpu.Temperature)
	}
	// Ocupação de disco entra como a maior entre discos e volumes: é o número
	// que determina se a máquina está sem espaço.
	var maiorUso float64
	temDisco := false
	for _, d := range h.Storage {
		roll("storage_temperature", d.Temperature)
		if d.UsedPct > maiorUso {
			maiorUso, temDisco = d.UsedPct, true
		}
		for _, v := range d.Volumes {
			if v.UsedPct > maiorUso {
				maiorUso, temDisco = v.UsedPct, true
			}
		}
	}
	if temDisco {
		roll(catStorage, &maiorUso)
	}

	// ATIVIDADE do disco, acumulada no histograma pelo mesmo caminho de CPU e
	// memória.
	//
	// Por que acumular e não só olhar o instantâneo: a máquina do parque com a
	// lentidão mais severa mediu 2,5 ms de latência no momento em que a medida
	// entrou no ar — ou seja, saudável naquele segundo. A lentidão dela é
	// EPISÓDICA, e episódio não aparece em amostra isolada; aparece na
	// contagem de quantas amostras passaram do limiar, que é exatamente o que
	// `acima_75/85/95` guarda.
	//
	// É a mesma lição da forma do episódio, aplicada uma camada abaixo: o que
	// diagnostica não é o valor, é a distribuição dele no tempo.
	if da := h.DiskActivity; da != nil {
		roll("disk_busy", da.BusyPct)
		// Latência só entra quando houve transferência. Sem operação na janela
		// não há latência para medir, e gravar zero contaminaria a média com
		// "instantâneo" toda vez que a máquina estivesse parada — enviesando o
		// histograma exatamente no sentido de esconder o problema.
		if da.Samples > 0 {
			roll("disk_latency_ms", da.LatencyMs)
		}
	}
}

// readHealthLevel devolve o nível já persistido, sem reavaliar nada.
//
// Listagens de dispositivos precisam do nível de cada device; rodar a análise
// ali seria caro (várias consultas por device) e, pior, escreveria estado de
// histerese num caminho de leitura. A avaliação acontece uma vez por
// telemetria, que é onde há dado novo.
func (s *Server) readHealthLevel(ctx context.Context, deviceID string) string {
	var level string
	if s.Pool.QueryRow(ctx, `
		SELECT level FROM device_health_state
		WHERE device_id=$1
		ORDER BY CASE level
			WHEN 'maximum' THEN 3 WHEN 'critical' THEN 2 WHEN 'warning' THEN 1 ELSE 0 END DESC
		LIMIT 1`, deviceID).Scan(&level) != nil {
		return "normal"
	}
	return level
}

// janelaMetrica é o resumo de uma métrica num horizonte de tempo.
type janelaMetrica struct {
	Samples    int
	Media      float64
	Pico       float64
	PctAcima75 float64
	PctAcima85 float64
	PctAcima95 float64
}

// metricWindow lê o rollup de uma métrica num horizonte. Lê buckets horários,
// não snapshots brutos: 30 dias são ~720 linhas em vez de ~86.400.
func (s *Server) metricWindow(ctx context.Context, deviceID, metrica string, horas int) janelaMetrica {
	var w janelaMetrica
	var soma float64
	var a75, a85, a95 int
	var pico *float64
	err := s.Pool.QueryRow(ctx, `
		SELECT coalesce(sum(samples),0), coalesce(sum(soma),0), max(maximo),
		       coalesce(sum(acima_75),0), coalesce(sum(acima_85),0), coalesce(sum(acima_95),0)
		FROM device_metric_rollup
		WHERE device_id=$1 AND metrica=$2
		  AND bucket_hora >= date_trunc('hour', now()) - make_interval(hours => $3)`,
		deviceID, metrica, horas).Scan(&w.Samples, &soma, &pico, &a75, &a85, &a95)
	if err != nil || w.Samples == 0 {
		return janelaMetrica{}
	}
	if pico != nil {
		w.Pico = *pico
	}
	total := float64(w.Samples)
	w.Media = soma / total
	w.PctAcima75 = float64(a75) / total * 100
	w.PctAcima85 = float64(a85) / total * 100
	w.PctAcima95 = float64(a95) / total * 100
	return w
}

// occupancyLevel classifica ocupação de armazenamento pelo NÍVEL, não pelo
// tempo de exposição.
//
// Espaço em disco é uma condição, não um evento: um disco a 88% fica 100% do
// tempo acima de 85%, o que sob a regra de exposição viraria "maximum" — o
// grau reservado a uma máquina em colapso. Um computador ótimo com o disco
// relativamente cheio não é uma emergência, e tratá-lo como tal é justamente o
// que fazia a tela do cliente gritar sem motivo.
func occupancyLevel(w janelaMetrica) string {
	if w.Samples < 10 {
		return ""
	}
	switch {
	case w.Media >= 95:
		return "critical"
	case w.Media >= 85:
		return "warning"
	}
	return "normal"
}

// exposureLevel classifica pelo tempo de exposição em vez da média.
//
// Uma máquina que passa metade do dia acima de 85% tem um problema real mesmo
// que a média das 24h fique em 60% por causa das horas ociosas — e é
// exatamente esse caso que a média de 15 minutos não enxergava.
func exposureLevel(w janelaMetrica) string {
	if w.Samples < 10 {
		return ""
	}
	switch {
	case w.PctAcima95 >= 40 || w.PctAcima85 >= 70:
		return "maximum"
	case w.PctAcima95 >= 15 || w.PctAcima85 >= 40:
		return "critical"
	case w.PctAcima85 >= 15 || w.PctAcima75 >= 40:
		return "warning"
	}
	return "normal"
}

// applyHysteresis persiste o nível de uma categoria com subida rápida e descida
// lenta. Devolve o nível efetivo e desde quando ele vale.
//
// candidato vazio significa "sem amostra suficiente": nesse caso o nível
// anterior é MANTIDO. Zerar por falta de dado é o que hoje faz uma máquina
// voltar a "normal" só porque dormiu ou perdeu conexão.
func (s *Server) applyHysteresis(ctx context.Context, deviceID, categoria, candidato string) (string, time.Time) {
	var atual, pendente string
	var consecutivas int
	var desde time.Time
	err := s.Pool.QueryRow(ctx, `
		SELECT level, coalesce(nivel_candidato,''), consecutivas, desde
		FROM device_health_state WHERE device_id=$1 AND categoria=$2`,
		deviceID, categoria).Scan(&atual, &pendente, &consecutivas, &desde)
	if err != nil {
		atual, pendente, consecutivas, desde = "normal", "", 0, time.Now().UTC()
		_, _ = s.Pool.Exec(ctx, `
			INSERT INTO device_health_state(device_id,categoria,level)
			VALUES($1,$2,'normal') ON CONFLICT DO NOTHING`, deviceID, categoria)
	}
	if candidato == "" || candidato == atual {
		_, _ = s.Pool.Exec(ctx, `
			UPDATE device_health_state
			SET nivel_candidato=NULL, consecutivas=0, avaliado_em=now()
			WHERE device_id=$1 AND categoria=$2`, deviceID, categoria)
		return atual, desde
	}
	if candidato == pendente {
		consecutivas++
	} else {
		consecutivas = 1
	}
	necessarias := descidasParaConfirmar
	if severityRank(candidato) > severityRank(atual) {
		necessarias = subidasParaConfirmar
	}
	if consecutivas >= necessarias {
		agora := time.Now().UTC()
		_, _ = s.Pool.Exec(ctx, `
			UPDATE device_health_state
			SET level=$3, nivel_candidato=NULL, consecutivas=0,
			    desde=now(), ultima_mudanca=now(), avaliado_em=now()
			WHERE device_id=$1 AND categoria=$2`, deviceID, categoria, candidato)
		return candidato, agora
	}
	_, _ = s.Pool.Exec(ctx, `
		UPDATE device_health_state
		SET nivel_candidato=$3, consecutivas=$4, avaliado_em=now()
		WHERE device_id=$1 AND categoria=$2`, deviceID, categoria, candidato, consecutivas)
	return atual, desde
}
