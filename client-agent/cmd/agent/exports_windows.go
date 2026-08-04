//go:build windows

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"log"
	"os"
	"path/filepath"

	"tgdesk/agent/internal/updatecore"
)

// tgdesk.exe --tgdesk-update roda como app grafico (subsystem windows), sem
// console — fmt.Println nesse caminho nao vai a lugar nenhum e o resultado
// (sucesso ou falha) ficava totalmente invisivel. Redireciona pro mesmo
// padrao de log em arquivo usado no resto do agente.
func openUpdateLog() *os.File {
	logDir := filepath.Join(updatecore.DataDir(), "logs")
	_ = os.MkdirAll(logDir, 0755)
	logFile, err := os.OpenFile(filepath.Join(logDir, "update.log"),
		os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil
	}
	log.SetOutput(logFile)
	return logFile
}

//export TGDeskAgentHost
func TGDeskAgentHost(server *C.char, coreExe *C.char) C.int {
	args := []string{"host"}
	if server != nil {
		args = append(args, "--server", C.GoString(server))
	}
	if coreExe != nil {
		args = append(args, "--core-exe", C.GoString(coreExe))
	}
	runHost(args[1:])
	return 0
}

//export TGDeskAgentTechnician
func TGDeskAgentTechnician(server *C.char, token *C.char) C.int {
	args := []string{"technician"}
	if server != nil {
		args = append(args, "--server", C.GoString(server))
	}
	if token != nil {
		args = append(args, "--token", C.GoString(token))
	}
	return C.int(runTechnician(args[1:]))
}

//export TGDeskAgentTechnicianService
func TGDeskAgentTechnicianService(server *C.char) C.int {
	serverURL := ""
	if server != nil {
		serverURL = C.GoString(server)
	}
	return C.int(runTechnicianService(serverURL))
}

//export TGDeskAgentUpdate
func TGDeskAgentUpdate(checkOnly C.int) C.int {
	if logFile := openUpdateLog(); logFile != nil {
		defer logFile.Close()
	}
	if checkOnly != 0 {
		log.Println("--tgdesk-update-check: consultando atualização")
		result := updatecore.CheckForUpdate()
		log.Printf("--tgdesk-update-check: código de saída %d", result)
		return C.int(result)
	}
	log.Println("--tgdesk-update: iniciando verificação e aplicação")
	result := updatecore.RunUpdate()
	log.Printf("--tgdesk-update: código de saída %d", result)
	return C.int(result)
}

//export TGDeskAgentApplyStaged
func TGDeskAgentApplyStaged(staging *C.char, installDir *C.char, parentPID C.int) C.int {
	if staging == nil || installDir == nil {
		return 1
	}
	if err := updatecore.ApplyStaged(C.GoString(staging), C.GoString(installDir), uint32(parentPID)); err != nil {
		return 1
	}
	return 0
}

// c-shared requires package main to retain a main function. It is not invoked
// when tgdesk_agent.dll is loaded by tgdesk.exe.
var _ = os.Args
