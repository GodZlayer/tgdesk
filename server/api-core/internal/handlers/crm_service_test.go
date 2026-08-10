package handlers

import (
	"strings"
	"testing"
)

// O alcance no TGDesk é "compartilhar subrede não isolada", e é o que este
// endpoint concede. Cada verificação abaixo é uma forma de conceder alcance a
// mais do que foi pedido — todas silenciosas em runtime, nenhuma visível numa
// leitura rápida do handler.
func TestCRMJoinNaoAmpliaAlcance(t *testing.T) {
	source := functionSource(t, "crm_service.go", "func (s *Server) CRMJoin", "")

	obrigatorios := map[string]string{
		"d.role='crm'":
		// sem isto qualquer dispositivo viraria destino de ingresso, e um
		// cliente poderia se colocar na subrede de outro cliente.
		"o destino precisa ser um dispositivo de serviço",

		"d.control_technician_id IS NULL":
		// máquina de controle tem dono humano; abri-la a pedido de qualquer
		// um exporia o computador dessa pessoa, nos dois sentidos.
		"o destino não pode ser máquina de controle de alguém",

		"NOT sub.peer_isolation":
		// em subrede isolada nem os membros se enxergam (0042): ingressar ali
		// não concede nada e o cliente fica sem entender o silêncio.
		"não pode ingressar em subrede isolada",

		"ja_vinculado_a_outro_servico":
		// uma subrede por organização é a regra que UpdateDeviceSubnetworks
		// defende. Aqui ela vira recusa, e não substituição: tirar o
		// dispositivo do servidor anterior é decisão de quem opera.
		"vínculo a outro servidor da mesma organização precisa ser recusado",

		"ReconcileSessionIsolation":
		// sem reconciliar na hora, o primeiro acesso — a única razão deste
		// endpoint existir — esperaria a passada de 30s.
		"a liberação precisa valer imediatamente",
	}
	for trecho, porque := range obrigatorios {
		if !strings.Contains(source, trecho) {
			t.Errorf("CRMJoin precisa conter %q: %s", trecho, porque)
		}
	}

	// O cliente não escolhe onde entra: a subrede é derivada do servidor. Se o
	// corpo do pedido passasse a carregar subnetwork_id, qualquer dispositivo
	// da VPN escolheria a própria subrede de destino.
	if strings.Contains(source, "req.SubnetworkID") {
		t.Error("a subrede de destino não pode vir do pedido do cliente")
	}
	// O servidor é nomeado pelo endereço VPN — o mesmo que o app usa depois.
	// Se voltasse a ser device_id, o instalador do produto passaria a precisar
	// de um identificador que ele não tem de onde tirar.
	if !strings.Contains(source, "d.wg_virtual_ip=$1") {
		t.Error("o servidor precisa ser resolvido pelo endereço VPN informado")
	}
	// Quem pede é o dono do IP de origem, garantido pelo allowed_ip /32 do
	// peer. Aceitar device_id pelo corpo devolveria ao cliente a escolha de em
	// nome de quem ele fala — e obrigaria todo produto na máquina a ler a
	// identidade do TGDesk em disco.
	if !strings.Contains(source, "vpnSourceIP(r)") {
		t.Error("quem pede precisa ser identificado pelo IP de origem")
	}
	if strings.Contains(source, "req.DeviceID") || strings.Contains(source, "req.DeviceToken") {
		t.Error("a identidade de quem pede não pode vir do corpo do pedido")
	}
	// Ingressar num serviço não pode mexer em vínculo nenhum que já exista:
	// nem na organização da empresa do cliente, nem em outro serviço.
	if strings.Contains(source, "DELETE FROM device_subnetworks") ||
		strings.Contains(source, "DELETE FROM device_networks") {
		t.Error("ingressar num serviço não pode remover vínculo existente")
	}
}
