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
	result["health"] = health
	return result
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

	avaliar := func(categoria, metrica string) {
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
		// Quem tem o histórico é o servidor, então ele manda desde quando a
		// condição dura e para onde caminha. A narrativa em cima disso é do
		// cliente: só ele sabe em que tela cabe e em que idioma.
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
			// Código mais números. A frase é do cliente, que sabe em que tela
			// ela cabe e em que idioma quem lê a espera.
			code := "sustained_usage"
			params := map[string]any{
				"window": janelaEscolhida, "peak_pct": melhor.Pico,
				"average_pct": melhor.Media, "threshold_pct": exposicaoLimiar(melhor),
				"time_above_pct": exposicaoTempo(melhor),
			}
			if categoria == catStorage {
				code = "storage_occupancy"
				params = map[string]any{
					"window": janelaEscolhida, "average_pct": melhor.Media,
				}
			}
			issues = append(issues, map[string]any{
				"severity": nivel, "client_severity": nivel, "category": categoria,
				"code": code, "params": params,
				"desde": desde.Format(time.RFC3339),
			})
		}
	}

	avaliar(catProcessing, catProcessing)
	avaliar(catMemory, catMemory)
	avaliar(catStorage, catStorage)

	return map[string]any{
		"level": nivelGeral, "client_level": nivelCliente,
		"issues": issues, "metrics": metrics,
		"evaluated_at": time.Now().UTC().Format(time.RFC3339),
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

// exposicaoLimiar e exposicaoTempo devolvem o par (limiar, tempo acima dele)
// que caracteriza a exposição. São os números que a frase antiga embutia em
// português: quanto tempo a máquina passou acima de qual limiar.
func exposicaoLimiar(w janelaMetrica) int {
	switch {
	case w.PctAcima95 >= 15:
		return 95
	case w.PctAcima85 >= 15:
		return 85
	default:
		return 75
	}
}

func exposicaoTempo(w janelaMetrica) float64 {
	switch {
	case w.PctAcima95 >= 15:
		return w.PctAcima95
	case w.PctAcima85 >= 15:
		return w.PctAcima85
	default:
		return w.PctAcima75
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
	// Cada condição vira código mais números. A frase — técnica ou para o
	// cliente — é do cliente, que conhece a tela em que vai caber e o idioma
	// de quem lê. Antes saíam daqui duas redações por problema, e a escolha de
	// quem via qual estava resolvida no servidor.
	add := func(severity, clientSeverity, category, code string, params map[string]any) {
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
		issue := map[string]any{
			"severity": severity, "client_severity": clientSeverity,
			"category": category, "code": code,
		}
		if params != nil {
			issue["params"] = params
		}
		issues = append(issues, issue)
	}

	usageThreshold := map[string]int{"maximum": 95, "critical": 85, "warning": 75}
	if grade := sustainedUsageLevel(cpuUsage.Average, cpuUsage.Samples); grade != "normal" {
		add(grade, grade, "processing", "cpu_sustained_usage", map[string]any{
			"threshold_pct": usageThreshold[grade], "average_pct": cpuUsage.Average,
			"window_minutes": 15,
		})
	}
	if grade := sustainedUsageLevel(memoryUsage.Average, memoryUsage.Samples); grade != "normal" {
		add(grade, grade, "memory", "memory_sustained_usage", map[string]any{
			"threshold_pct": usageThreshold[grade], "average_pct": memoryUsage.Average,
			"window_minutes": 15,
		})
	}

	for _, d := range h.Storage {
		if d.SMARTStatus != "" && d.SMARTStatus != "Healthy" {
			add("critical", "critical", "storage", "storage_smart_failing", map[string]any{
				"device": d.Model, "smart_status": d.SMARTStatus,
			})
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
			add("maximum", "maximum", "storage", "storage_space_low", map[string]any{
				"volume": label, "used_pct": highest, "threshold_pct": 95,
			})
		case highest >= 85:
			add("warning", "warning", "storage", "storage_space_low", map[string]any{
				"volume": label, "used_pct": highest, "threshold_pct": 85,
			})
		}
		if d.LifePct != nil && *d.LifePct <= 10 {
			add("critical", "critical", "storage", "storage_life_low", map[string]any{
				"device": d.Model, "life_pct": *d.LifePct, "threshold_pct": 10,
			})
		} else if d.LifePct != nil && *d.LifePct <= 20 {
			add("warning", "warning", "storage", "storage_life_low", map[string]any{
				"device": d.Model, "life_pct": *d.LifePct, "threshold_pct": 20,
			})
		}
	}

	temperature := func(stats metricStats, code string, critical, warning float64) {
		if stats.Samples < 3 {
			return
		}
		switch {
		case stats.Average >= critical:
			add("critical", "critical", "temperature", code, map[string]any{
				"average_c": stats.Average, "threshold_c": critical, "window_minutes": 15,
			})
		case stats.Average >= warning:
			add("warning", "warning", "temperature", code, map[string]any{
				"average_c": stats.Average, "threshold_c": warning, "window_minutes": 15,
			})
		}
	}
	temperature(storageTemperature, "storage_temperature_high", 65, 55)
	temperature(gpuTemperature, "gpu_temperature_high", 90, 80)
	temperature(cpuTemperature, "cpu_temperature_high", 90, 80)

	// Título e resumo saíam daqui em quatro versões — duas para o técnico,
	// duas para o cliente — e todas eram função apenas do nível. O cliente já
	// recebe o nível; a frase é dele.
	return map[string]any{
		"level": level, "client_level": clientLevel,
		"issues": issues, "metrics": metrics, "recent_window_minutes": 15,
		"recent_samples": recentSamples, "evaluated_at": time.Now().UTC().Format(time.RFC3339),
	}
}
