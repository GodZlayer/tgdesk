package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

// O instalador resolve o destino do cliente — empresarial escolhe o técnico,
// particular vai para a rede avulsa da TGDevs — e grava a escolha aqui. O
// agente só materializa: sem isso o instalador precisaria de rede no momento
// da instalação, e uma máquina instalada offline ficaria inutilizável.
//
// É o que substitui a tela de bifurcação do primeiro início. A decisão já foi
// tomada; o que sobra é uma chamada que pode esperar a conexão aparecer.

type installIntent struct {
	Kind         string `json:"kind"` // "empresarial" ou "particular"
	TechnicianID string `json:"technician_id,omitempty"`
}

func installIntentPath() string {
	return filepath.Join(tgdeskDataDir(), "identity", "install-intent.json")
}

// installBranding devolve o branding que o instalador já baixou do técnico
// escolhido. Serve à janela entre instalar e entrar na rede: nesse intervalo o
// dispositivo ainda não recebeu branding pelo canal de controle, e sem isto o
// ícone da bandeja apareceria genérico até a primeira conexão.
//
// O formato do arquivo é a própria resposta de
// GET /api/v1/public/technicians/{id}/branding.
func installBranding() BrandingState {
	var branding BrandingState
	data, err := os.ReadFile(filepath.Join(
		tgdeskDataDir(), "identity", "install-branding.json"))
	if err != nil || json.Unmarshal(data, &branding) != nil {
		return BrandingState{}
	}
	return branding
}

func loadInstallIntent() *installIntent {
	data, err := os.ReadFile(installIntentPath())
	if err != nil {
		return nil
	}
	var intent installIntent
	if json.Unmarshal(data, &intent) != nil {
		return nil
	}
	return &intent
}

// applyInstallIntent executa a escolha feita na instalação. Falha de rede não
// consome o arquivo: a próxima inicialização tenta de novo.
func applyInstallIntent(cfg *agentConfig) {
	intent := loadInstallIntent()
	if intent == nil {
		applyTechnicianCredentialBind(cfg)
		return
	}
	var status int
	var err error
	switch intent.Kind {
	case "particular":
		status, err = postJSON("/api/v1/pairing/standalone-bind", map[string]string{
			"device_id":    cfg.DeviceID,
			"device_token": cfg.DeviceToken,
		}, nil)
	case "empresarial":
		if intent.TechnicianID == "" {
			log.Println("intenção de instalação empresarial sem técnico — descartando")
			_ = os.Remove(installIntentPath())
			return
		}
		status, err = postJSON("/api/v1/pairing/org-intake-bind", map[string]string{
			"device_id":     cfg.DeviceID,
			"device_token":  cfg.DeviceToken,
			"technician_id": intent.TechnicianID,
		}, nil)
	case "tecnico":
		// A máquina do técnico entra sozinha, como a do cliente avulso. Quem
		// diz o papel — e portanto a rede de sistema de destino — é a
		// credencial de técnico desta máquina, não o instalador: o instalador
		// só sabe que é uma instalação de técnico, e o nível vem do servidor.
		status, err = postTechnicianSelfBind(cfg)
	default:
		log.Printf("intenção de instalação desconhecida (%q) — descartando", intent.Kind)
		_ = os.Remove(installIntentPath())
		return
	}
	if err != nil {
		log.Printf("intenção de instalação adiada (sem servidor): %v", err)
		return
	}
	// 409 significa que o dispositivo já pertence a uma rede: alguém já o
	// vinculou, e insistir só repetiria o erro a cada inicialização.
	if status == http.StatusOK || status == http.StatusConflict {
		log.Printf("intenção de instalação aplicada (%s, status %d)", intent.Kind, status)
		_ = os.Remove(installIntentPath())
		return
	}
	log.Printf("intenção de instalação recusada (status %d) — nova tentativa na próxima inicialização", status)
}

// postTechnicianSelfBind coloca esta máquina na rede de sistema do papel do
// técnico que a instalou.
//
// Precisa de duas provas ao mesmo tempo: a credencial de técnico, que diz QUEM
// é e portanto qual o papel, e o par dispositivo/token, que diz QUAL máquina é.
// Uma sem a outra não basta — a primeira não identifica o computador, e a
// segunda não identifica o nível.
//
// A credencial é renovada aqui em vez de reaproveitar alguma sessão aberta: a
// vinculação acontece na primeira conexão depois da instalação, quando ainda
// não há sessão nenhuma.
func applyTechnicianCredentialBind(cfg *agentConfig) {
	credentialPath := filepath.Join(tgdeskDataDir(), "identity", "technician.dat")
	if _, err := os.Stat(credentialPath); err != nil {
		return
	}
	status, err := postTechnicianSelfBind(cfg)
	if err != nil {
		log.Printf("auto-vinculação técnica adiada: %v", err)
		return
	}
	if status == http.StatusOK || status == http.StatusConflict {
		log.Printf("auto-vinculação técnica conferida (status %d)", status)
		return
	}
	log.Printf("auto-vinculação técnica recusada (status %d)", status)
}

func postTechnicianSelfBind(cfg *agentConfig) (int, error) {
	credentialPath := filepath.Join(tgdeskDataDir(), "identity", "technician.dat")
	credential, err := unprotectMachineCredential(credentialPath)
	if err != nil {
		return 0, fmt.Errorf("credencial de técnico indisponível: %w", err)
	}
	token, err := refreshMachineSession(baseURL(), credential)
	if err != nil {
		return 0, fmt.Errorf("sessão de técnico: %w", err)
	}
	body, _ := json.Marshal(map[string]string{
		"device_id":    cfg.DeviceID,
		"device_token": cfg.DeviceToken,
	})
	req, err := http.NewRequest(http.MethodPost,
		baseURL()+"/api/v1/pairing/technician-self-bind", bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := httpClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}
