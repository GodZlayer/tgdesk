package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"sync"
	"time"

	"golang.org/x/sys/windows"
)

const (
	clientVersion  = "0.2.4"
	privateAPIBase = "http://10.70.0.1:8080"
)

var updaterOnce sync.Once

type updateInfo struct {
	Version string `json:"version"`
	SHA256  string `json:"sha256"`
	Size    int64  `json:"size"`
	URL     string `json:"url"`
}

func startAutoUpdater() {
	updaterOnce.Do(func() {
		go func() {
			for {
				updating, err := checkAndInstallUpdate()
				if err != nil {
					log.Printf("falha ao verificar atualização pela VPN: %v", err)
				} else if updating {
					log.Println("atualização validada e iniciada; encerrando agente atual")
					time.Sleep(time.Second)
					os.Exit(0)
				}
				time.Sleep(10 * time.Minute)
			}
		}()
	})
}

func runManualUpdate() int {
	updating, err := checkAndInstallUpdate()
	if err != nil {
		fmt.Println(err.Error())
		return 1
	}
	if !updating {
		fmt.Println("O TGDesk já está atualizado.")
		return 0
	}
	fmt.Println("Atualização baixada e iniciada.")
	return 10
}

func checkAndInstallUpdate() (bool, error) {
	metadataClient := &http.Client{Timeout: 15 * time.Second}
	resp, err := metadataClient.Get(privateAPIBase + "/api/v1/client/update?version=" + clientVersion)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNoContent {
		return false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("consulta retornou status %d", resp.StatusCode)
	}
	var info updateInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return false, err
	}
	if info.Version == "" || info.URL == "" || len(info.SHA256) != 64 {
		return false, fmt.Errorf("metadados inválidos")
	}
	target := filepath.Join(os.TempDir(), "tgdesk-client-update-"+info.Version+".exe")
	downloadClient := &http.Client{Timeout: 15 * time.Minute}
	if err := downloadVerified(downloadClient, privateAPIBase+info.URL, target, info); err != nil {
		return false, err
	}
	if err := launchInstallerElevated(target); err != nil {
		_ = os.Remove(target)
		return false, err
	}
	return true, nil
}

func launchInstallerElevated(installer string) error {
	verb, err := syscall.UTF16PtrFromString("runas")
	if err != nil {
		return err
	}
	file, err := syscall.UTF16PtrFromString(installer)
	if err != nil {
		return err
	}
	params, err := syscall.UTF16PtrFromString(
		"/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS",
	)
	if err != nil {
		return err
	}
	dir, err := syscall.UTF16PtrFromString(filepath.Dir(installer))
	if err != nil {
		return err
	}
	if err := windows.ShellExecute(0, verb, file, params, dir, windows.SW_HIDE); err != nil {
		return fmt.Errorf("não foi possível elevar o atualizador: %w", err)
	}
	return nil
}

func downloadVerified(client *http.Client, url, target string, info updateInfo) error {
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download retornou status %d", resp.StatusCode)
	}
	f, err := os.Create(target)
	if err != nil {
		return err
	}
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(f, hash), resp.Body)
	closeErr := f.Close()
	if copyErr != nil {
		_ = os.Remove(target)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(target)
		return closeErr
	}
	if info.Size > 0 && written != info.Size {
		_ = os.Remove(target)
		return fmt.Errorf("tamanho inválido")
	}
	if !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), info.SHA256) {
		_ = os.Remove(target)
		return fmt.Errorf("SHA-256 inválido")
	}
	return nil
}
