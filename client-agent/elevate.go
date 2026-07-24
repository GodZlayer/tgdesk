package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"

	"golang.org/x/sys/windows"
)

// isElevated reports whether the current process already holds an elevated
// (Administrator) token.
func isElevated() bool {
	var token windows.Token
	proc, err := windows.GetCurrentProcess()
	if err != nil {
		return false
	}
	if err := windows.OpenProcessToken(proc, windows.TOKEN_QUERY, &token); err != nil {
		return false
	}
	defer token.Close()
	return token.IsElevated()
}

// relaunchElevated re-executes this same binary with the same working
// directory via the Windows "runas" verb, which triggers the standard UAC
// consent prompt. Só é chamado no momento em que o técnico vincula o
// dispositivo (Seção 3.3) — é o único instante em que pedir elevação faz
// sentido pro usuário final, evitando o UAC "do nada" no primeiro boot.
func relaunchElevated() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	dir := workingDir(exe)
	verb, _ := syscall.UTF16PtrFromString("runas")
	exePtr, _ := syscall.UTF16PtrFromString(exe)
	dirPtr, _ := syscall.UTF16PtrFromString(dir)
	escapedArgs := make([]string, 0, len(os.Args)-1)
	for _, arg := range os.Args[1:] {
		escapedArgs = append(escapedArgs, syscall.EscapeArg(arg))
	}
	paramsPtr, _ := syscall.UTF16PtrFromString(strings.Join(escapedArgs, " "))

	return windows.ShellExecute(0, verb, exePtr, paramsPtr, dirPtr, windows.SW_SHOWNORMAL)
}

func workingDir(exe string) string {
	idx := strings.LastIndexAny(exe, `\/`)
	if idx < 0 {
		return "."
	}
	return exe[:idx]
}

func elevateAndRestart() {
	fmt.Println("solicitando privilégio de administrador para instalar os módulos (janela do Windows vai aparecer)...")
	if err := relaunchElevated(); err != nil {
		fmt.Println("falha ao solicitar elevação:", err)
		return
	}
	os.Exit(0)
}

// acquireHostSingleton garante que só uma instância do papel Host rode por
// máquina (por sessão), usando um mutex nomeado do Windows. Necessário porque
// o Host pode ser iniciado tanto pelo atalho de autostart (versão instalada)
// quanto automaticamente pelo tgdesk.exe (versão portátil) — sem essa trava
// as duas tentariam registrar/heartbeat o mesmo dispositivo ao mesmo tempo.
func acquireHostSingleton() bool {
	name, err := syscall.UTF16PtrFromString("Local\\TGDeskHostAgentSingleton")
	if err != nil {
		return true
	}
	_, err = windows.CreateMutex(nil, false, name)
	if err == windows.ERROR_ALREADY_EXISTS {
		return false
	}
	return true
}

func acquireTechnicianSingleton() bool {
	name, err := syscall.UTF16PtrFromString("Local\\TGDeskTechnicianAgentSingleton")
	if err != nil {
		return true
	}
	_, err = windows.CreateMutex(nil, false, name)
	return err != windows.ERROR_ALREADY_EXISTS
}
