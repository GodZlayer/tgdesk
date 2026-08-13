package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
)

// Evidência vinda do EXAME — o teste completo, não a telemetria passiva.
//
// A diferença entre os dois, e o motivo de este arquivo existir:
//
//   - telemetria passiva observa a máquina como ela está. Barata, contínua, e
//     limitada ao que acontece por acaso enquanto se olha.
//   - o exame FORÇA. Ele lê a superfície inteira do disco, satura a CPU, exige
//     memória, mede latência por região. Produz medida onde a observação
//     passiva só teria silêncio.
//
// Até aqui os resultados do exame eram gravados e nunca lidos: `diagnostic_runs.
// results` acumulava e o dossiê continuava se baseando só na telemetria. O
// técnico rodava o teste completo e o diagnóstico não mudava — o que é a pior
// combinação possível, porque o exame custa tempo da máquina do cliente.
//
// Cada extração abaixo existe porque separa causas com CONDUTAS diferentes. Um
// número que não muda conduta não vira evidência, por mais interessante que
// seja de olhar.

// exameDoDispositivo lê o último exame concluído e devolve evidências.
//
// Só exame CONCLUÍDO entra. Um exame interrompido no meio tem resultado
// parcial, e resultado parcial de um teste de superfície é indistinguível de
// "a parte lida estava boa" — usá-lo afirmaria saúde onde houve desistência.
func (s *Server) evidenciasDoExame(ctx context.Context, deviceID string) []EvidenciaDoDossie {
	var bruto []byte
	err := s.Pool.QueryRow(ctx, `
		SELECT results FROM diagnostic_runs
		WHERE device_id = $1 AND status = 'completed' AND results ? 'tests'
		ORDER BY finished_at DESC NULLS LAST LIMIT 1`, deviceID).Scan(&bruto)
	if err != nil {
		return nil
	}

	var envelope struct {
		Tests map[string]struct {
			Status  string          `json:"status"`
			Results json.RawMessage `json:"results"`
		} `json:"tests"`
	}
	if json.Unmarshal(bruto, &envelope) != nil {
		return nil
	}

	var ev []EvidenciaDoDossie
	for nome, t := range envelope.Tests {
		if t.Status != "completed" || len(t.Results) == 0 {
			continue
		}
		ev = append(ev, evidenciasDeUmTeste(nome, t.Results)...)
	}
	// Ordem estável: a tela lista evidência na ordem que recebe, e ordem que
	// muda a cada leitura faria o mesmo dossiê parecer diferente.
	sort.Slice(ev, func(i, j int) bool { return ev[i].Sinal < ev[j].Sinal })
	return ev
}

func evidenciasDeUmTeste(nome string, bruto json.RawMessage) []EvidenciaDoDossie {
	switch nome {
	case "storage_surface_read":
		return evidenciaSuperficieDeDisco(bruto)
	case "smart_extended":
		return evidenciaSMART(bruto)
	case "memory_integrity", "memory_extended":
		return evidenciaMemoria(bruto)
	case "disk_performance", "disk_random_performance":
		return evidenciaDesempenhoDeDisco(nome, bruto)
	case "resource_pressure_series":
		return evidenciaSerieDePressao(bruto)
	case "temperature_sensors":
		return evidenciaTermica(bruto)
	case "critical_events", "driver_errors", "service_failures":
		return evidenciaDeLog(nome, bruto)
	case "battery_health":
		return evidenciaBateria(bruto)
	default:
		return nil
	}
}

// evidenciaSuperficieDeDisco é a mais valiosa do exame inteiro.
//
// O teste lê 240 regiões espalhadas pelo disco e cronometra CADA UMA. Isso
// separa três coisas que a telemetria passiva confunde:
//
//   - erro de leitura em qualquer região  -> disco DEGRADADO (trocar, com backup)
//   - região lenta isolada                -> setor em vias de falhar
//   - todas as regiões lentas por igual   -> disco LENTO, não defeituoso (upgrade)
//
// A distinção entre a primeira e a terceira é a que mais muda dinheiro: uma é
// troca urgente com risco de perda de dado, a outra é upgrade planejado.
func evidenciaSuperficieDeDisco(bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		Disks []struct {
			Model   string `json:"model"`
			Status  string `json:"status"`
			Errors  int    `json:"errors"`
			Regions []struct {
				DurationMs float64 `json:"duration_ms"`
				Bytes      uint64  `json:"bytes"`
				Error      string  `json:"error"`
			} `json:"regions"`
		} `json:"disks"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}

	var ev []EvidenciaDoDossie
	for _, d := range r.Disks {
		if d.Errors > 0 {
			v := float64(d.Errors)
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "erro_io_log",
				Literal: fmt.Sprintf("%s: %d erro(s) de leitura na varredura de superfície", d.Model, d.Errors),
				Valor:   &v,
			})
		}
		if len(d.Regions) == 0 {
			continue
		}

		// MEDIANA e p99, não média.
		//
		// A média é exatamente o que apaga o sinal mais importante deste teste.
		// Medido no parque: um NVMe com mediana de 2,15 s por região — vazão
		// saudável — e p99 de 9,53 s, com 12 regiões de 240 acima de 5 s. Na
		// média ele parece ótimo; na cauda ele PARA.
		//
		// E parar é o sintoma que o usuário relata: "trava alguns segundos e
		// volta". Um disco uniformemente lento e um disco que engasga pedem
		// condutas opostas — trocar a peça contra liberar espaço para o
		// controlador respirar — então precisam ser evidências diferentes.
		duracoes := make([]float64, 0, len(d.Regions))
		for _, reg := range d.Regions {
			duracoes = append(duracoes, reg.DurationMs)
		}
		sort.Float64s(duracoes)
		mediana := percentil(duracoes, 0.50)
		p99 := percentil(duracoes, 0.99)

		// ENGASGO: a cauda é muito pior que o típico. A razão importa mais que
		// o valor absoluto, porque disco rápido e disco lento têm medianas
		// muito diferentes e o mesmo engasgo relativo incomoda igual.
		if mediana > 0 && p99/mediana >= 3 {
			v := p99 / 1000
			ev = append(ev, EvidenciaDoDossie{
				Sinal: "trava_confirmada",
				Literal: fmt.Sprintf(
					"%s: leitura típica de %.1f s por região, mas 1%% das regiões levou %.1f s — o disco para e volta, não é lento por igual",
					d.Model, mediana/1000, p99/1000),
				Valor: &v,
			})
			continue
		}

		// LENTO POR IGUAL: a peça é sã e devagar. Conduta é upgrade planejado,
		// não troca urgente — e confundir os dois assusta o cliente à toa.
		if mediana > 0 {
			mbps := float64(d.Regions[0].Bytes) / 1024 / 1024 / (mediana / 1000)
			if mbps > 0 && mbps < 100 {
				v := mbps
				ev = append(ev, EvidenciaDoDossie{
					Sinal: "latencia_disco",
					Literal: fmt.Sprintf(
						"%s: %.0f MB/s de leitura sequencial, uniforme e sem erros",
						d.Model, mbps),
					Valor: &v,
				})
			}
		}
	}
	return ev
}

func evidenciaSMART(bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		Disks []struct {
			Model       string `json:"model"`
			Health      string `json:"health_status"`
			Reallocated *int   `json:"reallocated_sectors"`
			Pending     *int   `json:"pending_sectors"`
			Uncorrect   *int   `json:"uncorrectable_errors"`
			WearPct     *int   `json:"wear_leveling_pct"`
		} `json:"disks"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	var ev []EvidenciaDoDossie
	for _, d := range r.Disks {
		// Setor realocado é o indicador mais direto de disco morrendo que
		// existe: o disco já perdeu pedaço e está usando reserva.
		if d.Reallocated != nil && *d.Reallocated > 0 {
			v := float64(*d.Reallocated)
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_reallocated",
				Literal: fmt.Sprintf("%s: %d setores realocados", d.Model, *d.Reallocated),
				Valor:   &v,
			})
		}
		if d.Pending != nil && *d.Pending > 0 {
			v := float64(*d.Pending)
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_pending",
				Literal: fmt.Sprintf("%s: %d setores pendentes de realocação", d.Model, *d.Pending),
				Valor:   &v,
			})
		}
		if d.Uncorrect != nil && *d.Uncorrect > 0 {
			v := float64(*d.Uncorrect)
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_geral",
				Literal: fmt.Sprintf("%s: %d erros não corrigíveis", d.Model, *d.Uncorrect),
				Valor:   &v,
			})
		}
		if d.WearPct != nil && *d.WearPct < 10 {
			v := float64(*d.WearPct)
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "smart_desgaste",
				Literal: fmt.Sprintf("%s: %d%% de vida útil restante", d.Model, *d.WearPct),
				Valor:   &v,
			})
		}
	}
	return ev
}

// evidenciaMemoria: erro de memória é FATO, não indício.
//
// Um único erro num teste de integridade já justifica troca — memória não erra
// "um pouquinho". É por isso que aqui não há limiar: qualquer erro entra.
func evidenciaMemoria(bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		Errors   *int    `json:"errors"`
		Failed   *int    `json:"failed"`
		Status   string  `json:"status"`
		TestedMB float64 `json:"tested_mb"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	n := 0
	if r.Errors != nil {
		n += *r.Errors
	}
	if r.Failed != nil {
		n += *r.Failed
	}
	if n == 0 {
		return nil
	}
	v := float64(n)
	return []EvidenciaDoDossie{{
		Sinal:   "erro_memoria",
		Literal: fmt.Sprintf("teste de memória: %d erro(s) em %.0f MB testados", n, r.TestedMB),
		Valor:   &v,
	}}
}

func evidenciaDesempenhoDeDisco(nome string, bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		ReadMBs   *float64 `json:"read_mb_s"`
		WriteMBs  *float64 `json:"write_mb_s"`
		IOPS      *float64 `json:"iops"`
		LatencyMs *float64 `json:"latency_ms"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	var ev []EvidenciaDoDossie
	// 50 MB/s sequencial é abaixo até de disco mecânico saudável. Com SMART
	// limpo, isso é peça insuficiente ou gargalo de barramento — nunca defeito.
	if r.ReadMBs != nil && *r.ReadMBs > 0 && *r.ReadMBs < 50 {
		v := *r.ReadMBs
		ev = append(ev, EvidenciaDoDossie{
			Sinal:   "latencia_disco",
			Literal: fmt.Sprintf("%s: leitura sequencial de apenas %.0f MB/s", nome, v),
			Valor:   &v,
		})
	}
	if r.LatencyMs != nil && *r.LatencyMs >= 20 {
		v := *r.LatencyMs
		ev = append(ev, EvidenciaDoDossie{
			Sinal:   "latencia_disco",
			Literal: fmt.Sprintf("%s: %.1f ms de latência sob carga", nome, v),
			Valor:   &v,
		})
	}
	return ev
}

// evidenciaSerieDePressao lê a série de 30 amostras do exame.
//
// A série é o único lugar do produto onde CPU, memória, disco e processos são
// medidos JUNTOS no mesmo instante. É isso que permite dizer "o disco saturou
// enquanto a CPU estava livre" — e essa frase separa gargalo de disco de
// gargalo de processamento, que têm condutas opostas.
func evidenciaSerieDePressao(bruto json.RawMessage) []EvidenciaDoDossie {
	var amostras []struct {
		CPU     *float64 `json:"CpuPercent"`
		MemMB   *float64 `json:"AvailableMemoryMb"`
		DiskPct *float64 `json:"DiskBusyPercent"`
		TopCPU  []struct {
			Name string   `json:"Name"`
			CPU  *float64 `json:"CPU"`
			WS   *float64 `json:"WorkingSet64"`
		} `json:"TopCpu"`
	}
	if json.Unmarshal(bruto, &amostras) != nil || len(amostras) == 0 {
		return nil
	}

	var somaCPU, somaDisco float64
	nCPU, nDisco, discoSaturado := 0, 0, 0
	porProcesso := map[string]float64{}
	for _, a := range amostras {
		if a.CPU != nil {
			somaCPU += *a.CPU
			nCPU++
		}
		if a.DiskPct != nil {
			somaDisco += *a.DiskPct
			nDisco++
			if *a.DiskPct >= 90 {
				discoSaturado++
			}
		}
		for _, p := range a.TopCPU {
			if p.WS != nil {
				mb := *p.WS / (1024 * 1024)
				if mb > porProcesso[p.Name] {
					porProcesso[p.Name] = mb
				}
			}
		}
	}

	var ev []EvidenciaDoDossie
	mediaCPU := 0.0
	if nCPU > 0 {
		mediaCPU = somaCPU / float64(nCPU)
	}

	// A frase que separa gargalo de disco de gargalo de CPU. Disco no teto com
	// CPU livre é o retrato de I/O como gargalo — trocar processador não
	// resolveria nada.
	if nDisco > 0 && discoSaturado > nDisco/3 && mediaCPU < 50 {
		v := float64(discoSaturado) / float64(nDisco) * 100
		ev = append(ev, EvidenciaDoDossie{
			Sinal: "latencia_disco",
			Literal: fmt.Sprintf(
				"disco em 90%%+ de ocupação em %.0f%% das amostras, com CPU em apenas %.0f%% de média — o gargalo é I/O, não processamento",
				v, mediaCPU),
			Valor: &v,
		})
	}

	// Processo dominante em memória durante o exame.
	maiorNome, maiorMB := "", 0.0
	for nome, mb := range porProcesso {
		if mb > maiorMB {
			maiorNome, maiorMB = nome, mb
		}
	}
	if maiorMB >= 2048 {
		v := maiorMB
		ev = append(ev, EvidenciaDoDossie{
			Sinal:   "processo_dominante",
			Literal: fmt.Sprintf("%s ocupou %.1f GB durante o exame", maiorNome, maiorMB/1024),
			Valor:   &v,
		})
	}
	return ev
}

func evidenciaTermica(bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		Sensors []struct {
			Name    string   `json:"name"`
			Celsius *float64 `json:"celsius"`
		} `json:"sensors"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	var ev []EvidenciaDoDossie
	for _, s := range r.Sensors {
		if s.Celsius != nil && *s.Celsius >= 85 {
			v := *s.Celsius
			ev = append(ev, EvidenciaDoDossie{
				Sinal:   "temperatura",
				Literal: fmt.Sprintf("%s a %.0f °C durante o exame", s.Name, v),
				Valor:   &v,
			})
		}
	}
	return ev
}

// evidenciaDeLog: se o sistema operacional já disse, não se adivinha (§7.3).
func evidenciaDeLog(nome string, bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		Total  *int `json:"total"`
		Events []struct {
			ID      int    `json:"id"`
			Message string `json:"message"`
			Source  string `json:"source"`
		} `json:"events"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	if len(r.Events) == 0 {
		return nil
	}

	sinal := "erro_sistema_log"
	switch nome {
	case "driver_errors":
		sinal = "driver_falho"
	case "service_failures":
		sinal = "servico_caiu"
	}

	v := float64(len(r.Events))
	primeiro := r.Events[0]
	return []EvidenciaDoDossie{{
		Sinal: sinal,
		Literal: fmt.Sprintf("%d ocorrência(s) no log do sistema; a mais recente: %s (evento %d)",
			len(r.Events), trecho(primeiro.Message), primeiro.ID),
		Valor: &v,
	}}
}

func evidenciaBateria(bruto json.RawMessage) []EvidenciaDoDossie {
	var r struct {
		DesignCapacity *float64 `json:"design_capacity"`
		FullCapacity   *float64 `json:"full_charge_capacity"`
		CycleCount     *int     `json:"cycle_count"`
	}
	if json.Unmarshal(bruto, &r) != nil {
		return nil
	}
	if r.DesignCapacity == nil || r.FullCapacity == nil || *r.DesignCapacity <= 0 {
		return nil
	}
	saude := *r.FullCapacity / *r.DesignCapacity * 100
	if saude >= 60 {
		return nil
	}
	return []EvidenciaDoDossie{{
		Sinal:   "bateria",
		Literal: fmt.Sprintf("bateria com %.0f%% da capacidade de projeto", saude),
		Valor:   &saude,
	}}
}

// percentil sobre uma fatia JÁ ORDENADA.
//
// Interpolação seria precisão falsa: com 240 amostras o índice inteiro já
// descreve a cauda, e o número que importa é a ordem de grandeza da pausa.
func percentil(ordenado []float64, p float64) float64 {
	if len(ordenado) == 0 {
		return 0
	}
	i := int(float64(len(ordenado)-1) * p)
	return ordenado[i]
}

// trecho corta uma mensagem de log para caber na tela sem virar parágrafo.
func trecho(s string) string {
	const max = 90
	if len(s) <= max {
		return s
	}
	return s[:max] + "…"
}
