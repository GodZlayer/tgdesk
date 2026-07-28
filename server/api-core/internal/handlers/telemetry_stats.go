package handlers

import (
	"context"
	"encoding/json"
	"time"
)

type hardwareSample struct {
	CPU struct {
		Usage float64 `json:"usage"`
		Clock float64 `json:"clock_mhz"`
	} `json:"cpu"`
	GPUs []struct {
		ID    string  `json:"id"`
		Usage float64 `json:"usage"`
		Clock float64 `json:"clock_mhz"`
	} `json:"gpus"`
	Memory []struct {
		ID   string `json:"id"`
		Used uint64 `json:"used_bytes"`
	} `json:"memory"`
	Networks []struct {
		ID, Status string
		Rx         uint64 `json:"rx_bytes_total"`
		Tx         uint64 `json:"tx_bytes_total"`
	} `json:"networks"`
}

type metricStats struct {
	Average float64 `json:"average"`
	Peak    float64 `json:"peak"`
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
	count := float64(len(samples))
	for i, sample := range samples {
		accumulate(&cpuUsage, sample.h.CPU.Usage)
		accumulate(&cpuClock, sample.h.CPU.Clock)
		for _, g := range sample.h.GPUs {
			u, c := gpuUsage[g.ID], gpuClock[g.ID]
			accumulate(&u, g.Usage)
			accumulate(&c, g.Clock)
			gpuUsage[g.ID], gpuClock[g.ID] = u, c
		}
		for _, m := range sample.h.Memory {
			v := mem[m.ID]
			accumulate(&v, float64(m.Used))
			mem[m.ID] = v
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
		if count > 0 {
			m.Average /= count
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
	intervals := count - 1
	for k, v := range nets {
		if intervals > 0 {
			v.AverageBps /= intervals
		}
		nets[k] = v
	}
	return map[string]any{
		"window_days": 30, "samples": len(samples),
		"cpu":       map[string]any{"usage": cpuUsage, "clock_mhz": cpuClock},
		"gpu_usage": gpuUsage, "gpu_clock_mhz": gpuClock,
		"memory_used_bytes": mem, "networks": nets,
	}
}

func accumulate(s *metricStats, v float64) {
	s.Average += v
	if v > s.Peak {
		s.Peak = v
	}
}
