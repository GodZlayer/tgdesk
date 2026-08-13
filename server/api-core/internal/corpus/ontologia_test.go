package corpus

import "testing"

// O conjunto de causas é FECHADO, e "fechado" só significa alguma coisa se
// nada puder referenciar uma causa que não existe. Sem este teste, apagar uma
// causa deixa referências penduradas que só aparecem na tela do técnico, como
// um título cru no lugar da frase — silenciosamente errado, que é o pior modo
// de falha deste projeto.
func TestToda_CausaDeclarada_Existe(t *testing.T) {
	conhecidas := map[string]bool{}
	for _, c := range CausasConhecidas() {
		conhecidas[c] = true
	}
	for _, status := range StatusConhecidos() {
		for _, c := range CausasDoStatus(status) {
			if !conhecidas[c] {
				t.Errorf("status %q admite a causa %q, que não existe no conjunto fechado",
					status, c)
			}
		}
	}
	// Status sem causa candidata abstém sempre — é um jeito elegante de nunca
	// responder, e não deveria existir no catálogo.
	for _, status := range StatusConhecidos() {
		if len(CausasDoStatus(status)) == 0 {
			t.Errorf("status %q não tem causa candidata nenhuma", status)
		}
	}
}

// Toda causa precisa de conduta. É a regra que funda a taxonomia: duas coisas
// são causas diferentes quando geram condutas diferentes — então causa sem
// conduta declarada não deveria ser uma causa.
func TestToda_CausaTemAcao(t *testing.T) {
	for _, c := range CausasConhecidas() {
		if AcaoDaCausa(c) == "" {
			t.Errorf("causa %q não diz o que fazer", c)
		}
	}
}

// Duas causas com a MESMA conduta são a mesma causa, e mantê-las separadas só
// divide a massa de probabilidade entre sinônimos — o que faz as duas
// parecerem menos prováveis do que o problema realmente é.
func TestNenhumaDuplicidade_DeConduta(t *testing.T) {
	vistas := map[string]string{}
	for _, c := range CausasConhecidas() {
		a := AcaoDaCausa(c)
		if outra, existe := vistas[a]; existe {
			t.Errorf("causas %q e %q têm a mesma conduta (%q) — ou são a mesma causa, "+
				"ou a conduta de uma está descrita errado", outra, c, a)
		}
		vistas[a] = c
	}
}
