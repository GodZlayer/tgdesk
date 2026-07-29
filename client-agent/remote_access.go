package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var configuredCoreExe string

// rustdeskExePath looks for the RustDesk-core binary bundled next to this
// agent. Prefers the unified tgdesk.exe (núcleo RustDesk + Hub no mesmo
// binário); cai para rustdesk.exe por compatibilidade com pacotes antigos.
func rustdeskExePath() (string, error) {
	if configuredCoreExe != "" {
		if info, err := os.Stat(configuredCoreExe); err == nil && !info.IsDir() {
			return configuredCoreExe, nil
		}
	}
	for _, root := range []string{os.Getenv("ProgramFiles"), os.Getenv("ProgramW6432")} {
		if root == "" {
			continue
		}
		candidate := filepath.Join(root, "TGDesk Client", "tgdesk.exe")
		if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
			configuredCoreExe = candidate
			return candidate, nil
		}
	}
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
	return "", fmt.Errorf("núcleo TGDesk não encontrado; esperado em Program Files ou no caminho recebido do aplicativo")
}

// writeRustdeskOptions points the bundled RustDesk client at the TGDesk
// rendezvous/relay instead of the public RustDesk network (Seção 8.B).
func writeRustdeskOptions(rendezvousHost, rendezvousKey string) error {
	appData := os.Getenv("APPDATA")
	if appData == "" {
		return fmt.Errorf("variável de ambiente APPDATA vazia")
	}
	dir := filepath.Join(appData, "TGDesk", "config")
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
approve-mode = 'password'
verification-method = 'use-permanent-password'
access-mode = 'full'
enable-keyboard = 'Y'
enable-file-transfer = 'Y'
enable-file-copy-paste = 'Y'
`, rendezvousHost, rendezvousKey)
	return os.WriteFile(filepath.Join(dir, "TGDesk2.toml"), []byte(content), 0600)
}

func coreCommand(exePath string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, exePath, args...).CombinedOutput()
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	return strings.TrimSpace(string(output)), err
}

func configureRemoteCore(exePath string, cfg *agentConfig) error {
	options := []struct {
		key   string
		value string
	}{
		{"custom-rendezvous-server", cfg.RendezvousHost},
		{"key", cfg.RendezvousPubkey},
		{"approve-mode", "password"},
		{"verification-method", "use-permanent-password"},
		{"access-mode", "full"},
		{"enable-keyboard", "Y"},
		{"enable-file-transfer", "Y"},
		{"enable-file-copy-paste", "Y"},
	}
	for _, option := range options {
		output, err := coreCommand(exePath, "--option", option.key, option.value)
		if err != nil {
			return fmt.Errorf("configurar %s: %w (%s)", option.key, err, output)
		}
		confirmed, err := coreCommand(exePath, "--option", option.key)
		if err != nil || confirmed != option.value {
			if option.key == "key" {
				confirmed = "<oculto>"
			}
			return fmt.Errorf("núcleo remoto não confirmou %s (recebido=%q)", option.key, confirmed)
		}
	}
	var lastOutput string
	for attempt := 0; attempt < 5; attempt++ {
		output, err := coreCommand(exePath, "--password", cfg.RemoteCredential)
		lastOutput = output
		if err == nil && strings.Contains(output, "Done!") {
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("núcleo remoto recusou a credencial automática: %s", lastOutput)
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
	if cfg.RemoteCredential == "" {
		return fmt.Errorf("credencial automática de acesso remoto não recebida")
	}
	if err := configureRemoteCore(exePath, cfg); err != nil {
		return fmt.Errorf("configurar backend remoto: %w", err)
	}
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(cfg.RendezvousHost, "21116"), 3*time.Second)
	if err != nil {
		return fmt.Errorf("rendezvous privado ainda não alcançável pela VPN: %w", err)
	}
	_ = conn.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, exePath, "--get-id").Output()
	if err != nil {
		if ctx.Err() != nil {
			return fmt.Errorf("tempo esgotado ao obter ID do núcleo TGDesk")
		}
		return fmt.Errorf("obter ID do RustDesk: %w", err)
	}
	id := strings.TrimSpace(string(out))
	if id == "" {
		return fmt.Errorf("RustDesk retornou ID vazio")
	}

	cfg.RustdeskID = id
	_ = saveConfig(cfg)
	return nil
}
