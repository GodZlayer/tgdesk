//go:build !windows

package main

import "time"

// Fora do Windows o agente não tem os contadores baratos equivalentes, e o
// buffer segue guardando só a linha do tempo — que já é o que detecta o salto
// de relógio. Devolver zeros aqui é correto: o campo é `omitempty`, então ele
// simplesmente não sobe.
func amostrarRapido() amostraDeContexto {
	return amostraDeContexto{T: time.Now().UnixMilli()}
}
