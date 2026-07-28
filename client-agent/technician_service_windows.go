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
	// O Host cria primeiro o adaptador usado pelo próprio computador. Isso
	// também faz a aba Cliente sair do código de pareamento antes de iniciar
	// o segundo adaptador exclusivo do modo Admin/Tech.
	time.Sleep(8 * time.Second)
	appendAgentLog("vpn-service: iniciando túnel Admin/Tech")
	return runTechnician([]string{"--server", serverURL, "--token", token})
}
