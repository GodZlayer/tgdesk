// Package updatecore contém a lógica de atualização modular do TGDesk —
// manifesto, verificação SHA256, staging e aplicação transacional com
// rollback. É importado tanto pela DLL do agente (client-agent/cmd/agent,
// carregada por tgdesk.exe) quanto pelo executável standalone
// client-agent/cmd/updater (tgdesk-updater.exe), que precisa funcionar
// mesmo que tgdesk.exe não consiga iniciar.
package updatecore

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
	"tgdesk/agent/internal/versioning"
)

const (
	compiledClientVersion = "0.3.48"
	privateAPIBase        = "http://10.70.0.1:8080"
	recoveryAPIBase       = "http://168.232.199.161:8090"
)

// DataDir retorna o diretório de dados do TGDesk (ProgramData\TGDesk por
// padrão, ou TGDESK_DATA_DIR se configurado). Duplica a lógica equivalente
// de host.go (main package) deliberadamente: é um filepath.Join simples e
// não vale a complexidade de compartilhar entre os dois pacotes.
func DataDir() string {
	if configured := os.Getenv("TGDESK_DATA_DIR"); configured != "" {
		_ = os.MkdirAll(filepath.Join(configured, "identity"), 0700)
		_ = os.MkdirAll(filepath.Join(configured, "state"), 0700)
		_ = os.MkdirAll(filepath.Join(configured, "logs"), 0700)
		return configured
	}
	base := os.Getenv("ProgramData")
	if base == "" {
		base = `C:\ProgramData`
	}
	dir := filepath.Join(base, "TGDesk")
	_ = os.MkdirAll(filepath.Join(dir, "identity"), 0700)
	_ = os.MkdirAll(filepath.Join(dir, "state"), 0700)
	_ = os.MkdirAll(filepath.Join(dir, "logs"), 0700)
	return dir
}

// CurrentClientVersion retorna a versão instalada do cliente TGDesk, lida de
// version.txt ao lado do executável em execução, ou a versão compilada como
// fallback.
func CurrentClientVersion() string {
	exe, err := os.Executable()
	if err == nil {
		if raw, readErr := os.ReadFile(filepath.Join(filepath.Dir(exe), "version.txt")); readErr == nil {
			if version := strings.TrimSpace(string(raw)); version != "" &&
				len(version) <= 32 && !strings.ContainsAny(version, `/\`) {
				return version
			}
		}
	}
	return compiledClientVersion
}

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
	FormatVersion      int          `json:"format_version"`
	Version            string       `json:"version"`
	Processes          []string     `json:"processes"`
	Services           []string     `json:"services"`
	RestartApplication string       `json:"restart_application"`
	Files              []moduleFile `json:"files"`
}

// ProgressEvent descreve uma transicao observavel da atualizacao offline.
// A UI do updater usa estes eventos; a transacao continua independente dela.
type ProgressEvent struct {
	Percent int
	Message string
}

type ProgressReporter func(ProgressEvent)

func reportProgress(report ProgressReporter, percent int, message string) {
	log.Printf("update: %d%% - %s", percent, message)
	if report != nil {
		report(ProgressEvent{Percent: percent, Message: message})
	}
}

func updateIsNewer(version string) bool {
	return versioning.Compare(version, CurrentClientVersion()) > 0
}

// UpdateIsNewer reports whether version is newer than the currently
// installed client version.
func UpdateIsNewer(version string) bool {
	return updateIsNewer(version)
}

// RunUpdate baixa e prepara (ou aplica, no caso de fallback via instalador)
// a atualização disponível. Códigos de saída: 0 = já atualizado,
// 10 = atualização baixada/iniciada, 1 = erro.
func RunUpdate() int {
	log.Printf("RunUpdate: versão atual %s", CurrentClientVersion())
	updating, err := checkAndInstallUpdate()
	if err != nil {
		log.Printf("RunUpdate: falhou: %v", err)
		return 1
	}
	if !updating {
		log.Println("RunUpdate: já está atualizado")
		return 0
	}
	log.Println("RunUpdate: atualização baixada e iniciada")
	return 10
}

// CheckForUpdate apenas consulta se há atualização disponível, sem baixar.
// Códigos de saída: 0 = atualizado, 10 = tem atualização, 1 = erro.
func CheckForUpdate() int {
	client := &http.Client{Timeout: 15 * time.Second}
	resp, apiBase, err := getUpdate(client, "/api/v1/client/update?version="+CurrentClientVersion())
	if err != nil {
		log.Printf("CheckForUpdate: falhou: %v", err)
		return 1
	}
	defer resp.Body.Close()
	log.Printf("CheckForUpdate: consultou %s, status %d", apiBase, resp.StatusCode)
	if resp.StatusCode == http.StatusNoContent {
		return 0
	}
	if resp.StatusCode != http.StatusOK {
		log.Printf("CheckForUpdate: consulta retornou status %d", resp.StatusCode)
		return 1
	}
	var info updateInfo
	if json.NewDecoder(resp.Body).Decode(&info) != nil || info.Version == "" {
		log.Println("CheckForUpdate: metadados inválidos")
		return 1
	}
	if !updateIsNewer(info.Version) {
		return 0
	}
	log.Printf("CheckForUpdate: nova versão disponível %s", info.Version)
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
		"/api/v1/client/update?version="+CurrentClientVersion())
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
	if !updateIsNewer(info.Version) {
		return false, nil
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
	resp, apiBase, err := getUpdate(client, "/api/v1/client/modules?version="+CurrentClientVersion())
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

	if !updateIsNewer(manifest.Version) {
		return false, false, nil
	}
	exe, err := os.Executable()
	if err != nil {
		return false, false, err
	}
	installDir := filepath.Dir(exe)
	changed, requiresInstaller, err := selectChangedModules(manifest, installDir)
	if err != nil {
		return false, false, err
	}
	if requiresInstaller {
		return false, true, nil
	}
	if len(changed) == 0 {
		return false, false, nil
	}

	staging := filepath.Join(DataDir(), "updates", "staging", manifest.Version, "files")
	if err := os.RemoveAll(staging); err != nil {
		return false, false, err
	}
	var totalBytes int64
	for _, item := range changed {
		totalBytes += item.Size
	}
	BeginTransfer(manifest.Version, totalBytes)
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
	// O staging contem somente os arquivos efetivamente baixados. Persistir o
	// manifesto completo faria o aplicador exigir arquivos inalterados e, em
	// especial, rejeitar o tgdesk-updater.exe protegido mesmo sem ele estar no
	// staging.
	manifest.Files = changed
	manifestBytes, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return false, false, err
	}
	manifestPath := filepath.Join(filepath.Dir(staging), "manifest.json")
	manifestTemp := manifestPath + ".tmp"
	if err := os.WriteFile(manifestTemp, manifestBytes, 0600); err != nil {
		return false, false, err
	}
	_ = os.Remove(manifestPath)
	if err := os.Rename(manifestTemp, manifestPath); err != nil {
		return false, false, err
	}

	if err := launchStagedUpdaterElevated(
		filepath.Dir(staging), installDir, uint32(os.Getpid())); err != nil {
		return false, false, err
	}
	return true, false, nil
}

func selectChangedModules(manifest moduleManifest, installDir string) (
	[]moduleFile, bool, error,
) {
	changed := make([]moduleFile, 0)
	for _, item := range manifest.Files {
		if !safeModulePath(item.Path) || len(item.SHA256) != 64 {
			return nil, false, fmt.Errorf("módulo inválido no manifesto")
		}
		target := filepath.Join(installDir, filepath.FromSlash(item.Path))
		hash, _ := fileSHA256(target)
		if !strings.EqualFold(hash, item.SHA256) {
			changed = append(changed, item)
		}
	}
	return changed, false, nil
}

var (
	user32Lib              = windows.NewLazySystemDLL("user32.dll")
	procFindWindowW        = user32Lib.NewProc("FindWindowW")
	procIsWindowVisible    = user32Lib.NewProc("IsWindowVisible")
	procIsIconic           = user32Lib.NewProc("IsIconic")
	procGetWindowThreadPID = user32Lib.NewProc("GetWindowThreadProcessId")
)

// tgdeskWindowClass precisa bater com kWindowClassName em
// flutter/windows/runner/win32_window.cpp e com
// FLUTTER_RUNNER_WIN32_WINDOW_CLASS em src/platform/windows.rs. As três pontas
// se acham por este nome.
const tgdeskWindowClass = "TGDESK_RUNNER_WIN32_WINDOW"

// mainWindowIsOnScreen diz se a janela do TGDesk está de fato à vista — não
// apenas existindo, mas visível e não minimizada.
//
// A janela é conferida contra o processo dono dela: classe própria reduz a
// chance de casar com outro aplicativo, mas não a elimina, e é exatamente esse
// descuido que fazia o TGDesk trazer (e às vezes fechar) a janela do cliente
// Cloudflare WARP. Aqui o erro seria mais silencioso — mostrar ou esconder o
// atualizador pelo estado da janela de outro programa —, e por isso a
// verificação é a mesma.
//
// Na dúvida responde false: esconder uma janela que deveria aparecer é um
// aborrecimento; abri-la por cima do trabalho de alguém é o que se quis evitar.
func mainWindowIsOnScreen(installDir string) bool {
	class, err := syscall.UTF16PtrFromString(tgdeskWindowClass)
	if err != nil {
		return false
	}
	hwnd, _, _ := procFindWindowW.Call(uintptr(unsafe.Pointer(class)), 0)
	if hwnd == 0 {
		return false
	}
	if visible, _, _ := procIsWindowVisible.Call(hwnd); visible == 0 {
		return false
	}
	if iconic, _, _ := procIsIconic.Call(hwnd); iconic != 0 {
		return false
	}

	var pid uint32
	procGetWindowThreadPID.Call(hwnd, uintptr(unsafe.Pointer(&pid)))
	if pid == 0 {
		return false
	}
	process, err := windows.OpenProcess(
		windows.PROCESS_QUERY_LIMITED_INFORMATION, false, pid)
	if err != nil {
		return false
	}
	defer windows.CloseHandle(process)
	path := make([]uint16, windows.MAX_PATH)
	size := uint32(len(path))
	if windows.QueryFullProcessImageName(process, 0, &path[0], &size) != nil {
		return false
	}
	esperado := filepath.Join(installDir, "tgdesk.exe")
	return strings.EqualFold(syscall.UTF16ToString(path[:size]), esperado)
}

// launchStagedUpdaterElevated relança tgdesk-updater.exe elevado para aplicar
// a atualização staged. Diferente do comportamento antigo (que relançava o
// próprio tgdesk.exe via os.Executable(), já que este código rodava dentro
// da DLL carregada por ele), agora sempre aponta para tgdesk-updater.exe no
// diretório de instalação — a aplicação da atualização deixa de depender de
// tgdesk.exe conseguir sequer iniciar.
//
// installDir já é o diretório de instalação (calculado em stageModularUpdate
// a partir de os.Executable(), que dentro da DLL resolve para o tgdesk.exe
// hospedeiro); usamos esse diretório, não o executável em si, para montar o
// caminho do tgdesk-updater.exe.
func launchStagedUpdaterElevated(staging, installDir string, parentPID uint32) error {
	// tgdesk-updater.exe roda direto do diretório de instalação. A cópia pra
	// uma pasta runtime com nome aleatório só fazia sentido se o próprio
	// updater pudesse ser substituído por uma atualização modular — mas ele
	// é deliberadamente excluído do pacote modular (por design, sempre foi
	// assim) e nunca se auto-atualiza. Manter a cópia só adicionava um
	// arquivo recém-criado sem reputação, alvo fácil do SmartScreen/Defender,
	// sem nenhum ganho real.
	updaterExe := filepath.Join(installDir, "tgdesk-updater.exe")
	if info, err := os.Stat(updaterExe); err != nil || info.IsDir() {
		return fmt.Errorf("atualizador standalone ausente: %w", err)
	}
	readyFile := filepath.Join(filepath.Dir(staging),
		fmt.Sprintf("updater-ui-ready-%d.signal", os.Getpid()))
	_ = os.Remove(readyFile)
	verb, err := syscall.UTF16PtrFromString("runas")
	if err != nil {
		return err
	}
	file, err := syscall.UTF16PtrFromString(updaterExe)
	if err != nil {
		return err
	}
	quote := func(value string) string {
		return `"` + strings.ReplaceAll(value, `"`, `\"`) + `"`
	}
	params, err := syscall.UTF16PtrFromString(strings.Join([]string{
		"--apply-staged",
		"--staging", quote(staging),
		"--install-dir", quote(installDir),
		"--parent", fmt.Sprint(parentPID),
		"--ready-file", quote(readyFile),
	}, " "))
	if err != nil {
		return err
	}
	dir, err := syscall.UTF16PtrFromString(installDir)
	if err != nil {
		return err
	}
	// A janela do atualizador aparece ou não conforme o que a pessoa está
	// vendo no momento.
	//
	// Com a janela do TGDesk aberta na frente, ela aparece: quem está com o
	// programa à vista tem a barra de título mostrando progresso, mas a
	// atualização troca binários e reinicia o serviço — sumir a janela no meio
	// disso deixa a pessoa no escuro justamente enquanto o programa dela some.
	//
	// Com o TGDesk minimizado na bandeja, ela não aparece: quem minimizou está
	// fazendo outra coisa, e uma janela nascendo sozinha por cima do trabalho
	// alheio é interrupção, não aviso. O indicador da barra de título dá conta
	// quando a pessoa voltar.
	//
	// Antes era sempre oculta, e o caso de a janela estar aberta ficava sem
	// resposta nenhuma.
	show := int32(windows.SW_HIDE)
	if mainWindowIsOnScreen(installDir) {
		show = int32(windows.SW_SHOWNORMAL)
	}
	if err := windows.ShellExecute(0, verb, file, params, dir, show); err != nil {
		return fmt.Errorf("não foi possível elevar a atualização modular: %w", err)
	}
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(readyFile); err == nil {
			_ = os.Remove(readyFile)
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("a janela do atualizador nao confirmou que ficou visivel")
}

func getUpdate(client *http.Client, path string) (*http.Response, string, error) {
	resp, err := client.Get(privateAPIBase + path)
	if err == nil {
		return resp, privateAPIBase, nil
	}
	// Atualização é também o mecanismo de recuperação da VPN. Quando o
	// gateway privado não existe, consulta o mesmo pacote somente-leitura
	// pelo endpoint público inicial.
	resp, recoveryErr := client.Get(recoveryAPIBase + path)
	if recoveryErr != nil {
		return nil, "", fmt.Errorf(
			"atualização indisponível pela VPN (%v) e pela recuperação pública (%v)",
			err, recoveryErr)
	}
	return resp, recoveryAPIBase, nil
}

func safeModulePath(path string) bool {
	clean := filepath.Clean(filepath.FromSlash(path))
	return path != "" && clean != "." && !strings.HasPrefix(path, "/") &&
		!strings.HasPrefix(path, `\`) && !strings.Contains(clean, ":") &&
		!filepath.IsAbs(clean) &&
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

// ApplyStaged aplica a transação de módulos já staged em `staging/files` para
// dentro de installDir, com rollback automático em caso de falha (incluindo
// falha do TGDesk ao reiniciar). Se parentPID != 0, aguarda até 60s pelo
// encerramento do processo pai antes de trocar os arquivos (evita conflito
// de arquivo em uso).
func ApplyStaged(staging, installDir string, parentPID uint32) error {
	if parentPID != 0 {
		if process, err := windows.OpenProcess(windows.SYNCHRONIZE, false, parentPID); err == nil {
			_, _ = windows.WaitForSingleObject(process, 60_000)
			windows.CloseHandle(process)
		}
	}
	filesRoot := filepath.Join(staging, "files")
	rollback := filepath.Join(DataDir(), "updates", "rollback",
		fmt.Sprintf("%d", time.Now().Unix()))
	applied, err := applyModuleTransaction(filesRoot, installDir, rollback)
	if err != nil {
		if rollbackErr := restoreModuleTransaction(applied, installDir, rollback); rollbackErr != nil {
			return fmt.Errorf("atualização falhou: %v; rollback falhou: %w", err, rollbackErr)
		}
		return err
	}
	app := exec.Command(filepath.Join(installDir, "tgdesk.exe"))
	if err := app.Start(); err != nil {
		if rollbackErr := restoreModuleTransaction(applied, installDir, rollback); rollbackErr != nil {
			return fmt.Errorf("reinício falhou: %v; rollback falhou: %w", err, rollbackErr)
		}
		return fmt.Errorf("não foi possível reiniciar o TGDesk: %w", err)
	}
	// Uma falha imediata indica pacote inválido (DLL ausente/incompatível).
	// Depois desta janela o processo fica independente do atualizador.
	exited := make(chan error, 1)
	go func() { exited <- app.Wait() }()
	select {
	case startErr := <-exited:
		if rollbackErr := restoreModuleTransaction(applied, installDir, rollback); rollbackErr != nil {
			return fmt.Errorf("TGDesk encerrou durante validação: %v; rollback falhou: %w",
				startErr, rollbackErr)
		}
		return fmt.Errorf("TGDesk encerrou durante validação: %v", startErr)
	case <-time.After(5 * time.Second):
		return nil
	}
}

// ApplyStagedOffline applies an already downloaded release without network
// access. It owns process/service shutdown, destination verification, restart,
// and operational rollback. The updater executable itself is never a payload.
func ApplyStagedOffline(staging, installDir string, parentPID uint32) error {
	return ApplyStagedOfflineWithProgress(staging, installDir, parentPID, nil)
}

// ApplyStagedOfflineWithProgress executa a mesma transacao offline e publica
// somente mudancas de fase. O callback nunca controla o fluxo nem substitui
// verificacoes reais de arquivo, servico ou processo.
func ApplyStagedOfflineWithProgress(staging, installDir string, parentPID uint32,
	report ProgressReporter) error {
	reportProgress(report, 5, "Preparando a atualizacao...")
	if parentPID != 0 {
		reportProgress(report, 10, "Aguardando o TGDesk encerrar com seguranca...")
		if process, err := windows.OpenProcess(windows.SYNCHRONIZE, false, parentPID); err == nil {
			_, _ = windows.WaitForSingleObject(process, 60_000)
			windows.CloseHandle(process)
		}
	}
	reportProgress(report, 18, "Validando o pacote baixado...")
	manifest, err := readStagedManifest(filepath.Join(staging, "manifest.json"))
	if err != nil {
		return err
	}
	filesRoot := filepath.Join(staging, "files")
	if err := verifyStagedFiles(filesRoot, manifest); err != nil {
		return err
	}
	reportProgress(report, 30, "Parando os componentes do TGDesk...")
	stoppedServices, err := stopServices(manifest.Services, 30*time.Second)
	if err != nil {
		return err
	}
	if err := stopProcesses(manifest.Processes); err != nil {
		_ = startServices(stoppedServices, 30*time.Second)
		return err
	}
	reportProgress(report, 48, "Instalando os novos arquivos...")
	rollback := filepath.Join(DataDir(), "updates", "rollback", fmt.Sprintf("%d", time.Now().Unix()))
	applied, err := applyModuleTransaction(filesRoot, installDir, rollback)
	if err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	if err := verifyInstalledFiles(installDir, filesRoot); err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	reportProgress(report, 72, "Reiniciando o servico TGDesk...")
	if err := startServices(stoppedServices, 30*time.Second); err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	reportProgress(report, 78, "Aguardando VPN e telemetria do servico...")
	if err := waitForOperationalReadiness(report, 2*time.Minute); err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	application := manifest.RestartApplication
	if application == "" {
		// The TGDesk Windows service owns the session UI and starts --server
		// after reaching Running. Do not launch a competing second UI instance.
		reportProgress(report, 100, "Atualizacao concluida.")
		return nil
	}
	if !safeModulePath(application) {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest,
			fmt.Errorf("invalid restart application"))
	}
	if err := ensureInteractiveStartup(installDir); err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	reportProgress(report, 84, "Abrindo o TGDesk atualizado...")
	app := exec.Command(filepath.Join(installDir, filepath.FromSlash(application)))
	if err := app.Start(); err != nil {
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest, err)
	}
	exited := make(chan error, 1)
	go func() { exited <- app.Wait() }()
	select {
	case startErr := <-exited:
		return rollbackAndRecover(applied, installDir, rollback, stoppedServices, manifest,
			fmt.Errorf("TGDesk exited during startup validation: %v", startErr))
	case <-time.After(5 * time.Second):
		reportProgress(report, 100, "Atualizacao concluida. TGDesk iniciado.")
		return nil
	}
}

// waitForOperationalReadiness impede que a UI seja reaberta sobre um servico
// apenas marcado como Running, mas ainda incapaz de entregar a rede privada.
// Em instalacoes Client puras nao existe identidade administrativa e o
// servico Running e o estado suficiente. Em Admin/Tech, a transicao exige uma
// conexao real pela VPN com a API privada.
func waitForOperationalReadiness(report ProgressReporter, timeout time.Duration) error {
	credential := filepath.Join(DataDir(), "identity", "technician.dat")
	if _, err := os.Stat(credential); os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return fmt.Errorf("nao foi possivel validar a identidade administrativa: %w", err)
	}
	deadline := time.Now().Add(timeout)
	var lastError error
	for time.Now().Before(deadline) {
		connection, err := net.DialTimeout("tcp", "10.70.0.1:8080", 2*time.Second)
		if err == nil {
			connection.Close()
			return nil
		}
		lastError = err
		reportProgress(report, 78, "Servico ativo; aguardando a rede privada administrativa...")
		time.Sleep(750 * time.Millisecond)
	}
	return fmt.Errorf("servico iniciou, mas a rede privada administrativa nao ficou pronta: %v", lastError)
}

func ensureInteractiveStartup(installDir string) error {
	runKey, _, err := registry.CreateKey(registry.CURRENT_USER,
		`SOFTWARE\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		return fmt.Errorf("nao foi possivel restaurar o inicio automatico: %w", err)
	}
	defer runKey.Close()
	executable := filepath.Join(installDir, "tgdesk.exe")
	if err := runKey.SetStringValue("TGDesk", `"`+executable+`"`); err != nil {
		return fmt.Errorf("nao foi possivel registrar o TGDesk no inicio do Windows: %w", err)
	}
	settings, _, err := registry.CreateKey(registry.CURRENT_USER,
		`SOFTWARE\TGDesk`, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer settings.Close()
	if err := settings.SetDWordValue("StartWithWindowsConfigured", 1); err != nil {
		return err
	}
	return settings.SetDWordValue("StartWithWindows", 1)
}

func readStagedManifest(path string) (moduleManifest, error) {
	var manifest moduleManifest
	raw, err := os.ReadFile(path)
	if err != nil {
		return manifest, fmt.Errorf("offline manifest missing: %w", err)
	}
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return manifest, fmt.Errorf("invalid offline manifest: %w", err)
	}
	if manifest.FormatVersion != 1 || manifest.Version == "" {
		return manifest, fmt.Errorf("unsupported offline manifest format")
	}
	return manifest, nil
}

func verifyStagedFiles(filesRoot string, manifest moduleManifest) error {
	allowed := make(map[string]moduleFile, len(manifest.Files))
	for _, item := range manifest.Files {
		if !safeModulePath(item.Path) || len(item.SHA256) != 64 {
			return fmt.Errorf("invalid module in manifest: %s", item.Path)
		}
		allowed[filepath.Clean(filepath.FromSlash(item.Path))] = item
	}
	return filepath.WalkDir(filesRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil || entry.IsDir() {
			return walkErr
		}
		relative, err := filepath.Rel(filesRoot, path)
		if err != nil {
			return err
		}
		item, ok := allowed[filepath.Clean(relative)]
		if !ok {
			return fmt.Errorf("staged file is not in manifest: %s", relative)
		}
		info, err := os.Stat(path)
		if err != nil || (item.Size > 0 && info.Size() != item.Size) {
			return fmt.Errorf("invalid staged file size: %s", relative)
		}
		hash, err := fileSHA256(path)
		if err != nil || !strings.EqualFold(hash, item.SHA256) {
			return fmt.Errorf("invalid staged file SHA-256: %s", relative)
		}
		return nil
	})
}

func verifyInstalledFiles(installDir, filesRoot string) error {
	return filepath.WalkDir(filesRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil || entry.IsDir() {
			return walkErr
		}
		relative, err := filepath.Rel(filesRoot, path)
		if err != nil {
			return err
		}
		sourceHash, err := fileSHA256(path)
		if err != nil {
			return err
		}
		targetHash, err := fileSHA256(filepath.Join(installDir, relative))
		if err != nil || !strings.EqualFold(sourceHash, targetHash) {
			return fmt.Errorf("post-install verification failed: %s", relative)
		}
		return nil
	})
}

func stopProcesses(names []string) error {
	for _, name := range names {
		if name == "" || filepath.Base(name) != name || strings.EqualFold(name, "tgdesk-updater.exe") {
			return fmt.Errorf("invalid process in manifest: %q", name)
		}
		// The TGDesk service is stopped through SCM first. Killing by image name
		// without /T avoids taskkill failing on already-detached service children.
		//
		// The exit status is deliberately ignored. taskkill reports "process not
		// found" through localized text in the OEM code page, so deciding what is
		// a real failure by matching that text never worked reliably. Stopping is
		// idempotent by design and file replacement remains the hard gate: if a
		// process really is holding a file, the replacement fails and reports it.
		_, _ = exec.Command("taskkill.exe", "/F", "/IM", name).CombinedOutput()
	}
	return nil
}

func stopServices(names []string, timeout time.Duration) ([]string, error) {
	manager, err := mgr.Connect()
	if err != nil {
		return nil, err
	}
	defer manager.Disconnect()
	stopped := make([]string, 0, len(names))
	for _, name := range names {
		service, openErr := manager.OpenService(name)
		if openErr != nil {
			continue
		}
		stopped = append(stopped, name)
		status, queryErr := service.Query()
		if queryErr == nil && status.State != svc.Stopped {
			_, _ = service.Control(svc.Stop)
			deadline := time.Now().Add(timeout)
			for time.Now().Before(deadline) {
				status, queryErr = service.Query()
				if queryErr == nil && status.State == svc.Stopped {
					break
				}
				time.Sleep(250 * time.Millisecond)
			}
			if queryErr != nil || status.State != svc.Stopped {
				service.Close()
				return stopped, fmt.Errorf("service %s did not stop", name)
			}
		}
		service.Close()
	}
	return stopped, nil
}

func startServices(names []string, timeout time.Duration) error {
	if len(names) == 0 {
		return nil
	}
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	for _, name := range names {
		service, err := manager.OpenService(name)
		if err != nil {
			return err
		}
		status, _ := service.Query()
		if status.State != svc.Running {
			if err := service.Start(); err != nil {
				service.Close()
				return err
			}
		}
		deadline := time.Now().Add(timeout)
		for time.Now().Before(deadline) {
			status, err = service.Query()
			if err == nil && status.State == svc.Running {
				break
			}
			time.Sleep(250 * time.Millisecond)
		}
		service.Close()
		if err != nil || status.State != svc.Running {
			return fmt.Errorf("service %s did not start", name)
		}
	}
	return nil
}

func rollbackAndRecover(applied []appliedModule, installDir, rollback string,
	services []string, manifest moduleManifest, cause error) error {
	_, _ = stopServices(manifest.Services, 30*time.Second)
	_ = stopProcesses(manifest.Processes)
	if rollbackErr := restoreModuleTransaction(applied, installDir, rollback); rollbackErr != nil {
		return fmt.Errorf("%v; rollback failed: %w", cause, rollbackErr)
	}
	serviceErr := startServices(services, 30*time.Second)
	application := manifest.RestartApplication
	if application == "" {
		if serviceErr != nil {
			return fmt.Errorf("%v; rollback applied but service recovery failed: %v", cause, serviceErr)
		}
		return fmt.Errorf("%v; rollback applied and previous service restarted", cause)
	}
	restartErr := exec.Command(filepath.Join(installDir, filepath.FromSlash(application))).Start()
	if serviceErr != nil || restartErr != nil {
		return fmt.Errorf("%v; rollback applied but recovery failed: service=%v app=%v",
			cause, serviceErr, restartErr)
	}
	return fmt.Errorf("%v; rollback applied and previous version restarted", cause)
}

type appliedModule struct {
	relative  string
	hadBackup bool
}

func applyModuleTransaction(filesRoot, installDir, rollback string) ([]appliedModule, error) {
	applied := make([]appliedModule, 0)
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
		item := appliedModule{relative: relative}
		if _, err := os.Stat(target); err == nil {
			backup := filepath.Join(rollback, relative)
			if err := os.MkdirAll(filepath.Dir(backup), 0700); err != nil {
				return err
			}
			if err := copyFile(target, backup); err != nil {
				return err
			}
			item.hadBackup = true
		}
		// Registra antes da troca para que até uma falha no meio da cópia
		// restaure o arquivo corrente ou remova o módulo recém-criado.
		applied = append(applied, item)
		if err := copyFile(path, target); err != nil {
			return err
		}
		return nil
	})
	return applied, err
}

func restoreModuleTransaction(applied []appliedModule, installDir, rollback string) error {
	var failures []string
	for index := len(applied) - 1; index >= 0; index-- {
		item := applied[index]
		target := filepath.Join(installDir, item.relative)
		if item.hadBackup {
			if err := copyFile(filepath.Join(rollback, item.relative), target); err != nil {
				failures = append(failures, item.relative+": "+err.Error())
			}
		} else if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
			failures = append(failures, item.relative+": "+err.Error())
		}
	}
	if len(failures) != 0 {
		return fmt.Errorf("%s", strings.Join(failures, "; "))
	}
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
	if strings.EqualFold(filepath.Base(target), "tgdesk-updater.exe") {
		// Uma instância legada pode ter sido iniciada diretamente do diretório
		// instalado. O aplicador atual roda da cópia externa runtime, portanto
		// encerrar apenas a imagem exata instalada não encerra a GUI atual.
		_, _ = exec.Command("taskkill.exe", "/F", "/IM", "tgdesk-updater.exe").CombinedOutput()
	}
	var removeErr error
	for attempt := 0; attempt < 20; attempt++ {
		removeErr = os.Remove(target)
		if removeErr == nil || os.IsNotExist(removeErr) {
			removeErr = nil
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
	if removeErr != nil {
		_ = os.Remove(temp)
		return fmt.Errorf("nao foi possivel liberar %s para substituicao: %w", target, removeErr)
	}
	if err := os.Rename(temp, target); err != nil {
		_ = os.Remove(temp)
		return err
	}
	return nil
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
	// A leitura passa pelo limitador: é ela que consome a banda do servidor,
	// e é dali que sai o progresso mostrado na tela.
	written, copyErr := io.Copy(io.MultiWriter(f, hash), newThrottledReader(resp.Body))
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
