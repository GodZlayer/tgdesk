package main

import (
	"encoding/json"
	"os/exec"
	"strings"
	"syscall"
)

// extendedHealth traz os indicadores de "qualidade de vida" do hardware que
// vão além de uso de CPU/mem/disco: saúde SMART do disco, temperatura da CPU
// e status/uso da GPU. Nem toda máquina expõe todos (temperatura de CPU via
// ACPI costuma faltar em desktops; GPU depende de nvidia-smi), então cada
// campo é best-effort e fica zerado/vazio quando indisponível.
type extendedHealth struct {
	DiskHealth string  `json:"disk_health,omitempty"` // Healthy | Warning | Unhealthy
	CPUTemp    float64 `json:"cpu_temp,omitempty"`    // °C
	GPUUtil    float64 `json:"gpu_util,omitempty"`    // %
	GPUTemp    float64 `json:"gpu_temp,omitempty"`    // °C
	GPUName    string  `json:"gpu_name,omitempty"`
}

// powershell coleta tudo numa única invocação (menos processos por ciclo) e
// devolve JSON. Roda com janela escondida — sem isso, como o agente é
// windowsgui, cada chamada piscaria um console.
const psHealthScript = `
$ErrorActionPreference='SilentlyContinue'
$out=@{}
try {
  $h = Get-PhysicalDisk | Where-Object { $_.HealthStatus } | Select-Object -First 1
  if ($h) { $out.disk_health = "$($h.HealthStatus)" }
} catch {}
try {
  $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
  $c = ($t | Select-Object -First 1).CurrentTemperature
  if ($c) { $out.cpu_temp = [math]::Round(($c/10)-273.15,1) }
} catch {}
try {
  $g = & nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null
  if ($g) {
    $p = ($g -split ',')
    $out.gpu_name = $p[0].Trim()
    $out.gpu_util = [double]($p[1].Trim())
    $out.gpu_temp = [double]($p[2].Trim())
  }
} catch {}
$out | ConvertTo-Json -Compress
`

func collectExtendedHealth() extendedHealth {
	var eh extendedHealth
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", psHealthScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000} // CREATE_NO_WINDOW
	out, err := cmd.Output()
	if err != nil {
		return eh
	}
	s := strings.TrimSpace(string(out))
	if s == "" {
		return eh
	}
	_ = json.Unmarshal([]byte(s), &eh)
	return eh
}
