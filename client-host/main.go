// tgdesk-host — cliente mínimo do Módulo A (Fase 1): registra o dispositivo,
// exibe o código de pareamento, aguarda vinculação por um técnico, e então
// sobe um túnel WireGuard real até o hub do servidor central.
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

type agentConfig struct {
	DeviceID         string `json:"device_id"`
	DeviceToken      string `json:"device_token"`
	PairingCode      string `json:"pairing_code,omitempty"`
	PrivateKey       string `json:"private_key,omitempty"`
	VirtualIP        string `json:"virtual_ip,omitempty"`
	RustdeskID       string `json:"rustdesk_id,omitempty"`
	RendezvousHost   string `json:"rendezvous_host,omitempty"`
	RendezvousPubkey string `json:"rendezvous_pubkey,omitempty"`
}

func configPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "tgdesk-agent.json"
	}
	return filepath.Join(filepath.Dir(exe), "tgdesk-agent.json")
}

func loadConfig() *agentConfig {
	var cfg agentConfig
	b, err := os.ReadFile(configPath())
	if err != nil {
		return nil
	}
	if json.Unmarshal(b, &cfg) != nil {
		return nil
	}
	return &cfg
}

func saveConfig(cfg *agentConfig) error {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(configPath(), b, 0600)
}

func baseURL() string {
	if v := os.Getenv("TGDESK_SERVER"); v != "" {
		return v
	}
	return "http://127.0.0.1:8090"
}

func postJSON(path string, body any, out any) (int, error) {
	b, _ := json.Marshal(body)
	resp, err := http.Post(baseURL()+path, "application/json", bytes.NewReader(b))
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if out != nil {
		_ = json.NewDecoder(resp.Body).Decode(out)
	}
	return resp.StatusCode, nil
}

func localHostname() string {
	h, err := os.Hostname()
	if err != nil {
		return "TGDESK-HOST"
	}
	return h
}

func localMAC() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, i := range ifaces {
		if len(i.HardwareAddr) == 6 && i.Flags&net.FlagLoopback == 0 {
			return i.HardwareAddr.String()
		}
	}
	return ""
}

func registerDevice() (*agentConfig, error) {
	var resp struct {
		DeviceID    string `json:"device_id"`
		PairingCode string `json:"pairing_code"`
		DeviceToken string `json:"device_token"`
	}
	status, err := postJSON("/api/v1/devices/register", map[string]string{
		"hostname": localHostname(),
		"mac":      localMAC(),
		"role":     "host",
	}, &resp)
	if err != nil {
		return nil, err
	}
	if status != http.StatusCreated {
		return nil, fmt.Errorf("registro falhou (status %d)", status)
	}
	fmt.Println("========================================================")
	fmt.Println(" TGDesk Host — dispositivo instalado, aguardando vínculo")
	fmt.Println(" Código de pareamento:", resp.PairingCode)
	fmt.Println(" Informe esse código a um técnico autorizado no Hub.")
	fmt.Println("========================================================")
	cfg := &agentConfig{DeviceID: resp.DeviceID, DeviceToken: resp.DeviceToken, PairingCode: resp.PairingCode}
	return cfg, saveConfig(cfg)
}

// heartbeat returns the device's current state (guest/ativo/suspenso).
func heartbeat(cfg *agentConfig) (string, error) {
	var resp struct {
		State string `json:"state"`
	}
	status, err := postJSON("/api/v1/devices/heartbeat", map[string]string{
		"device_id":    cfg.DeviceID,
		"device_token": cfg.DeviceToken,
	}, &resp)
	if err != nil {
		return "", err
	}
	if status != http.StatusOK {
		return "", fmt.Errorf("heartbeat status %d", status)
	}
	return resp.State, nil
}

type wgKeyResponse struct {
	VirtualIP        string `json:"virtual_ip"`
	HubPublicKey     string `json:"hub_public_key"`
	HubEndpoint      string `json:"hub_endpoint"`
	HubVirtualIP     string `json:"hub_virtual_ip"`
	RendezvousHost   string `json:"rendezvous_host"`
	RendezvousPubkey string `json:"rendezvous_pubkey"`
}

func submitWGKey(cfg *agentConfig, pub wgKey) (*wgKeyResponse, error) {
	var resp wgKeyResponse
	status, err := postJSON("/api/v1/devices/wg-key", map[string]string{
		"device_id":    cfg.DeviceID,
		"device_token": cfg.DeviceToken,
		"public_key":   pub.base64(),
	}, &resp)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("wg-key status %d", status)
	}
	return &resp, nil
}

func main() {
	log.SetFlags(0)
	cfg := loadConfig()
	if cfg == nil {
		var err error
		cfg, err = registerDevice()
		if err != nil {
			log.Fatalf("erro ao registrar dispositivo: %v", err)
		}
	} else {
		log.Printf("dispositivo já registrado (id=%s)", cfg.DeviceID)
	}

	var tunnelUp bool
	var lastTelemetry time.Time
	writeStatus(tgdeskStatus{State: "guest", PairingCode: cfg.PairingCode, Hostname: localHostname(), DeviceID: cfg.DeviceID})

	for {
		state, err := heartbeat(cfg)
		if err != nil {
			log.Printf("heartbeat falhou: %v (tentando novamente em 5s)", err)
			time.Sleep(5 * time.Second)
			continue
		}

		switch state {
		case "guest":
			log.Println("aguardando vinculação por um técnico...")
		case "suspenso":
			log.Println("dispositivo suspenso pelo Super Admin — nenhuma função ativa")
		case "ativo":
			if !isElevated() {
				// Só pedimos UAC agora — é o único momento em que faz sentido
				// pro usuário (o técnico acabou de vincular o dispositivo).
				elevateAndRestart()
				return
			}
			ensureInstalled()
			if !tunnelUp {
				if err := bringUpTunnel(cfg); err != nil {
					log.Printf("falha ao subir túnel WireGuard: %v", err)
				} else {
					tunnelUp = true
				}
			}
			if cfg.RustdeskID == "" {
				if err := setupRemoteAccess(cfg); err != nil {
					log.Printf("falha ao configurar acesso remoto (RustDesk): %v", err)
				}
			}
			if time.Since(lastTelemetry) >= 30*time.Second {
				if err := reportTelemetry(cfg); err != nil {
					log.Printf("falha ao reportar telemetria: %v", err)
				}
				lastTelemetry = time.Now()
			}
		}

		writeStatus(tgdeskStatus{
			State:       state,
			PairingCode: cfg.PairingCode,
			Hostname:    localHostname(),
			DeviceID:    cfg.DeviceID,
			VirtualIP:   cfg.VirtualIP,
			RustdeskID:  cfg.RustdeskID,
			TunnelUp:    tunnelUp,
		})
		time.Sleep(5 * time.Second)
	}
}

func reportRustdeskID(cfg *agentConfig, id string) error {
	status, err := postJSON("/api/v1/devices/rustdesk-id", map[string]string{
		"device_id":    cfg.DeviceID,
		"device_token": cfg.DeviceToken,
		"rustdesk_id":  id,
	}, nil)
	if err != nil {
		return err
	}
	if status != http.StatusOK {
		return fmt.Errorf("rustdesk-id status %d", status)
	}
	return nil
}

func bringUpTunnel(cfg *agentConfig) error {
	var priv wgKey
	if cfg.PrivateKey == "" {
		k, err := generateKey()
		if err != nil {
			return err
		}
		priv = k
	} else {
		b, err := decodeBase64Key(cfg.PrivateKey)
		if err != nil {
			return err
		}
		priv = b
	}

	hubCfg, err := submitWGKey(cfg, priv.public())
	if err != nil {
		return fmt.Errorf("envio de chave pública ao servidor: %w", err)
	}
	cfg.PrivateKey = priv.base64()
	cfg.VirtualIP = hubCfg.VirtualIP
	cfg.RendezvousHost = hubCfg.RendezvousHost
	cfg.RendezvousPubkey = hubCfg.RendezvousPubkey
	_ = saveConfig(cfg)

	log.Printf("vinculado! IP virtual atribuído: %s (hub: %s em %s)", hubCfg.VirtualIP, hubCfg.HubVirtualIP, hubCfg.HubEndpoint)

	tunDev, err := tun.CreateTUN("tgdesk0", device.DefaultMTU)
	if err != nil {
		return fmt.Errorf("criar adaptador WireGuard (requer privilégio de administrador para instalar o driver Wintun na primeira vez): %w", err)
	}
	realName, _ := tunDev.Name()

	logger := device.NewLogger(device.LogLevelError, "tgdesk-host: ")
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), logger)

	hubPub, err := decodeBase64Key(hubCfg.HubPublicKey)
	if err != nil {
		return err
	}
	uapi := fmt.Sprintf(
		"private_key=%s\npublic_key=%s\nendpoint=%s\nallowed_ip=%s/16\npersistent_keepalive_interval=25\n",
		priv.hex(), hubPub.hex(), hubCfg.HubEndpoint, "10.70.0.0",
	)
	if err := dev.IpcSet(uapi); err != nil {
		return fmt.Errorf("configurar peer do hub: %w", err)
	}
	if err := dev.Up(); err != nil {
		return fmt.Errorf("subir interface: %w", err)
	}

	if err := assignWindowsIP(realName, hubCfg.VirtualIP); err != nil {
		log.Printf("aviso: não foi possível configurar o IP da interface automaticamente: %v", err)
		log.Printf("configure manualmente: netsh interface ip set address name=\"%s\" static %s 255.255.0.0", realName, hubCfg.VirtualIP)
	}

	log.Println("túnel WireGuard ativo — dispositivo Online no painel do técnico")
	return nil
}

func decodeBase64Key(s string) (wgKey, error) {
	var k wgKey
	raw, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(raw) != 32 {
		return wgKey{}, fmt.Errorf("chave inválida")
	}
	copy(k[:], raw)
	return k, nil
}
