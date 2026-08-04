package handlers

import (
	"context"
	"encoding/json"
	"strconv"
	"time"
)

type hardwareSample struct {
	CPU struct {
		Usage       *float64 `json:"usage"`
		Clock       *float64 `json:"clock_mhz"`
		Temperature *float64 `json:"temperature"`
		Source      string   `json:"measurement_source"`
	} `json:"cpu"`
	GPUs []struct {
		ID          string   `json:"id"`
		Usage       *float64 `json:"usage"`
		Clock       *float64 `json:"clock_mhz"`
		Temperature *float64 `json:"temperature"`
		Source      string   `json:"measurement_source"`
	} `json:"gpus"`
	MemorySummary struct {
		Used  uint64   `json:"used_bytes"`
		Total uint64   `json:"total_bytes"`
		Usage *float64 `json:"usage"`
	} `json:"memory_summary"`
	Memory []struct {
		ID   string `json:"id"`
		Used uint64 `json:"used_bytes"`
	} `json:"memory"`
	Storage []struct {
		ID          string   `json:"id"`
		Model       string   `json:"model"`
		UsedPct     float64  `json:"used_pct"`
		SMARTStatus string   `json:"smart_status"`
		LifePct     *float64 `json:"life_pct"`
		Temperature *float64 `json:"temperature"`
		Volumes     []struct {
			Label   string  `json:"label"`
			UsedPct float64 `json:"used_pct"`
		} `json:"volumes"`
	} `json:"storage"`
	Networks []struct {
		ID, Status string
		Rx         uint64 `json:"rx_bytes_total"`
		Tx         uint64 `json:"tx_bytes_total"`
	} `json:"networks"`
}

type metricStats struct {
	Average float64 `json:"average"`
	Minimum float64 `json:"minimum"`
	Peak    float64 `json:"peak"`
	Samples int     `json:"samples"`
}

type networkStats struct {
	AverageBps      float64 `json:"average_bps"`
	MinBps          float64 `json:"min_bps"`
	MaxBps          float64 `json:"max_bps"`
	Down            bool    `json:"down"`
	LastDownAt      string  `json:"last_down_at,omitempty"`
	DowntimeSeconds int64   `json:"downtime_seconds"`
}

type timedHardwareSample struct {
	h  hardwareSample
	at time.Time
}

func (s *Server) hardwareStatistics(ctx context.Context, deviceID string) map[string]any {
	rows, err := s.Pool.Query(ctx, `
		SELECT hardware, coletado_em FROM telemetry_snapshots
		WHERE device_id=$1 AND coletado_em >= now()-interval '30 days'
		ORDER BY coletado_em`, deviceID)
	if err != nil {
		return map[string]any{}
	}
	defer rows.Close()
	samples := []timedHardwareSample{}
	for rows.Next() {
		var raw []byte
		var at time.Time
		if rows.Scan(&raw, &at) == nil {
			var h hardwareSample
			if json.Unmarshal(raw, &h) == nil {
				samples = append(samples, timedHardwareSample{h, at})
			}
		}
	}
	cpuUsage, cpuClock := metricStats{}, metricStats{}
	recentCPUUsage, recentMemoryUsage := metricStats{}, metricStats{}
	recentCPUTemperature, recentGPUTemperature := metricStats{}, metricStats{}
	recentStorageTemperature := metricStats{}
	recentSamples := 0
	gpuUsage := map[string]metricStats{}
	gpuClock := map[string]metricStats{}
	mem := map[string]metricStats{}
	nets := map[string]networkStats{}
	for i, sample := range samples {
		accumulate(&cpuUsage, sample.h.CPU.Usage)
		if sample.h.CPU.Source != "" {
			accumulate(&cpuClock, sample.h.CPU.Clock)
		}
		for _, g := range sample.h.GPUs {
			u, c := gpuUsage[g.ID], gpuClock[g.ID]
			if g.Source != "" {
				accumulate(&u, g.Usage)
				accumulate(&c, g.Clock)
			}
			gpuUsage[g.ID], gpuClock[g.ID] = u, c
		}
		if sample.h.MemorySummary.Total > 0 {
			v := mem["system"]
			used := float64(sample.h.MemorySummary.Used)
			accumulate(&v, &used)
			mem["system"] = v
		} else {
			for _, m := range sample.h.Memory {
				v := mem[m.ID]
				used := float64(m.Used)
				accumulate(&v, &used)
				mem[m.ID] = v
			}
		}
		if i == 0 {
			continue
		}
		seconds := sample.at.Sub(samples[i-1].at).Seconds()
		if seconds <= 0 {
			continue
		}
		prev := map[string]struct{ rx, tx uint64 }{}
		for _, n := range samples[i-1].h.Networks {
			prev[n.ID] = struct{ rx, tx uint64 }{n.Rx, n.Tx}
		}
		for _, n := range sample.h.Networks {
			st := nets[n.ID]
			if n.Status != "Up" {
				if !st.Down {
					st.LastDownAt = sample.at.UTC().Format(time.RFC3339)
				}
				st.Down = true
				st.DowntimeSeconds += int64(seconds)
			} else {
				st.Down = false
			}
			if p, ok := prev[n.ID]; ok && n.Rx >= p.rx && n.Tx >= p.tx {
				rate := float64((n.Rx-p.rx)+(n.Tx-p.tx)) / seconds
				if st.MinBps == 0 || rate < st.MinBps {
					st.MinBps = rate
				}
				if rate > st.MaxBps {
					st.MaxBps = rate
				}
				st.AverageBps += rate
			}
			nets[n.ID] = st
		}
	}
	if len(samples) > 0 {
		// Alerts describe sustained behavior in a short rolling window. The
		// 30-day statistics above remain available for long-term trends.
		recentSince := samples[len(samples)-1].at.Add(-15 * time.Minute)
		for _, sample := range samples {
			if sample.at.Before(recentSince) {
				continue
			}
			recentSamples++
			accumulate(&recentCPUUsage, sample.h.CPU.Usage)
			accumulate(&recentMemoryUsage, sample.h.MemorySummary.Usage)
			accumulate(&recentCPUTemperature, sample.h.CPU.Temperature)
			for _, gpu := range sample.h.GPUs {
				accumulate(&recentGPUTemperature, gpu.Temperature)
			}
			for _, disk := range sample.h.Storage {
				accumulate(&recentStorageTemperature, disk.Temperature)
			}
		}
	}
	finalize := func(m metricStats) metricStats {
		if m.Samples > 0 {
			m.Average /= float64(m.Samples)
		}
		return m
	}
	cpuUsage, cpuClock = finalize(cpuUsage), finalize(cpuClock)
	recentCPUUsage = finalize(recentCPUUsage)
	recentMemoryUsage = finalize(recentMemoryUsage)
	recentCPUTemperature = finalize(recentCPUTemperature)
	recentGPUTemperature = finalize(recentGPUTemperature)
	recentStorageTemperature = finalize(recentStorageTemperature)
	for k, v := range gpuUsage {
		gpuUsage[k] = finalize(v)
	}
	for k, v := range gpuClock {
		gpuClock[k] = finalize(v)
	}
	for k, v := range mem {
		mem[k] = finalize(v)
	}
	intervals := float64(len(samples) - 1)
	for k, v := range nets {
		if intervals > 0 {
			v.AverageBps /= intervals
		}
		nets[k] = v
	}
	result := map[string]any{
		"window_days": 30, "samples": len(samples),
		"cpu":       map[string]any{"usage": cpuUsage, "clock_mhz": cpuClock},
		"gpu_usage": gpuUsage, "gpu_clock_mhz": gpuClock,
		"memory_used_bytes": mem, "networks": nets,
	}
	// A saúde vem da análise persistida sobre o histórico agregado, com
	// histerese — não mais de um recálculo da janela de 15 minutos a cada
	// telemetria. É o que faz a tela parar de oscilar.
	health := s.persistedHealth(ctx, deviceID)
	health["client_title"], health["client_summary"] = resumoCliente(health)
	result["health"] = health
	return result
}

// resumoCliente monta o título e o texto de cabeçalho da tela do cliente a
// partir do nível já persistido, em vez de a tela decidi-los por conta própria.
func resumoCliente(health map[string]any) (string, string) {
	nivel, _ := health["client_level"].(string)
	switch nivel {
	case "maximum", "critical":
		return "Entre em contato com seu técnico",
			"Foi identificada uma condição persistente neste computador."
	case "warning":
		return "Vale falar com seu técnico",
			"Uma condição vem se mantendo e merece atenção."
	}
	return "Tudo certo por aqui", "O TGDesk está acompanhando este computador."
}

func accumulate(s *metricStats, v *float64) {
	if v == nil {
		return
	}
	s.Average += *v
	if s.Samples == 0 || *v < s.Minimum {
		s.Minimum = *v
	}
	if s.Samples == 0 || *v > s.Peak {
		s.Peak = *v
	}
	s.Samples++
}

// persistedHealth avalia a saúde do dispositivo sobre o histórico agregado, em
// vários horizontes, e persiste o resultado com histerese.
//
// Substitui a avaliação sobre a janela móvel de 15 minutos, que era
// recalculada do zero a cada telemetria. Três defeitos daquela abordagem:
// limiar seco (a média passeando em torno de 75% alternava o nível a cada
// 30s), reset por contagem de amostras (máquina que dorme voltava a "normal"),
// e ocupação de disco tratada como alerta oscilante em vez de condição
// persistente.
func (s *Server) persistedHealth(ctx context.Context, deviceID string) map[string]any {
	// 1h capta o agora; 24h e 7d é onde um padrão real aparece. O nível de uma
	// categoria é o mais severo entre os horizontes.
	horizontes := []struct {
		nome  string
		horas int
	}{{"1h", 1}, {"24h", 24}, {"7d", 168}}

	metrics := map[string]any{}
	issues := []map[string]any{}
	nivelGeral, nivelCliente := "normal", "normal"

	avaliar := func(categoria, metrica, rotulo string) {
		candidato := ""
		var melhor janelaMetrica
		var janelaEscolhida string
		detalhe := map[string]any{}
		for _, h := range horizontes {
			w := s.metricWindow(ctx, deviceID, metrica, h.horas)
			detalhe[h.nome] = map[string]any{
				"samples": w.Samples, "media": w.Media, "pico": w.Pico,
				"pct_acima_85": w.PctAcima85, "pct_acima_95": w.PctAcima95,
			}
			nivel := exposureLevel(w)
			if categoria == catStorage {
				nivel = occupancyLevel(w)
			}
			if nivel != "" && severityRank(nivel) > severityRank(candidato) {
				candidato, melhor, janelaEscolhida = nivel, w, h.nome
			}
		}
		nivel, desde := s.applyHysteresis(ctx, deviceID, categoria, candidato)
		detalhe["level"] = nivel
		detalhe["desde"] = desde.Format(time.RFC3339)
		// A tela do cliente derivava esses textos localmente, por if de nível,
		// sem saber há quanto tempo a condição dura nem para onde ela caminha.
		// Quem tem o histórico é o servidor, então é ele quem narra.
		detalhe["titulo"] = rotulo
		detalhe["estado"] = estadoLegivel(categoria, nivel)
		detalhe["detalhe"] = narrativaCliente(categoria, nivel, desde)
		detalhe["tendencia"] = tendencia(
			s.metricWindow(ctx, deviceID, metrica, 24),
			s.metricWindow(ctx, deviceID, metrica, 168))
		metrics[categoria] = detalhe
		if severityRank(nivel) > severityRank(nivelGeral) {
			nivelGeral = nivel
		}
		// Ocupação de disco é CONDIÇÃO, não evento: um disco cheio numa máquina
		// ótima não deve gritar "procure seu técnico" com o mesmo peso de uma
		// CPU sobrecarregada. Entra no relatório técnico, mas não eleva o nível
		// mostrado ao cliente.
		if categoria != catStorage && severityRank(nivel) > severityRank(nivelCliente) {
			nivelCliente = nivel
		}
		if severityRank(nivel) > 0 {
			tecnica := rotulo + ": " + descreveExposicao(melhor, janelaEscolhida)
			cliente := rotulo + " vem apresentando uso elevado de forma persistente."
			if categoria == catStorage {
				tecnica = rotulo + ": " + fmtPct(melhor.Media) +
					" de ocupação média nas últimas " + janelaEscolhida
				cliente = "O espaço de armazenamento está ficando reduzido."
			}
			issues = append(issues, map[string]any{
				"severity": nivel, "client_severity": nivel, "category": categoria,
				"technical_message": tecnica, "client_message": cliente,
				"desde": desde.Format(time.RFC3339),
			})
		}
	}

	avaliar(catProcessing, catProcessing, "Processamento")
	avaliar(catMemory, catMemory, "Memória")
	avaliar(catStorage, catStorage, "Armazenamento")

	return map[string]any{
		"level": nivelGeral, "client_level": nivelCliente,
		"issues": issues, "metrics": metrics,
		"evaluated_at": time.Now().UTC().Format(time.RFC3339),
	}
}

// estadoLegivel é o rótulo curto do card, em linguagem de cliente.
func estadoLegivel(categoria, nivel string) string {
	if categoria == catStorage {
		switch nivel {
		case "maximum", "critical":
			return "Espaço quase no fim"
		case "warning":
			return "Espaço reduzido"
		}
		return "Espaço disponível"
	}
	if categoria == catMemory {
		switch nivel {
		case "maximum", "critical":
			return "Memória sobrecarregada"
		case "warning":
			return "Uso elevado"
		}
		return "Uso adequado"
	}
	switch nivel {
	case "maximum", "critical":
		return "Uso no limite"
	case "warning":
		return "Uso elevado"
	}
	return "Desempenho estável"
}

// narrativaCliente explica a condição e há quanto tempo ela dura. O "desde" é o
// que faltava: saber que algo está assim há seis dias muda completamente a
// leitura em relação a um alerta que apareceu agora.
func narrativaCliente(categoria, nivel string, desde time.Time) string {
	if severityRank(nivel) == 0 {
		switch categoria {
		case catStorage:
			return "Há espaço livre suficiente neste computador."
		case catMemory:
			return "Há memória suficiente para as atividades atuais."
		}
		return "O computador está respondendo como esperado."
	}
	base := "Esta condição se mantém " + haQuantoTempo(desde) + "."
	if categoria == catStorage {
		return "O disco está ficando cheio. " + base +
			" Liberar espaço costuma resolver."
	}
	return base + " Seu técnico consegue ver o histórico completo."
}

// haQuantoTempo devolve a duração em linguagem corrente, sem precisão falsa.
func haQuantoTempo(desde time.Time) string {
	d := time.Since(desde)
	switch {
	case d < time.Hour:
		return "há menos de uma hora"
	case d < 24*time.Hour:
		return "há " + strconv.Itoa(int(d.Hours())) + "h"
	case d < 48*time.Hour:
		return "há um dia"
	default:
		return "há " + strconv.Itoa(int(d.Hours()/24)) + " dias"
	}
}

// tendencia compara o curto prazo com o longo para dizer se a situação está
// melhorando, estável ou piorando.
func tendencia(curto, longo janelaMetrica) string {
	if curto.Samples < 10 || longo.Samples < 10 {
		return "indefinida"
	}
	delta := curto.PctAcima85 - longo.PctAcima85
	switch {
	case delta > 10:
		return "piorando"
	case delta < -10:
		return "melhorando"
	}
	return "estavel"
}

// descreveExposicao narra o padrão real em vez de citar um limiar cru, para que
// o chamado sintetizado e o card digam desde quando e com que frequência.
func descreveExposicao(w janelaMetrica, janela string) string {
	switch {
	case w.PctAcima95 >= 15:
		return fmtPct(w.PctAcima95) + " do tempo acima de 95% nas últimas " + janela +
			" (pico de " + fmtPct(w.Pico) + ")"
	case w.PctAcima85 >= 15:
		return fmtPct(w.PctAcima85) + " do tempo acima de 85% nas últimas " + janela +
			" (pico de " + fmtPct(w.Pico) + ")"
	default:
		return fmtPct(w.PctAcima75) + " do tempo acima de 75% nas últimas " + janela +
			" (pico de " + fmtPct(w.Pico) + ")"
	}
}

func fmtPct(v float64) string {
	return strconv.FormatFloat(v, 'f', 0, 64) + "%"
}

func (s *Server) recentHardwareHealth(ctx context.Context, deviceID string) map[string]any {
	rows, err := s.Pool.Query(ctx, `
		SELECT hardware FROM telemetry_snapshots
		WHERE device_id=$1 AND coletado_em >= now()-interval '15 minutes'
		ORDER BY coletado_em`, deviceID)
	if err != nil {
		return map[string]any{}
	}
	defer rows.Close()
	var last hardwareSample
	samples := 0
	cpuUsage, memoryUsage := metricStats{}, metricStats{}
	cpuTemperature, gpuTemperature, storageTemperature := metricStats{}, metricStats{}, metricStats{}
	for rows.Next() {
		var raw []byte
		if rows.Scan(&raw) != nil {
			continue
		}
		var h hardwareSample
		if json.Unmarshal(raw, &h) != nil {
			continue
		}
		last = h
		samples++
		accumulate(&cpuUsage, h.CPU.Usage)
		accumulate(&memoryUsage, h.MemorySummary.Usage)
		accumulate(&cpuTemperature, h.CPU.Temperature)
		for _, gpu := range h.GPUs {
			accumulate(&gpuTemperature, gpu.Temperature)
		}
		for _, disk := range h.Storage {
			accumulate(&storageTemperature, disk.Temperature)
		}
	}
	finalize := func(m metricStats) metricStats {
		if m.Samples > 0 {
			m.Average /= float64(m.Samples)
		}
		return m
	}
	if samples == 0 {
		return map[string]any{}
	}
	return analyzeHardwareHealth(
		last,
		finalize(cpuUsage),
		finalize(memoryUsage),
		finalize(cpuTemperature),
		finalize(gpuTemperature),
		finalize(storageTemperature),
		samples,
	)
}

func severityRank(level string) int {
	switch level {
	case "maximum":
		return 3
	case "critical":
		return 2
	case "warning":
		return 1
	default:
		return 0
	}
}

func sustainedUsageLevel(average float64, samples int) string {
	if samples < 3 {
		return "normal"
	}
	switch {
	case average >= 95:
		return "maximum"
	case average >= 85:
		return "critical"
	case average >= 75:
		return "warning"
	default:
		return "normal"
	}
}

func analyzeHardwareHealth(
	h hardwareSample,
	cpuUsage metricStats,
	memoryUsage metricStats,
	cpuTemperature metricStats,
	gpuTemperature metricStats,
	storageTemperature metricStats,
	recentSamples int,
) map[string]any {
	level, clientLevel := "normal", "normal"
	issues := []map[string]any{}
	metrics := map[string]any{
		"processing":  map[string]any{"level": "normal", "average": cpuUsage.Average, "samples": cpuUsage.Samples},
		"memory":      map[string]any{"level": "normal", "average": memoryUsage.Average, "samples": memoryUsage.Samples},
		"storage":     map[string]any{"level": "normal"},
		"temperature": map[string]any{"level": "normal"},
	}
	add := func(severity, clientSeverity, category, clientMessage, technicalMessage string) {
		if severityRank(severity) > severityRank(level) {
			level = severity
		}
		if severityRank(clientSeverity) > severityRank(clientLevel) {
			clientLevel = clientSeverity
		}
		if metric, ok := metrics[category].(map[string]any); ok &&
			severityRank(severity) > severityRank(metric["level"].(string)) {
			metric["level"] = severity
		}
		issues = append(issues, map[string]any{
			"severity": severity, "client_severity": clientSeverity, "category": category,
			"client_message": clientMessage, "technical_message": technicalMessage,
		})
	}

	switch sustainedUsageLevel(cpuUsage.Average, cpuUsage.Samples) {
	case "maximum":
		add("maximum", "maximum", "processing", "O processamento permanece no limite.",
			"Média de CPU dos últimos 15 minutos acima de 95%.")
	case "critical":
		add("critical", "critical", "processing", "O processamento está sobrecarregado.",
			"Média de CPU dos últimos 15 minutos acima de 85%.")
	case "warning":
		add("warning", "warning", "processing", "O uso do computador está elevado.",
			"Média de CPU dos últimos 15 minutos acima de 75%.")
	}
	switch sustainedUsageLevel(memoryUsage.Average, memoryUsage.Samples) {
	case "maximum":
		add("maximum", "maximum", "memory", "A memória permanece no limite.",
			"Média de RAM dos últimos 15 minutos acima de 95%.")
	case "critical":
		add("critical", "critical", "memory", "A memória está sobrecarregada.",
			"Média de RAM dos últimos 15 minutos acima de 85%.")
	case "warning":
		add("warning", "warning", "memory", "O uso de memória está elevado.",
			"Média de RAM dos últimos 15 minutos acima de 75%.")
	}

	for _, d := range h.Storage {
		if d.SMARTStatus != "" && d.SMARTStatus != "Healthy" {
			add("critical", "critical", "storage", "O armazenamento precisa de verificação imediata.",
				"Disco "+d.Model+" reportou SMART/HealthStatus "+d.SMARTStatus+".")
		}
		highest := d.UsedPct
		label := d.Model
		for _, v := range d.Volumes {
			if v.UsedPct > highest {
				highest, label = v.UsedPct, v.Label
			}
		}
		switch {
		case highest >= 95:
			add("maximum", "maximum", "storage", "O computador está praticamente sem espaço disponível.",
				label+" está com mais de 95% do espaço ocupado.")
		case highest >= 85:
			add("warning", "warning", "storage", "O espaço de armazenamento está ficando baixo.",
				label+" está com mais de 85% do espaço ocupado.")
		}
		if d.LifePct != nil && *d.LifePct <= 10 {
			add("critical", "critical", "storage", "A vida útil do armazenamento está próxima do limite.",
				"Disco "+d.Model+" reportou no máximo 10% de vida útil restante.")
		} else if d.LifePct != nil && *d.LifePct <= 20 {
			add("warning", "warning", "storage", "O armazenamento apresenta desgaste relevante.",
				"Disco "+d.Model+" reportou no máximo 20% de vida útil restante.")
		}
	}

	if storageTemperature.Samples >= 3 && storageTemperature.Average >= 65 {
		add("critical", "critical", "temperature", "O armazenamento permanece em temperatura elevada.",
			"Média dos discos nos últimos 15 minutos acima de 65 °C.")
	} else if storageTemperature.Samples >= 3 && storageTemperature.Average >= 55 {
		add("warning", "warning", "temperature", "A temperatura do armazenamento merece atenção.",
			"Média dos discos nos últimos 15 minutos acima de 55 °C.")
	}
	if gpuTemperature.Samples >= 3 && gpuTemperature.Average >= 90 {
		add("critical", "critical", "temperature", "A temperatura gráfica permanece elevada.",
			"Média da GPU nos últimos 15 minutos acima de 90 °C.")
	} else if gpuTemperature.Samples >= 3 && gpuTemperature.Average >= 80 {
		add("warning", "warning", "temperature", "A temperatura gráfica merece atenção.",
			"Média da GPU nos últimos 15 minutos acima de 80 °C.")
	}
	if cpuTemperature.Samples >= 3 && cpuTemperature.Average >= 90 {
		add("critical", "critical", "temperature", "O processador permanece em temperatura elevada.",
			"Média da CPU nos últimos 15 minutos acima de 90 °C.")
	} else if cpuTemperature.Samples >= 3 && cpuTemperature.Average >= 80 {
		add("warning", "warning", "temperature", "A temperatura do processador merece atenção.",
			"Média da CPU nos últimos 15 minutos acima de 80 °C.")
	}

	title, summary := "Sistema funcionando normalmente", "Nenhum problema importante foi identificado nesta análise."
	if level == "warning" {
		title, summary = "Atenção recomendada", "O TGDesk identificou uma condição sustentada que deve ser acompanhada."
	} else if level == "critical" || level == "maximum" {
		title, summary = "Verificação técnica necessária", "O TGDesk identificou uma condição sustentada que pode afetar este computador."
	}
	clientTitle, clientSummary := "Tudo certo por aqui", "O TGDesk está monitorando este computador."
	if clientLevel == "warning" {
		clientTitle, clientSummary = "Vale falar com seu técnico", "Foi identificada uma condição persistente que merece atenção."
	} else if clientLevel == "critical" || clientLevel == "maximum" {
		clientTitle, clientSummary = "Entre em contato com seu técnico", "Foi identificado um problema persistente neste computador."
	}
	return map[string]any{
		"level": level, "title": title, "summary": summary,
		"client_level": clientLevel, "client_title": clientTitle, "client_summary": clientSummary,
		"issues": issues, "metrics": metrics, "recent_window_minutes": 15,
		"recent_samples": recentSamples, "evaluated_at": time.Now().UTC().Format(time.RFC3339),
	}
}
