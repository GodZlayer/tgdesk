package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
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

// runTechnician não sobe mais túnel próprio.
//
// O TGDesk é uma base só: todo dispositivo tem UM adaptador ("tgdesk0") e um
// endereço na VPN. Papel — cliente, técnico, supervisor, admin — é decidido
// pelo servidor a partir da credencial apresentada, nunca pela rede.
//
// Antes existia um segundo adaptador ("TGDesk-Tech", pool 10.70.1.x) para o
// papel Técnico. Isso deixava a mesma máquina com duas rotas para
// 10.70.0.0/16, resolvidas por métrica do Windows, tornando imprevisível qual
// endereço originava o tráfego — e o isolamento por subrede depende de saber
// exatamente isso.
//
// Mantido como ponto de entrada porque o serviço Windows e o Hub ainda o
// invocam: garante que o túnel do dispositivo está de pé, e é por ele que o
// técnico alcança o hub.
func runTechnician(args []string) int {
	if !isElevated() {
		elevateAndRestart()
		return 0
	}
	fs := flag.NewFlagSet("technician", flag.ExitOnError)
	_ = fs.String("server", os.Getenv("TGDESK_SERVER"), "URL do api-core")
	_ = fs.String("token", os.Getenv("TGDESK_TOKEN"), "JWT do técnico logado no Hub")
	_ = fs.Parse(args)

	// Remove o adaptador antigo, se a máquina vem de uma versão anterior: duas
	// rotas para o mesmo /16 é justamente o que estamos eliminando.
	if err := stopWireGuardNT("TGDesk-Tech"); err == nil {
		log.Println("adaptador TGDesk-Tech removido — o técnico passa a usar o túnel do dispositivo")
	}
	log.Println("papel de técnico usa o túnel do dispositivo (tgdesk0); nenhum adaptador adicional é criado")

	// Quem sobe o túnel é o Host. Aqui só se confere que ele subiu — e se não
	// subiu, isso é dito em voz alta.
	//
	// O comentário desta função dizia que ela "garante que o túnel do
	// dispositivo está de pé". Não garantia: removia o adaptador antigo e
	// retornava sucesso, com ou sem rede. Numa atualização isso apareceu do
	// pior jeito — o Host tinha morrido por não conseguir o singleton, esta
	// função declarou tudo certo, e o updater ficou dois minutos esperando uma
	// rede que ninguém estava subindo.
	if err := aguardarTunelDoDispositivo(90 * time.Second); err != nil {
		log.Printf("aviso: o túnel do dispositivo não respondeu: %v", err)
	} else {
		log.Println("túnel do dispositivo respondendo — hub alcançável")
	}
	return 0
}

// aguardarTunelDoDispositivo espera o hub responder pelo túnel que o Host
// mantém. Não cria adaptador nenhum: um segundo adaptador para o mesmo /16 é
// justamente o que a unificação eliminou.
func aguardarTunelDoDispositivo(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var ultimo error
	for time.Now().Before(deadline) {
		conexao, err := net.DialTimeout("tcp", "10.70.0.1:8080", 2*time.Second)
		if err == nil {
			conexao.Close()
			return nil
		}
		ultimo = err
		time.Sleep(time.Second)
	}
	return ultimo
}
