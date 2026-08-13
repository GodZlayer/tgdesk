//go:build !windows

package main

// Fora do Windows o exame de disco não roda, então o gate devolve "não sei" —
// e o chamador trata desconhecido como "não bloqueia", porque bloquear por
// ignorância impediria o teste em plataforma onde ele nem chega a ser chamado.
func espacoDoVolume(string) (livre, total uint64, err error) { return 0, 0, nil }
