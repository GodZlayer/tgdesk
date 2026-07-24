// tgdesk-agent — um único binário para os dois papéis de rede do TGDesk:
//
//	tgdesk-agent.exe                       → papel Host (padrão)
//	tgdesk-agent.exe host                  → papel Host (explícito)
//	tgdesk-agent.exe technician --token X  → papel Técnico (usado pelo Hub)
//
// Consolida o que antes eram dois executáveis Go separados
// (tgdesk-host.exe e tgdesk-tunnel.exe) — cada papel continua com sua
// própria identidade de rede, adaptador e pool de IP (ver
// client-tgdesk/ARCHITECTURE_FLOW.md, Seção 3), só o binário é compartilhado.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "technician":
			os.Exit(runTechnician(os.Args[2:]))
		case "host":
			runHost(os.Args[2:])
			return
		case "update":
			os.Exit(runManualUpdate())
		default:
			fmt.Printf("argumento desconhecido: %q (use \"host\" ou \"technician\")\n", os.Args[1])
			os.Exit(1)
		}
		return
	}
	runHost(nil)
}
