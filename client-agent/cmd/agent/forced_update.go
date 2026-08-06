package main

import (
	"log"
	"sync"
	"time"

	"tgdesk/agent/internal/updatecore"
)

// Atualização empurrada pelo servidor.
//
// O cliente não clica em nada e não decide nada: a ordem chega pelo canal de
// controle, junto do teto de velocidade, e o resultado volta pelo mesmo canal.
// Enquanto o resultado não chega, a vaga na fila do servidor continua ocupada
// e ninguém mais atualiza — por isso o resultado é sempre reportado, inclusive
// quando falha.

type updateOrder struct {
	Version      string `json:"version"`
	ThrottleKbps int    `json:"throttle_kbps"`
}

type updateOutcome struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

var forcedUpdate struct {
	sync.Mutex
	running  bool
	progress updatecore.Progress
}

func updateProgressSnapshot() updatecore.Progress {
	forcedUpdate.Lock()
	defer forcedUpdate.Unlock()
	return forcedUpdate.progress
}

func updateInProgress() bool {
	forcedUpdate.Lock()
	defer forcedUpdate.Unlock()
	return forcedUpdate.running
}

// startForcedUpdate executa a ordem uma vez só. Ordem repetida enquanto a
// anterior roda é ignorada: o servidor reenvia a cada heartbeat até receber o
// resultado, e sem esta trava a máquina baixaria a mesma versão várias vezes.
func startForcedUpdate(order updateOrder, onProgress func(updatecore.Progress),
	onDone func(updateOutcome)) {
	forcedUpdate.Lock()
	if forcedUpdate.running {
		forcedUpdate.Unlock()
		return
	}
	forcedUpdate.running = true
	forcedUpdate.Unlock()

	updatecore.SetTransferLimit(order.ThrottleKbps)
	updatecore.SetProgressReporter(func(progress updatecore.Progress) {
		forcedUpdate.Lock()
		forcedUpdate.progress = progress
		forcedUpdate.Unlock()
		onProgress(progress)
	})

	go func() {
		defer func() {
			updatecore.SetProgressReporter(nil)
			forcedUpdate.Lock()
			forcedUpdate.running = false
			forcedUpdate.Unlock()
		}()
		// Ordem vazia é a verificação periódica do próprio agente, não um
		// update_now: sem versão nem teto, ela pergunta ao servidor o que há.
		if order.Version == "" {
			log.Println("verificação periódica de atualização")
		} else {
			log.Printf("atualização ordenada pelo servidor: versão %s, teto %d kbps",
				order.Version, order.ThrottleKbps)
		}
		// 0 = já atualizado, 10 = atualização iniciada, 1 = erro. Nos dois
		// primeiros a vaga na fila pode ser liberada; no terceiro o servidor
		// devolve o dispositivo para a fila e tenta de novo mais tarde.
		switch code := updatecore.RunUpdate(); code {
		case 0, 10:
			onDone(updateOutcome{OK: true})
		default:
			onDone(updateOutcome{OK: false,
				Error: "atualização falhou no dispositivo"})
		}
	}()
}

// ultimaVerificacaoDeAtualizacao guarda quando o Host checou pela última vez.
var ultimaVerificacaoDeAtualizacao time.Time

// intervaloDeVerificacao é o piso entre duas checagens do Host.
//
// O laço do Host gira a cada poucos segundos; sem este espaçamento ele pediria
// o manifesto o tempo todo. Dez minutos é frequente o bastante para uma máquina
// recém-instalada não ficar parada, e raro o bastante para não fazer barulho.
const intervaloDeVerificacao = 10 * time.Minute

// verificarAtualizacaoPeriodica é o piso da atualização automática.
//
// Chamada do laço do Host, que roda em qualquer estado do dispositivo — o
// canal de controle privado só existe depois da vinculação, e quem está
// esperando ser vinculado é exatamente quem não pode ficar para trás.
//
// Não decide nada: pergunta ao servidor e obedece. E respeita a mesma trava do
// push, para as duas entradas não baixarem a mesma versão ao mesmo tempo.
func verificarAtualizacaoPeriodica() {
	if updateInProgress() {
		return
	}
	if time.Since(ultimaVerificacaoDeAtualizacao) < intervaloDeVerificacao {
		return
	}
	ultimaVerificacaoDeAtualizacao = time.Now()
	startForcedUpdate(updateOrder{}, func(updatecore.Progress) {}, func(updateOutcome) {})
}
