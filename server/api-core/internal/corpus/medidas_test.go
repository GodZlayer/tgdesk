package corpus

import "testing"

// Testes da extração de medidas (§19.1).
//
// A regra que estes testes existem para proteger: **nada aqui inventa valor**.
// Um extrator que preenche lacuna com zero ensina a rede que "sem dado" e "dado
// zerado" são a mesma coisa — e são exatamente opostos.

func acharMedida(ms []Medida, campo, chave string) (Medida, bool) {
	for _, m := range ms {
		if m.Campo == campo && m.Chave == chave {
			return m, true
		}
	}
	return Medida{}, false
}

func TestEventoDoWindowsSaiComFonteNivelEId(t *testing.T) {
	// Formato real do Visualizador de Eventos, como aparece nos casos.
	bloco := `Log Name: System
Source: Microsoft-Windows-Kernel-Power
Date: 1/1/2013 1:52:24 PM
Event ID: 41
Task Category: (63)
Level: Error
Keywords: (2)
User: N/A
Computer: andrew-pc
Description: The system has rebooted without cleanly shutting down first.`

	m, ok := acharMedida(ExtrairMedidas(bloco), "evento_sistema", "Microsoft-Windows-Kernel-Power:41")
	if !ok {
		t.Fatalf("evento não extraído: %+v", ExtrairMedidas(bloco))
	}
	if m.Valor == nil || *m.Valor != 41 {
		t.Fatal("Event ID não virou valor numérico")
	}
	// O nível vem do próprio sistema. Se o sistema já diz, não se adivinha.
	if m.Nivel != "Error" {
		t.Fatalf("nível %q, esperado Error", m.Nivel)
	}
	if m.Literal == "" {
		t.Fatal("medida sem literal: não teria como ser citada na tela nem auditada")
	}
}

func TestBugcheckSaiComNomeECodigo(t *testing.T) {
	bloco := `SYSTEM_THREAD_EXCEPTION_NOT_HANDLED_M (1000007e)
This is a very common bugcheck.`
	ms := ExtrairMedidas(bloco)
	if _, ok := acharMedida(ms, "bugcheck", "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED_M"); !ok {
		t.Fatalf("bugcheck não extraído: %+v", ms)
	}
}

func TestCabecalhoDoDepuradorNaoViraBugcheck(t *testing.T) {
	// O dump do WinDbg tem seções chamadas BUGCHECK_STR, MODULE_NAME etc.
	// Sem a lista de exclusão, cada uma viraria uma "causa" no corpus.
	bloco := `BUGCHECK_STR:  0x7E
MODULE_NAME: nvlddmkm
IMAGE_NAME:  nvlddmkm.sys
FAILURE_BUCKET_ID:  0x7E_nvlddmkm`
	for _, m := range ExtrairMedidas(bloco) {
		if m.Campo == "bugcheck" && naoSaoBugcheck[m.Chave] {
			t.Fatalf("cabeçalho do depurador virou bugcheck: %q", m.Chave)
		}
	}
}

func TestSmartSaiComValorNumerico(t *testing.T) {
	bloco := `  5 Reallocated_Sector_Ct   0x0033   100   100   036    Pre-fail  Always       -       12
197 Current_Pending_Sector  0x0012   100   100   000    Old_age   Always       -       3`

	ms := ExtrairMedidas(bloco)
	realoc, ok := acharMedida(ms, "smart", "reallocated")
	if !ok || realoc.Valor == nil || *realoc.Valor != 12 {
		t.Fatalf("reallocated não extraído corretamente: %+v", ms)
	}
	pend, ok := acharMedida(ms, "smart", "pending")
	if !ok || pend.Valor == nil || *pend.Valor != 3 {
		t.Fatalf("pending não extraído corretamente: %+v", ms)
	}
}

func TestTemperaturaForaDeFaixaNaoEhTemperatura(t *testing.T) {
	// "3 c" e "800 celsius" são número solto com letra ao lado, não leitura de
	// componente. Aceitá-los envenenaria o limiar térmico.
	if ms := ExtrairMedidas("versão 3 c e algo com 800 celsius"); len(ms) != 0 {
		t.Fatalf("número fora de faixa virou temperatura: %+v", ms)
	}
	ms := ExtrairMedidas("core hit 97 °C under load")
	m, ok := acharMedida(ms, "temperatura", "max_observada")
	if !ok || m.Valor == nil || *m.Valor != 97 {
		t.Fatalf("temperatura real não extraída: %+v", ms)
	}
	if m.Unidade != "°C" {
		t.Fatal("temperatura sem unidade")
	}
}

func TestMedidaCategoricaTemValorNuloNaoZero(t *testing.T) {
	// Kernel panic não tem número. Preencher com zero ensinaria a rede que
	// "sem dado" e "dado zerado" são a mesma coisa.
	ms := ExtrairMedidas("panic(cpu 0 caller 0xffffff80002c4794): Kernel trap")
	m, ok := acharMedida(ms, "kernel_panic", "panic")
	if !ok {
		t.Fatalf("panic não extraído: %+v", ms)
	}
	if m.Valor != nil {
		t.Fatal("medida categórica ganhou valor numérico inventado")
	}
}

func TestBlocoSemMedidaDevolveVazio(t *testing.T) {
	// Muito bloco de log é ruído de console. Forçá-lo a render alguma coisa
	// seria fabricar dado.
	if ms := ExtrairMedidas("[ OK ] Started Show Plymouth Boot Screen."); len(ms) != 0 {
		t.Fatalf("ruído de console virou medida: %+v", ms)
	}
}

func TestMesmaMedidaDuasVezesContaUma(t *testing.T) {
	bloco := `Event ID: 41 ... Event ID: 41 de novo`
	n := 0
	for _, m := range ExtrairMedidas(bloco) {
		if m.Campo == "evento_sistema" {
			n++
		}
	}
	if n != 1 {
		t.Fatalf("mesma medida contada %d vezes; a frequência infla e a poda decide errado", n)
	}
}

func TestCasoSemMedidaNaoViraExemploDeTreino(t *testing.T) {
	c := CasoReal{ThreadID: "t1", Sintoma: "trava", Sinais: []string{"latencia_disco"}}
	if c.TemMedida() {
		t.Fatal("caso sem medida foi aceito como exemplo de treino; não há o que sintetizar")
	}
}

func TestCamposDoDossieSaoAPonteParaATelemetria(t *testing.T) {
	// O conjunto destes campos, sobre todos os casos, É a telemetria
	// necessária (§19.2) — em vez de alguém decidir por intuição.
	valor := 12.0
	c := CasoReal{
		Medidas: []Medida{
			{Campo: "smart", Chave: "reallocated", Valor: &valor},
			{Campo: "evento_sistema", Chave: "disk:51"},
			{Campo: "smart", Chave: "pending"},
		},
	}
	campos := c.CamposDoDossie()
	if len(campos) != 2 || campos[0] != "evento_sistema" || campos[1] != "smart" {
		t.Fatalf("campos errados: %v", campos)
	}
}

func TestRegistradorZeradoNaoViraBugcheck(t *testing.T) {
	// Regressão do primeiro ensaio contra os casos reais: a medida MAIS
	// frequente do corpus tinha virado `bugcheck/0x00000000` — que não é código
	// de parada, é registrador zerado num dump. Sem contexto qualificando o
	// número, todo dump vira falso bugcheck.
	dump := `CR0: 0x00000000 CR2: 0x00000001 CR3: 0x00000002 CR4: 0x00000660`
	for _, m := range ExtrairMedidas(dump) {
		if m.Campo == "bugcheck" {
			t.Fatalf("registrador virou bugcheck: %q", m.Chave)
		}
	}

	// Com a palavra que qualifica, o mesmo formato É um bugcheck.
	real := `Bugcheck code: 0x0000007A`
	if _, ok := acharMedida(ExtrairMedidas(real), "bugcheck", "0x0000007A"); !ok {
		t.Fatalf("bugcheck qualificado não foi extraído: %+v", ExtrairMedidas(real))
	}
}
