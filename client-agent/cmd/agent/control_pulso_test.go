package main

import (
	"os"
	"regexp"
	"testing"
)

// O pulso de 2 Hz é o relógio externo que mede travamento (§6). Se qualquer
// coisa demorada rodar no mesmo `select`, o pulso para junto — e o servidor
// registra como TRAVA o tempo que o agente passou trabalhando.
//
// Foi exatamente o que aconteceu: `collectHardwareSnapshot` (PowerShell + CIM,
// 9 a 13 s) rodava dentro do laço, e as três máquinas do parque produziram
// ~250 travas falsas por hora, cada uma. O detector estava medindo a própria
// coleta de telemetria.
//
// Nenhum teste unitário pegava isso, porque cada peça funcionava sozinha. O que
// estava errado era ONDE a peça era chamada — então o teste precisa olhar para
// a estrutura, não para o comportamento de uma função.
func TestColetaPesadaNaoBloqueiaOPulso(t *testing.T) {
	fonte, err := os.ReadFile("control.go")
	if err != nil {
		t.Fatalf("não foi possível ler control.go: %v", err)
	}

	// Chamada síncrona de coleta dentro de um `case` do select é o defeito.
	// Procuramos a atribuição direta, que é a forma que ele tinha.
	direto := regexp.MustCompile(`(?m)^\s+hardware = collectHardwareSnapshot\(\)`)
	if direto.Match(fonte) {
		t.Error("collectHardwareSnapshot é chamada direto no laço de controle: " +
			"ela leva ~10s e para o pulso de 2Hz, fazendo o servidor registrar " +
			"trava falsa a cada ciclo de telemetria")
	}

	// E a forma correta precisa estar lá: coleta em goroutine, resultado
	// chegando por canal.
	if !regexp.MustCompile(`go func\(\) \{\s*h := collectHardwareSnapshot\(\)`).Match(fonte) {
		t.Error("a coleta de hardware precisa rodar fora do laço, em goroutine")
	}
	if !regexp.MustCompile(`case h := <-telemetriaPronta:`).Match(fonte) {
		t.Error("o resultado da coleta precisa voltar por canal, sem bloquear o select")
	}
}
