package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
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
	ID    string
	Test  string
	Tests []string
}

type diagnosticProgress struct {
	ID             string         `json:"-"`
	Test           string         `json:"test"`
	Group          string         `json:"group,omitempty"`
	Progress       int            `json:"progress"`
	TestProgress   int            `json:"test_progress,omitempty"`
	GroupProgress  int            `json:"group_progress,omitempty"`
	CompletedTests int            `json:"completed_tests,omitempty"`
	TotalTests     int            `json:"total_tests,omitempty"`
	Message        string         `json:"message"`
	Results        map[string]any `json:"results,omitempty"`
	Order          []string       `json:"order,omitempty"`
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

type diagnosticPauseGate struct {
	mu      sync.Mutex
	paused  bool
	changed chan struct{}
}

type diagnosticPauseKey struct{}

func newDiagnosticPauseGate() *diagnosticPauseGate {
	return &diagnosticPauseGate{changed: make(chan struct{})}
}

func (gate *diagnosticPauseGate) set(paused bool) {
	gate.mu.Lock()
	if gate.paused != paused {
		gate.paused = paused
		close(gate.changed)
		gate.changed = make(chan struct{})
	}
	gate.mu.Unlock()
}

func (gate *diagnosticPauseGate) wait(ctx context.Context) error {
	for {
		gate.mu.Lock()
		paused, changed := gate.paused, gate.changed
		gate.mu.Unlock()
		if !paused {
			return ctx.Err()
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-changed:
		}
	}
}

func waitDiagnosticPause(ctx context.Context) error {
	if gate, ok := ctx.Value(diagnosticPauseKey{}).(*diagnosticPauseGate); ok {
		return gate.wait(ctx)
	}
	return ctx.Err()
}

func (r contextReader) Read(buffer []byte) (int, error) {
	if err := r.ctx.Err(); err != nil {
		return 0, err
	}
	return r.r.Read(buffer)
}

func runDiagnostic(ctx context.Context, req diagnosticRequest, gate *diagnosticPauseGate, progress chan<- diagnosticProgress, result chan<- diagnosticResult) {
	ctx = context.WithValue(ctx, diagnosticPauseKey{}, gate)
	selected := req.Tests
	if len(selected) == 0 && req.Test != "" {
		selected = []string{req.Test}
	}
	rootTest := "custom_queue"
	if len(selected) == 1 {
		rootTest = selected[0]
	}
	progress <- diagnosticProgress{ID: req.ID, Test: rootTest, Progress: 5, Message: "Preparando teste"}
	started := time.Now()
	var data map[string]any
	var err error
	if rootTest == "all_tests" || len(selected) > 1 {
		tests := selected
		if rootTest == "all_tests" {
			tests = completeDiagnosticTests
		}
		data, err = diagnosticSuite(ctx, tests, func(event diagnosticProgress) {
			event.ID = req.ID
			progress <- event
		})
	} else {
		data, err = executeDiagnostic(ctx, rootTest, func(percent int, message string) {
			progress <- diagnosticProgress{ID: req.ID, Test: rootTest, Progress: percent,
				TestProgress: percent, Message: message}
		})
	}
	data["test"] = rootTest
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
	case "memory_extended":
		return memoryExtended(ctx, progress)
	case "internet_quality":
		return internetQuality(ctx, progress)
	case "network_latency_series":
		return networkLatencySeries(ctx, progress)
	case "disk_performance":
		return diskPerformance(ctx, progress)
	case "disk_random_performance":
		return diskRandomPerformance(ctx, progress)
	case "smart_extended":
		return commandDiagnostic(ctx, progress, 40, "Consultando saúde física",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"Get-PhysicalDisk | ForEach-Object { $d=$_; $r=$d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Name=$d.FriendlyName;Health=$d.HealthStatus;Operational=$d.OperationalStatus;Temperature=$r.Temperature;Wear=$r.Wear;ReadErrors=$r.ReadErrorsTotal;WriteErrors=$r.WriteErrorsTotal} } | ConvertTo-Json -Depth 4")
	case "badblocks-read":
		return commandDiagnostic(ctx, progress, 30, "Lendo contadores de confiabilidade e setores defeituosos (somente leitura)",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"Get-PhysicalDisk | ForEach-Object { $d=$_; $r=$d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; [pscustomobject]@{Name=$d.FriendlyName;Health=$d.HealthStatus;ReadErrorsTotal=$r.ReadErrorsTotal;ReadErrorsUncorrected=$r.ReadErrorsUncorrected;ReadErrorsCorrected=$r.ReadErrorsCorrected} } | ConvertTo-Json -Depth 4")
	case "storage_surface_read":
		return storageSurfaceRead(ctx, progress)
	case "filesystem_scan":
		return commandDiagnostic(ctx, progress, 15, "Verificando volumes e eventos do sistema de arquivos",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"$ErrorActionPreference='SilentlyContinue'; $v=Get-Volume | Select-Object DriveLetter,FileSystem,HealthStatus,OperationalStatus,Size,SizeRemaining; $e=Get-WinEvent -FilterHashtable @{LogName='System';Id=55,98;StartTime=(Get-Date).AddDays(-30)} -MaxEvents 100 | Select-Object TimeCreated,Id,ProviderName,Message; [pscustomobject]@{Volumes=$v;FileSystemEvents=$e} | ConvertTo-Json -Depth 5; exit 0")
	case "filesystem_deep_scan":
		return commandDiagnostic(ctx, progress, 10, "Executando varredura online dos volumes",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"$ErrorActionPreference='Continue'; $results=@(); Get-Volume | Where-Object {$_.DriveLetter -and $_.FileSystem -in @('NTFS','ReFS')} | ForEach-Object { $v=$_; try { Repair-Volume -DriveLetter $v.DriveLetter -Scan -ErrorAction Stop | Out-Null; $results += [pscustomobject]@{Drive=($v.DriveLetter+':');FileSystem=$v.FileSystem;Status='healthy';Error=$null} } catch { $results += [pscustomobject]@{Drive=($v.DriveLetter+':');FileSystem=$v.FileSystem;Status='failed';Error=$_.Exception.Message} } }; [pscustomobject]@{Volumes=$results;Scanned=$results.Count;Failed=@($results|Where-Object Status -eq 'failed').Count} | ConvertTo-Json -Depth 5; exit 0")
	case "gpu_stress":
		return commandDiagnostic(ctx, progress, 20, "Amostrando controladores e motores gráficos",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"$ErrorActionPreference='SilentlyContinue'; $g=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,Status,AdapterRAM,CurrentHorizontalResolution,CurrentVerticalResolution; $s=@(Get-Counter '\\GPU Engine(*)\\Utilization Percentage' -SampleInterval 1 -MaxSamples 10).CounterSamples | Select-Object InstanceName,CookedValue; [pscustomobject]@{Controllers=$g;EngineSamples=$s} | ConvertTo-Json -Depth 5; exit 0")
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
		return commandDiagnostic(ctx, progress, 35, "Consultando segurança", "powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='SilentlyContinue'; $d=try{Get-MpComputerStatus}catch{$null}; $f=try{Get-NetFirewallProfile|Select-Object Name,Enabled}catch{$null}; $s=try{Confirm-SecureBootUEFI}catch{$null}; $b=try{Get-BitLockerVolume|Select-Object MountPoint,VolumeStatus,ProtectionStatus}catch{$null}; [pscustomobject]@{Defender=$d;Firewall=$f;SecureBoot=$s;BitLocker=$b} | ConvertTo-Json -Depth 5; exit 0")
	case "defender_quick_scan":
		return commandDiagnostic(ctx, progress, 5, "Executando verificação rápida do Microsoft Defender",
			"powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
			"$ErrorActionPreference='Stop'; Start-MpScan -ScanType QuickScan; $status=Get-MpComputerStatus; $threats=@(Get-MpThreatDetection | Select-Object -First 100 ThreatID,InitialDetectionTime,Resources,ActionSuccess); [pscustomobject]@{Status='completed';AntivirusEnabled=$status.AntivirusEnabled;LastQuickScan=$status.QuickScanEndTime;Threats=$threats;ThreatCount=$threats.Count} | ConvertTo-Json -Depth 6")
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

var completeDiagnosticTests = []string{
	"system_overview", "driver_errors", "critical_events", "service_failures",
	"startup_inventory", "windows_integrity", "update_status", "cpu_stress",
	"process_pressure", "memory_integrity", "memory_extended", "internet_quality",
	"network_latency_series", "network_adapters", "dns_diagnostics", "route_table",
	"disk_performance", "disk_random_performance", "smart_extended", "badblocks-read",
	"storage_surface_read", "filesystem_scan", "filesystem_deep_scan", "storage_volumes",
	"gpu_stress", "battery_health", "security_posture", "defender_quick_scan",
	"temperature_sensors",
}

var diagnosticGroups = map[string]string{
	"system_overview": "Sistema", "driver_errors": "Sistema", "critical_events": "Sistema",
	"service_failures": "Sistema", "startup_inventory": "Sistema", "windows_integrity": "Sistema",
	"update_status": "Sistema", "cpu_stress": "Processamento", "process_pressure": "Processamento",
	"memory_integrity": "Memória", "memory_extended": "Memória", "internet_quality": "Rede",
	"network_latency_series": "Rede", "network_adapters": "Rede",
	"dns_diagnostics": "Rede", "route_table": "Rede", "disk_performance": "Armazenamento",
	"smart_extended": "Armazenamento", "badblocks-read": "Armazenamento",
	"storage_surface_read": "Armazenamento", "filesystem_scan": "Armazenamento",
	"disk_random_performance": "Armazenamento", "filesystem_deep_scan": "Armazenamento",
	"storage_volumes": "Armazenamento", "gpu_stress": "Vídeo", "battery_health": "Energia",
	"security_posture": "Segurança", "defender_quick_scan": "Segurança",
	"temperature_sensors": "Hardware",
}

func cloneDiagnosticResults(results map[string]any) map[string]any {
	raw, _ := json.Marshal(results)
	var clone map[string]any
	_ = json.Unmarshal(raw, &clone)
	return clone
}

func allDiagnostics(ctx context.Context, report func(diagnosticProgress)) (map[string]any, error) {
	return diagnosticSuite(ctx, completeDiagnosticTests, report)
}

func diagnosticSuite(ctx context.Context, selectedTests []string, report func(diagnosticProgress)) (map[string]any, error) {
	results := make(map[string]any, len(selectedTests))
	failures := make([]string, 0)
	groupTotals := map[string]int{}
	groupCompleted := map[string]int{}
	for _, test := range selectedTests {
		results[test] = map[string]any{"status": "queued", "group": diagnosticGroups[test], "progress": 0}
		groupTotals[diagnosticGroups[test]]++
	}
	for index, test := range selectedTests {
		if err := waitDiagnosticPause(ctx); err != nil {
			return map[string]any{"tests": results, "failures": failures}, err
		}
		if err := ctx.Err(); err != nil {
			return map[string]any{"tests": results, "failures": failures}, err
		}
		group := diagnosticGroups[test]
		entry := map[string]any{"status": "running", "group": group, "progress": 0}
		results[test] = entry
		data, err := executeDiagnostic(ctx, test, func(child int, message string) {
			entry["progress"] = child
			entry["message"] = message
			overall := (index*100 + child) / len(selectedTests)
			groupProgress := (groupCompleted[group]*100 + child) / groupTotals[group]
			report(diagnosticProgress{Test: test, Group: group, Progress: overall,
				TestProgress: child, GroupProgress: groupProgress, CompletedTests: index,
				TotalTests: len(selectedTests), Message: message,
				Results: cloneDiagnosticResults(results), Order: selectedTests})
		})
		entry = map[string]any{"status": "completed", "group": group, "progress": 100, "results": data}
		if err != nil {
			if ctx.Err() != nil {
				return map[string]any{"tests": results, "failures": failures}, ctx.Err()
			}
			entry["status"] = "failed"
			entry["error"] = err.Error()
			failures = append(failures, test+": "+err.Error())
		}
		results[test] = entry
		groupCompleted[group]++
		report(diagnosticProgress{Test: test, Group: group, Progress: (index + 1) * 100 / len(selectedTests),
			TestProgress: 100, GroupProgress: groupCompleted[group] * 100 / groupTotals[group],
			CompletedTests: index + 1, TotalTests: len(selectedTests),
			Message: fmt.Sprintf("%s concluído (%d/%d)", test, index+1, len(selectedTests)),
			Results: cloneDiagnosticResults(results), Order: selectedTests})
	}
	assessment := map[string]any{
		"level": "normal", "title": "Nenhuma falha técnica detectada",
		"summary": fmt.Sprintf("Os %d testes foram executados e concluídos sem falhas.", len(selectedTests)),
	}
	if len(failures) > 0 {
		assessment = map[string]any{
			"level": "attention", "title": "Existem testes que precisam de análise",
			"summary": fmt.Sprintf("%d de %d testes concluíram; %d apresentaram falha. Abra cada resultado para ver a causa.", len(selectedTests)-len(failures), len(selectedTests), len(failures)),
		}
	}
	summary := map[string]any{
		"tests": results, "order": selectedTests, "total": len(selectedTests),
		"executed": len(selectedTests), "completed": len(selectedTests) - len(failures),
		"failed": len(failures), "failures": failures, "assessment": assessment,
	}
	return summary, nil
}

type physicalDisk struct {
	DeviceID string `json:"DeviceID"`
	Model    string `json:"Model"`
	Size     uint64 `json:"Size"`
}

func storageSurfaceRead(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	if runtime.GOOS != "windows" {
		return map[string]any{}, fmt.Errorf("leitura de disco físico disponível somente no Windows")
	}
	cmd := exec.CommandContext(ctx, "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
		"@(Get-CimInstance Win32_DiskDrive | Select-Object DeviceID,Model,@{n='Size';e={[uint64]$_.Size}}) | ConvertTo-Json -Compress")
	output, err := cmd.Output()
	if err != nil {
		return map[string]any{}, fmt.Errorf("falha ao enumerar discos: %w", err)
	}
	var disks []physicalDisk
	if err := json.Unmarshal(output, &disks); err != nil {
		var disk physicalDisk
		if singleErr := json.Unmarshal(output, &disk); singleErr != nil {
			return map[string]any{}, fmt.Errorf("resposta de discos inválida: %w", err)
		}
		disks = []physicalDisk{disk}
	}
	var total uint64
	for _, disk := range disks {
		total += disk.Size
	}
	if total == 0 {
		return map[string]any{}, fmt.Errorf("nenhum disco físico acessível")
	}
	buffer := make([]byte, 8*1024*1024)
	var readTotal uint64
	resultDisks := make([]map[string]any, 0, len(disks))
	for _, disk := range disks {
		if err := waitDiagnosticPause(ctx); err != nil {
			return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, err
		}
		entry := map[string]any{"device_id": disk.DeviceID, "model": disk.Model, "size": disk.Size}
		file, openErr := os.Open(disk.DeviceID)
		if openErr != nil {
			entry["status"], entry["error"] = "failed", openErr.Error()
			resultDisks = append(resultDisks, entry)
			return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, openErr
		}
		var diskRead uint64
		var diskErrors int
		regions := make([]map[string]any, 0, 240)
		regionSize := disk.Size / 240
		if regionSize < uint64(len(buffer)) {
			regionSize = uint64(len(buffer))
		}
		var regionStart, regionBytes uint64
		var regionDuration time.Duration
		regionStatus := "healthy"
		flushRegion := func() {
			if regionBytes == 0 && regionStatus == "healthy" {
				return
			}
			milliseconds := float64(regionDuration.Microseconds()) / 1000
			mbps := float64(0)
			if regionDuration > 0 {
				mbps = float64(regionBytes) / 1024 / 1024 / regionDuration.Seconds()
			}
			status := regionStatus
			if status == "healthy" && milliseconds > 0 && mbps < 10 {
				status = "slow"
			}
			regions = append(regions, map[string]any{
				"offset": regionStart, "bytes": regionBytes, "latency_ms": milliseconds,
				"mbps": mbps, "status": status,
			})
			regionStart = diskRead
			regionBytes = 0
			regionDuration = 0
			regionStatus = "healthy"
		}
		for diskRead < disk.Size {
			if err := waitDiagnosticPause(ctx); err != nil {
				file.Close()
				return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, err
			}
			if err := ctx.Err(); err != nil {
				file.Close()
				return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, err
			}
			want := len(buffer)
			if remaining := disk.Size - diskRead; remaining < uint64(want) {
				want = int(remaining)
			}
			readStarted := time.Now()
			n, readErr := file.Read(buffer[:want])
			regionDuration += time.Since(readStarted)
			diskRead += uint64(n)
			readTotal += uint64(n)
			regionBytes += uint64(n)
			progress(int(readTotal*100/total), fmt.Sprintf("Lendo %s: %d de %d bytes", disk.Model, diskRead, disk.Size))
			if readErr != nil {
				diskErrors++
				regionStatus = "error"
				if n == 0 {
					skip := int64(want)
					if _, seekErr := file.Seek(skip, io.SeekCurrent); seekErr != nil {
						flushRegion()
						file.Close()
						entry["status"], entry["error"], entry["bytes_read"] = "failed", readErr.Error(), diskRead
						entry["regions"], entry["read_errors"] = regions, diskErrors
						resultDisks = append(resultDisks, entry)
						return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, readErr
					}
					diskRead += uint64(want)
					readTotal += uint64(want)
				}
			}
			if n == 0 && readErr == nil {
				file.Close()
				return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, io.ErrNoProgress
			}
			if diskRead-regionStart >= regionSize || diskRead >= disk.Size {
				flushRegion()
			}
		}
		file.Close()
		entry["status"], entry["bytes_read"] = "completed", diskRead
		entry["regions"], entry["read_errors"] = regions, diskErrors
		resultDisks = append(resultDisks, entry)
	}
	return map[string]any{"disks": resultDisks, "bytes_read": readTotal}, nil
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
				if waitDiagnosticPause(ctx) != nil {
					break
				}
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
		if i%(4*1024*1024) == 0 {
			if err := waitDiagnosticPause(ctx); err != nil {
				return map[string]any{}, err
			}
		}
		if i%(1024*1024) == 0 && ctx.Err() != nil {
			return map[string]any{}, ctx.Err()
		}
		block[i] = byte((i*31 + 17) & 0xff)
	}
	progress(60, "Validando padrões gravados")
	for i, value := range block {
		if i%(4*1024*1024) == 0 {
			if err := waitDiagnosticPause(ctx); err != nil {
				return map[string]any{}, err
			}
		}
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

func memoryExtended(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	const bytesToTest = 256 * 1024 * 1024
	patterns := []byte{0x00, 0xff, 0x55, 0xaa, 0x33, 0xcc}
	block := make([]byte, bytesToTest)
	passes := make([]map[string]any, 0, len(patterns))
	for pass, pattern := range patterns {
		if err := waitDiagnosticPause(ctx); err != nil {
			return map[string]any{"passes": passes, "bytes_tested": bytesToTest}, err
		}
		progress(pass*100/len(patterns), fmt.Sprintf("Padrão %02X (%d/%d)", pattern, pass+1, len(patterns)))
		for index := range block {
			if index%(4*1024*1024) == 0 && ctx.Err() != nil {
				return map[string]any{"passes": passes, "bytes_tested": bytesToTest}, ctx.Err()
			}
			block[index] = pattern
		}
		mismatches := 0
		firstOffset := -1
		for index, value := range block {
			if value != pattern {
				mismatches++
				if firstOffset < 0 {
					firstOffset = index
				}
			}
		}
		passes = append(passes, map[string]any{
			"pass": pass + 1, "pattern": fmt.Sprintf("0x%02X", pattern),
			"status": "healthy", "mismatches": mismatches, "first_error_offset": firstOffset,
		})
		if mismatches > 0 {
			passes[len(passes)-1]["status"] = "failed"
			return map[string]any{"passes": passes, "bytes_tested": bytesToTest},
				fmt.Errorf("%d divergência(s) no padrão %02X", mismatches, pattern)
		}
	}
	progress(100, "Todos os padrões de memória foram validados")
	return map[string]any{
		"bytes_tested": bytesToTest, "patterns": len(patterns), "passes": passes,
		"status": "healthy", "limitations": "teste online; a memória reservada pelo Windows não é acessível",
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

func networkLatencySeries(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	const samples = 20
	latencies := make([]float64, 0, samples)
	failed := 0
	dialer := net.Dialer{Timeout: 3 * time.Second}
	for index := 0; index < samples; index++ {
		if err := waitDiagnosticPause(ctx); err != nil {
			return map[string]any{"latency_ms": latencies, "failed": failed}, err
		}
		if err := ctx.Err(); err != nil {
			return map[string]any{"latency_ms": latencies, "failed": failed}, err
		}
		started := time.Now()
		connection, err := dialer.DialContext(ctx, "tcp", "1.1.1.1:443")
		elapsed := float64(time.Since(started).Microseconds()) / 1000
		if err != nil {
			failed++
		} else {
			latencies = append(latencies, elapsed)
			connection.Close()
		}
		progress((index+1)*100/samples, fmt.Sprintf("Amostra de rede %d/%d", index+1, samples))
		time.Sleep(250 * time.Millisecond)
	}
	average, jitter := float64(0), float64(0)
	for index, value := range latencies {
		average += value
		if index > 0 {
			jitter += math.Abs(value - latencies[index-1])
		}
	}
	if len(latencies) > 0 {
		average /= float64(len(latencies))
	}
	if len(latencies) > 1 {
		jitter /= float64(len(latencies) - 1)
	}
	result := map[string]any{
		"target": "1.1.1.1:443", "latency_ms": latencies, "average_ms": average,
		"jitter_ms": jitter, "samples": samples, "failed": failed,
		"loss_percent": float64(failed) * 100 / samples,
	}
	if len(latencies) == 0 {
		return result, fmt.Errorf("nenhuma amostra de rede respondeu")
	}
	return result, nil
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
		if err := waitDiagnosticPause(ctx); err != nil {
			file.Close()
			return map[string]any{}, err
		}
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

func diskRandomPerformance(ctx context.Context, progress func(int, string)) (map[string]any, error) {
	path := filepath.Join(os.TempDir(), "tgdesk-random-io.bin")
	defer os.Remove(path)
	const fileSize = 256 * 1024 * 1024
	const blockSize = 4 * 1024
	const operations = 1000
	file, err := os.Create(path)
	if err != nil {
		return map[string]any{}, err
	}
	seedBlock := make([]byte, 1024*1024)
	for offset := 0; offset < fileSize; offset += len(seedBlock) {
		if err := waitDiagnosticPause(ctx); err != nil {
			file.Close()
			return map[string]any{}, err
		}
		if _, err = file.Write(seedBlock); err != nil {
			file.Close()
			return map[string]any{}, err
		}
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return map[string]any{}, err
	}
	latencies := make([]float64, 0, operations)
	buffer := make([]byte, blockSize)
	state := uint64(0x54474445534b)
	started := time.Now()
	for operation := 0; operation < operations; operation++ {
		if err := waitDiagnosticPause(ctx); err != nil {
			file.Close()
			return map[string]any{"latency_ms": latencies}, err
		}
		if err := ctx.Err(); err != nil {
			file.Close()
			return map[string]any{"latency_ms": latencies}, err
		}
		state = state*6364136223846793005 + 1
		offset := int64((state % uint64(fileSize/blockSize)) * blockSize)
		readStarted := time.Now()
		if _, err = file.ReadAt(buffer, offset); err != nil {
			file.Close()
			return map[string]any{"latency_ms": latencies, "offset": offset}, err
		}
		latencies = append(latencies, float64(time.Since(readStarted).Microseconds())/1000)
		if operation%25 == 0 {
			progress(operation*100/operations, fmt.Sprintf("Leitura aleatória %d/%d", operation, operations))
		}
	}
	file.Close()
	duration := time.Since(started).Seconds()
	average := float64(0)
	maximum := float64(0)
	for _, latency := range latencies {
		average += latency
		if latency > maximum {
			maximum = latency
		}
	}
	average /= operations
	return map[string]any{
		"block_bytes": blockSize, "operations": operations,
		"iops": float64(operations) / duration, "average_latency_ms": average,
		"maximum_latency_ms": maximum, "latency_ms": latencies,
	}, nil
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
	result := map[string]any{"exit_code": exitCode}
	if logText != "" {
		var structured any
		if json.Unmarshal([]byte(logText), &structured) == nil {
			switch value := structured.(type) {
			case map[string]any:
				for key, item := range value {
					result[key] = item
				}
			default:
				result["items"] = value
			}
		} else {
			result["log"] = logText
		}
	}
	return result, err
}
