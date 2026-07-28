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
	CoreExe          string `json:"core_exe,omitempty"`
}

func configPath() string {
	return filepath.Join(tgdeskDataDir(), "identity", "device.json")
}

func tgdeskDataDir() string {
	if configured := os.Getenv("TGDESK_DATA_DIR"); configured != "" {
		_ = os.MkdirAll(filepath.Join(configured, "identity"), 0700)
		_ = os.MkdirAll(filepath.Join(configured, "state"), 0700)
		_ = os.MkdirAll(filepath.Join(configured, "logs"), 0700)
		return configured
	}
	base := os.Getenv("ProgramData")
	if base == "" {
		base = `C:\ProgramData`
	}
	dir := filepath.Join(base, "TGDesk")
	_ = os.MkdirAll(filepath.Join(dir, "identity"), 0700)
	_ = os.MkdirAll(filepath.Join(dir, "state"), 0700)
	_ = os.MkdirAll(filepath.Join(dir, "logs"), 0700)
	return dir
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

// configuredServer é preenchido pela flag --server (passada pelo tgdesk.exe
// ao lançar o agente). É a fonte da verdade do endereço do plano de controle
// — o mesmo valor que a UI Flutter usa (TGDESK_SERVER). Sem isso o agente
// caía no localhost e um client em outra rede nunca registrava.
var configuredServer string

func baseURL() string {
	if configuredServer != "" {
		return configuredServer
	}
	if v := os.Getenv("TGDESK_SERVER"); v != "" {
		return v
	}
	return "http://168.232.199.161:8090"
}

// httpClient com timeout curto: sem isso, uma conexão a um servidor
// inalcançável (client em outra rede, IP errado) travava ~21s no timeout de
// TCP do SO antes de reportar erro — deixando a UI parada. 12s cobre latência
// real de internet e falha rápido quando não dá.
var httpClient = &http.Client{Timeout: 12 * time.Second}

func postJSON(path string, body any, out any) (int, error) {
	b, _ := json.Marshal(body)
	resp, err := httpClient.Post(baseURL()+path, "application/json", bytes.NewReader(b))
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
		State       string `json:"state"`
		PairingCode string `json:"pairing_code"`
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
	if resp.PairingCode != "" && resp.PairingCode != cfg.PairingCode {
		cfg.PairingCode = resp.PairingCode
		_ = saveConfig(cfg)
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

// runHost implementa o papel Host: registro/pareamento/heartbeat, elevação
// sob demanda no bind, túnel WireGuard próprio (adaptador "tgdesk0", pool
// 10.70.2.x+), acesso remoto e telemetria.
func runHost(args []string) {
	log.SetFlags(0)
	// --server define o endereço do plano de controle (passado pelo tgdesk.exe).
	for i := 0; i < len(args); i++ {
		if args[i] == "--server" && i+1 < len(args) {
			configuredServer = args[i+1]
		} else if args[i] == "--core-exe" && i+1 < len(args) {
			configuredCoreExe = args[i+1]
		}
	}
	if !acquireHostSingleton() {
		log.Println("outra instância do agente Host já está rodando — encerrando")
		return
	}
	cfg := loadConfig()
	if cfg == nil {
		// Registro pode falhar se o servidor estiver inacessível (client em
		// outra rede, servidor fora do ar). Em vez de morrer calado — o que
		// deixava a UI presa em "aguardando agente" pra sempre — escrevemos
		// um status de erro visível e tentamos de novo a cada 5s.
		for {
			var err error
			cfg, err = registerDevice()
			if err == nil {
				break
			}
			log.Printf("falha ao registrar (servidor %s): %v — tentando de novo em 5s", baseURL(), err)
			writeStatus(tgdeskStatus{
				State:    "erro",
				Hostname: localHostname(),
				Error:    "Sem conexão com o servidor (" + baseURL() + "): " + err.Error(),
			})
			time.Sleep(5 * time.Second)
		}
	} else {
		log.Printf("dispositivo já registrado (id=%s)", cfg.DeviceID)
	}
	if configuredCoreExe != "" {
		cfg.CoreExe = configuredCoreExe
		_ = saveConfig(cfg)
	} else if cfg.CoreExe != "" {
		configuredCoreExe = cfg.CoreExe
	}

	var tunnelUp bool
	var remoteReady bool
	var privateFailures int
	writeStatus(tgdeskStatus{State: "guest", PairingCode: cfg.PairingCode, Hostname: localHostname(), DeviceID: cfg.DeviceID})
	for {
		if tunnelUp {
			if !remoteReady {
				if err := setupRemoteAccess(cfg); err != nil {
					log.Printf("acesso remoto privado ainda não disponível: %v", err)
					writeStatus(tgdeskStatus{
						State:       "ativo",
						Hostname:    localHostname(),
						DeviceID:    cfg.DeviceID,
						VirtualIP:   cfg.VirtualIP,
						TunnelUp:    true,
						RemoteError: err.Error(),
						FilesError:  "aguardando o módulo de acesso remoto privado",
					})
					time.Sleep(2 * time.Second)
					continue
				}
				remoteReady = true
				writeStatus(tgdeskStatus{
					State:       "ativo",
					Hostname:    localHostname(),
					DeviceID:    cfg.DeviceID,
					VirtualIP:   cfg.VirtualIP,
					RustdeskID:  cfg.RustdeskID,
					TunnelUp:    true,
					RemoteReady: true,
					FilesReady:  true,
				})
			}
			if err := runDeviceControlLoop(cfg, remoteReady); err != nil {
				privateFailures++
				log.Printf("canal privado caiu: %v — reconectando pela VPN", err)
				if privateFailures >= 3 {
					if err := refreshHubPeer(cfg); err != nil {
						log.Printf("recuperação pública do peer WireGuard falhou: %v", err)
					} else {
						log.Println("peer WireGuard renovado pelo canal público de recuperação")
					}
					// Não basta manter o adaptador marcado como Up: após uma
					// reinicialização do servidor o peer e o socket podem ter
					// expirado. Volta deliberadamente à etapa de criação do
					// túnel antes de reabrir o WebSocket.
					tunnelUp = false
					remoteReady = false
					privateFailures = 0
					writeStatus(tgdeskStatus{
						State: "erro", Hostname: localHostname(), DeviceID: cfg.DeviceID,
						VirtualIP: cfg.VirtualIP, TunnelUp: false,
						Error: "Reconectando ao servidor TGDesk",
					})
				}
				time.Sleep(2 * time.Second)
				continue
			}
		}

		state, err := heartbeat(cfg)
		if err != nil {
			log.Printf("heartbeat falhou: %v (tentando novamente em 5s)", err)
			writeStatus(tgdeskStatus{
				State:       "erro",
				PairingCode: cfg.PairingCode,
				Hostname:    localHostname(),
				DeviceID:    cfg.DeviceID,
				Error:       "Sem conexão com o servidor (" + baseURL() + ")",
			})
			time.Sleep(5 * time.Second)
			continue
		}

		switch state {
		case "guest":
			log.Println("aguardando vinculação por um técnico...")
			if tunnelUp {
				bringDownTunnel()
				tunnelUp, remoteReady = false, false
			}
		case "suspenso":
			log.Println("dispositivo suspenso pelo Super Admin — nenhuma função ativa")
			if tunnelUp {
				bringDownTunnel()
				tunnelUp, remoteReady = false, false
			}
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
		}

		writeStatus(tgdeskStatus{
			State:       state,
			PairingCode: cfg.PairingCode,
			Hostname:    localHostname(),
			DeviceID:    cfg.DeviceID,
			VirtualIP:   cfg.VirtualIP,
			RustdeskID:  cfg.RustdeskID,
			TunnelUp:    tunnelUp,
			RemoteReady: remoteReady,
			FilesReady:  remoteReady,
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

func bringDownTunnel() {
	if err := stopWireGuardNT("tgdesk0"); err != nil {
		log.Printf("falha ao desativar rede privada: %v", err)
	}
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

	hubPub, err := decodeBase64Key(hubCfg.HubPublicKey)
	if err != nil {
		return err
	}
	log.Println("criando adaptador WireGuardNT TGDesk")
	if err := startWireGuardNT("TGDesk", tgdeskHostAdapterGUID, priv, hubPub, hubCfg.HubEndpoint); err != nil {
		return fmt.Errorf("subir túnel WireGuardNT: %w", err)
	}

	if err := assignWindowsIP("TGDesk", hubCfg.VirtualIP); err != nil {
		log.Printf("aviso: não foi possível configurar o IP da interface automaticamente: %v", err)
		log.Printf("configure manualmente: netsh interface ip set address name=\"TGDesk\" static %s 255.255.0.0", hubCfg.VirtualIP)
	}
	if err := waitForPrivateGateway(); err != nil {
		return err
	}

	log.Println("túnel WireGuardNT ativo — dispositivo Online no painel do técnico")
	return nil
}

func waitForPrivateGateway() error {
	client := &http.Client{Timeout: 3 * time.Second}
	deadline := time.Now().Add(30 * time.Second)
	var lastErr error
	for time.Now().Before(deadline) {
		resp, err := client.Get("http://10.70.0.1:8080/healthz")
		if err == nil {
			_ = resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return nil
			}
			lastErr = fmt.Errorf("gateway respondeu status %d", resp.StatusCode)
		} else {
			lastErr = err
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("túnel criado, mas o gateway privado 10.70.0.1 não respondeu: %w", lastErr)
}

func refreshHubPeer(cfg *agentConfig) error {
	priv, err := decodeBase64Key(cfg.PrivateKey)
	if err != nil {
		return err
	}
	_, err = submitWGKey(cfg, priv.public())
	return err
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
