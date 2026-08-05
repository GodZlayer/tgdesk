package handlers

import (
	"os"
	"strings"
	"testing"
)

// A instalação acontece antes de existir dispositivo, logo antes de existir
// túnel: a busca de técnico, o branding e a entrada empresarial precisam
// continuar fora de private(), pelo mesmo motivo que standalone-bind já está.
func TestEntradaDaInstalacaoNaoDependeDaVPN(t *testing.T) {
	source := readSource(t, "router.go")
	publicos := []string{
		`mux.HandleFunc("POST /api/v1/pairing/org-intake-bind"`,
		`mux.HandleFunc("GET /api/v1/public/technicians/search"`,
		`mux.HandleFunc("GET /api/v1/public/technicians/{id}/branding"`,
		`mux.HandleFunc("POST /api/v1/auth/control-key/validate"`,
	}
	for _, rota := range publicos {
		if !strings.Contains(source, rota) {
			t.Errorf("rota %s precisa estar registrada sem private()", rota)
		}
	}
	if strings.Contains(source, `private(http.HandlerFunc(s.OrgIntakeBindDevice))`) ||
		strings.Contains(source, `private(http.HandlerFunc(s.SearchPublicTechnicians))`) {
		t.Fatal("a entrada da instalação não pode exigir a VPN")
	}
}

// Busca vazia não pode devolver o parque inteiro de técnicos: o endpoint é
// aberto na internet, e sem piso de caracteres e teto de resultados ele vira
// um catálogo de pessoas.
func TestBuscaPublicaNaoEnumeraTecnicos(t *testing.T) {
	source := functionSource(t, "public_intake.go",
		"func (s *Server) SearchPublicTechnicians", "func (s *Server) GetPublicTechnicianBranding")
	if !strings.Contains(source, "minTechnicianQueryLen") {
		t.Error("a busca precisa exigir um mínimo de caracteres")
	}
	if !strings.Contains(source, "LIMIT $2") {
		t.Error("a busca precisa limitar o número de resultados")
	}
	for _, coluna := range []string{"password_hash", "t.*", "SELECT *"} {
		if strings.Contains(source, coluna) {
			t.Errorf("a busca pública não pode expor %s", coluna)
		}
	}
}

// A chave é de uso único. Consumi-la na conferência significaria queimá-la
// antes da remoção da instalação anterior — e se a remoção falhasse, o
// técnico ficaria sem chave e sem instalação.
func TestValidacaoDaChaveNaoConsome(t *testing.T) {
	source := functionSource(t, "technician_enrollment.go",
		"func (s *Server) ValidateTechnicianEnrollment", "func (s *Server) RedeemTechnicianEnrollment")
	for _, efeito := range []string{"consumed_at=now()", "INSERT INTO technician_machine_credentials", "IssueToken"} {
		if strings.Contains(source, efeito) {
			t.Errorf("a conferência da chave não pode executar %q", efeito)
		}
	}
}

// Estar na rede de entrada é a intenção declarada na instalação, não vínculo.
// Se contasse como organização natal, quem escolhesse o técnico errado ficaria
// preso naquela organização: o 409 de UpdateDeviceNetworks bloquearia a
// correção e não há saída por DELETE /admin/guest-devices/{id}, que só alcança
// dispositivo guest.
func TestRedeDeEntradaNaoFixaOrganizacao(t *testing.T) {
	source := functionSource(t, "devices.go",
		"func (s *Server) UpdateDeviceNetworks", "func (s *Server) UpdateDeviceDisplayName")
	if !strings.Contains(source, "NOT n.is_intake") {
		t.Fatal("a rede de entrada não pode contar como organização natal do dispositivo")
	}
}

// A entrada empresarial precisa dos mesmos quatro efeitos de Bind e
// StandaloneBindDevice. Esquecer device_subnetworks deixa o dispositivo dentro
// da rede e fora do modelo de visibilidade — já custou caro antes.
func TestEntradaEmpresarialTemOsMesmosEfeitos(t *testing.T) {
	source := functionSource(t, "public_intake.go",
		"func (s *Server) OrgIntakeBindDevice", "")
	obrigatorios := []string{
		"INSERT INTO device_networks",
		"INSERT INTO device_subnetworks",
		"pairing_code=NULL",
		"subnetwork_id=(SELECT id FROM subnetworks",
	}
	for _, efeito := range obrigatorios {
		if !strings.Contains(source, efeito) {
			t.Errorf("a entrada empresarial precisa executar %q", efeito)
		}
	}
	// Sem esta recusa um dispositivo empresarial poderia se mudar de
	// organização sozinho, apagando o vínculo feito por um técnico.
	if !strings.Contains(source, "dispositivo já vinculado a uma rede") {
		t.Error("a entrada empresarial precisa recusar dispositivo já vinculado")
	}
}

// Desde 0042 quem decide contato direto é a SUBREDE. Marcar isolamento só na
// rede deixaria os clientes da rede de entrada se enxergando — e a rede de
// entrada é justamente o "sem rede/subrede": participa da VPN, não alcança
// ninguém.
func TestRedeDeEntradaIsolaNaSubrede(t *testing.T) {
	source := readSource(t, "../../../migrations/0049_rede_de_entrada.sql")
	if !strings.Contains(source, "INSERT INTO subnetworks(network_id,name,peer_isolation)") {
		t.Fatal("a subrede da rede de entrada precisa nascer isolada")
	}
	if strings.Contains(source, "INSERT INTO subnetworks(network_id,name)\n") {
		t.Fatal("subrede de entrada criada sem peer_isolation")
	}
}

// Promover é o que dá visibilidade: sem entrar na subrede Principal da rede de
// destino, o dispositivo sai da entrada para lugar nenhum — em uma rede e em
// subrede alguma, logo sem par possível.
func TestPromocaoEntraNaSubredePrincipal(t *testing.T) {
	source := functionSource(t, "devices.go",
		"func (s *Server) UpdateDeviceNetworks", "func (s *Server) UpdateDeviceDisplayName")
	if !strings.Contains(source, "INSERT INTO device_subnetworks") {
		t.Error("a promoção precisa colocar o dispositivo na subrede da rede de destino")
	}
	if strings.Contains(source, "subnetwork_id=NULL") {
		t.Error("a promoção não pode deixar o dispositivo sem subrede")
	}
}

func readSource(t *testing.T, file string) string {
	t.Helper()
	b, err := os.ReadFile(file)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
