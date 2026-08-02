package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
)

var hostSingleton windows.Handle

func appendAgentLog(format string, values ...any) {
	logDir := filepath.Join(tgdeskDataDir(), "logs")
	_ = os.MkdirAll(logDir, 0755)
	f, err := os.OpenFile(filepath.Join(logDir, "agent.log"),
		os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	log.New(f, "", log.LstdFlags).Printf(format, values...)
}

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
	releaseHostSingleton()
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
	name, err := syscall.UTF16PtrFromString("Global\\TGDeskHostAgentSingleton")
	if err != nil {
		return true
	}
	// During a Windows service restart SCM can start the replacement while
	// the previous process is still releasing its embedded Host thread. Do
	// not permanently lose the Host on that short overlap: retry for a
	// bounded interval. Each failed CreateMutex returns a real handle to the
	// existing object, which must be closed before retrying.
	deadline := time.Now().Add(30 * time.Second)
	for {
		var candidate windows.Handle
		candidate, err = windows.CreateMutex(nil, false, name)
		if err != windows.ERROR_ALREADY_EXISTS {
			hostSingleton = candidate
			return true
		}
		if candidate != 0 {
			_ = windows.CloseHandle(candidate)
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func releaseHostSingleton() {
	if hostSingleton != 0 {
		_ = windows.CloseHandle(hostSingleton)
		hostSingleton = 0
	}
}

func acquireTechnicianSingleton() bool {
	name, err := syscall.UTF16PtrFromString("Global\\TGDeskTechnicianAgentSingleton")
	if err != nil {
		return true
	}
	_, err = windows.CreateMutex(nil, false, name)
	return err != windows.ERROR_ALREADY_EXISTS
}
