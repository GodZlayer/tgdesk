package main

import (
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows/registry"
)

var installChecked bool

// ensureInstalled copies the running agent (and whatever sits next to it —
// tgdesk.exe, wintun.dll, etc.) to a persistent location and registers
// autostart, so the Host survives a reboot. Só roda de verdade uma vez —
// depois disso o agente já está "instalado" e isso vira um no-op rápido.
// Chamado só depois de já estarmos elevados (Seção 3.3: instalação completa
// acontece no primeiro acesso do técnico, não antes).
func ensureInstalled() {
	if installChecked {
		return
	}
	installChecked = true

	exe, err := os.Executable()
	if err != nil {
		return
	}
	srcDir := filepath.Dir(exe)

	programFiles := os.Getenv("ProgramFiles")
	if programFiles == "" {
		programFiles = `C:\Program Files`
	}
	destDir := filepath.Join(programFiles, "TGDesk Client")

	if strings.EqualFold(srcDir, destDir) {
		// já estamos rodando da pasta instalada.
		registerAutostart(filepath.Join(destDir, filepath.Base(exe)))
		return
	}

	if err := copyDir(srcDir, destDir); err != nil {
		log.Printf("aviso: falha ao instalar em %s: %v (continuando a partir da pasta atual)", destDir, err)
		registerAutostart(exe)
		return
	}
	log.Printf("instalado em %s", destDir)
	registerAutostart(filepath.Join(destDir, filepath.Base(exe)))
}

func copyDir(src, dst string) error {
	if err := os.MkdirAll(dst, 0755); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if skipFromInstall(e.Name()) {
			continue
		}
		srcPath := filepath.Join(src, e.Name())
		dstPath := filepath.Join(dst, e.Name())
		if e.IsDir() {
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
			continue
		}
		if err := copyFile(srcPath, dstPath); err != nil {
			return err
		}
	}
	return nil
}

// skipFromInstall keeps dev-only artifacts (fonte Go, docs, config local já
// gravada) fora do pacote instalado — só o necessário pra rodar vai junto.
func skipFromInstall(name string) bool {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".go", ".md":
		return true
	}
	switch strings.ToLower(name) {
	case "go.mod", "go.sum", "tgdesk-agent.json":
		return true
	}
	return false
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

// registerAutostart adds a HKLM Run key so the agent (and the tgdesk.exe
// core it manages) survives a reboot for every user session.
func registerAutostart(exePath string) {
	k, _, err := registry.CreateKey(registry.LOCAL_MACHINE,
		`SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		log.Printf("aviso: falha ao registrar autostart: %v", err)
		return
	}
	defer k.Close()
	if err := k.SetStringValue("TGDeskHostAgent", `"`+exePath+`"`); err != nil {
		log.Printf("aviso: falha ao gravar valor de autostart: %v", err)
	}
}
