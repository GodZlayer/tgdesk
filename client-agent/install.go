package main

import (
	"log"
	"os"

	"golang.org/x/sys/windows/registry"
)

var installChecked bool

// ensureInstalled registra o autostart do agente. O binário NÃO é mais
// copiado para Program Files — ele vem embutido no `tgdesk.exe` (asset
// Flutter) e é extraído para `%LOCALAPPDATA%\TGDesk`, de onde roda. Isso é o
// que faz o cliente instalado não ter um `tgdesk-agent.exe` solto na pasta.
// Só precisamos garantir persistência: uma entrada Run por usuário apontando
// para o agente extraído. Chamado depois de já estarmos elevados.
func ensureInstalled() {
	if installChecked {
		return
	}
	installChecked = true

	exe, err := os.Executable()
	if err != nil {
		return
	}
	registerAutostart(exe)
}

// registerAutostart adiciona uma entrada Run por usuário (HKCU) apontando
// para o agente extraído em %LOCALAPPDATA%\TGDesk, para o Host sobreviver a
// um reboot. Por-usuário (não HKLM) porque o binário mora no perfil do
// usuário, não numa pasta de máquina.
func registerAutostart(exePath string) {
	k, _, err := registry.CreateKey(registry.CURRENT_USER,
		`SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		log.Printf("aviso: falha ao registrar autostart: %v", err)
		return
	}
	defer k.Close()
	if err := k.SetStringValue("TGDeskHostAgent", `"`+exePath+`" host`); err != nil {
		log.Printf("aviso: falha ao gravar valor de autostart: %v", err)
	}
}
