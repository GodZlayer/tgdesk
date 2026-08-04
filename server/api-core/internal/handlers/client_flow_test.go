package handlers

import "testing"

// Testes lógicos do fluxo da tela Client. Cobrem as decisões que a tela e o
// servidor tomam a partir do estado — sem banco nem rede, que é o que dá para
// afirmar com certeza aqui.

// ---------------------------------------------------------------- transporte

// A credencial define O QUE se pode fazer, nunca POR ONDE se fala. Só o
// resgate da instalação usa HTTP, porque nessa hora ainda não existe canal.
func TestSomenteVinculacaoUsaHTTP(t *testing.T) {
	noCanal := []string{
		"/api/v1/support/client/tickets",
		"/api/v1/support/client/tickets/open",
		"/api/v1/support/client/tickets/thread",
		"/api/v1/support/client/tickets/remote-access",
	}
	for _, path := range noCanal {
		if !deviceRPCPath(path) {
			t.Errorf("%s deveria trafegar pelo canal do dispositivo", path)
		}
	}
	foraDoCanal := []string{
		"/api/v1/pairing/standalone-bind", // device ainda guest, sem túnel
		"/api/v1/devices/register",
		"/api/v1/auth/technician/redeem",
	}
	for _, path := range foraDoCanal {
		if deviceRPCPath(path) {
			t.Errorf("%s é resgate de instalação e não pode depender do canal", path)
		}
	}
}

// A credencial do dispositivo não alcança o que é do staff. Sem isso, um
// dispositivo poderia operar chamados de terceiros pelo próprio canal.
func TestCredencialDeDispositivoNaoAlcancaStaff(t *testing.T) {
	proibidos := []string{
		"/api/v1/support/tickets",
		"/api/v1/support/tickets/abc/transition",
		"/api/v1/support/tickets/abc/remote-access",
		"/api/v1/devices",
		"/api/v1/organizations",
		"/api/v1/admin/audit",
		"/api/v1/technicians",
	}
	for _, path := range proibidos {
		if deviceRPCPath(path) {
			t.Errorf("credencial de dispositivo não pode alcançar %s", path)
		}
	}
}

// O servidor injeta a identidade a partir da credencial do canal. Um payload
// que tente se passar por outro dispositivo é sobrescrito, não obedecido.
func TestIdentidadeVemDoCanalNaoDoPayload(t *testing.T) {
	forjado := []byte(`{"device_id":"vitima","device_token":"roubado","message":"oi"}`)
	body := mergeDeviceCredential(forjado, "eu-mesmo", "meu-token")
	got := string(body)
	if !contains(got, `"device_id":"eu-mesmo"`) ||
		!contains(got, `"device_token":"meu-token"`) {
		t.Fatalf("identidade do canal deveria prevalecer, veio %s", got)
	}
	if contains(got, "vitima") || contains(got, "roubado") {
		t.Errorf("payload forjado sobreviveu: %s", got)
	}
	if !contains(got, `"message":"oi"`) {
		t.Errorf("conteúdo legítimo foi perdido: %s", got)
	}
}

func TestPayloadVazioAindaRecebeIdentidade(t *testing.T) {
	body := string(mergeDeviceCredential(nil, "dev1", "tok1"))
	if !contains(body, `"device_id":"dev1"`) || !contains(body, `"device_token":"tok1"`) {
		t.Errorf("chamada sem corpo deve receber a identidade do canal: %s", body)
	}
}

// ------------------------------------------------------------------- análise

// O caso do Daniel: máquina boa, disco cheio e estável, picos curtos de CPU.
// A tela não pode alarmar.
func TestTelaNaoAlarmaMaquinaSaudavel(t *testing.T) {
	cpu := janelaMetrica{Samples: 10080, Media: 18.5, Pico: 90,
		PctAcima75: 8.3, PctAcima85: 8.3}
	disco := janelaMetrica{Samples: 10080, Media: 88, Pico: 88,
		PctAcima75: 100, PctAcima85: 100}

	if exposureLevel(cpu) != "normal" {
		t.Errorf("picos curtos de CPU não são problema, veio %q", exposureLevel(cpu))
	}
	if got := occupancyLevel(disco); got != "warning" {
		t.Errorf("disco a 88%% é espaço reduzido, veio %q", got)
	}
	// Armazenamento é condição, não evento: não eleva o alerta do cliente.
	health := map[string]any{"client_level": "normal"}
	titulo, _ := resumoCliente(health)
	if titulo != "Tudo certo por aqui" {
		t.Errorf("cliente com disco cheio e CPU ociosa não deve ser alarmado, veio %q", titulo)
	}
}

// Máquina genuinamente sobrecarregada precisa alarmar, senão o critério não
// serve para nada.
func TestTelaAlarmaMaquinaSobrecarregada(t *testing.T) {
	w := janelaMetrica{Samples: 1440, Media: 70, Pico: 100,
		PctAcima75: 60, PctAcima85: 50, PctAcima95: 20}
	if got := exposureLevel(w); severityRank(got) < 2 {
		t.Errorf("uso sustentado deve alarmar, veio %q", got)
	}
	titulo, resumo := resumoCliente(map[string]any{"client_level": "critical"})
	if titulo == "Tudo certo por aqui" || resumo == "" {
		t.Errorf("nível crítico precisa de título próprio, veio %q", titulo)
	}
}

// Sem dado suficiente o nível fica indefinido, e a histerese mantém o
// anterior. Se virasse "normal", a máquina que dormiu voltaria sozinha para
// "tudo certo" e alarmaria de novo depois — o vai-e-vem original.
func TestFaltaDeAmostraNaoZeraOEstado(t *testing.T) {
	if got := exposureLevel(janelaMetrica{Samples: 3, PctAcima85: 100}); got != "" {
		t.Errorf("amostra insuficiente deve ser indefinida, veio %q", got)
	}
	if got := occupancyLevel(janelaMetrica{Samples: 3, Media: 99}); got != "" {
		t.Errorf("amostra insuficiente deve ser indefinida, veio %q", got)
	}
}

// Faixas de ocupação, incluindo a que não existia (85–95 pulava direto para o
// grau máximo).
func TestFaixasDeOcupacao(t *testing.T) {
	casos := []struct {
		media float64
		quer  string
	}{{50, "normal"}, {84.9, "normal"}, {85, "warning"},
		{94.9, "warning"}, {95, "critical"}, {99, "critical"}}
	for _, c := range casos {
		got := occupancyLevel(janelaMetrica{Samples: 100, Media: c.media})
		if got != c.quer {
			t.Errorf("ocupação %.1f%%: quer %q, veio %q", c.media, c.quer, got)
		}
	}
}

// A tendência compara curto e longo prazo; sem histórico dos dois lados ela
// não pode inventar uma direção.
func TestTendenciaExigeHistoricoDosDoisLados(t *testing.T) {
	cheio := janelaMetrica{Samples: 500, PctAcima85: 50}
	vazio := janelaMetrica{Samples: 2, PctAcima85: 50}
	if got := tendencia(cheio, vazio); got != "indefinida" {
		t.Errorf("sem histórico longo a tendência é indefinida, veio %q", got)
	}
	piorando := tendencia(janelaMetrica{Samples: 500, PctAcima85: 60},
		janelaMetrica{Samples: 500, PctAcima85: 20})
	if piorando != "piorando" {
		t.Errorf("mais exposição no curto prazo é piora, veio %q", piorando)
	}
	melhorando := tendencia(janelaMetrica{Samples: 500, PctAcima85: 10},
		janelaMetrica{Samples: 500, PctAcima85: 60})
	if melhorando != "melhorando" {
		t.Errorf("menos exposição no curto prazo é melhora, veio %q", melhorando)
	}
	estavel := tendencia(janelaMetrica{Samples: 500, PctAcima85: 30},
		janelaMetrica{Samples: 500, PctAcima85: 33})
	if estavel != "estavel" {
		t.Errorf("variação pequena é estabilidade, veio %q", estavel)
	}
}

// A histerese precisa subir mais rápido do que desce: um problema real não
// pode demorar a aparecer, e uma oscilação não pode apagá-lo.
func TestHistereseSobeRapidoDesceDevagar(t *testing.T) {
	if subidasParaConfirmar >= descidasParaConfirmar {
		t.Errorf("descida (%d) tem de exigir mais confirmações que subida (%d)",
			descidasParaConfirmar, subidasParaConfirmar)
	}
	if subidasParaConfirmar < 2 {
		t.Error("uma única leitura não pode mudar o nível")
	}
}

// A severidade tem de ser ordenável, senão "o mais grave entre as janelas" não
// significa nada.
func TestOrdemDeSeveridade(t *testing.T) {
	ordem := []string{"normal", "warning", "critical", "maximum"}
	for i := 1; i < len(ordem); i++ {
		if severityRank(ordem[i]) <= severityRank(ordem[i-1]) {
			t.Errorf("%q deveria ser mais grave que %q", ordem[i], ordem[i-1])
		}
	}
	if severityRank("desconhecido") != 0 {
		t.Error("valor desconhecido deve ser tratado como normal")
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
