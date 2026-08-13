package handlers

import (
	"context"
	"encoding/json"
	"time"
)

// Recepção da telemetria local com entrega diferida (store-and-forward).
//
// O agente coleta a cada 10 s, em disco, INDEPENDENTE de haver conexão — a
// máquina sem internet é justamente a que costuma estar com problema, e o
// buraco no histórico coincidia com o período que mais interessa. Quando o
// canal está de pé, ele drena o que ficou para trás.
//
// A regra que faz isso valer alguma coisa:
//
//	o carimbo é o da COLETA, nunca o da chegada.
//
// Um lote que subiu depois de um dia offline descreve um dia — não um segundo.
// Usar `now()` aqui comprimiria o dia inteiro no instante da reconexão, e todo
// histograma de pressão, toda janela de episódio e toda correlação com trava
// ficariam errados de um jeito que ninguém perceberia olhando a tela.

// AmostraLocalRecebida é uma linha do spool do agente.
type AmostraLocalRecebida struct {
	Em    time.Time       `json:"em"`
	Tipo  string          `json:"tipo"`
	Dados json.RawMessage `json:"dados"`
}

// amostraBarata é o retrato contínuo que o agente monta só com syscall.
//
// Cada campo existe porque uma causa da taxonomia o consome — campo que
// ninguém consome é custo puro (§13.6).
type amostraBarata struct {
	CPUPct        float64            `json:"cpu_pct"`
	MemPct        float64            `json:"mem_pct"`
	MemDispMB     uint64             `json:"mem_disponivel_mb"`
	CommitPct     float64            `json:"commit_pct"`
	Processos     uint32             `json:"processos"`
	Threads       uint32             `json:"threads"`
	Handles       uint32             `json:"handles"`
	UptimeS       uint64             `json:"uptime_s"`
	DiscoLivrePct map[string]float64 `json:"disco_livre_pct"`
}

// ReceberTelemetriaLocal grava o lote drenado do agente.
//
// Cada amostra vira linhas no histograma horário, no bucket da hora em que foi
// COLETADA. É por isso que `roll_metric` recebe o instante explícito em vez de
// usar o relógio do servidor.
func (s *Server) ReceberTelemetriaLocal(ctx context.Context, deviceID string, payload json.RawMessage) {
	var lote struct {
		Amostras []AmostraLocalRecebida `json:"amostras"`
		Completo bool                   `json:"completo"`
	}
	if json.Unmarshal(payload, &lote) != nil {
		return
	}

	for _, a := range lote.Amostras {
		if a.Em.IsZero() {
			// Amostra sem hora de coleta não pode ser situada na linha do
			// tempo. Carimbá-la com a chegada seria inventar quando aconteceu.
			continue
		}
		// Amostra do futuro é relógio local errado, não medição. Aceitar
		// deslocaria o histograma para frente e criaria buracos no presente.
		if a.Em.After(time.Now().Add(5 * time.Minute)) {
			continue
		}
		if a.Tipo != "amostra" {
			continue
		}

		var b amostraBarata
		if json.Unmarshal(a.Dados, &b) != nil {
			continue
		}
		s.rolarAmostraBarata(ctx, deviceID, a.Em, b)
	}
}

// rolarAmostraBarata acumula uma amostra no histograma horário.
//
// Reaproveita `roll_metric`, que é o mesmo caminho da telemetria cara: assim
// existe UMA série por métrica, e não duas que precisariam ser reconciliadas.
func (s *Server) rolarAmostraBarata(ctx context.Context, deviceID string, em time.Time, b amostraBarata) {
	roll := func(metrica string, valor float64) {
		_, _ = s.Pool.Exec(ctx, `SELECT roll_metric($1,$2,$3,$4)`,
			deviceID, metrica, valor, em)
	}

	roll("processing", b.CPUPct)
	roll("memory", b.MemPct)

	// `commit` é o que separa "memória insuficiente" de "memória ocupada": a
	// segunda tem folga de paginação, a primeira não. Era lacuna declarada na
	// taxonomia e deixa de ser.
	if b.CommitPct > 0 {
		roll("commit", b.CommitPct)
	}
	// Handles e threads detectam VAZAMENTO, que é o problema que só aparece na
	// derivada: o valor absoluto não diz nada, o crescimento monotônico diz
	// tudo. Guardar a série é o que torna a derivada calculável.
	if b.Handles > 0 {
		roll("handles", float64(b.Handles))
	}
	if b.Threads > 0 {
		roll("threads", float64(b.Threads))
	}
	if b.Processos > 0 {
		roll("processos", float64(b.Processos))
	}

	// Ocupação do volume mais cheio. É a mesma semântica da telemetria cara —
	// o número que determina se a máquina está sem espaço.
	pior := -1.0
	for _, livre := range b.DiscoLivrePct {
		if usado := 100 - livre; usado > pior {
			pior = usado
		}
	}
	if pior >= 0 {
		roll("storage", pior)
	}
}
