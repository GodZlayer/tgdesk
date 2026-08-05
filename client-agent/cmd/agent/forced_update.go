package main

import (
	"log"
	"sync"

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
		log.Printf("atualização ordenada pelo servidor: versão %s, teto %d kbps",
			order.Version, order.ThrottleKbps)
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
