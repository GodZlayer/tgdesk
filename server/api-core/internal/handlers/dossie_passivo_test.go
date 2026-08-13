package handlers

import "testing"

// O que estes testes protegem não é a extração em si: é a diferença entre
// "medida ausente" e "medida zero", que é onde um dossiê passivo vira mentira
// silenciosa.

func TestSmartSaudavelNaoViraEvidencia(t *testing.T) {
	// Disco saudável não é evidência de nada. Emitir sinal para ele encheria o
	// dossiê de ruído e faria o motor distribuir probabilidade sobre uma
	// máquina que não tem problema nenhum.
	ev := sinaisDoHardware([]byte(`{"storage":[{"model":"X","smart_status":"Healthy","life_pct":100,"temperature":40,"used_pct":50}]}`))
	if len(ev) != 0 {
		t.Fatalf("máquina saudável gerou %d evidências: %+v", len(ev), ev)
	}
}

func TestSmartDoenteViraEvidenciaLiteral(t *testing.T) {
	ev := sinaisDoHardware([]byte(`{"storage":[{"model":"KINGSTON SNV3S1000G","smart_status":"Warning"}]}`))
	if len(ev) != 1 || ev[0].Sinal != "smart_geral" {
		t.Fatalf("esperava sinal smart_geral, veio %+v", ev)
	}
	// §10.5.1: a evidência é literal e citável, nunca "indícios sugerem".
	if ev[0].Literal == "" {
		t.Fatal("evidência sem literal não pode aparecer na tela")
	}
}

func TestCampoAusenteNaoViraZero(t *testing.T) {
	// Este é o teste central de §19.3. Um disco sem `life_pct` não tem vida
	// útil ZERO — ele não informou. Tratar ausência como zero produziria
	// "vida útil restante 0%" numa máquina saudável, que é o pior erro que um
	// diagnóstico pode cometer: inventar gravidade.
	ev := sinaisDoHardware([]byte(`{"storage":[{"model":"X","smart_status":"Healthy"}]}`))
	for _, e := range ev {
		if e.Sinal == "smart_desgaste" {
			t.Fatalf("campo ausente virou desgaste: %+v", e)
		}
	}
}

func TestDiscoCheioNaoEDiscoDegradado(t *testing.T) {
	// A diferença muda a conduta inteira: um se troca, o outro se limpa.
	ev := sinaisDoHardware([]byte(`{"storage":[{"model":"X","smart_status":"Healthy","used_pct":97}]}`))
	for _, e := range ev {
		if e.Sinal == "smart_geral" || e.Sinal == "smart_desgaste" {
			t.Fatalf("ocupação alta foi lida como falha de disco: %+v", e)
		}
	}
	// O sinal instantâneo diz "está lento", não diz a FORMA do episódio —
	// engasgo curto e degradação sustentada pedem condutas opostas. Quem
	// refina é `formaDaLentidao`, com o histórico. Fixar um dos dois aqui
	// seria escolher entre limpar disco e trocar peça sem medida.
	if s := statusProvavel(ev); s != "lentidao_nao_caracterizada" {
		t.Fatalf("disco cheio devia cair em lentidão não caracterizada, veio %q", s)
	}
}

func TestSemSinalNaoInventaStatus(t *testing.T) {
	// Nenhum sinal implicando nada devolve "" — e "" vira dossiê sem
	// diagnóstico, não o status mais frequente.
	if s := statusProvavel(nil); s != "" {
		t.Fatalf("sem evidência inventou o status %q", s)
	}
}

func TestSistemaAcusouAPecaTemPrecedencia(t *testing.T) {
	// §7.3: se o sistema operacional já diz, não se adivinha. SMART doente
	// mais CPU quente resolve para erro de dispositivo, não superaquecimento.
	ev := []EvidenciaDoDossie{
		{Sinal: "temperatura", Literal: "CPU a 90 °C"},
		{Sinal: "smart_geral", Literal: "SMART Warning"},
	}
	if s := statusProvavel(ev); s != "erro_de_dispositivo" {
		t.Fatalf("evidência do sistema perdeu para inferência térmica: %q", s)
	}
}

func TestCategoriaDesconhecidaNaoViraSinal(t *testing.T) {
	// Categoria nova em `device_health_state` não pode virar sinal por
	// acidente: sinal que nenhuma causa consome é custo puro (§13.6).
	if sinalDaCategoria("categoria_que_nao_existe") != "" {
		t.Fatal("categoria desconhecida virou sinal")
	}
}

func TestSaudeDeStorageNaoAcusaDefeitoDeDisco(t *testing.T) {
	// O caso real do parque: `storage=critical` por disco cheio, com SMART
	// Healthy. Se isso virar erro de dispositivo, o produto manda trocar disco
	// de máquina sadia — e o técnico deixa de confiar na tela na primeira vez
	// que abrir o gabinete à toa.
	sinal := sinalDaCategoria("storage")
	if sinal == "erro_io_log" || sinal == "smart_geral" {
		t.Fatalf("saúde de storage virou acusação de defeito: %q", sinal)
	}
	if s := statusProvavel([]EvidenciaDoDossie{{Sinal: sinal, Literal: "estado de storage: critical"}}); s != "lentidao_nao_caracterizada" {
		t.Fatalf("disco cheio devia cair em lentidão não caracterizada, veio %q", s)
	}
}

func TestLentidaoNaoNasceCaracterizada(t *testing.T) {
	// A regra que a observação de campo impôs: "o Daniel tem lentidões
	// ocasionais rápidas; a Dani tem momentos de lentidão profunda". São dois
	// status, com causas e soluções diferentes, e NENHUM sinal instantâneo
	// consegue dizer qual é — a diferença está na forma do episódio, que só o
	// histórico carrega.
	//
	// Este teste existe para impedir a regressão mais tentadora: fazer
	// `statusProvavel` devolver um dos dois direto porque "está óbvio".
	for _, sinal := range []string{"uso_cpu", "uso_memoria", "processo_pesado"} {
		s := statusProvavel([]EvidenciaDoDossie{{Sinal: sinal, Literal: "x"}})
		if s == "lentidao_intermitente" || s == "lentidao_profunda" {
			t.Fatalf("sinal %q decidiu a forma do episódio sozinho: %q", sinal, s)
		}
	}
}

func TestDiscoOciosoNaoViraDiscoLento(t *testing.T) {
	// Disco parado na janela não mediu latência nenhuma. O agente manda o campo
	// AUSENTE, e ausente não pode virar "respondeu em 0 ms" nem "está lento".
	ev := sinaisDoHardware([]byte(`{"disk_activity":{"busy_pct":0,"queue_length":0,"samples":0}}`))
	for _, e := range ev {
		if e.Sinal == "latencia_disco" {
			t.Fatalf("disco ocioso virou evidência de lentidão: %+v", e)
		}
	}
}

func TestLatenciaAltaDecideLentidaoProfunda(t *testing.T) {
	// É o caso que motivou a medida: a máquina com a lentidão mais severa do
	// parque tinha CPU e memória tranquilas, e nenhum sinal a explicava.
	ev := sinaisDoHardware([]byte(`{"disk_activity":{"busy_pct":95,"latency_ms":42.5,"queue_length":8,"samples":1200}}`))
	achou := false
	for _, e := range ev {
		if e.Sinal == "latencia_disco" {
			achou = true
		}
	}
	if !achou {
		t.Fatal("latência de 42 ms não produziu evidência")
	}
	if s := statusProvavel(ev); s != "lentidao_profunda" {
		t.Fatalf("latência alta devia decidir lentidão profunda, veio %q", s)
	}
}

func TestDiscoRapidoNaoAcusaNada(t *testing.T) {
	// NVMe saudável: 1,4 ms por operação. Não é evidência de coisa nenhuma.
	ev := sinaisDoHardware([]byte(`{"disk_activity":{"busy_pct":3,"latency_ms":1.4,"queue_length":0,"samples":18}}`))
	if len(ev) != 0 {
		t.Fatalf("disco saudável gerou evidência: %+v", ev)
	}
}
