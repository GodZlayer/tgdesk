//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

// espacoDoVolume lê o espaço livre e total do volume que contém o caminho.
//
// Syscall direta, não CIM: isto roda no caminho do exame, e o exame já é caro o
// bastante sem uma consulta WMI de segundos só para decidir se pode escrever.
func espacoDoVolume(caminho string) (livre, total uint64, err error) {
	ptr, err := syscall.UTF16PtrFromString(caminho)
	if err != nil {
		return 0, 0, err
	}
	var livreParaUsuario, totalBytes, totalLivre uint64
	r, _, chamadaErr := kernel32Rapido.NewProc("GetDiskFreeSpaceExW").Call(
		uintptr(unsafe.Pointer(ptr)),
		uintptr(unsafe.Pointer(&livreParaUsuario)),
		uintptr(unsafe.Pointer(&totalBytes)),
		uintptr(unsafe.Pointer(&totalLivre)),
	)
	if r == 0 {
		return 0, 0, chamadaErr
	}
	return totalLivre, totalBytes, nil
}
