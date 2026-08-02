package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

type technicianConfig struct {
	PrivateKey string `json:"private_key,omitempty"`
	VirtualIP  string `json:"virtual_ip,omitempty"`
}

func technicianConfigPath() string {
	return filepath.Join(tgdeskDataDir(), "identity", "technician-vpn.json")
}

func loadTechnicianConfig() *technicianConfig {
	var cfg technicianConfig
	b, err := os.ReadFile(technicianConfigPath())
	if err != nil || json.Unmarshal(b, &cfg) != nil {
		return &technicianConfig{}
	}
	return &cfg
}

func saveTechnicianConfig(cfg *technicianConfig) {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(technicianConfigPath(), b, 0600)
}

func submitTechnicianWGKey(serverURL, token string, pub wgKey) (*wgKeyResponse, error) {
	body, _ := json.Marshal(map[string]string{"public_key": pub.base64()})
	req, err := http.NewRequest(http.MethodPost, serverURL+"/api/v1/technicians/wg-key", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := httpClient.Do(req) // timeout curto (ver host.go)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("wg-key status %d", resp.StatusCode)
	}
	var out wgKeyResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	return &out, nil
}

// runTechnician dá ao Técnico (Hub) seu próprio túnel WireGuard —
// identidade, adaptador ("tgdesk-tech0") e pool de IP (10.70.1.x)
// completamente independentes do papel Host que este mesmo binário também
// sabe desempenhar (ver ARCHITECTURE_FLOW.md, Seção 3).
func runTechnician(args []string) int {
	if !isElevated() {
		elevateAndRestart()
		return 0
	}
	if !acquireTechnicianSingleton() {
		log.Println("túnel do técnico já está ativo")
		return 0
	}
	fs := flag.NewFlagSet("technician", flag.ExitOnError)
	server := fs.String("server", os.Getenv("TGDESK_SERVER"), "URL do api-core")
	token := fs.String("token", os.Getenv("TGDESK_TOKEN"), "JWT do técnico logado no Hub")
	_ = fs.Parse(args)
	if *server == "" {
		*server = "http://127.0.0.1:8090"
	}
	if *token == "" {
		log.Println("faltou --token (ou TGDESK_TOKEN) — o Hub deve passar o JWT do login")
		return 1
	}

	cfg := loadTechnicianConfig()
	var priv wgKey
	if cfg.PrivateKey == "" {
		k, err := generateKey()
		if err != nil {
			log.Printf("gerar chave: %v", err)
			return 1
		}
		priv = k
	} else {
		k, err := decodeBase64Key(cfg.PrivateKey)
		if err != nil {
			log.Printf("chave salva inválida: %v", err)
			return 1
		}
		priv = k
	}

	hubCfg, err := submitTechnicianWGKey(*server, *token, priv.public())
	if err != nil {
		log.Printf("registrar chave no servidor: %v", err)
		return 1
	}
	cfg.PrivateKey = priv.base64()
	cfg.VirtualIP = hubCfg.VirtualIP
	saveTechnicianConfig(cfg)
	log.Printf("túnel do técnico: IP virtual %s (hub %s em %s)", hubCfg.VirtualIP, hubCfg.HubVirtualIP, hubCfg.HubEndpoint)

	hubPub, err := decodeBase64Key(hubCfg.HubPublicKey)
	if err != nil {
		log.Printf("chave do hub inválida: %v", err)
		return 1
	}
	log.Println("criando adaptador WireGuardNT TGDesk-Tech")
	if err := startWireGuardNT("TGDesk-Tech", tgdeskTechAdapterGUID, priv, hubPub, hubCfg.HubEndpoint); err != nil {
		log.Printf("subir túnel WireGuardNT: %v", err)
		return 1
	}

	if err := assignWindowsIP("TGDesk-Tech", hubCfg.VirtualIP); err != nil {
		log.Printf("aviso: configure o IP manualmente: netsh interface ip set address name=\"TGDesk-Tech\" static %s 255.255.0.0", hubCfg.VirtualIP)
	}

	log.Println("túnel WireGuardNT do técnico ativo — hbbs/hbbr agora alcançáveis pela VPN")
	select {}
}
