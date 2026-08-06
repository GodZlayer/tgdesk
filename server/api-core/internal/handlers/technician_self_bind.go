package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

// A máquina do técnico entra sozinha, como a do cliente avulso.
//
// Até aqui o cliente resolvia o próprio destino na instalação — empresarial vai
// para a rede de entrada da organização, particular para tgdevs.clientes_avulsos
// — e a máquina de técnico não tinha equivalente nenhum. Redimir a chave criava
// a credencial e não tocava na tabela de dispositivos, então o computador do
// técnico ficava 'guest' até alguém vinculá-lo à mão. Na prática ninguém
// vinculava, e a máquina ficava fora de tudo que depende de estar numa rede —
// inclusive de receber ordem de atualização.
//
// O destino sai do papel, que o servidor já conhece pela credencial: quem é
// supervisor ou admin vai para tgdevs.supervisores, quem é técnico vai para
// tgdevs.tecnicos. As duas redes já existiam desde 0035.
//
// A vinculação aqui é registro, não permissão: o que o técnico pode fazer
// continua vindo da credencial que ele apresenta, nunca da rede em que a
// máquina dele está. É o mesmo princípio do adaptador único.

// technicianSystemNetwork devolve a rede onde a máquina do técnico deve morar.
//
// Técnico vinculado a uma organização vai para a rede de técnicos DELA — é o
// que permite ao supervisor saber quem ele vinculou, sem que esses técnicos se
// enxerguem entre si (a rede é isolada por peer) e sem que estar ali conceda
// nada: acesso remoto e função de supervisão continuam vindo da credencial.
//
// Técnico sem vínculo é independente e vai para a rede de sistema do papel, na
// TGDevs, como antes.
func (s *Server) technicianSystemNetwork(
	ctx context.Context, technicianID, role string,
) (orgID string, netID string, err error) {
	var affiliated *string
	_ = s.Pool.QueryRow(ctx,
		`SELECT affiliated_organization_id FROM technicians WHERE id=$1`,
		technicianID).Scan(&affiliated)
	if affiliated != nil && *affiliated != "" {
		err = s.Pool.QueryRow(ctx, `
			SELECT organization_id,id FROM networks
			WHERE organization_id=$1 AND is_technicians AND status='ativa'`,
			*affiliated).Scan(&orgID, &netID)
		if err == nil {
			return orgID, netID, nil
		}
		// Organização sem rede de técnicos ainda: cai para a rede de sistema em
		// vez de recusar a vinculação. Ficar de fora de qualquer rede é pior
		// que ficar na rede menos específica.
	}
	key := "tgdevs.tecnicos"
	if role == models.RoleSupervisor || role == models.RoleSuperAdmin {
		key = "tgdevs.supervisores"
	}
	err = s.Pool.QueryRow(ctx, `
		SELECT organization_id,id FROM networks
		WHERE system_key=$1 AND status='ativa'`, key).Scan(&orgID, &netID)
	return orgID, netID, err
}

// TechnicianSelfBindDevice coloca a máquina de quem está autenticado na rede de
// sistema do papel dele.
//
// Autenticada pela credencial de técnico — é ela que diz o papel — e pelo par
// dispositivo/token, que prova que a máquina é esta. Sem os dois não dá para
// afirmar nem quem é nem qual computador.
func (s *Server) TechnicianSelfBindDevice(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	if claims == nil || claims.TechnicianID == "" {
		writeErrCode(w, http.StatusUnauthorized, "credencial_tecnico_obrigatoria",
			"credencial de técnico obrigatória")
		return
	}
	var req standaloneBindRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil ||
		req.DeviceID == "" || req.DeviceToken == "" {
		writeErrCode(w, http.StatusBadRequest, "dispositivo_token_sao_obrigatorios",
			"dispositivo e token são obrigatórios")
		return
	}
	var state string
	var networkID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT state,network_id FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&state, &networkID) != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_invalido", "dispositivo inválido")
		return
	}
	if state == "suspenso" {
		writeErrCode(w, http.StatusForbidden, "dispositivo_suspenso", "dispositivo suspenso")
		return
	}
	orgID, netID, err := s.technicianSystemNetwork(r.Context(), claims.TechnicianID, claims.Role)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "rede_de_sistema_indisponivel",
			"rede de sistema do papel indisponível")
		return
	}
	// Já numa outra rede é um dispositivo que alguém colocou onde está. Trocá-lo
	// de escopo aqui apagaria em silêncio uma decisão que foi tomada — o mesmo
	// cuidado do vínculo avulso.
	if networkID != nil && *networkID != "" && *networkID != netID {
		writeErrCode(w, http.StatusConflict, "dispositivo_ja_vinculado_rede",
			"dispositivo já vinculado a uma rede")
		return
	}
	// Mesmo conjunto de efeitos do pareamento por código: rede, subrede
	// principal, e as associações em device_networks e device_subnetworks — são
	// elas que as listagens e o Authorizer consultam, não só devices.network_id.
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET network_id=$2,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$2
				ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			state='ativo', pairing_code=NULL, updated_at=now()
		WHERE id=$1`, req.DeviceID, netID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_vincular_dispositivo",
			"falha ao vincular dispositivo")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id)
		SELECT $1,id FROM subnetworks WHERE network_id=$2
		ORDER BY (name='Principal') DESC, created_at LIMIT 1
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	// Vincular o dispositivo do técnico também o registra como a máquina de
	// controle dele — é o mesmo computador, e sem isto o painel continuaria
	// sem saber de qual máquina aquele técnico opera.
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE devices SET control_technician_id=$2 WHERE id=$1
		  AND control_technician_id IS NULL`, req.DeviceID, claims.TechnicianID)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "bind", TargetID: req.DeviceID})
	writeJSON(w, http.StatusOK, map[string]any{
		"state": "ativo", "organization_id": orgID, "network_id": netID,
	})
}
