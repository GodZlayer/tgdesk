//go:build !windows

package main

import "time"

// Fora do Windows o acesso remoto não é oferecido, e o vigia devolve "sim"
// para não marcar como quebrado algo que nem existe naquele sistema.
const (
	falhasAteReparar      = 3
	janelaDeInstabilidade = 5 * time.Minute
)

func ConexaoEstabelecidaCom(string, uint16) (bool, error) { return true, nil }

func ConexaoComPortaLocal(string, uint16) (bool, uint16, error) { return true, 0, nil }
