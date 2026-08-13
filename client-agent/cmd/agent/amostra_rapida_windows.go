//go:build windows

package main

import (
	"syscall"
	"time"
	"unsafe"
)

// Coleta barata o bastante para rodar a 10 Hz (§6, §7.1).
//
// O ring buffer de trava amostra dez vezes por segundo, sem parar, a vida
// inteira do agente. Isso exclui de saída tudo que o resto da telemetria usa:
// PowerShell custa a partida de um processo, e CIM custa segundos — foi
// exatamente esse custo que fez o laço de controle travar e o servidor
// registrar 250 travas falsas por hora em cada máquina.
//
// Aqui só entram chamadas diretas ao kernel, que custam microssegundos:
//
//	GetSystemTimes         tempo ocioso/kernel/usuário acumulado
//	GlobalMemoryStatusEx   carga de memória, já em porcentagem
//
// Não há leitura de disco: não existe contador de disco barato o suficiente
// para 10 Hz sem abrir handle de performance, e um campo ausente é honesto —
// enquanto um campo caro tornaria o buffer a causa do problema que ele mede.

var (
	kernel32Rapido         = syscall.NewLazyDLL("kernel32.dll")
	procGetSystemTimes     = kernel32Rapido.NewProc("GetSystemTimes")
	procGlobalMemoryStatus = kernel32Rapido.NewProc("GlobalMemoryStatusEx")
	procGetDiskFreeSpaceEx = kernel32Rapido.NewProc("GetDiskFreeSpaceExW")
	procGetTickCount64     = kernel32Rapido.NewProc("GetTickCount64")
	psapiRapido            = syscall.NewLazyDLL("psapi.dll")
	procGetPerformanceInfo = psapiRapido.NewProc("GetPerformanceInfo")
)

type filetimeRapido struct {
	low, high uint32
}

func (f filetimeRapido) uint64() uint64 {
	return uint64(f.high)<<32 | uint64(f.low)
}

type memoryStatusEx struct {
	length               uint32
	memoryLoad           uint32
	totalPhys            uint64
	availPhys            uint64
	totalPageFile        uint64
	availPageFile        uint64
	totalVirtual         uint64
	availVirtual         uint64
	availExtendedVirtual uint64
}

// estadoCPU guarda a leitura anterior. O contador do Windows é ACUMULADO desde
// o boot: a porcentagem só existe como diferença entre duas leituras, e usar o
// acumulado direto daria a média da vida da máquina em vez do instante.
type estadoCPU struct {
	ocioso, kernel, usuario uint64
	valido                  bool
}

var ultimaCPU estadoCPU

// amostrarRapido devolve uma amostra do instante, para o ring buffer.
//
// Campo que não pôde ser lido fica em zero e o chamador não o envia — a
// estrutura usa `omitempty`. Ausência é informação; inventar valor num buffer
// que existe para explicar congelamento seria inventar a explicação.
func amostrarRapido() amostraDeContexto {
	a := amostraDeContexto{T: time.Now().UnixMilli()}

	var ocioso, kernel, usuario filetimeRapido
	r, _, _ := procGetSystemTimes.Call(
		uintptr(unsafe.Pointer(&ocioso)),
		uintptr(unsafe.Pointer(&kernel)),
		uintptr(unsafe.Pointer(&usuario)),
	)
	if r != 0 {
		o, k, u := ocioso.uint64(), kernel.uint64(), usuario.uint64()
		if ultimaCPU.valido {
			// `kernel` já INCLUI `ocioso` na contagem do Windows — somar os três
			// contaria o tempo parado duas vezes e daria uso sempre baixo.
			dOcioso := o - ultimaCPU.ocioso
			dTotal := (k - ultimaCPU.kernel) + (u - ultimaCPU.usuario)
			if dTotal > 0 && dTotal >= dOcioso {
				a.CPU = float64(dTotal-dOcioso) / float64(dTotal) * 100
			}
		}
		ultimaCPU = estadoCPU{ocioso: o, kernel: k, usuario: u, valido: true}
	}

	var mem memoryStatusEx
	mem.length = uint32(unsafe.Sizeof(mem))
	if r, _, _ := procGlobalMemoryStatus.Call(uintptr(unsafe.Pointer(&mem))); r != 0 {
		a.RAM = float64(mem.memoryLoad)
	}

	return a
}

// AmostraBarata é o retrato contínuo da máquina, feito só com syscall.
//
// É o coração do requisito de custo: a coleta que roda o tempo todo NÃO pode
// usar PowerShell nem CIM. Medido nesta máquina, o script de hardware leva de
// 9 a 13 s e chegou a travar o laço de controle; isto aqui leva microssegundos
// e pode rodar a cada segundo sem aparecer no gerenciador de tarefas.
//
// O que ela NÃO traz — modelo de disco, SMART, temperatura, inventário — segue
// vindo da coleta cara, com intervalo largo. A divisão é essa: o que muda a
// toda hora é barato; o que quase não muda pode custar caro de vez em quando.
type AmostraBarata struct {
	Em            time.Time          `json:"em"`
	CPUPct        float64            `json:"cpu_pct"`
	MemPct        float64            `json:"mem_pct"`
	MemDispMB     uint64             `json:"mem_disponivel_mb"`
	CommitPct     float64            `json:"commit_pct"`
	Processos     uint32             `json:"processos"`
	Threads       uint32             `json:"threads"`
	Handles       uint32             `json:"handles"`
	UptimeS       uint64             `json:"uptime_s"`
	DiscoLivrePct map[string]float64 `json:"disco_livre_pct,omitempty"`
}

type performanceInformation struct {
	cb                uint32
	commitTotal       uintptr
	commitLimit       uintptr
	commitPeak        uintptr
	physicalTotal     uintptr
	physicalAvailable uintptr
	systemCache       uintptr
	kernelTotal       uintptr
	kernelPaged       uintptr
	kernelNonpaged    uintptr
	pageSize          uintptr
	handleCount       uint32
	processCount      uint32
	threadCount       uint32
}

// ColetarBarato monta o retrato contínuo.
//
// Cada campo aqui existe porque alguma causa da taxonomia o consome:
// commit e memória disponível separam "memória insuficiente" de "memória
// ocupada"; handles e threads detectam vazamento, que hoje é lacuna declarada;
// espaço livre separa "disco cheio" de "disco lento"; uptime distingue
// desligamento inesperado de reinício planejado.
func ColetarBarato() AmostraBarata {
	a := AmostraBarata{Em: time.Now().UTC()}

	base := amostrarRapido()
	a.CPUPct = base.CPU
	a.MemPct = base.RAM

	var pi performanceInformation
	pi.cb = uint32(unsafe.Sizeof(pi))
	if r, _, _ := procGetPerformanceInfo.Call(uintptr(unsafe.Pointer(&pi)), uintptr(pi.cb)); r != 0 {
		a.Processos, a.Threads, a.Handles = pi.processCount, pi.threadCount, pi.handleCount
		if pi.pageSize > 0 {
			a.MemDispMB = uint64(pi.physicalAvailable) * uint64(pi.pageSize) / (1024 * 1024)
			if pi.commitLimit > 0 {
				a.CommitPct = float64(pi.commitTotal) / float64(pi.commitLimit) * 100
			}
		}
	}

	if r, _, _ := procGetTickCount64.Call(); r != 0 {
		a.UptimeS = uint64(r) / 1000
	}

	// Espaço livre por volume fixo. `GetLogicalDrives` devolve um bitmask das
	// letras existentes — enumerar assim custa nada perto de consultar CIM.
	if letras, _, _ := kernel32Rapido.NewProc("GetLogicalDrives").Call(); letras != 0 {
		a.DiscoLivrePct = map[string]float64{}
		for i := 0; i < 26; i++ {
			if letras&(1<<uint(i)) == 0 {
				continue
			}
			raiz := string(rune('A'+i)) + `:\`
			ptr, err := syscall.UTF16PtrFromString(raiz)
			if err != nil {
				continue
			}
			var livre, total, totalLivre uint64
			r, _, _ := procGetDiskFreeSpaceEx.Call(
				uintptr(unsafe.Pointer(ptr)),
				uintptr(unsafe.Pointer(&livre)),
				uintptr(unsafe.Pointer(&total)),
				uintptr(unsafe.Pointer(&totalLivre)),
			)
			if r != 0 && total > 0 {
				a.DiscoLivrePct[string(rune('A'+i))] = float64(totalLivre) / float64(total) * 100
			}
		}
	}
	return a
}
