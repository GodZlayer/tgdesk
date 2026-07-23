// tgdesk-tunnel — dá ao Técnico (Hub) um túnel WireGuard próprio, com seu
// próprio adaptador de rede e chave, independente de qualquer tgdesk-host.exe
// que esteja instalado na mesma máquina física. Sem isso, o Hub não
// conseguiria alcançar o hbbs/hbbr (que só respondem dentro da VPN) nem
// coexistir com um Host na mesma máquina sem disputar o mesmo vínculo.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

type tunnelConfig struct {
	PrivateKey string `json:"private_key,omitempty"`
	VirtualIP  string `json:"virtual_ip,omitempty"`
}

func configPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "tgdesk-tunnel-config.json"
	}
	return filepath.Join(filepath.Dir(exe), "tgdesk-tunnel-config.json")
}

func loadConfig() *tunnelConfig {
	var cfg tunnelConfig
	b, err := os.ReadFile(configPath())
	if err != nil || json.Unmarshal(b, &cfg) != nil {
		return &tunnelConfig{}
	}
	return &cfg
}

func saveConfig(cfg *tunnelConfig) {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(configPath(), b, 0600)
}

type wgKeyResponse struct {
	VirtualIP        string `json:"virtual_ip"`
	HubPublicKey     string `json:"hub_public_key"`
	HubEndpoint      string `json:"hub_endpoint"`
	HubVirtualIP     string `json:"hub_virtual_ip"`
	RendezvousHost   string `json:"rendezvous_host"`
	RendezvousPubkey string `json:"rendezvous_pubkey"`
}

func submitTechnicianWGKey(serverURL, token string, pub wgKey) (*wgKeyResponse, error) {
	body, _ := json.Marshal(map[string]string{"public_key": pub.base64()})
	req, err := http.NewRequest(http.MethodPost, serverURL+"/api/v1/technicians/wg-key", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
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

func main() {
	log.SetFlags(0)
	server := flag.String("server", os.Getenv("TGDESK_SERVER"), "URL do api-core, ex: http://127.0.0.1:8090")
	token := flag.String("token", os.Getenv("TGDESK_TOKEN"), "JWT do técnico logado no Hub")
	flag.Parse()
	if *server == "" {
		*server = "http://127.0.0.1:8090"
	}
	if *token == "" {
		log.Fatal("faltou --token (ou TGDESK_TOKEN) — o Hub deve passar o JWT do login")
	}

	cfg := loadConfig()
	var priv wgKey
	if cfg.PrivateKey == "" {
		k, err := generateKey()
		if err != nil {
			log.Fatalf("gerar chave: %v", err)
		}
		priv = k
	} else {
		k, err := decodeBase64Key(cfg.PrivateKey)
		if err != nil {
			log.Fatalf("chave salva inválida: %v", err)
		}
		priv = k
	}

	hubCfg, err := submitTechnicianWGKey(*server, *token, priv.public())
	if err != nil {
		log.Fatalf("registrar chave no servidor: %v", err)
	}
	cfg.PrivateKey = priv.base64()
	cfg.VirtualIP = hubCfg.VirtualIP
	saveConfig(cfg)
	log.Printf("túnel do técnico: IP virtual %s (hub %s em %s)", hubCfg.VirtualIP, hubCfg.HubVirtualIP, hubCfg.HubEndpoint)

	tunDev, err := tun.CreateTUN("tgdesk-tech0", device.DefaultMTU)
	if err != nil {
		log.Fatalf("criar adaptador WireGuard (requer administrador na primeira vez): %v", err)
	}
	realName, _ := tunDev.Name()

	logger := device.NewLogger(device.LogLevelError, "tgdesk-tunnel: ")
	dev := device.NewDevice(tunDev, conn.NewDefaultBind(), logger)

	hubPub, err := decodeBase64Key(hubCfg.HubPublicKey)
	if err != nil {
		log.Fatalf("chave do hub inválida: %v", err)
	}
	uapi := fmt.Sprintf(
		"private_key=%s\npublic_key=%s\nendpoint=%s\nallowed_ip=%s/16\npersistent_keepalive_interval=25\n",
		priv.hex(), hubPub.hex(), hubCfg.HubEndpoint, "10.70.0.0",
	)
	if err := dev.IpcSet(uapi); err != nil {
		log.Fatalf("configurar peer do hub: %v", err)
	}
	if err := dev.Up(); err != nil {
		log.Fatalf("subir interface: %v", err)
	}

	if err := assignWindowsIP(realName, hubCfg.VirtualIP); err != nil {
		log.Printf("aviso: configure o IP manualmente: netsh interface ip set address name=\"%s\" static %s 255.255.0.0", realName, hubCfg.VirtualIP)
	}

	log.Println("túnel do técnico ativo — hbbs/hbbr agora alcançáveis pela VPN")
	select {} // mantém o processo vivo; o Hub o encerra junto quando fecha
}

func assignWindowsIP(ifaceName, ip string) error {
	cmd := exec.Command("netsh", "interface", "ip", "set", "address",
		"name="+ifaceName, "static", ip, "255.255.0.0")
	return cmd.Run()
}
