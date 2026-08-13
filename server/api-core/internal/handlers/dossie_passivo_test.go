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
	if statusProvavel(ev) != "lentidao_persistente" {
		t.Fatalf("disco cheio devia indicar recurso saturado, veio %q", statusProvavel(ev))
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
	if s := statusProvavel([]EvidenciaDoDossie{{Sinal: sinal, Literal: "estado de storage: critical"}}); s != "lentidao_persistente" {
		t.Fatalf("disco cheio devia indicar saturação, veio %q", s)
	}
}
