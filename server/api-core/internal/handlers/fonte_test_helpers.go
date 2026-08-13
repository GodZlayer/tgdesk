package handlers

import (
	"os"
	"strings"
	"testing"
)

// Alguns invariantes deste pacote são sobre ONDE uma coisa é chamada, ou sobre
// o filtro de uma consulta — não sobre o valor que uma função devolve. Testar
// isso pelo comportamento exigiria um banco e ainda assim não pegaria a
// regressão que importa, que é alguém afrouxar um filtro para "ter mais dado".
func lerFonte(t *testing.T, arquivo string) string {
	t.Helper()
	b, err := os.ReadFile(arquivo)
	if err != nil {
		t.Fatalf("não foi possível ler %s: %v", arquivo, err)
	}
	return string(b)
}

func contemTodos(fonte string, trechos []string) bool {
	for _, s := range trechos {
		if !strings.Contains(fonte, s) {
			return false
		}
	}
	return true
}
