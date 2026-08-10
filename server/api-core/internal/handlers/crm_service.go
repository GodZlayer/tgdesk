package handlers

import (
	"encoding/json"
	"net"
	"net/http"
	"time"
)

// vpnSourceIP devolve o endereço do túnel de quem fez o pedido, ou "" se o
// pedido não veio pela VPN.
//
// É credencial, e não só procedência: AddPeer autoriza cada peer com
// allowed_ip /32, então o WireGuard só entrega pacotes daquele peer com aquele
// endereço de origem. Forjar o IP exigiria a chave privada do dispositivo.
func vpnSourceIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	if ip == nil || ip.To4() == nil || ip.To4()[0] != 10 || ip.To4()[1] != 70 {
		return ""
	}
	return ip.To4().String()
}

// crmPromotionWindow é o prazo, contado do vínculo, em que um dispositivo ainda
// pode ser promovido a servidor de serviço. Fora dele a promoção deixa de ser
// possível pela API — é o que impede um cliente avulso antigo, já em operação e
// já esquecido, de virar destino de ingresso aberto por engano ou por abuso.
const crmPromotionWindow = "2 hours"

type crmTierRequest struct {
	Enabled bool `json:"enabled"`
}

// SetCRMTier promove ou rebaixa um dispositivo ao tier de serviço.
//
// Deliberadamente fora de RegisterDevice: lá o papel vem do instalador, ou seja,
// da própria máquina. Se 'crm' fosse aceito ali, qualquer computador se
// declararia serviço e passaria a receber ingresso de qualquer dispositivo da
// VPN. Ser serviço é uma afirmação sobre a infraestrutura, então quem afirma é
// o super admin.
func (s *Server) SetCRMTier(w http.ResponseWriter, r *http.Request, deviceID string) {
	var req crmTierRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || deviceID == "" {
		writeErrCode(w, http.StatusBadRequest, "dispositivo_obrigatorio", "dispositivo obrigatório")
		return
	}
	if !req.Enabled {
		// Rebaixar não tem janela: um servidor promovido por engano precisa
		// poder ser desfeito a qualquer momento. A janela existe para conter o
		// que amplia alcance, não o que o reduz.
		tag, e := s.Pool.Exec(r.Context(), `
			UPDATE devices SET role='host', updated_at=now() WHERE id=$1`, deviceID)
		if e != nil || tag.RowsAffected() == 0 {
			writeErrCode(w, http.StatusConflict, "dispositivo_inexistente", "dispositivo inexistente")
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"device_id": deviceID, "role": "host"})
		return
	}
	// A janela é medida pelo vínculo da rede PRINCIPAL, e não pelo vínculo mais
	// recente: CRMJoin também escreve em device_networks, então usar o mais
	// recente faria cada ingresso de cliente reabrir a janela do próprio
	// dispositivo. Promover é declarar que aquela máquina acabou de ser
	// instalada como servidor; um avulso antigo da base não pode virar destino
	// de ingresso aberto.
	//
	// control_technician_id é recusado aqui e não só pelo CHECK da 0071 para
	// que o super admin receba o motivo, em vez de um erro de banco.
	tag, e := s.Pool.Exec(r.Context(), `
		UPDATE devices d SET role='crm', updated_at=now()
		WHERE d.id=$1 AND d.control_technician_id IS NULL
		  AND EXISTS (
		      SELECT 1 FROM device_networks dn
		      WHERE dn.device_id=d.id AND dn.network_id=d.network_id
		        AND dn.created_at > now() - $2::interval
		  )`, deviceID, crmPromotionWindow)
	if e != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_definir_tier", "falha ao definir o tier")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErrCode(w, http.StatusConflict, "promocao_fora_da_janela",
			"dispositivo inexistente, é máquina de controle de alguém, ou o prazo de "+
				crmPromotionWindow+" desde o vínculo já passou")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"device_id": deviceID, "role": "crm"})
}

// ListCRMDevices alimenta a aba Serviços/CRM: os servidores já promovidos e os
// candidatos ainda dentro da janela, do vínculo mais recente para o mais
// antigo. A mesma janela do SetCRMTier é aplicada aqui, para a tela nunca
// oferecer algo que o servidor vai recusar.
func (s *Server) ListCRMDevices(w http.ResponseWriter, r *http.Request) {
	rows, e := s.Pool.Query(r.Context(), `
		SELECT d.id, d.hostname, d.role, coalesce(d.wg_virtual_ip,''),
		       coalesce(n.name,''), coalesce(o.name,''), dn.created_at
		FROM devices d
		JOIN device_networks dn ON dn.device_id=d.id AND dn.network_id=d.network_id
		LEFT JOIN networks n ON n.id=d.network_id
		LEFT JOIN organizations o ON o.id=n.organization_id
		WHERE d.state='ativo' AND d.control_technician_id IS NULL
		  AND (d.role='crm' OR (d.role='host' AND dn.created_at > now() - $1::interval))
		ORDER BY (d.role='crm') DESC, dn.created_at DESC`, crmPromotionWindow)
	if e != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_servicos", "falha ao listar serviços")
		return
	}
	defer rows.Close()
	lista := []map[string]any{}
	for rows.Next() {
		var id, hostname, papel, ip, rede, org string
		var vinculo time.Time
		if rows.Scan(&id, &hostname, &papel, &ip, &rede, &org, &vinculo) != nil {
			continue
		}
		lista = append(lista, map[string]any{
			"device_id": id, "hostname": hostname, "role": papel,
			"wg_virtual_ip": ip, "network": rede, "organization": org,
			"bound_at": vinculo,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"devices": lista, "promotion_window": crmPromotionWindow,
	})
}

type crmJoinRequest struct {
	CRMIP string `json:"crm_ip"`
}

// CRMJoin registra o dispositivo que pediu na subrede do servidor de serviço
// indicado pelo endereço VPN desse servidor.
//
// O servidor é nomeado pelo IP, e não por device_id, porque o cliente é sempre
// construído depois que o servidor já existe: o endereço é o que o instalador
// do produto conhece e é o mesmo que o app vai usar para conversar depois. Um
// UUID seria um segundo identificador para a mesma coisa, obtido de outro
// lugar, e que precisaria ser mantido em dia.
//
// Existe porque o alcance no TGDesk é sempre "compartilhar subrede não isolada"
// (session_isolation.go) e o firewall do hub bloqueia todo o resto. Um cliente
// que quisesse falar com um servidor de outra organização não teria como pedir:
// o pedido teria de trafegar exatamente pelo caminho que ainda está fechado.
// Falar com o hub, porém, é entrega local e nunca passa por FORWARD — então é
// aqui, e só aqui, que o pedido cabe.
//
// Aberto a qualquer dispositivo da VPN por decisão de produto: alcançar o
// servidor é chegar à porta, não entrar. A autenticação de quem entra é do
// produto que roda ali, não da VPN.
//
// Quem pede é identificado pelo IP de origem, e não por device_id +
// device_token no corpo como os demais endpoints de dispositivo. O motivo é que
// aqui a origem já é prova: AddPeer autoriza cada peer com allowed_ip /32, então
// o WireGuard descarta qualquer pacote daquele peer com origem diferente — o
// endereço está preso à chave privada do dispositivo. Pedir a credencial em
// cima disso não acrescentaria garantia, e obrigaria todo produto que roda na
// máquina a ler a identidade do TGDesk em disco.
func (s *Server) CRMJoin(w http.ResponseWriter, r *http.Request) {
	var req crmJoinRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.CRMIP == "" {
		writeErrCode(w, http.StatusBadRequest, "endereco_servidor_obrigatorio",
			"endereço do servidor é obrigatório")
		return
	}
	ownIP := vpnSourceIP(r)
	if ownIP == "" {
		writeErrCode(w, http.StatusForbidden, "operacao_disponivel_somente_vpn",
			"operação disponível somente pela VPN")
		return
	}
	var deviceID, state string
	if s.Pool.QueryRow(r.Context(),
		`SELECT id,state FROM devices WHERE wg_virtual_ip=$1`, ownIP).
		Scan(&deviceID, &state) != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_invalido", "dispositivo inválido")
		return
	}
	if state != "ativo" {
		writeErrCode(w, http.StatusForbidden, "dispositivo_sem_acesso",
			"dispositivo suspenso ou ainda não vinculado")
		return
	}
	if ownIP == req.CRMIP {
		writeErrCode(w, http.StatusConflict, "servico_nao_ingressa_em_si",
			"o próprio servidor não ingressa em si mesmo")
		return
	}

	// A subrede de destino é resolvida a partir do servidor, não informada pelo
	// cliente: quem pede não escolhe onde entra. Subrede isolada é recusada
	// porque nela nem os membros se enxergam (0042) — ingressar ali seria
	// silenciosamente inútil, e o cliente ficaria sem entender por quê.
	var subnetworkID, networkID, organizationID string
	if e := s.Pool.QueryRow(r.Context(), `
		SELECT sub.id, n.id, n.organization_id
		FROM devices d
		JOIN networks n ON n.id = d.network_id
		JOIN LATERAL (
		    SELECT s2.id, s2.peer_isolation FROM subnetworks s2
		    WHERE s2.network_id = n.id AND s2.status = 'ativa'
		    ORDER BY (s2.name='Principal') DESC, s2.created_at
		    LIMIT 1
		) sub ON true
		WHERE d.wg_virtual_ip=$1 AND d.role='crm' AND d.state='ativo'
		  AND d.control_technician_id IS NULL
		  AND NOT sub.peer_isolation`, req.CRMIP).
		Scan(&subnetworkID, &networkID, &organizationID); e != nil {
		writeErrCode(w, http.StatusNotFound, "servico_indisponivel",
			"nenhum servidor de serviço nesse endereço")
		return
	}

	tx, txErr := s.Pool.Begin(r.Context())
	if txErr != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_ingressar_servico", "falha ao ingressar no serviço")
		return
	}
	defer tx.Rollback(r.Context())

	// Um dispositivo pode pertencer a várias organizações, mas a uma subrede por
	// organização — a mesma regra que UpdateDeviceSubnetworks defende.
	//
	// Recusa em vez de substituir: o caso só existe com dois servidores de
	// serviço na MESMA organização, e trocar de um para o outro é uma decisão de
	// quem opera, não deste handler. Substituir em silêncio tiraria o
	// dispositivo do primeiro servidor sem ninguém pedir nem perceber.
	var ocupada string
	if e := tx.QueryRow(r.Context(), `
		SELECT s.id FROM device_subnetworks ds
		JOIN subnetworks s ON s.id=ds.subnetwork_id
		JOIN networks n ON n.id=s.network_id
		WHERE ds.device_id=$1 AND n.organization_id=$2 AND s.id<>$3
		LIMIT 1`, deviceID, organizationID, subnetworkID).Scan(&ocupada); e == nil {
		writeErrCode(w, http.StatusConflict, "ja_vinculado_a_outro_servico",
			"este dispositivo já está vinculado a outro servidor desta organização")
		return
	}
	if _, e := tx.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES($1,$2)
		ON CONFLICT DO NOTHING`, deviceID, networkID); e != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_ingressar_servico", "falha ao ingressar no serviço")
		return
	}
	if _, e := tx.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id) VALUES($1,$2)
		ON CONFLICT (device_id,subnetwork_id) DO NOTHING`,
		deviceID, subnetworkID); e != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_ingressar_servico", "falha ao ingressar no serviço")
		return
	}
	if tx.Commit(r.Context()) != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_ingressar_servico", "falha ao ingressar no serviço")
		return
	}

	// Sem isto o cliente esperaria até a passada periódica de 30s para alcançar
	// o servidor — e o primeiro acesso, que é justamente o que este endpoint
	// existe para resolver, pareceria quebrado.
	_ = s.ReconcileSessionIsolation(r.Context())

	writeJSON(w, http.StatusOK, map[string]any{
		"service_ip":      req.CRMIP,
		"organization_id": organizationID,
		"network_id":      networkID,
		"subnetwork_id":   subnetworkID,
	})
}
