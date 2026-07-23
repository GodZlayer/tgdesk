package main

import (
	"fmt"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Módulo D (Seção 8.D) sem driver de kernel: usa só as APIs padrão do
// Windows (GlobalMemoryStatusEx, GetDiskFreeSpaceEx, GetSystemTimes) — dá
// CPU/memória/disco reais sem precisar de System Informer/KSystemInformer.sys.
// Temperatura fica de fora por enquanto (isso sim exigiria WMI/ACPI ou
// driver, ver ARCHITECTURE_FLOW.md).

var (
	modkernel32            = syscall.NewLazyDLL("kernel32.dll")
	procGetSystemTimes     = modkernel32.NewProc("GetSystemTimes")
	procGetDiskFreeSpaceEx = modkernel32.NewProc("GetDiskFreeSpaceExW")
)

type memoryStatusEx struct {
	Length               uint32
	MemoryLoad           uint32
	TotalPhys            uint64
	AvailPhys            uint64
	TotalPageFile        uint64
	AvailPageFile        uint64
	TotalVirtual         uint64
	AvailVirtual         uint64
	AvailExtendedVirtual uint64
}

func memoryPercent() float64 {
	var m memoryStatusEx
	m.Length = uint32(unsafe.Sizeof(m))
	ret, _, _ := modkernel32.NewProc("GlobalMemoryStatusEx").Call(uintptr(unsafe.Pointer(&m)))
	if ret == 0 {
		return 0
	}
	return float64(m.MemoryLoad)
}

func diskPercent(path string) float64 {
	p, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return 0
	}
	var freeAvail, total, totalFree uint64
	ret, _, _ := procGetDiskFreeSpaceEx.Call(
		uintptr(unsafe.Pointer(p)),
		uintptr(unsafe.Pointer(&freeAvail)),
		uintptr(unsafe.Pointer(&total)),
		uintptr(unsafe.Pointer(&totalFree)),
	)
	if ret == 0 || total == 0 {
		return 0
	}
	used := total - totalFree
	return float64(used) / float64(total) * 100
}

func fileTimeToUint64(ft windows.Filetime) uint64 {
	return uint64(ft.HighDateTime)<<32 | uint64(ft.LowDateTime)
}

// cpuPercent amostra duas leituras de GetSystemTimes com um pequeno
// intervalo e calcula o percentual ocupado (não-ocioso) da CPU no período.
func cpuPercent() float64 {
	sample := func() (idle, kernel, user uint64, ok bool) {
		var idleFT, kernelFT, userFT windows.Filetime
		ret, _, _ := procGetSystemTimes.Call(
			uintptr(unsafe.Pointer(&idleFT)),
			uintptr(unsafe.Pointer(&kernelFT)),
			uintptr(unsafe.Pointer(&userFT)),
		)
		if ret == 0 {
			return 0, 0, 0, false
		}
		return fileTimeToUint64(idleFT), fileTimeToUint64(kernelFT), fileTimeToUint64(userFT), true
	}

	idle1, kernel1, user1, ok1 := sample()
	time.Sleep(300 * time.Millisecond)
	idle2, kernel2, user2, ok2 := sample()
	if !ok1 || !ok2 {
		return 0
	}

	idleDelta := idle2 - idle1
	totalDelta := (kernel2 - kernel1) + (user2 - user1) // kernel time já inclui idle no Windows
	if totalDelta == 0 {
		return 0
	}
	busy := totalDelta - idleDelta
	pct := float64(busy) / float64(totalDelta) * 100
	if pct < 0 {
		return 0
	}
	if pct > 100 {
		return 100
	}
	return pct
}

func collectTelemetry() (cpu, mem, disco float64) {
	return cpuPercent(), memoryPercent(), diskPercent(`C:\`)
}

func reportTelemetry(cfg *agentConfig, cpu, mem, disco, temp float64) error {
	status, err := postJSON("/api/v1/devices/telemetry", map[string]any{
		"device_id":    cfg.DeviceID,
		"device_token": cfg.DeviceToken,
		"cpu":          cpu,
		"mem":          mem,
		"disco":        disco,
		"temp":         temp,
	}, nil)
	if err != nil {
		return err
	}
	if status != 200 {
		return fmt.Errorf("telemetry status %d", status)
	}
	return nil
}
