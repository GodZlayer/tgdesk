package main

import (
	"encoding/json"
	"os/exec"
	"strings"
	"syscall"
)

// HardwareSnapshot contém somente leituras instantâneas. Médias, picos,
// mínimos e histórico de quedas são responsabilidade exclusiva do servidor.
type HardwareSnapshot struct {
	CPU      CPUReading       `json:"cpu"`
	GPUs     []GPUReading     `json:"gpus"`
	Memory   []MemoryReading  `json:"memory"`
	Storage  []StorageReading `json:"storage"`
	Networks []NetworkReading `json:"networks"`
}

type CPUReading struct {
	Name        string  `json:"name"`
	Usage       float64 `json:"usage"`
	Temperature float64 `json:"temperature,omitempty"`
	ClockMHz    float64 `json:"clock_mhz"`
}

type GPUReading struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Usage       float64 `json:"usage"`
	Temperature float64 `json:"temperature,omitempty"`
	ClockMHz    float64 `json:"clock_mhz,omitempty"`
}

type MemoryReading struct {
	ID             string `json:"id"`
	Slot           string `json:"slot"`
	Manufacturer   string `json:"manufacturer,omitempty"`
	PartNumber     string `json:"part_number,omitempty"`
	Type           string `json:"type"`
	SpeedMHz       uint64 `json:"speed_mhz"`
	TotalBytes     uint64 `json:"total_bytes"`
	UsedBytes      uint64 `json:"used_bytes"`
	UsageEstimated bool   `json:"usage_estimated"`
}

type StorageReading struct {
	ID          string  `json:"id"`
	Model       string  `json:"model"`
	MediaType   string  `json:"media_type"`
	BusType     string  `json:"bus_type"`
	TotalBytes  uint64  `json:"total_bytes"`
	UsedBytes   uint64  `json:"used_bytes"`
	UsedPct     float64 `json:"used_pct"`
	SMARTStatus string  `json:"smart_status"`
	LifePct     float64 `json:"life_pct,omitempty"`
	Temperature float64 `json:"temperature,omitempty"`
}

type NetworkReading struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	Description  string `json:"description"`
	Status       string `json:"status"`
	LinkSpeedBps uint64 `json:"link_speed_bps"`
	RxBytesTotal uint64 `json:"rx_bytes_total"`
	TxBytesTotal uint64 `json:"tx_bytes_total"`
}

// Uma única invocação evita janelas piscando e relaciona partições aos discos
// físicos. O uso de RAM por slot é proporcional ao uso global porque o Windows
// não atribui páginas físicas a um DIMM específico.
const psHardwareScript = `
$ErrorActionPreference='SilentlyContinue'
$os=Get-CimInstance Win32_OperatingSystem
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuTemp=0
try { $t=Get-CimInstance -Namespace root/wmi -Class MSAcpi_ThermalZoneTemperature | Select-Object -First 1; if($t.CurrentTemperature){$cpuTemp=[math]::Round(($t.CurrentTemperature/10)-273.15,1)} } catch {}
$cpuUsage=[double]$cpu.LoadPercentage
$memoryLoad=if([double]$os.TotalVisibleMemorySize -gt 0){1-([double]$os.FreePhysicalMemory/[double]$os.TotalVisibleMemorySize)}else{0}
$dimms=@(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
  $ddr=@{20='DDR';21='DDR2';24='DDR3';26='DDR4';34='DDR5'}[[int]$_.SMBIOSMemoryType]
  if(!$ddr){$ddr='Desconhecida'}
  [ordered]@{id=("$($_.DeviceLocator)|$($_.SerialNumber)").Trim();slot="$($_.DeviceLocator)";manufacturer="$($_.Manufacturer)".Trim();part_number="$($_.PartNumber)".Trim();type=$ddr;speed_mhz=[uint64]$_.ConfiguredClockSpeed;total_bytes=[uint64]$_.Capacity;used_bytes=[uint64]([double]$_.Capacity*$memoryLoad);usage_estimated=$true}
})
$gpus=@()
try {
  $lines=@(& nvidia-smi --query-gpu=uuid,name,utilization.gpu,temperature.gpu,clocks.current.graphics --format=csv,noheader,nounits 2>$null)
  foreach($line in $lines){$p=$line -split ',';if($p.Count-ge 5){$gpus += [ordered]@{id=$p[0].Trim();name=$p[1].Trim();usage=[double]$p[2];temperature=[double]$p[3];clock_mhz=[double]$p[4]}}}
} catch {}
if($gpus.Count-eq 0){
  $gpus=@(Get-CimInstance Win32_VideoController | Where-Object {$_.Name -and $_.Name -notmatch 'Remote|Basic Display'} | ForEach-Object {[ordered]@{id="$($_.PNPDeviceID)";name="$($_.Name)";usage=0;temperature=0;clock_mhz=0}})
}
$storage=@()
try {
  foreach($d in @(Get-PhysicalDisk)){
    $used=0
    try { foreach($part in @($d | Get-Disk | Get-Partition)){foreach($vol in @($part | Get-Volume)){if($vol.Size){$used += [uint64]($vol.Size-$vol.SizeRemaining)}}} } catch {}
    $life=0;$temp=0
    try {$r=$d|Get-StorageReliabilityCounter;if($null-ne $r.Wear){$life=[math]::Max(0,100-[double]$r.Wear)};if($r.Temperature){$temp=[double]$r.Temperature}}catch{}
    $total=[uint64]$d.Size;$pct=if($total){[math]::Round(($used/$total)*100,2)}else{0}
    $storage += [ordered]@{id="$($d.UniqueId)";model="$($d.FriendlyName)";media_type="$($d.MediaType)";bus_type="$($d.BusType)";total_bytes=$total;used_bytes=[uint64]$used;used_pct=$pct;smart_status="$($d.HealthStatus)";life_pct=$life;temperature=$temp}
  }
} catch {}
$nets=@(Get-NetAdapter -Physical | ForEach-Object {
  $s=$_|Get-NetAdapterStatistics
  [ordered]@{id="$($_.InterfaceGuid)";name="$($_.Name)";description="$($_.InterfaceDescription)";status="$($_.Status)";link_speed_bps=[uint64]$_.TransmitLinkSpeed;rx_bytes_total=[uint64]$s.ReceivedBytes;tx_bytes_total=[uint64]$s.SentBytes}
})
[ordered]@{
 cpu=[ordered]@{name="$($cpu.Name)".Trim();usage=$cpuUsage;temperature=$cpuTemp;clock_mhz=[double]$cpu.CurrentClockSpeed}
 gpus=$gpus;memory=$dimms;storage=$storage;networks=$nets
}|ConvertTo-Json -Depth 6 -Compress
`

func collectHardwareSnapshot() HardwareSnapshot {
	h := HardwareSnapshot{
		GPUs: []GPUReading{}, Memory: []MemoryReading{},
		Storage: []StorageReading{}, Networks: []NetworkReading{},
	}
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", psHardwareScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}
	out, err := cmd.Output()
	if err != nil {
		return h
	}
	if s := strings.TrimSpace(string(out)); s != "" {
		_ = json.Unmarshal([]byte(s), &h)
	}
	return h
}
