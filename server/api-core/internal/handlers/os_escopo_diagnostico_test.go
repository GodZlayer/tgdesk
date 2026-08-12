package handlers

import "testing"

// Testes da derivação de escopo (§11).
//
// O que estes testes protegem é a diferença entre um técnico que resolve na
// primeira visita e um que volta. Cada caso aqui é uma viagem perdida evitada
// — ou uma mala cheia de item que ninguém usou.

func acharItem(itens []ItemDeEscopo, codigo string) (ItemDeEscopo, bool) {
	for _, i := range itens {
		if i.ToolCodigo == codigo {
			return i, true
		}
	}
	return ItemDeEscopo{}, false
}

func TestItemBaratoVaiPorHipoteseSecundaria(t *testing.T) {
	// 25% de chance, item leve e barato: levar custa quase nada, e voltar custa
	// uma visita inteira.
	itens := DerivarEscopo(
		[]CausaProvavel{{"disco_degradado", 0.60}, {"memoria_instavel", 0.25}},
		[]Requisito{
			{CausaCodigo: "memoria_instavel", ToolCodigo: "pente_ram_teste",
				Nivel: NivelNecessaria, Quantidade: 1, Portatil: true, CustoRelativo: 1},
		},
		nil,
	)
	item, ok := acharItem(itens, "pente_ram_teste")
	if !ok {
		t.Fatal("item da hipótese 2 sumiu do escopo")
	}
	if item.SobDemanda {
		t.Fatal("item barato de hipótese plausível virou sob demanda: é o tipo de economia que custa uma segunda visita")
	}
}

func TestItemCaroEVolumosoViraSobDemanda(t *testing.T) {
	itens := DerivarEscopo(
		[]CausaProvavel{{"disco_degradado", 0.20}},
		[]Requisito{
			{CausaCodigo: "disco_degradado", ToolCodigo: "disco_2tb",
				Nivel: NivelNecessaria, Quantidade: 1, Portatil: false, CustoRelativo: 5},
		},
		nil,
	)
	item, _ := acharItem(itens, "disco_2tb")
	if !item.SobDemanda {
		t.Fatal("disco de 2 TB entrou na mala por 20% de chance")
	}
}

func TestNivelSobePelaUniaoDasHipoteses(t *testing.T) {
	// O caso de §11.2: facilitador para a causa 1, essencial para a causa 2.
	// Vence o mais forte — senão a OS seria liberada sem o que a destrava.
	itens := DerivarEscopo(
		[]CausaProvavel{{"causa_a", 0.55}, {"causa_b", 0.30}},
		[]Requisito{
			{CausaCodigo: "causa_a", ToolCodigo: "adaptador_sata",
				Nivel: NivelFacilitadora, Quantidade: 1, Portatil: true, CustoRelativo: 1},
			{CausaCodigo: "causa_b", ToolCodigo: "adaptador_sata",
				Nivel: NivelEssencial, Quantidade: 2, Portatil: true, CustoRelativo: 1},
		},
		nil,
	)
	item, _ := acharItem(itens, "adaptador_sata")
	if item.Nivel != NivelEssencial {
		t.Fatalf("nível ficou %q; a união sobre as hipóteses tem que subir para essencial", item.Nivel)
	}
	if item.Quantidade != 2 {
		t.Fatalf("quantidade %d; vence a maior exigida entre as hipóteses", item.Quantidade)
	}
	if len(item.PorCausa) != 2 {
		t.Fatal("item perdeu a justificativa de por que está na lista")
	}
}

func TestEssencialVaiMesmoComProbabilidadeBaixa(t *testing.T) {
	// Sem ele a OS não começa. A conta de custo não se aplica.
	itens := DerivarEscopo(
		[]CausaProvavel{{"causa_x", 0.10}},
		[]Requisito{
			{CausaCodigo: "causa_x", ToolCodigo: "estacao_solda",
				Nivel: NivelEssencial, Quantidade: 1, Portatil: false, CustoRelativo: 5},
		},
		nil,
	)
	item, _ := acharItem(itens, "estacao_solda")
	if item.SobDemanda {
		t.Fatal("item essencial virou sob demanda; sem ele a OS não pode nem começar")
	}
}

func TestChaveDeRecuperacaoSoEntraComVolumeCriptografado(t *testing.T) {
	// É exatamente o que se descobre tarde demais, com a máquina já aberta
	// (§11.3). Com a condição ativa, tem que aparecer ANTES.
	req := []Requisito{{
		CausaCodigo: "disco_degradado", ToolCodigo: "chave_recuperacao",
		Nivel: NivelEssencial, Quantidade: 1, Condicao: "so_se_volume_criptografado",
		Portatil: true, CustoRelativo: 1,
	}}
	causas := []CausaProvavel{{"disco_degradado", 0.70}}

	semCripto := DerivarEscopo(causas, req, map[string]bool{})
	if _, ok := acharItem(semCripto, "chave_recuperacao"); ok {
		t.Fatal("pediu chave de recuperação para volume não criptografado")
	}

	comCripto := DerivarEscopo(causas, req, map[string]bool{"so_se_volume_criptografado": true})
	item, ok := acharItem(comCripto, "chave_recuperacao")
	if !ok || item.Nivel != NivelEssencial {
		t.Fatal("volume criptografado sem exigir a chave: a máquina seria aberta e o dado ficaria inacessível")
	}
}

func TestCausaForaDoTop3NaoGeraEscopo(t *testing.T) {
	itens := DerivarEscopo(
		[]CausaProvavel{{"causa_a", 0.80}},
		[]Requisito{
			{CausaCodigo: "causa_descartada", ToolCodigo: "ferramenta_inutil",
				Nivel: NivelEssencial, Quantidade: 1, Portatil: true, CustoRelativo: 1},
		},
		nil,
	)
	if _, ok := acharItem(itens, "ferramenta_inutil"); ok {
		t.Fatal("hipótese descartada gerou item; isso é encher a mala de medo, não de método")
	}
}

func TestItemComAprovacaoNaoEntraAutomatico(t *testing.T) {
	itens := DerivarEscopo(
		[]CausaProvavel{{"causa_a", 0.95}},
		[]Requisito{
			{CausaCodigo: "causa_a", ToolCodigo: "placa_mae_nova", Nivel: NivelEssencial,
				Quantidade: 1, Portatil: true, CustoRelativo: 4, RequerAprovacao: true},
		},
		nil,
	)
	item, _ := acharItem(itens, "placa_mae_nova")
	if !item.Pendente {
		t.Fatal("item que exige aprovação entrou sozinho, mesmo com 95%")
	}
	bloqueado, motivos := EscopoBloqueado(itens)
	if !bloqueado || len(motivos) != 1 {
		t.Fatal("essencial pendente não bloqueou a liberação da OS")
	}
}

func TestOrdemColocaEssencialPrimeiro(t *testing.T) {
	itens := DerivarEscopo(
		[]CausaProvavel{{"c", 0.9}},
		[]Requisito{
			{CausaCodigo: "c", ToolCodigo: "z_facil", Nivel: NivelFacilitadora, Portatil: true, CustoRelativo: 1},
			{CausaCodigo: "c", ToolCodigo: "a_essencial", Nivel: NivelEssencial, Portatil: true, CustoRelativo: 1},
		},
		nil,
	)
	if itens[0].ToolCodigo != "a_essencial" {
		t.Fatalf("primeiro item é %q; essencial tem que vir primeiro na tela", itens[0].ToolCodigo)
	}
}

func TestDispensaDaEscadaEhDeterministica(t *testing.T) {
	altaBaixoRisco := []CausaProvavel{{"causa_a", 0.88}}
	if ok, motivo := DispensaEscada(altaBaixoRisco, "baixo", 0.80); !ok || motivo == "" {
		t.Fatal("causa dominante com ação de baixo risco deveria dispensar a escada")
	}
	if ok, _ := DispensaEscada(altaBaixoRisco, "alto", 0.80); ok {
		t.Fatal("dispensou a escada para ação de risco alto")
	}
	if ok, _ := DispensaEscada([]CausaProvavel{{"causa_a", 0.79}}, "baixo", 0.80); ok {
		t.Fatal("dispensou abaixo do limiar")
	}
	if ok, _ := DispensaEscada(nil, "baixo", 0.80); ok {
		t.Fatal("dispensou a escada sem hipótese nenhuma")
	}
}
