package main

import (
	"runtime"
	"testing"
	"time"
)

// O requisito é CUSTO. A coleta contínua roda a vida toda na máquina do
// cliente, e o produto não pode ser o motivo de a máquina ficar lenta — seria
// a contradição mais cara possível num produto de diagnóstico.
//
// O número de referência é a coleta cara: medida nesta máquina, o script
// PowerShell de hardware leva de 9 a 13 segundos. Este teste exige três ordens
// de grandeza a menos.
func TestColetaContinuaEBarata(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("a coleta barata é implementada por syscall do Windows")
	}
	ColetarBarato() // descarta a primeira: a CPU precisa de duas leituras

	inicio := time.Now()
	const n = 20
	for i := 0; i < n; i++ {
		ColetarBarato()
	}
	media := time.Since(inicio) / n

	t.Logf("coleta barata: %v por amostra", media)
	if media > 50*time.Millisecond {
		t.Fatalf("coleta contínua custando %v por amostra: cara demais para rodar sempre", media)
	}
}

// Cada campo existe porque uma causa da taxonomia o consome. Campo que ninguém
// consome é custo puro (§13.6) — e campo que uma causa precisa e não existe é
// uma lacuna que o produto não sabe que tem.
func TestAmostraTrazOQueAsCausasConsomem(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("syscall do Windows")
	}
	ColetarBarato()
	a := ColetarBarato()

	if a.Processos == 0 || a.Threads == 0 {
		t.Error("sem contagem de processos/threads: vazamento fica indetectável")
	}
	if a.Handles == 0 {
		t.Error("sem handles: vazamento de handle fica indetectável")
	}
	if a.UptimeS == 0 {
		t.Error("sem uptime: não dá para separar desligamento inesperado de reinício planejado")
	}
	if len(a.DiscoLivrePct) == 0 {
		t.Error("sem espaço livre: 'disco cheio' e 'disco lento' ficam indistinguíveis")
	}
	if a.MemDispMB == 0 {
		t.Error("sem memória disponível: 'insuficiente' e 'ocupada' ficam indistinguíveis")
	}
}
