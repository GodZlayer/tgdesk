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
