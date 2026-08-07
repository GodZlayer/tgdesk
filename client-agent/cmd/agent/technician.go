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

	// Remove o adaptador antigo UMA vez por processo, se a máquina vem de uma
	// versão anterior: duas rotas para o mesmo /16 é o que estamos eliminando.
	//
	// Uma vez, e não a cada chamada, porque o serviço reinvoca esta função em
	// laço para supervisionar o túnel — e mexer no driver WireGuardNT a cada
	// volta é metade do padrão que leva a DRIVER_UNLOADED_WITHOUT_CANCELLING_
	// PENDING_OPERATIONS. Depois da primeira remoção o adaptador não volta a
	// existir: nada neste código o cria.
	removerAdaptadorLegadoUmaVez()
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
	// UMA criação de adaptador, e depois só espera.
	//
	// A versão anterior desta função recriava o adaptador a cada tentativa
	// falha, até três vezes em cem segundos — e o serviço reinvocava tudo a
	// cada trinta. Criar e destruir adaptador WireGuardNT em laço é
	// exatamente o padrão que produz DRIVER_UNLOADED_WITHOUT_CANCELLING_
	// PENDING_OPERATIONS: o handle de cada criação nunca é fechado, e o driver
	// acaba descarregado com E/S pendente. Esta máquina teve um BSOD 0xCE
	// depois que essa versão entrou.
	//
	// Não consigo provar a causa sem o minidump, mas o padrão é indefensável
	// de qualquer forma: o aperto de mão do WireGuard demora, e recriar o
	// adaptador no meio dele destrói justamente o que estava prestes a
	// completar. Cria uma vez e espera — que é o que faltava na versão que
	// desistia em trinta segundos.
	if err := bringUpTunnel(cfg); err != nil {
		log.Printf("aviso: não foi possível criar o túnel do dispositivo: %v", err)
		return 0
	}
	// A espera vai até um pouco antes do que o atualizador tolera: seguir
	// esperando depois que ele desistiu não serve para nada.
	if tunelDoDispositivoResponde(90 * time.Second) {
		log.Println("túnel do dispositivo ativo")
	} else {
		log.Println("aviso: túnel criado, mas o hub não respondeu no prazo; " +
			"o adaptador fica de pé e a próxima verificação reavalia")
	}
	return 0
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

// adaptadorLegadoRemovido garante que a limpeza do TGDesk-Tech aconteça uma vez
// só na vida do processo.
var adaptadorLegadoRemovido bool

func removerAdaptadorLegadoUmaVez() {
	if adaptadorLegadoRemovido {
		return
	}
	adaptadorLegadoRemovido = true
	if err := stopWireGuardNT("TGDesk-Tech"); err == nil {
		log.Println("adaptador TGDesk-Tech removido — o técnico passa a usar o túnel do dispositivo")
	}
}
