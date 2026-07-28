package handlers

import (
	"context"
	"encoding/json"
	"time"
)

type hardwareSample struct {
	CPU struct {
		Usage  *float64 `json:"usage"`
		Clock  *float64 `json:"clock_mhz"`
		Source string   `json:"measurement_source"`
	} `json:"cpu"`
	GPUs []struct {
		ID     string   `json:"id"`
		Usage  *float64 `json:"usage"`
		Clock  *float64 `json:"clock_mhz"`
		Source string   `json:"measurement_source"`
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

func (s *Server) hardwareStatistics(ctx context.Context, deviceID string) map[string]any {
	rows, err := s.Pool.Query(ctx, `
		SELECT hardware, coletado_em FROM telemetry_snapshots
		WHERE device_id=$1 AND coletado_em >= now()-interval '30 days'
		ORDER BY coletado_em`, deviceID)
	if err != nil {
		return map[string]any{}
	}
	defer rows.Close()
	type timed struct {
		h  hardwareSample
		at time.Time
	}
	samples := []timed{}
	for rows.Next() {
		var raw []byte
		var at time.Time
		if rows.Scan(&raw, &at) == nil {
			var h hardwareSample
			if json.Unmarshal(raw, &h) == nil {
				samples = append(samples, timed{h, at})
			}
		}
	}
	cpuUsage, cpuClock := metricStats{}, metricStats{}
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
	finalize := func(m metricStats) metricStats {
		if m.Samples > 0 {
			m.Average /= float64(m.Samples)
		}
		return m
	}
	cpuUsage, cpuClock = finalize(cpuUsage), finalize(cpuClock)
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
		result["health"] = analyzeHardwareHealth(samples[len(samples)-1].h)
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

func analyzeHardwareHealth(h hardwareSample) map[string]any {
	level := "normal"
	clientLevel := "normal"
	issues := []map[string]any{}
	add := func(severity, clientSeverity, category, clientMessage, technicalMessage string) {
		if severity == "critical" || (severity == "warning" && level == "normal") {
			level = severity
		}
		if clientSeverity == "critical" ||
			(clientSeverity == "warning" && clientLevel == "normal") {
			clientLevel = clientSeverity
		}
		issues = append(issues, map[string]any{
			"severity": severity, "client_severity": clientSeverity, "category": category,
			"client_message": clientMessage, "technical_message": technicalMessage,
		})
	}
	if h.MemorySummary.Usage != nil {
		switch {
		case *h.MemorySummary.Usage >= 95:
			add("critical", "warning", "memory", "A memória do computador está no limite.",
				"Uso atual de RAM acima de 95%; verificar paginação e processos consumidores.")
		case *h.MemorySummary.Usage >= 85:
			add("warning", "normal", "memory", "O computador está com pouca memória disponível.",
				"Uso atual de RAM acima de 85%; confirmar persistência no histórico.")
		}
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
			add("critical", "critical", "storage", "O computador está praticamente sem espaço disponível.",
				label+" está com mais de 95% do espaço ocupado.")
		case highest >= 85:
			add("warning", "warning", "storage", "O espaço de armazenamento está ficando baixo.",
				label+" está com mais de 85% do espaço ocupado.")
		}
		if d.Temperature != nil && *d.Temperature >= 65 {
			add("critical", "critical", "temperature", "Foi detectada temperatura elevada no armazenamento.",
				"Disco "+d.Model+" está acima de 65 °C.")
		} else if d.Temperature != nil && *d.Temperature >= 55 {
			add("warning", "normal", "temperature", "O armazenamento está operando acima da temperatura recomendada.",
				"Disco "+d.Model+" está acima de 55 °C.")
		}
		if d.LifePct != nil && *d.LifePct <= 10 {
			add("critical", "critical", "storage", "A vida útil do armazenamento está próxima do limite.",
				"Disco "+d.Model+" reportou no máximo 10% de vida útil restante.")
		} else if d.LifePct != nil && *d.LifePct <= 20 {
			add("warning", "normal", "storage", "O armazenamento apresenta desgaste relevante.",
				"Disco "+d.Model+" reportou no máximo 20% de vida útil restante.")
		}
	}
	title, summary := "Sistema funcionando normalmente", "Nenhum problema importante foi identificado nesta análise."
	if level == "warning" {
		title, summary = "Atenção recomendada", "O TGDesk identificou uma condição que deve ser acompanhada pelo responsável técnico."
	} else if level == "critical" {
		title, summary = "Verificação técnica necessária", "O TGDesk identificou uma condição que pode afetar o funcionamento deste computador."
	}
	clientTitle, clientSummary := "Tudo certo por aqui", "O TGDesk está monitorando este computador."
	if clientLevel == "warning" {
		clientTitle, clientSummary = "Vale falar com seu técnico", "Foi identificada uma condição que pode afetar o uso deste computador."
	} else if clientLevel == "critical" {
		clientTitle, clientSummary = "Entre em contato com seu técnico", "Foi identificado um problema importante neste computador."
	}
	return map[string]any{
		"level": level, "title": title, "summary": summary,
		"client_level": clientLevel, "client_title": clientTitle, "client_summary": clientSummary,
		"issues": issues, "evaluated_at": time.Now().UTC().Format(time.RFC3339),
	}
}
