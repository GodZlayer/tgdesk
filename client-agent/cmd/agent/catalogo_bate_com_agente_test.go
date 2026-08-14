package main

import (
	"os"
	"regexp"
	"sort"
	"testing"
)

// O catálogo do servidor e o que o agente sabe executar precisam ser a MESMA
// lista.
//
// Quando eles divergem, a falha é silenciosa e das piores: o técnico vê um
// exame na tela, seleciona, e recebe erro — ou pior, um exame útil existe no
// agente e ninguém consegue chamá-lo porque não está listado.
//
// Foi exatamente o que aconteceu. O catálogo oferecia `defender_quick_scan`,
// que o agente nunca implementou, enquanto `defender_status` — leitura pura,
// implementada, funcionando — estava fora da lista e portanto inalcançável.
// Ninguém percebeu porque nada comparava as duas pontas.
//
// Este teste existe para que a divergência apareça no gate e não em produção.
const (
	catalogoDoServidor = "../../../server/api-core/internal/handlers/diagnostics.go"
	implementacao      = "diagnostics.go"
)

func TestCatalogoDoServidorBateComOAgente(t *testing.T) {
	catalogo := idsDoCatalogo(t)
	implementados := idsImplementados(t)

	for _, id := range catalogo {
		if !implementados[id] {
			t.Errorf("o catálogo oferece %q, mas o agente não sabe executá-lo — "+
				"quem selecionar esse exame recebe falha", id)
		}
	}
}

// A recíproca é aviso, não erro: um exame implementado e fora do catálogo pode
// ser deliberado (uso interno), mas quase sempre é esquecimento — e foi assim
// que `defender_status` ficou inacessível.
func TestExameImplementadoForaDoCatalogoApareceNoLog(t *testing.T) {
	catalogo := map[string]bool{}
	for _, id := range idsDoCatalogo(t) {
		catalogo[id] = true
	}
	for id := range idsImplementados(t) {
		if !catalogo[id] {
			t.Logf("aviso: %q é implementado pelo agente mas não está no "+
				"catálogo do servidor — ninguém consegue chamá-lo", id)
		}
	}
}

func idsDoCatalogo(t *testing.T) []string {
	t.Helper()
	fonte, err := os.ReadFile(catalogoDoServidor)
	if err != nil {
		t.Skipf("catálogo do servidor indisponível deste diretório: %v", err)
	}
	achados := regexp.MustCompile(`\{"id": "([a-z_]+)"`).FindAllStringSubmatch(string(fonte), -1)
	if len(achados) == 0 {
		t.Fatal("nenhum id encontrado no catálogo: o formato mudou e este teste " +
			"passou a não verificar nada")
	}
	var ids []string
	for _, m := range achados {
		if m[1] == "all_tests" {
			// Não é um exame: é o pedido de rodar todos.
			continue
		}
		ids = append(ids, m[1])
	}
	sort.Strings(ids)
	return ids
}

func idsImplementados(t *testing.T) map[string]bool {
	t.Helper()
	fonte, err := os.ReadFile(implementacao)
	if err != nil {
		t.Fatalf("%s: %v", implementacao, err)
	}
	achados := regexp.MustCompile(`case "([a-z_]+)"`).FindAllStringSubmatch(string(fonte), -1)
	if len(achados) == 0 {
		t.Fatal("nenhum case encontrado no agente: o formato mudou e este teste " +
			"passou a não verificar nada")
	}
	ids := map[string]bool{}
	for _, m := range achados {
		ids[m[1]] = true
	}
	return ids
}
