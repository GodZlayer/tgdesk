//go:build windows

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

type storedMachineCredential struct {
	CredentialID string `json:"credential_id"`
	Secret       string `json:"secret"`
	MachineID    string `json:"machine_id"`
}

type refreshedMachineSession struct {
	Token string `json:"token"`
}

func unprotectMachineCredential(path string) (*storedMachineCredential, error) {
	encrypted, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	if len(encrypted) == 0 {
		return nil, fmt.Errorf("credencial vazia")
	}
	input := windows.DataBlob{Size: uint32(len(encrypted)), Data: &encrypted[0]}
	var output windows.DataBlob
	if err := windows.CryptUnprotectData(&input, nil, nil, 0, nil, 0, &output); err != nil {
		return nil, err
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(output.Data)))
	clear := unsafe.Slice(output.Data, output.Size)
	var credential storedMachineCredential
	if err := json.Unmarshal(clear, &credential); err != nil {
		return nil, err
	}
	if credential.CredentialID == "" || credential.Secret == "" || credential.MachineID == "" {
		return nil, fmt.Errorf("credencial incompleta")
	}
	return &credential, nil
}

func refreshMachineSession(serverURL string, credential *storedMachineCredential) (string, error) {
	body, _ := json.Marshal(credential)
	resp, err := httpClient.Post(
		serverURL+"/api/v1/auth/technician/refresh",
		"application/json", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("refresh status %d", resp.StatusCode)
	}
	var session refreshedMachineSession
	if err := json.NewDecoder(resp.Body).Decode(&session); err != nil {
		return "", err
	}
	if session.Token == "" {
		return "", fmt.Errorf("token vazio")
	}
	return session.Token, nil
}

// runTechnicianService is started by the TGDesk Windows service. LocalSystem
// can create/open the WireGuardNT adapter without a second UAC prompt.
func runTechnicianService(serverURL string) int {
	logDir := filepath.Join(tgdeskDataDir(), "logs")
	_ = os.MkdirAll(logDir, 0755)
	if logFile, err := os.OpenFile(filepath.Join(logDir, "agent.log"),
		os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644); err == nil {
		log.SetOutput(logFile)
		defer logFile.Close()
	}
	if serverURL == "" {
		serverURL = "http://168.232.199.161:8090"
	}
	credentialPath := filepath.Join(tgdeskDataDir(), "identity", "technician.dat")
	credential, err := unprotectMachineCredential(credentialPath)
	if os.IsNotExist(err) {
		return 0 // Client puro: não possui identidade Admin/Tech.
	}
	if err != nil {
		appendAgentLog("vpn-service: ler credencial: %v", err)
		return 1
	}
	var token string
	for {
		token, err = refreshMachineSession(serverURL, credential)
		if err == nil {
			break
		}
		appendAgentLog("vpn-service: renovar sessão: %v; nova tentativa em 10s", err)
		time.Sleep(10 * time.Second)
	}
	// A identidade Admin/Tech é independente do cadastro deste computador
	// como host. Exigir que o host estivesse ativo aqui criava um deadlock:
	// uma instalação Admin nova permanecia guest e nunca ganhava sua VPN.
	appendAgentLog("vpn-service: iniciando túnel Admin/Tech")
	if code := runTechnician([]string{"--server", serverURL, "--token", token}); code != 0 {
		return code
	}

	// E agora fica de pé, porque o túnel morre junto com quem o criou.
	//
	// O adaptador WireGuardNT pertence ao processo que abriu o handle — e o
	// handle nunca é fechado, de propósito: enquanto o processo vive, o
	// adaptador vive. Retornar aqui encerrava o processo do serviço e levava o
	// túnel junto, segundos depois de o criar.
	//
	// Era esse o buraco que sobrou da unificação de adaptador. Ela tirou do
	// técnico a criação do túnel contando com o Host, mas em máquina Admin/Tech
	// é este serviço que roda, não o Host. O log de quatro atualizações
	// seguidas mostrou o mesmo desenho: adaptador criado, gateway sem
	// responder, reversão — e o host.log vazio o tempo todo.
	//
	// O laço também vigia: se o túnel cair, ele volta. Um serviço que só sobe
	// a rede uma vez e dorme não é serviço, é script de inicialização.
	appendAgentLog("vpn-service: túnel de pé; supervisionando")
	// A vigilância confere de perto e age de longe.
	//
	// Conferir a cada 30 segundos é barato: é um dial TCP. Mas AGIR a cada 30
	// segundos não é — cada ação cria um adaptador WireGuardNT, e criar
	// adaptador em laço é o padrão que leva o driver a ser descarregado com
	// E/S pendente (BSOD 0xCE). Depois de uma tentativa, espera de verdade
	// antes da seguinte: o aperto de mão do WireGuard leva dezenas de segundos,
	// e insistir por cima dele destrói o que estava quase pronto.
	const esperaEntreTentativas = 5 * time.Minute
	var ultimaTentativa time.Time
	for {
		time.Sleep(30 * time.Second)
		if tunelDoDispositivoResponde(5 * time.Second) {
			continue
		}
		// QUEM É DONO DO ADAPTADOR NÃO PODE SER DOIS.
		//
		// Numa máquina que é dispositivo E técnico, o `tgdesk0` pertence ao
		// agente do dispositivo — este serviço apenas o usa. Reconstruí-lo
		// daqui cria dois supervisores para o mesmo adaptador, e o resultado
		// medido no parque foi um ciclo: o técnico recria, o adaptador some e
		// volta, TODAS as conexões TCP que passavam por ele morrem, e o
		// RustDesk reconecta com porta nova a cada dois minutos.
		//
		// Era essa a causa de "a máquina está online mas não acessível": não
		// era o RustDesk desistindo, era o chão sumindo embaixo dele.
		//
		// Quando existe identidade de dispositivo, este serviço só espera. O
		// host supervisiona o próprio túnel, e um dono é o suficiente.
		if loadConfig() != nil {
			appendAgentLog("vpn-service: túnel do dispositivo não responde, " +
				"mas quem o supervisiona é o agente do host — aguardando sem recriar")
			continue
		}
		if time.Since(ultimaTentativa) < esperaEntreTentativas {
			continue
		}
		ultimaTentativa = time.Now()
		appendAgentLog("vpn-service: túnel caiu; subindo de novo")
		if code := runTechnician([]string{"--server", serverURL, "--token", token}); code != 0 {
			appendAgentLog("vpn-service: falha ao restabelecer o túnel (código %d)", code)
		}
	}
}
