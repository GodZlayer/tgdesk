package handlers

import "testing"

// A fórmula do preço dinâmico com números na mão.
//
// Cada caso é uma situação de mercado descrita em português, e o número
// esperado foi conferido à parte. Se alguém mexer nos pesos ou nas constantes,
// é aqui que fica visível o que mudou para quem paga.
func TestAjusteDeDemanda(t *testing.T) {
	casos := []struct {
		nome                          string
		esperando, tecnicos, clientes int64
		querido                       int64
	}{
		{
			// 1 chamado por técnico e 40 clientes por técnico: as duas
			// pressões valem 1, nenhuma se afasta do equilíbrio.
			nome:      "equilíbrio dá preço cheio",
			esperando: 5, tecnicos: 5, clientes: 200, querido: 100,
		},
		{
			// imediata = 3, estrutural = 1 -> 100*(1+0,6*2+0,4*0) = 220
			nome:      "fila triplicada encarece",
			esperando: 15, tecnicos: 5, clientes: 200, querido: 220,
		},
		{
			// imediata = 0,2, estrutural = 1 -> 100*(1+0,6*(-0,8)) = 52 -> piso
			nome:      "região parada cai até o piso, não abaixo",
			esperando: 1, tecnicos: 5, clientes: 200, querido: 70,
		},
		{
			// imediata = 1, estrutural = 2 -> 100*(1+0+0,4*1) = 140
			nome:      "lugar cronicamente mal atendido é caro mesmo em dia calmo",
			esperando: 5, tecnicos: 5, clientes: 400, querido: 140,
		},
		{
			nome:      "sem técnico e sem fila não há mercado a precificar",
			esperando: 0, tecnicos: 0, clientes: 100, querido: 100,
		},
		{
			nome:      "sem técnico e com fila é escassez completa: teto",
			esperando: 3, tecnicos: 0, clientes: 100, querido: 250,
		},
		{
			// imediata = 20, estrutural = 5 -> muito acima do teto
			nome:      "pico extremo não passa do teto",
			esperando: 20, tecnicos: 1, clientes: 200, querido: 250,
		},
	}

	for _, c := range casos {
		t.Run(c.nome, func(t *testing.T) {
			got := ajusteDeDemanda(c.esperando, c.tecnicos, c.clientes)
			if got != c.querido {
				t.Errorf("esperando=%d tecnicos=%d clientes=%d: deu %d, queria %d",
					c.esperando, c.tecnicos, c.clientes, got, c.querido)
			}
		})
	}
}

// O multiplicador nunca sai dos limites, para nenhuma combinação plausível.
// É a garantia que importa: o resto da conta pode ser discutido, mas preço
// fora da faixa é defeito.
func TestAjusteDeDemandaSempreDentroDosLimites(t *testing.T) {
	for esperando := int64(0); esperando <= 100; esperando += 7 {
		for tecnicos := int64(0); tecnicos <= 50; tecnicos += 3 {
			for clientes := int64(0); clientes <= 5000; clientes += 250 {
				got := ajusteDeDemanda(esperando, tecnicos, clientes)
				if got < int64(multiplicadorPiso) || got > int64(multiplicadorTeto) {
					t.Fatalf("esperando=%d tecnicos=%d clientes=%d: %d fora de [%v,%v]",
						esperando, tecnicos, clientes, got,
						multiplicadorPiso, multiplicadorTeto)
				}
			}
		}
	}
}
