//go:build !windows

package main

import (
	"context"
	"fmt"
)

// Os exames combinados dependem de contadores que só existem no Windows —
// memória disponível em tempo real e leitura de dispositivo físico. Fora dele
// o agente declara a ausência em vez de devolver número inventado.

func bandaDeMemoria(context.Context, func(int, string)) (map[string]any, error) {
	return nil, fmt.Errorf("banda de memória disponível somente no Windows")
}

func nucleosDoProcessador(context.Context, func(int, string)) (map[string]any, error) {
	return nil, fmt.Errorf("medição por núcleo disponível somente no Windows")
}

func pressaoDePaginacao(context.Context, func(int, string)) (map[string]any, error) {
	return nil, fmt.Errorf("pressão de paginação disponível somente no Windows")
}

func disputaCPUMemoria(context.Context, func(int, string)) (map[string]any, error) {
	return nil, fmt.Errorf("disputa CPU/memória disponível somente no Windows")
}
