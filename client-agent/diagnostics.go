package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

type diagnosticRequest struct {
	ID   string
	Test string
}

type diagnosticProgress struct {
	ID       string `json:"-"`
	Test     string `json:"test"`
	Progress int    `json:"progress"`
	Message  string `json:"message"`
}

type diagnosticResult struct {
	ID      string         `json:"-"`
	Status  string         `json:"status"`
	Results map[string]any `json:"results"`
	Error   string         `json:"error,omitempty"`
}

func runDiagnostic(req diagnosticRequest, progress chan<- diagnosticProgress, result chan<- diagnosticResult) {
	progress <- diagnosticProgress{ID: req.ID, Test: req.Test, Progress: 5, Message: "Preparando teste"}
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
	defer cancel()
	started := time.Now()
	data, err := executeDiagnostic(ctx, req.Test, func(percent int, message string) {
		progress <- diagnosticProgress{ID: req.ID, Test: req.Test, Progress: percent, Message: message}
	})
	data["test"] = req.Test
	data["duration_seconds"] = time.Since(started).Seconds()
	data["finished_at"] = time.Now().UTC().Format(time.RFC3339)
	status, errorText := "completed", ""
	if err != nil {
		status, errorText = "failed", err.Error()
	}
	result <- diagnosticResult{ID: req.ID, Status: status, Results: data, Error: errorText}
}

func executeDiagnostic(ctx context.Context, test string, progress func(int, string)) (map[string]any, error) {
	switch test {
	case "system_overview":
		progress(40, "Coletando inventário e estado do sistema")
		return map[string]any{"snapshot": collectHardwareSnapshot()}, nil
	case "cpu_stress":
		return cpuStress(ctx, progress)
	case "memory_integrity":
		return memoryIntegrity(progress)
	case "internet_quality":
		return internetQuality(ctx, progress)
	case "disk_performance":
		return diskPerformance(ctx, progress)
	case "smart_extended":
		return commandDiagnostic(ctx, progress, 40, "Consultando saúde física",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"Get-PhysicalDisk | ForEach-Object { $d=$_; $r=$d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Name=$d.FriendlyName;Health=$d.HealthStatus;Operational=$d.OperationalStatus;Temperature=$r.Temperature;Wear=$r.Wear;ReadErrors=$r.ReadErrorsTotal;WriteErrors=$r.WriteErrorsTotal} } | ConvertTo-Json -Depth 4")
	case "filesystem_scan":
		drive := os.Getenv("SystemDrive")
		if drive == "" {
			drive = "C:"
		}
		return commandDiagnostic(ctx, progress, 15, "Verificando setores e sistema de arquivos em modo leitura",
			"chkdsk.exe", drive, "/scan")
	case "gpu_stress":
		return commandDiagnostic(ctx, progress, 20, "Executando carga gráfica do Windows",
			"winsat.exe", "d3d", "-time", "20")
	default:
		return map[string]any{}, fmt.Errorf("teste não suportado: %s", test)
	}
}

func cpuStress(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	progress(15, "Aplicando carga em todos os núcleos")
	deadline := time.Now().Add(30 * time.Second)
	var wg sync.WaitGroup
	var operations uint64
	var mu sync.Mutex
	for i := 0; i < runtime.NumCPU(); i++ {
		wg.Add(1)
		go func(seed byte) {
			defer wg.Done()
			buf := make([]byte, 1024*1024)
			buf[0] = seed
			local := uint64(0)
			for time.Now().Before(deadline) && ctx.Err() == nil {
				sum := sha256.Sum256(buf)
				copy(buf[:], sum[:])
				local++
			}
			mu.Lock()
			operations += local
			mu.Unlock()
		}(byte(i))
	}
	wg.Wait()
	if err := ctx.Err(); err != nil {
		return map[string]any{}, err
	}
	progress(90, "Consolidando estabilidade do processador")
	return map[string]any{
		"logical_processors": runtime.NumCPU(),
		"sha256_operations":  operations,
		"operations_second":  float64(operations) / 30,
	}, nil
}

func memoryIntegrity(progress func(int, string)) (map[string]any, error) {
	const bytesToTest = 128 * 1024 * 1024
	progress(20, "Reservando 128 MB para verificação")
	block := make([]byte, bytesToTest)
	for i := range block {
		block[i] = byte((i*31 + 17) & 0xff)
	}
	progress(60, "Validando padrões gravados")
	for i, value := range block {
		if value != byte((i*31+17)&0xff) {
			return map[string]any{"bytes_tested": bytesToTest, "error_offset": i},
				fmt.Errorf("divergência de memória no offset %d", i)
		}
	}
	sum := sha256.Sum256(block)
	return map[string]any{
		"bytes_tested": bytesToTest,
		"integrity":    "ok",
		"sha256":       hex.EncodeToString(sum[:]),
	}, nil
}

func internetQuality(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	progress(20, "Testando resolução DNS")
	dnsStart := time.Now()
	addresses, dnsErr := net.DefaultResolver.LookupHost(ctx, "cloudflare.com")
	dnsMs := time.Since(dnsStart).Milliseconds()
	progress(50, "Testando acesso HTTPS externo")
	client := &http.Client{Timeout: 15 * time.Second}
	httpStart := time.Now()
	resp, httpErr := client.Get("https://www.cloudflare.com/cdn-cgi/trace")
	httpMs := time.Since(httpStart).Milliseconds()
	status := 0
	if resp != nil {
		status = resp.StatusCode
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 1024*1024))
		resp.Body.Close()
	}
	data := map[string]any{
		"dns_ms": dnsMs, "dns_addresses": addresses,
		"https_ms": httpMs, "https_status": status,
	}
	if dnsErr != nil {
		data["dns_error"] = dnsErr.Error()
	}
	if httpErr != nil {
		data["https_error"] = httpErr.Error()
	}
	if dnsErr != nil && httpErr != nil {
		return data, fmt.Errorf("DNS e acesso HTTPS falharam")
	}
	return data, nil
}

func diskPerformance(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	path := filepath.Join(os.TempDir(), "tgdesk-diagnostic.bin")
	defer os.Remove(path)
	const size = 128 * 1024 * 1024
	block := make([]byte, 1024*1024)
	for i := range block {
		block[i] = byte(i)
	}
	progress(15, "Medindo escrita temporária")
	start := time.Now()
	file, err := os.Create(path)
	if err != nil {
		return map[string]any{}, err
	}
	for written := 0; written < size; written += len(block) {
		if ctx.Err() != nil {
			file.Close()
			return map[string]any{}, ctx.Err()
		}
		if _, err = file.Write(block); err != nil {
			file.Close()
			return map[string]any{}, err
		}
	}
	_ = file.Sync()
	file.Close()
	writeSeconds := time.Since(start).Seconds()
	progress(60, "Medindo leitura e validando conteúdo")
	start = time.Now()
	file, err = os.Open(path)
	if err != nil {
		return map[string]any{}, err
	}
	hash := sha256.New()
	_, err = io.Copy(hash, file)
	file.Close()
	readSeconds := time.Since(start).Seconds()
	return map[string]any{
		"bytes_tested": size,
		"write_mbps":   float64(size) / 1024 / 1024 / writeSeconds,
		"read_mbps":    float64(size) / 1024 / 1024 / readSeconds,
		"sha256":       hex.EncodeToString(hash.Sum(nil)),
	}, err
}

func commandDiagnostic(ctx context.Context, progress func(int, string), percent int,
	message, name string, args ...string) (map[string]any, error) {
	progress(percent, message)
	cmd := exec.CommandContext(ctx, name, args...)
	output, err := cmd.CombinedOutput()
	logText := strings.TrimSpace(string(output))
	if len(logText) > 256*1024 {
		logText = logText[len(logText)-256*1024:]
	}
	exitCode := -1
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}
	return map[string]any{"exit_code": exitCode, "log": logText}, err
}
