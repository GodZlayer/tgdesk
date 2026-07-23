package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// rustdeskExePath looks for the RustDesk-core binary bundled next to this
// agent. Prefers the unified tgdesk.exe (núcleo RustDesk + Hub no mesmo
// binário); cai para rustdesk.exe por compatibilidade com pacotes antigos.
func rustdeskExePath() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	dir := filepath.Dir(exe)
	for _, name := range []string{"tgdesk.exe", "rustdesk.exe"} {
		candidate := filepath.Join(dir, name)
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	return "", fmt.Errorf("tgdesk.exe/rustdesk.exe não encontrado ao lado do agente (%s)", dir)
}

// writeRustdeskOptions points the bundled RustDesk client at the TGDesk
// rendezvous/relay instead of the public RustDesk network (Seção 8.B).
func writeRustdeskOptions(rendezvousHost, rendezvousKey string) error {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return fmt.Errorf("variável de ambiente APPDATA vazia")
	}
	dir := filepath.Join(appData, "RustDesk", "config")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	content := fmt.Sprintf(`rendezvous_server = ''
nat_type = 0
serial = 0
unlock_pin = ''
trusted_devices = ''

[options]
custom-rendezvous-server = '%s'
key = '%s'
`, rendezvousHost, rendezvousKey)
	return os.WriteFile(filepath.Join(dir, "RustDesk2.toml"), []byte(content), 0600)
}

// setupRemoteAccess points the RustDesk core (tgdesk.exe, já rodando desde o
// boot via atalho de inicialização do instalador) para o nosso hbbs, e
// reporta o RustDesk ID resultante ao servidor para aparecer ao lado do
// device no Hub do Técnico (Seção 8.B / integração Fase 2). Não lança um
// processo novo — tgdesk.exe já contém o núcleo RustDesk e já está de pé.
func setupRemoteAccess(cfg *agentConfig) error {
	if cfg.RendezvousHost == "" || cfg.RendezvousPubkey == "" {
		return fmt.Errorf("configuração do rendezvous ainda não recebida do servidor")
	}
	exePath, err := rustdeskExePath()
	if err != nil {
		return err
	}
	if err := writeRustdeskOptions(cfg.RendezvousHost, cfg.RendezvousPubkey); err != nil {
		return fmt.Errorf("gravar config do RustDesk: %w", err)
	}

	out, err := exec.Command(exePath, "--get-id").Output()
	if err != nil {
		return fmt.Errorf("obter ID do RustDesk: %w", err)
	}
	id := strings.TrimSpace(string(out))
	if id == "" {
		return fmt.Errorf("RustDesk retornou ID vazio")
	}

	if err := reportRustdeskID(cfg, id); err != nil {
		return fmt.Errorf("reportar ID ao servidor: %w", err)
	}
	cfg.RustdeskID = id
	_ = saveConfig(cfg)
	return nil
}
