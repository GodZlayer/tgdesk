package handlers

import (
	"context"
	"encoding/json"
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
	if len(samples) > 0 {
		result["health"] = analyzeHardwareHealth(
			samples[len(samples)-1].h,
			recentCPUUsage,
			recentMemoryUsage,
			recentCPUTemperature,
			recentGPUTemperature,
			recentStorageTemperature,
			recentSamples,
		)
	}
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
