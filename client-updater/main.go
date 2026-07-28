package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"syscall"

	"golang.org/x/sys/windows"
)

//go:embed payload/tgdesk-installer.exe
var installer []byte

func main() {
	target := filepath.Join(os.TempDir(), "tgdesk-installer-0.3.0.exe")
	if err := os.WriteFile(target, installer, 0700); err != nil {
		showError("Não foi possível preparar a atualização: " + err.Error())
		return
	}
	if err := launchElevated(target); err != nil {
		showError("Não foi possível iniciar a atualização: " + err.Error())
	}
}

func launchElevated(target string) error {
	verb, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(target)
	params, _ := syscall.UTF16PtrFromString(
		"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS",
	)
	dir, _ := syscall.UTF16PtrFromString(filepath.Dir(target))
	return windows.ShellExecute(0, verb, file, params, dir, windows.SW_HIDE)
}

func showError(message string) {
	text, _ := syscall.UTF16PtrFromString(message)
	title, _ := syscall.UTF16PtrFromString("TGDesk Update")
	_, _ = windows.MessageBox(0, text, title, windows.MB_OK|windows.MB_ICONERROR)
	fmt.Fprintln(os.Stderr, message)
}
