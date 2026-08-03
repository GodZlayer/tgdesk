// tgdesk-updater — atualizador standalone do TGDesk. Roda independente de
// tgdesk.exe estar operacional ou não: consulta/baixa/aplica atualizações
// usando a mesma lógica de client-agent/internal/updatecore (fonte de
// verdade única, sem duplicação com a DLL tgdesk_agent.dll).
package main

import (
	"flag"
	"fmt"
	"os"
)

func usage() {
	fmt.Fprintln(os.Stderr, "uso: tgdesk-updater.exe [opção]")
	fmt.Fprintln(os.Stderr, "  -apply-staged -staging X -install-dir Y -parent PID   aplica uma atualização já staged")
}

func main() {
	applyStaged := flag.Bool("apply-staged", false, "aplica uma atualização já staged")
	staging := flag.String("staging", "", "diretório de staging (usado com -apply-staged)")
	installDir := flag.String("install-dir", "", "diretório de instalação (usado com -apply-staged)")
	parent := flag.Int("parent", 0, "PID do processo pai a aguardar antes de aplicar (usado com -apply-staged)")
	readyFile := flag.String("ready-file", "", "arquivo de confirmacao da janela visivel")
	flag.Parse()

	switch {
	case *applyStaged:
		if *staging == "" || *installDir == "" {
			usage()
			os.Exit(1)
		}
		if err := runApplyStagedWithStatus(*staging, *installDir, uint32(*parent), *readyFile); err != nil {
			fmt.Fprintln(os.Stderr, err.Error())
			os.Exit(1)
		}
		os.Exit(0)
	default:
		usage()
		os.Exit(1)
	}
}
