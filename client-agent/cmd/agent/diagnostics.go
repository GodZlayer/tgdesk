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

type contextReader struct {
	ctx context.Context
	r   io.Reader
}

func (r contextReader) Read(buffer []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.r.Read(buffer)
}

func runDiagnostic(ctx context.Context, req diagnosticRequest, progress chan<- diagnosticProgress, result chan<- diagnosticResult) {
	progress <- diagnosticProgress{ID: req.ID, Test: req.Test, Progress: 5, Message: "Preparando teste"}
	ctx, cancel := context.WithTimeout(ctx, 12*time.Minute)
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
		if ctx.Err() == context.Canceled {
			status, errorText = "cancelled", "cancelado pelo técnico"
		}
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
		return memoryIntegrity(ctx, progress)
	case "internet_quality":
		return internetQuality(ctx, progress)
	case "disk_performance":
		return diskPerformance(ctx, progress)
	case "smart_extended":
		return commandDiagnostic(ctx, progress, 40, "Consultando saúde física",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"Get-PhysicalDisk | ForEach-Object { $d=$_; $r=$d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Name=$d.FriendlyName;Health=$d.HealthStatus;Operational=$d.OperationalStatus;Temperature=$r.Temperature;Wear=$r.Wear;ReadErrors=$r.ReadErrorsTotal;WriteErrors=$r.WriteErrorsTotal} } | ConvertTo-Json -Depth 4")
	case "badblocks-read":
		return commandDiagnostic(ctx, progress, 30, "Lendo contadores de confiabilidade e setores defeituosos (somente leitura)",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"Get-PhysicalDisk | ForEach-Object { $d=$_; $r=$d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Name=$d.FriendlyName;Health=$d.HealthStatus;ReadErrorsTotal=$r.ReadErrorsTotal;ReadErrorsUncorrected=$r.ReadErrorsUncorrected;ReadErrorsCorrected=$r.ReadErrorsCorrected} } | ConvertTo-Json -Depth 4")
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
	case "battery_health":
		return commandDiagnostic(ctx, progress, 35, "Consultando bateria", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_Battery | Select-Object Name,Status,EstimatedChargeRemaining,DesignVoltage | ConvertTo-Json")
	case "driver_errors":
		return commandDiagnostic(ctx, progress, 35, "Consultando dispositivos com erro", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_PnPEntity | Where-Object ConfigManagerErrorCode -ne 0 | Select-Object Name,PNPClass,ConfigManagerErrorCode | ConvertTo-Json")
	case "critical_events":
		return commandDiagnostic(ctx, progress, 25, "Lendo eventos críticos", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 200 | Select-Object TimeCreated,Id,ProviderName,LevelDisplayName,Message | ConvertTo-Json -Depth 3")
	case "service_failures":
		return commandDiagnostic(ctx, progress, 35, "Verificando serviços", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_Service | Where-Object {$_.StartMode -eq 'Auto' -and $_.State -ne 'Running'} | Select-Object Name,DisplayName,State,StartMode,ExitCode | ConvertTo-Json")
	case "startup_inventory":
		return commandDiagnostic(ctx, progress, 35, "Inventariando inicialização", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance Win32_StartupCommand | Select-Object Name,Command,Location,User | ConvertTo-Json")
	case "network_adapters":
		return commandDiagnostic(ctx, progress, 35, "Analisando adaptadores", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress | ConvertTo-Json")
	case "dns_diagnostics":
		return commandDiagnostic(ctx, progress, 35, "Testando DNS", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-DnsClientServerAddress | Where-Object ServerAddresses | ForEach-Object {[pscustomobject]@{Interface=$_.InterfaceAlias;Servers=$_.ServerAddresses;TGDesk=(Resolve-DnsName cloudflare.com -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty IPAddress)}} | ConvertTo-Json -Depth 3")
	case "route_table":
		return commandDiagnostic(ctx, progress, 35, "Analisando rotas", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-NetRoute -AddressFamily IPv4 | Sort-Object RouteMetric | Select-Object DestinationPrefix,NextHop,InterfaceAlias,RouteMetric,State | ConvertTo-Json")
	case "windows_integrity":
		return commandDiagnostic(ctx, progress, 10, "Executando DISM ScanHealth", "dism.exe", "/Online", "/Cleanup-Image", "/ScanHealth")
	case "update_status":
		return commandDiagnostic(ctx, progress, 35, "Consultando atualizações", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "[pscustomobject]@{HotFixes=(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 30);RebootPending=(Test-Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\\RebootRequired')} | ConvertTo-Json -Depth 4")
	case "security_posture":
		return commandDiagnostic(ctx, progress, 35, "Consultando segurança", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "[pscustomobject]@{Defender=(Get-MpComputerStatus -ErrorAction SilentlyContinue);Firewall=(Get-NetFirewallProfile | Select-Object Name,Enabled);SecureBoot=(Confirm-SecureBootUEFI -ErrorAction SilentlyContinue);BitLocker=(Get-BitLockerVolume -ErrorAction SilentlyContinue | Select-Object MountPoint,VolumeStatus,ProtectionStatus)} | ConvertTo-Json -Depth 4")
	case "temperature_sensors":
		return commandDiagnostic(ctx, progress, 35, "Lendo sensores térmicos", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object InstanceName,@{n='Celsius';e={[math]::Round(($_.CurrentTemperature/10)-273.15,1)}} | ConvertTo-Json")
	case "storage_volumes":
		return commandDiagnostic(ctx, progress, 35, "Analisando volumes", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystem,HealthStatus,OperationalStatus,Size,SizeRemaining | ConvertTo-Json")
	case "process_pressure":
		return commandDiagnostic(ctx, progress, 35, "Analisando processos", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "Get-Process | Sort-Object CPU -Descending | Select-Object -First 30 Name,Id,CPU,WorkingSet64,PrivateMemorySize64,Handles | ConvertTo-Json")
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

func memoryIntegrity(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	const bytesToTest = 128 * 1024 * 1024
	progress(20, "Reservando 128 MB para verificação")
	block := make([]byte, bytesToTest)
	for i := range block {
		if i%(1024*1024) == 0 && ctx.Err() != nil {
			return map[string]any{}, ctx.Err()
		}
		block[i] = byte((i*31 + 17) & 0xff)
	}
	progress(60, "Validando padrões gravados")
	for i, value := range block {
		if i%(1024*1024) == 0 && ctx.Err() != nil {
			return map[string]any{}, ctx.Err()
		}
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
	request, requestErr := http.NewRequestWithContext(ctx, http.MethodGet,
		"https://www.cloudflare.com/cdn-cgi/trace", nil)
	var resp *http.Response
	var httpErr error
	if requestErr != nil {
		httpErr = requestErr
	} else {
		resp, httpErr = client.Do(request)
	}
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
	_, err = io.Copy(hash, contextReader{ctx: ctx, r: file})
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
