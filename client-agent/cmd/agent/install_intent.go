package main

import (
	"encoding/json"
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
