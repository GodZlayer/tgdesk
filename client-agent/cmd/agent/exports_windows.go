//go:build windows

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"os"

	"tgdesk/agent/internal/updatecore"
)

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
	if checkOnly != 0 {
		return C.int(updatecore.CheckForUpdate())
	}
	return C.int(updatecore.RunUpdate())
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
