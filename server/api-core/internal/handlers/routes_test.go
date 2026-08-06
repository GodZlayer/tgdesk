package handlers

import "testing"

// O roteador do Go 1.22 entra em PÂNICO ao registrar padrões ambíguos — não
// devolve erro na requisição, derruba o servidor inteiro no start. Foi assim
// que a 1.1.51 subiu com as migrations aplicadas e a API em crashloop.
//
// Este teste registra todas as rotas de verdade. Se duas voltarem a colidir,
// ele falha aqui, e não em produção.
func TestRouterNaoTemPadroesAmbiguos(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("registro de rotas entrou em pânico: %v", r)
		}
	}()
	_ = NewRouter(&Server{})
}
