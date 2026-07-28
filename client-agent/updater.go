package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
)

const (
	clientVersion  = "0.3.8"
	privateAPIBase = "http://10.70.0.1:8080"
)

type updateInfo struct {
	Version string `json:"version"`
	SHA256  string `json:"sha256"`
	Size    int64  `json:"size"`
	URL     string `json:"url"`
}

type moduleFile struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
	Scope  string `json:"scope"`
}

type moduleManifest struct {
	Version string       `json:"version"`
	Files   []moduleFile `json:"files"`
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

func runUpdateCheck() int {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, _, err := getUpdate(client, "/api/v1/client/update?version="+clientVersion)
	if err != nil {
		fmt.Println(err.Error())
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNoContent {
		return 0
	}
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("consulta retornou status %d\n", resp.StatusCode)
		return 1
	}
	var info updateInfo
	if json.NewDecoder(resp.Body).Decode(&info) != nil || info.Version == "" {
		fmt.Println("metadados inválidos")
		return 1
	}
	fmt.Println(info.Version)
	return 10
}

func checkAndInstallUpdate() (bool, error) {
	modular, fallback, err := stageModularUpdate()
	if err != nil {
		return false, err
	}
	if modular {
		return true, nil
	}
	if !fallback {
		return false, nil
	}

	metadataClient := &http.Client{Timeout: 15 * time.Second}
	resp, apiBase, err := getUpdate(metadataClient,
		"/api/v1/client/update?version="+clientVersion)
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
	if err := downloadVerified(downloadClient, apiBase+info.URL, target, info); err != nil {
		return false, err
	}
	if err := launchInstallerElevated(target); err != nil {
		_ = os.Remove(target)
		return false, err
	}
	return true, nil
}

func stageModularUpdate() (updating bool, requireInstaller bool, err error) {
	client := &http.Client{Timeout: 30 * time.Second}
	resp, apiBase, err := getUpdate(client, "/api/v1/client/modules?version="+clientVersion)
	if err != nil {
		return false, true, nil
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNoContent {
		return false, false, nil
	}
	if resp.StatusCode != http.StatusOK {
		return false, true, nil
	}
	var manifest moduleManifest
	if err := json.NewDecoder(resp.Body).Decode(&manifest); err != nil ||
		manifest.Version == "" {
		return false, false, fmt.Errorf("manifesto modular inválido")
	}

	exe, err := os.Executable()
	if err != nil {
		return false, false, err
	}
	installDir := filepath.Dir(exe)
	changed := make([]moduleFile, 0)
	for _, item := range manifest.Files {
		if !safeModulePath(item.Path) || len(item.SHA256) != 64 {
			return false, false, fmt.Errorf("módulo inválido no manifesto")
		}
		target := filepath.Join(installDir, filepath.FromSlash(item.Path))
		hash, _ := fileSHA256(target)
		if !strings.EqualFold(hash, item.SHA256) {
			if item.Scope == "service" {
				return false, true, nil
			}
			changed = append(changed, item)
		}
	}
	if len(changed) == 0 {
		return false, false, nil
	}

	staging := filepath.Join(tgdeskDataDir(), "updates", "staging", manifest.Version, "files")
	if err := os.RemoveAll(staging); err != nil {
		return false, false, err
	}
	for _, item := range changed {
		target := filepath.Join(staging, filepath.FromSlash(item.Path))
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			return false, false, err
		}
		info := updateInfo{SHA256: item.SHA256, Size: item.Size}
		escaped := escapeModulePath(item.Path)
		if err := downloadVerified(client,
			apiBase+"/api/v1/client/modules/"+url.PathEscape(manifest.Version)+"/"+escaped,
			target, info); err != nil {
			return false, false, err
		}
	}

	cmd := exec.Command(exe,
		"--tgdesk-apply-update",
		"--staging", filepath.Dir(staging),
		"--install-dir", installDir,
		"--parent", fmt.Sprint(os.Getpid()))
	if err := cmd.Start(); err != nil {
		return false, false, err
	}
	return true, false, nil
}

func getUpdate(client *http.Client, path string) (*http.Response, string, error) {
	resp, err := client.Get(privateAPIBase + path)
	return resp, privateAPIBase, err
}

func safeModulePath(path string) bool {
	clean := filepath.Clean(filepath.FromSlash(path))
	return path != "" && clean != "." && !filepath.IsAbs(clean) &&
		clean != ".." && !strings.HasPrefix(clean, ".."+string(filepath.Separator))
}

func escapeModulePath(path string) string {
	parts := strings.Split(strings.ReplaceAll(path, "\\", "/"), "/")
	for i := range parts {
		parts[i] = url.PathEscape(parts[i])
	}
	return strings.Join(parts, "/")
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func applyStagedModules(staging, installDir string, parentPID uint32) error {
	if parentPID != 0 {
		if process, err := windows.OpenProcess(windows.SYNCHRONIZE, false, parentPID); err == nil {
			_, _ = windows.WaitForSingleObject(process, 60_000)
			windows.CloseHandle(process)
		}
	}
	filesRoot := filepath.Join(staging, "files")
	rollback := filepath.Join(tgdeskDataDir(), "updates", "rollback",
		fmt.Sprintf("%d", time.Now().Unix()))
	err := filepath.WalkDir(filesRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(filesRoot, path)
		if err != nil || !safeModulePath(relative) {
			return fmt.Errorf("caminho de staging inválido")
		}
		target := filepath.Join(installDir, relative)
		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}
		if _, err := os.Stat(target); err == nil {
			backup := filepath.Join(rollback, relative)
			if err := os.MkdirAll(filepath.Dir(backup), 0700); err != nil {
				return err
			}
			if err := copyFile(target, backup); err != nil {
				return err
			}
		}
		return copyFile(path, target)
	})
	if err != nil {
		return err
	}
	_ = exec.Command(filepath.Join(installDir, "tgdesk.exe")).Start()
	return nil
}

func copyFile(source, target string) error {
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	temp := target + ".tgdesk-new"
	out, err := os.Create(temp)
	if err != nil {
		return err
	}
	if _, err = io.Copy(out, in); err != nil {
		out.Close()
		_ = os.Remove(temp)
		return err
	}
	if err = out.Close(); err != nil {
		return err
	}
	_ = os.Remove(target)
	return os.Rename(temp, target)
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
