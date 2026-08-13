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
	CPU           CPUReading       `json:"cpu"`
	GPUs          []GPUReading     `json:"gpus"`
	Memory        []MemoryReading  `json:"memory"`
	MemorySummary MemorySummary    `json:"memory_summary"`
	Storage       []StorageReading `json:"storage"`
	Networks      []NetworkReading `json:"networks"`
	// Atividade agregada do subsistema de disco (_Total). Fica fora de
	// `Storage` de propósito: aquilo é por peça, e o contador do Windows que
	// mede atividade é por VOLUME/instância, não por disco físico. Reportar
	// como se fosse da peça seria atribuir uma medida ao objeto errado.
	DiskActivity *DiskActivity `json:"disk_activity,omitempty"`
	// Os processos que mais consomem, no instante da amostra (§7.1).
	//
	// É a medida que faltava para `processo_em_segundo_plano` — provavelmente a
	// causa mais comum de lentidão intermitente, e até agora INDETECTÁVEL: sem
	// ela o produto sabia que a causa existe e não conseguia vê-la.
	TopProcessos []ProcessoTop `json:"top_processos,omitempty"`
}

// ProcessoTop é um processo entre os que mais consomem.
//
// PRIVACIDADE (§7.2), e não é opcional: nome de executável revela o que a
// pessoa faz; linha de comando e título de janela revelam que documento ela
// abriu. Aqui sobe APENAS o nome do executável, normalizado. Linha de comando,
// caminho e título de janela não sobem nunca por este caminho — só em rajada de
// incidente, com consentimento registrado.
type ProcessoTop struct {
	// Nome do executável, sem caminho e sem o sufixo de instância que o
	// contador do Windows acrescenta ("chrome#3" vira "chrome").
	Nome string `json:"nome"`
	// Percentual de CPU JÁ NORMALIZADO pelo número de núcleos.
	//
	// O contador do Windows soma entre núcleos: 213% num processador de 8
	// núcleos é 27% da máquina. Reportar o número cru faria o servidor comparar
	// máquinas de núcleos diferentes com a mesma régua.
	CPUPct *float64 `json:"cpu_pct,omitempty"`
	// Memória privada em MB — a que realmente pertence ao processo.
	MemoriaMB *float64 `json:"memoria_mb,omitempty"`
	// Bytes de I/O por segundo.
	IOBytesPorSeg *float64 `json:"io_bytes_por_seg,omitempty"`
}

type CPUReading struct {
	Name                 string   `json:"name"`
	Usage                *float64 `json:"usage,omitempty"`
	Temperature          *float64 `json:"temperature,omitempty"`
	ClockMHz             *float64 `json:"clock_mhz,omitempty"`
	BaseClockMHz         *float64 `json:"base_clock_mhz,omitempty"`
	PerformancePercent   *float64 `json:"performance_percent,omitempty"`
	DPCTimePercent       *float64 `json:"dpc_time_percent,omitempty"`
	InterruptTimePercent *float64 `json:"interrupt_time_percent,omitempty"`
	QueueLength          *float64 `json:"queue_length,omitempty"`
	MeasurementSource    string   `json:"measurement_source,omitempty"`
}

type GPUReading struct {
	ID                   string   `json:"id"`
	Name                 string   `json:"name"`
	Usage                *float64 `json:"usage,omitempty"`
	Temperature          *float64 `json:"temperature,omitempty"`
	ClockMHz             *float64 `json:"clock_mhz,omitempty"`
	DedicatedMemoryBytes *uint64  `json:"dedicated_memory_bytes,omitempty"`
	SharedMemoryBytes    *uint64  `json:"shared_memory_bytes,omitempty"`
	MeasurementSource    string   `json:"measurement_source,omitempty"`
}

type MemoryReading struct {
	ID             string `json:"id"`
	Slot           string `json:"slot"`
	Manufacturer   string `json:"manufacturer,omitempty"`
	PartNumber     string `json:"part_number,omitempty"`
	Type           string `json:"type"`
	SpeedMHz       uint64 `json:"speed_mhz"`
	TotalBytes     uint64 `json:"total_bytes"`
	UsedBytes      uint64 `json:"used_bytes,omitempty"` // compatibilidade com amostras 0.3.8
	UsageEstimated bool   `json:"usage_estimated,omitempty"`
}

type MemorySummary struct {
	TotalBytes       uint64   `json:"total_bytes"`
	UsedBytes        uint64   `json:"used_bytes"`
	AvailableBytes   uint64   `json:"available_bytes"`
	Usage            *float64 `json:"usage,omitempty"`
	CommitUsedBytes  uint64   `json:"commit_used_bytes,omitempty"`
	CommitLimitBytes uint64   `json:"commit_limit_bytes,omitempty"`
}

type VolumeReading struct {
	ID             string  `json:"id"`
	Label          string  `json:"label,omitempty"`
	FileSystem     string  `json:"file_system,omitempty"`
	TotalBytes     uint64  `json:"total_bytes"`
	UsedBytes      uint64  `json:"used_bytes"`
	AvailableBytes uint64  `json:"available_bytes"`
	UsedPct        float64 `json:"used_pct"`
}

type StorageReading struct {
	ID          string          `json:"id"`
	Model       string          `json:"model"`
	MediaType   string          `json:"media_type"`
	BusType     string          `json:"bus_type"`
	TotalBytes  uint64          `json:"total_bytes"`
	UsedBytes   uint64          `json:"used_bytes"`
	UsedPct     float64         `json:"used_pct"`
	SMARTStatus string          `json:"smart_status"`
	LifePct     *float64        `json:"life_pct,omitempty"`
	Temperature *float64        `json:"temperature,omitempty"`
	Volumes     []VolumeReading `json:"volumes,omitempty"`
}

// DiskActivity é a medida que faltava para explicar lentidão profunda.
//
// `used_pct` acima diz o quanto o disco está CHEIO. Isso não explica lentidão —
// disco cheio e disco lento são coisas diferentes, e o parque provou: a máquina
// com a lentidão mais severa tinha CPU e memória tranquilas e nenhum sinal
// coletado a explicava. O que falta é ATIVIDADE:
//
//	busy_pct   fração do tempo em que o disco não esteve ocioso
//	latency_ms tempo médio por transferência
//
// São essas duas que separam "o computador engasga porque um processo tomou a
// CPU por 3 segundos" de "tudo está lento porque cada leitura demora 40 ms".
// A primeira se resolve controlando o processo; a segunda, trocando a peça.
type DiskActivity struct {
	// Média sobre a janela de amostragem, em porcentagem.
	BusyPct *float64 `json:"busy_pct,omitempty"`
	// Latência média por transferência, em milissegundos.
	LatencyMs *float64 `json:"latency_ms,omitempty"`
	// Comprimento médio da fila. Fila alta com latência baixa é carga; fila
	// alta com latência alta é o disco não dando conta.
	QueueLength *float64 `json:"queue_length,omitempty"`
	// Quantas amostras sustentam a média. Sem isso não dá para distinguir
	// "medido e baixo" de "quase não medido" — e ausência é informação.
	Samples int `json:"samples"`
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
$cpuPerf=Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
$systemPerf=Get-CimInstance Win32_PerfFormattedData_PerfOS_System | Select-Object -First 1
$cpuUsage=if($null-ne $cpuPerf.PercentProcessorTime){[double]$cpuPerf.PercentProcessorTime}else{[double]$cpu.LoadPercentage}
$cpuBase=if($null-ne $cpu.MaxClockSpeed){[double]$cpu.MaxClockSpeed}else{$null}
$cpuPerformance=if($null-ne $cpuPerf.PercentProcessorPerformance){[double]$cpuPerf.PercentProcessorPerformance}else{$null}
$cpuClock=if($null-ne $cpuBase-and$null-ne $cpuPerformance-and$cpuBase-gt 0){[math]::Round($cpuBase*$cpuPerformance/100,0)}elseif($null-ne $cpuPerf.ProcessorFrequency){[double]$cpuPerf.ProcessorFrequency}else{$null}
$cpuDpc=if($null-ne $cpuPerf.PercentDPCTime){[double]$cpuPerf.PercentDPCTime}else{$null}
$cpuInterrupt=if($null-ne $cpuPerf.PercentInterruptTime){[double]$cpuPerf.PercentInterruptTime}else{$null}
$cpuQueue=if($null-ne $systemPerf.ProcessorQueueLength){[double]$systemPerf.ProcessorQueueLength}else{$null}
$memoryLoad=if([double]$os.TotalVisibleMemorySize -gt 0){1-([double]$os.FreePhysicalMemory/[double]$os.TotalVisibleMemorySize)}else{0}
$memoryTotal=[uint64]([double]$os.TotalVisibleMemorySize*1024)
$memoryAvailable=[uint64]([double]$os.FreePhysicalMemory*1024)
$memoryUsed=[uint64]($memoryTotal-$memoryAvailable)
$commitLimit=[uint64]([double]$os.TotalVirtualMemorySize*1024)
$commitUsed=[uint64]($commitLimit-([double]$os.FreeVirtualMemory*1024))
$dimms=@(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
  $ddr=@{20='DDR';21='DDR2';24='DDR3';26='DDR4';34='DDR5'}[[int]$_.SMBIOSMemoryType]
  if(!$ddr){$ddr='Desconhecida'}
  [ordered]@{id=("$($_.DeviceLocator)|$($_.SerialNumber)").Trim();slot="$($_.DeviceLocator)";manufacturer="$($_.Manufacturer)".Trim();part_number="$($_.PartNumber)".Trim();type=$ddr;speed_mhz=[uint64]$_.ConfiguredClockSpeed;total_bytes=[uint64]$_.Capacity}
})
$gpus=@()
try {
  $lines=@(& nvidia-smi --query-gpu=uuid,name,utilization.gpu,temperature.gpu,clocks.current.graphics --format=csv,noheader,nounits 2>$null)
  foreach($line in $lines){$p=$line -split ',';if($p.Count-ge 5){$gpus += [ordered]@{id=$p[0].Trim();name=$p[1].Trim();usage=[double]$p[2];temperature=[double]$p[3];clock_mhz=[double]$p[4];measurement_source='NVML'}}}
} catch {}
if($gpus.Count-eq 0){
  $physical=@(Get-CimInstance Win32_VideoController | Where-Object {$_.Name -and $_.Name -notmatch 'Remote|Basic Display|Parsec|Virtual|Indirect|Mirror|Hyper-V'})
  $engineGroups=@{}
  foreach($e in @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine)){
    if("$($e.Name)" -match '_phys_(\d+)_'){
      $key=$matches[1];$value=[double]$e.UtilizationPercentage
      if(!$engineGroups.ContainsKey($key)-or$value-gt[double]$engineGroups[$key]){$engineGroups[$key]=$value}
    }
  }
  $memoryGroups=@{}
  foreach($m in @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory)){
    if("$($m.Name)" -match '_phys_(\d+)'){
      $memoryGroups[$matches[1]]=[ordered]@{dedicated=[uint64]$m.DedicatedUsage;shared=[uint64]$m.SharedUsage}
    }
  }
  $perfKeys=@($engineGroups.Keys|Sort-Object{[int]$_})
  if($physical.Count-eq 1-and$perfKeys.Count-gt 1){
    $perfKeys=@($perfKeys|Sort-Object{[double]$engineGroups[$_]}-Descending|Select-Object-First 1)
  }
  for($i=0;$i-lt$physical.Count;$i++){
    $v=$physical[$i];$key=if($i-lt$perfKeys.Count){$perfKeys[$i]}else{$null}
    $reading=[ordered]@{id="$($v.PNPDeviceID)";name="$($v.Name)";measurement_source='Windows GPU Performance Counters'}
    if($null-ne$key-and$engineGroups.ContainsKey($key)){$reading.usage=[double]$engineGroups[$key]}
    if($null-ne$key-and$memoryGroups.ContainsKey($key)){$reading.dedicated_memory_bytes=[uint64]$memoryGroups[$key].dedicated;$reading.shared_memory_bytes=[uint64]$memoryGroups[$key].shared}
    $gpus += $reading
  }
}
$storage=@()
try {
  foreach($d in @(Get-PhysicalDisk)){
    $used=0;$volumes=@()
    try { foreach($part in @($d | Get-Disk | Get-Partition)){foreach($vol in @($part | Get-Volume)){if($vol.Size){$volUsed=[uint64]($vol.Size-$vol.SizeRemaining);$used += $volUsed;$volumes += [ordered]@{id="$($vol.UniqueId)";label=if($vol.DriveLetter){"$($vol.DriveLetter):"}else{"$($vol.FileSystemLabel)"};file_system="$($vol.FileSystem)";total_bytes=[uint64]$vol.Size;used_bytes=$volUsed;available_bytes=[uint64]$vol.SizeRemaining;used_pct=[math]::Round(($volUsed/[double]$vol.Size)*100,2)}}}} } catch {}
    $life=$null;$temp=$null
    try {$r=$d|Get-StorageReliabilityCounter;if($null-ne $r.Wear){$life=[math]::Max(0,100-[double]$r.Wear)};if($null-ne $r.Temperature-and[double]$r.Temperature-gt 0){$temp=[double]$r.Temperature}}catch{}
    $total=[uint64]$d.Size;$pct=if($total){[math]::Round(($used/$total)*100,2)}else{0}
    $storage += [ordered]@{id="$($d.UniqueId)";model="$($d.FriendlyName)";media_type="$($d.MediaType)";bus_type="$($d.BusType)";total_bytes=$total;used_bytes=[uint64]$used;used_pct=$pct;smart_status="$($d.HealthStatus)";life_pct=$life;temperature=$temp;volumes=$volumes}
  }
} catch {}
$nets=@(Get-NetAdapter -Physical | ForEach-Object {
  $s=$_|Get-NetAdapterStatistics
  [ordered]@{id="$($_.InterfaceGuid)";name="$($_.Name)";description="$($_.InterfaceDescription)";status="$($_.Status)";link_speed_bps=[uint64]$_.TransmitLinkSpeed;rx_bytes_total=[uint64]$s.ReceivedBytes;tx_bytes_total=[uint64]$s.SentBytes}
})
$diskActivity=$null
try {
  # ATIVIDADE do disco, nao ocupacao. Sao coisas diferentes, e so esta explica
  # lentidao: um disco 97% cheio pode estar rapido, e um disco vazio pode estar
  # levando 40 ms por leitura.
  #
  # Duas decisoes que custaram tentativa errada antes de acertar:
  #
  # 1. CIM, nunca Get-Counter. Nome de contador no Get-Counter e LOCALIZADO —
  #    "\PhysicalDisk(_Total)\% Idle Time" nao existe em Windows portugues, e
  #    falharia calado justamente nas maquinas do parque. A classe CIM tem
  #    nome neutro de idioma, e e o padrao que o resto deste script ja segue.
  #
  # 2. Latencia pelo contador CRU, por DIFERENCA entre duas amostras. O valor
  #    "formatado" de AvgDisksecPerTransfer e inteiro em SEGUNDOS: latencia de
  #    disco e sub-segundo, entao ele trunca para 0 sempre e seria uma medida
  #    que so parece medida. E o acumulado desde o boot esconderia um disco que
  #    ficou lento na semana passada.
  $a=Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" | Select-Object -First 1
  Start-Sleep -Milliseconds 1000
  $b=Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" | Select-Object -First 1
  $fmt=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" | Select-Object -First 1
  if($null -ne $fmt){
    $ops=[double]$b.AvgDisksecPerTransfer_Base-[double]$a.AvgDisksecPerTransfer_Base
    $tempo=[double]$b.AvgDisksecPerTransfer-[double]$a.AvgDisksecPerTransfer
    $freq=[double]$b.Frequency_PerfTime
    # Disco ocioso na janela: latencia fica AUSENTE, nunca zero. Zero diria
    # "respondeu instantaneamente", e ninguem mediu nada.
    $lat=$null
    if($ops -gt 0 -and $freq -gt 0){ $lat=[math]::Round(($tempo/$ops)/$freq*1000,3) }
    $diskActivity=[ordered]@{
      busy_pct=[math]::Round([math]::Max(0,[math]::Min(100,100-[double]$fmt.PercentIdleTime)),2)
      latency_ms=$lat
      queue_length=[double]$fmt.CurrentDiskQueueLength
      samples=[int]$ops
    }
  }
} catch {}
$topProcs=@()
try {
  # Os processos que mais consomem (S7.1). Contador CIM, nao Get-Counter: nome
  # de contador e localizado, e falharia calado em Windows portugues.
  #
  # PRIVACIDADE (S7.2): sobe SO o nome do executavel. Nada de linha de comando,
  # caminho ou titulo de janela — esses revelam que documento a pessoa abriu, e
  # so podem subir em rajada de incidente com consentimento registrado.
  $nucleos=[double]((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors)
  if(-not $nucleos -or $nucleos -lt 1){ $nucleos=1 }
  $procs=Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop |
    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' }
  # Top por CPU e por memoria, unidos: um processo pode dominar so um dos dois,
  # e olhar apenas CPU perderia o vazamento de memoria.
  $sel=@($procs | Sort-Object PercentProcessorTime -Descending | Select-Object -First 5) +
       @($procs | Sort-Object WorkingSetPrivate -Descending | Select-Object -First 5)
  $vistos=@{}
  foreach($x in $sel){
    # O contador acrescenta sufixo de instancia: "chrome#3" e o mesmo programa
    # que "chrome". Sem tirar, o mesmo processo aparece varias vezes e o topo
    # fica cheio de duplicata em vez de mostrar quem mais consome.
    $nome=($x.Name -split '#')[0]
    if($vistos.ContainsKey($nome)){ continue }
    $vistos[$nome]=$true
    $topProcs += [ordered]@{
      nome=$nome
      cpu_pct=[math]::Round([double]$x.PercentProcessorTime/$nucleos,2)
      memoria_mb=[math]::Round([double]$x.WorkingSetPrivate/1MB,1)
      io_bytes_por_seg=[double]$x.IODataBytesPersec
    }
    if($topProcs.Count -ge 8){ break }
  }
} catch {}
[ordered]@{
 cpu=[ordered]@{name="$($cpu.Name)".Trim();usage=$cpuUsage;temperature=$null;clock_mhz=$cpuClock;base_clock_mhz=$cpuBase;performance_percent=$cpuPerformance;dpc_time_percent=$cpuDpc;interrupt_time_percent=$cpuInterrupt;queue_length=$cpuQueue;measurement_source='Windows Processor Performance Counters'}
 gpus=$gpus
 memory=$dimms
 memory_summary=[ordered]@{total_bytes=$memoryTotal;used_bytes=$memoryUsed;available_bytes=$memoryAvailable;usage=[math]::Round($memoryLoad*100,2);commit_used_bytes=$commitUsed;commit_limit_bytes=$commitLimit}
 storage=$storage;networks=$nets;disk_activity=$diskActivity;top_processos=$topProcs
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
