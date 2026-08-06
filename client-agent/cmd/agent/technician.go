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

	// E se o túnel do dispositivo não estiver de pé, esta função o sobe.
	//
	// Era aqui que a unificação de adaptador tinha deixado um buraco. Ela
	// tirou do técnico a criação do túnel — correto, dois adaptadores para o
	// mesmo /16 era o problema — e assumiu que o Host cuidaria. Só que numa
	// máquina Admin/Tech o serviço chama este caminho, e o Host não roda por
	// ele: ninguém subia nada. O log de uma atualização mostrou o buraco
	// inteiro — esta função anunciando "usa o túnel do dispositivo", o
	// host.log vazio, e a rede só voltando quando a versão anterior foi
	// restaurada.
	//
	// Subir aqui não recria o problema antigo: é o MESMO adaptador do Host
	// ("TGDesk", mesmo GUID), pela mesma bringUpTunnel. Continua sendo um só.
	if tunelDoDispositivoResponde(3 * time.Second) {
		log.Println("túnel do dispositivo já ativo — hub alcançável")
		return 0
	}
	log.Println("túnel do dispositivo ausente — subindo pelo caminho do Host")
	cfg := loadConfig()
	if cfg.DeviceID == "" || cfg.DeviceToken == "" {
		log.Println("aviso: dispositivo ainda não vinculado; o túnel sobe quando ele for")
		return 0
	}
	// Tenta de novo até o prazo, em vez de desistir na primeira.
	//
	// A primeira tentativa criou o adaptador e o gateway não respondeu em 30
	// segundos — o aperto de mão do WireGuard e o registro do peer nem sempre
	// fecham nesse tempo. Só que desistir ali deixava os 90 segundos seguintes
	// do orçamento do atualizador passando com ninguém tentando nada, e a
	// atualização revertia por falta de uma segunda tentativa.
	//
	// O prazo fica abaixo do que o atualizador tolera esperar pela rede: não
	// adianta seguir tentando depois que ele já desistiu.
	deadline := time.Now().Add(100 * time.Second)
	for tentativa := 1; ; tentativa++ {
		err := bringUpTunnel(cfg)
		if err == nil {
			log.Println("túnel do dispositivo ativo")
			return 0
		}
		if time.Now().After(deadline) {
			log.Printf("aviso: túnel do dispositivo não subiu em %d tentativas: %v",
				tentativa, err)
			return 0
		}
		log.Printf("túnel do dispositivo: tentativa %d falhou (%v); tentando de novo",
			tentativa, err)
		// Se o gateway responder enquanto esperamos, acabou: o adaptador da
		// tentativa anterior pode ter fechado o aperto de mão depois do prazo
		// dela.
		if tunelDoDispositivoResponde(5 * time.Second) {
			log.Println("túnel do dispositivo ativo")
			return 0
		}
	}
}

// tunelDoDispositivoResponde diz se o hub já é alcançável.
func tunelDoDispositivoResponde(timeout time.Duration) bool {
	conexao, err := net.DialTimeout("tcp", "10.70.0.1:8080", timeout)
	if err != nil {
		return false
	}
	conexao.Close()
	return true
}
