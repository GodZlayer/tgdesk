package handlers

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

const pairingCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // sem caracteres ambíguos

func genPairingCode(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	out := make([]byte, n)
	for i, v := range b {
		out[i] = pairingCodeAlphabet[int(v)%len(pairingCodeAlphabet)]
	}
	return string(out)
}

type registerDeviceRequest struct {
	Hostname string `json:"hostname"`
	MAC      string `json:"mac"`
	Role     string `json:"role"` // host | supervisor
}

type registerDeviceResponse struct {
	DeviceID    string `json:"device_id"`
	PairingCode string `json:"pairing_code"`
	DeviceToken string `json:"device_token"`
	State       string `json:"state"`
}

// RegisterDevice is called by a freshly-installed agent. No auth required —
// the device starts in guest state with zero sensitive capability, per Seção 3.3.
func (s *Server) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req registerDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Hostname == "" {
		writeErr(w, http.StatusBadRequest, "hostname obrigatório")
		return
	}
	role := req.Role
	if role != "supervisor" {
		role = "host"
	}
	req.MAC = strings.ToLower(strings.TrimSpace(req.MAC))

	if req.MAC != "" {
		var existing registerDeviceResponse
		err := s.Pool.QueryRow(r.Context(), `
			SELECT id,coalesce(pairing_code,''),device_token,state
			FROM devices WHERE lower(btrim(mac))=$1
			ORDER BY created_at LIMIT 1`, req.MAC).
			Scan(&existing.DeviceID, &existing.PairingCode,
				&existing.DeviceToken, &existing.State)
		if err == nil {
			if existing.State != models.DeviceStateGuest {
				writeErr(w, http.StatusConflict,
					"este computador já possui uma identidade TGDesk; restaure a identidade existente")
				return
			}
			_, _ = s.Pool.Exec(r.Context(),
				`UPDATE devices SET hostname=$1,role=$2,updated_at=now() WHERE id=$3`,
				req.Hostname, role, existing.DeviceID)
			writeJSON(w, http.StatusOK, existing)
			return
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			writeErr(w, http.StatusInternalServerError, "falha ao consultar identidade do dispositivo")
			return
		}
	}

	code := genPairingCode(6)
	var id, token string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO devices (hostname, mac, role, state, pairing_code)
		VALUES ($1, $2, $3, 'guest', $4)
		RETURNING id, device_token`, req.Hostname, req.MAC, role, code,
	).Scan(&id, &token)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao registrar dispositivo")
		return
	}

	writeJSON(w, http.StatusCreated, registerDeviceResponse{
		DeviceID: id, PairingCode: code, DeviceToken: token, State: "guest",
	})
}

type heartbeatRequest struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
}

// Heartbeat keeps the minimal control channel alive. It never activates
// sensitive modules on its own — that only happens after Bind.
func (s *Server) Heartbeat(w http.ResponseWriter, r *http.Request) {
	var req heartbeatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "corpo inválido")
		return
	}
	var state string
	var pairingCode *string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT state,pairing_code FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken,
	).Scan(&state, &pairingCode)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE devices SET last_seen_at=now() WHERE id=$1`, req.DeviceID)

	// No canal público, heartbeat é apenas descoberta de estado para bootstrap
	// ou recuperação. Presença online só nasce no canal privado da VPN.
	if state == "ativo" && requestFromVPN(r) {
		_ = presence.Heartbeat(r.Context(), s.RDB, req.DeviceID)
		_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "presence", TargetID: req.DeviceID})
	}
	response := map[string]string{"state": state}
	if pairingCode != nil {
		response["pairing_code"] = *pairingCode
	}
	writeJSON(w, http.StatusOK, response)
}

type bindRequest struct {
	PairingCode    string `json:"pairing_code"`
	OrganizationID string `json:"organization_id"`
	NetworkID      string `json:"network_id"`
}

// Bind is the first-access flow: an authorized technician consumes the
// pairing code shown on the Host screen and links the device to a Network.
func (s *Server) Bind(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	var req bindRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PairingCode == "" || req.NetworkID == "" {
		writeErr(w, http.StatusBadRequest, "pairing_code e network_id são obrigatórios")
		return
	}

	var netOrgID, networkStatus, organizationStatus string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id,n.status,o.status FROM networks n
		JOIN organizations o ON o.id=n.organization_id WHERE n.id=$1`,
		req.NetworkID).Scan(&netOrgID, &networkStatus, &organizationStatus); err != nil {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}
	if networkStatus != "ativa" || organizationStatus != "ativa" {
		writeErr(w, http.StatusConflict, "organização ou rede suspensa")
		return
	}

	// Check authorization using centralized authorizer
	allowed, err := s.Authorizer.CanAccessNetwork(r.Context(), claims, req.NetworkID)
	if err != nil || !allowed {
		writeErr(w, http.StatusForbidden, "sem permissão para essa rede")
		return
	}

	var deviceID string
	err = s.Pool.QueryRow(r.Context(), `
		UPDATE devices SET network_id=$1,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$1 ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			state='ativo', pairing_code=NULL, updated_at=now()
		WHERE pairing_code=$2 AND state='guest'
		RETURNING id`, req.NetworkID, strings.ToUpper(req.PairingCode),
	).Scan(&deviceID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "código de pareamento inválido ou já usado")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING`, deviceID, req.NetworkID)
	// Sem isto o dispositivo fica fora de device_subnetworks, e portanto fora
	// do modelo de visibilidade: nem máquinas da mesma loja se enxergariam.
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id)
		SELECT $1,id FROM subnetworks WHERE network_id=$2
		ORDER BY (name='Principal') DESC, created_at LIMIT 1
		ON CONFLICT DO NOTHING`, deviceID, req.NetworkID)

	detalhes, _ := json.Marshal(map[string]string{"network_id": req.NetworkID})
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO admin_actions (actor_id, tipo, alvo_id, detalhes)
		VALUES ($1, 'vinculacao', $2, $3::jsonb)`, claims.TechnicianID, deviceID, string(detalhes))

	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "bind", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]string{"device_id": deviceID, "state": "ativo"})
}

// SelfBindDevice lets a supervisor or super_admin whose own physical machine
// also runs the Host/device layer skip the manual pairing-code approval.
// The technician already proved who they are through the machine-bound
// enrollment credential (a stronger check than a pairing code); requiring a
// second human approval for the same machine's device identity is pure
// friction, not additional security. Binds straight into the caller's own
// organization, picking its "Principal" network when there is one.
func (s *Server) SelfBindDevice(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	if claims.Role != models.RoleSupervisor && claims.Role != models.RoleSuperAdmin {
		writeErr(w, http.StatusForbidden, "apenas supervisor ou admin")
		return
	}
	var req struct {
		PairingCode string `json:"pairing_code"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.PairingCode == "" {
		writeErr(w, http.StatusBadRequest, "pairing_code é obrigatório")
		return
	}
	var networkID string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT n.id FROM networks n JOIN organizations o ON o.id=n.organization_id
		WHERE o.owner_technician_id=$1 AND n.status='ativa' AND o.status='ativa'
		ORDER BY (n.name='Principal') DESC, n.created_at LIMIT 1`,
		claims.TechnicianID).Scan(&networkID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "nenhuma rede própria encontrada para vincular automaticamente")
		return
	}
	var deviceID string
	err = s.Pool.QueryRow(r.Context(), `
		UPDATE devices SET network_id=$1,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$1 ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			state='ativo', pairing_code=NULL, updated_at=now()
		WHERE pairing_code=$2 AND state='guest'
		RETURNING id`, networkID, strings.ToUpper(req.PairingCode),
	).Scan(&deviceID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "código de pareamento inválido ou já usado")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING`, deviceID, networkID)

	detalhes, _ := json.Marshal(map[string]string{"network_id": networkID, "self_bind": "true"})
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO admin_actions (actor_id, tipo, alvo_id, detalhes)
		VALUES ($1, 'vinculacao', $2, $3::jsonb)`, claims.TechnicianID, deviceID, string(detalhes))

	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "bind", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]any{
		"device_id": deviceID, "network_id": networkID, "state": "ativo",
	})
}

// ListDevices returns devices visible to the caller, RBAC-filtered by
// technician_assignments (super_admin sees everything, including unbound guests).
func (s *Server) ListDevices(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())

	var query string
	var args []any
	if claims.Role == models.RoleSuperAdmin {
		query = `SELECT d.id,d.network_id,coalesce((SELECT array_agg(dn.network_id::text ORDER BY dn.created_at) FROM device_networks dn WHERE dn.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d ORDER BY d.created_at DESC`
	} else if claims.Role == models.RoleSupervisor {
		query = `
			SELECT DISTINCT d.id,d.network_id,coalesce((SELECT array_agg(dn2.network_id::text ORDER BY dn2.created_at) FROM device_networks dn2 WHERE dn2.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'')
			FROM devices d
			JOIN device_networks dn ON dn.device_id=d.id
			JOIN networks n ON dn.network_id=n.id
			JOIN organizations o ON o.id=n.organization_id
			WHERE o.owner_technician_id=$1
			   OR (lower(o.name)='tgdevs' AND EXISTS (
				SELECT 1 FROM technician_assignments ta
				WHERE ta.technician_id=$1 AND ta.network_id=n.id)
				AND (NOT n.peer_isolation OR d.control_technician_id=$1))
			ORDER BY d.created_at DESC`
		args = append(args, claims.TechnicianID)
	} else {
		query = `
			SELECT d.id,d.network_id,coalesce((SELECT array_agg(dn2.network_id::text ORDER BY dn2.created_at) FROM device_networks dn2 WHERE dn2.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'')
			FROM devices d
			JOIN networks n ON d.network_id = n.id
			WHERE n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1)
			   OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL)
			ORDER BY d.created_at DESC`
		args = append(args, claims.TechnicianID)
	}

	rs, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar dispositivos")
		return
	}
	defer rs.Close()

	devices := []models.Device{}
	for rs.Next() {
		var d models.Device
		if err := rs.Scan(&d.ID, &d.NetworkID, &d.NetworkIDs, &d.SubnetworkID,
			&d.SubnetworkIDs, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey,
			&d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt,
			&d.RustdeskID); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler dispositivos")
			return
		}
		if d.State == "ativo" && presence.IsOnline(r.Context(), s.RDB, d.ID) {
			d.Presence = "online"
		} else if d.State == "ativo" {
			d.Presence = "offline"
		} else {
			d.Presence = d.State
		}
		capabilities := presence.GetCapabilities(r.Context(), s.RDB, d.ID)
		d.RemoteReady = capabilities.RemoteReady
		d.FilesReady = capabilities.FilesReady
		d.HealthLevel = s.readHealthLevel(r.Context(), d.ID)
		d.CanManage, _ = s.Authorizer.CanManageDevice(r.Context(), claims, d.ID)
		devices = append(devices, d)
	}
	writeJSON(w, http.StatusOK, devices)
}

type updateDeviceDisplayNameRequest struct {
	DisplayName string `json:"display_name"`
}

func (s *Server) ClaimControlMachine(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	tag, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET control_technician_id=$1,updated_at=now()
		WHERE id=$2 AND state IN ('ativo','suspenso')`,
		claims.TechnicianID, deviceID)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "dispositivo de controle nao encontrado")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": deviceID, "control_machine": true})
}

type updateDeviceNetworksRequest struct {
	NetworkIDs []string `json:"network_ids"`
}

type updateDeviceSubnetworkRequest struct {
	SubnetworkID  string   `json:"subnetwork_id"`
	SubnetworkIDs []string `json:"subnetwork_ids"`
}

func (s *Server) UpdateDeviceSubnetwork(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req updateDeviceSubnetworkRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "sub-redes inválidas")
		return
	}
	if len(req.SubnetworkIDs) == 0 && req.SubnetworkID != "" {
		req.SubnetworkIDs = []string{req.SubnetworkID}
	}
	if len(req.SubnetworkIDs) == 0 {
		writeErr(w, http.StatusBadRequest, "selecione ao menos uma sub-rede")
		return
	}
	canManageDevice, err := s.Authorizer.CanManageDevice(r.Context(), claims, deviceID)
	if err != nil || !canManageDevice {
		writeErr(w, http.StatusForbidden, "sem permissão para alterar este dispositivo")
		return
	}
	targetOrganizations := make([]string, 0, len(req.SubnetworkIDs))
	seenOrganizations := map[string]bool{}
	for _, subnetworkID := range req.SubnetworkIDs {
		var networkID, organizationID string
		if err := s.Pool.QueryRow(r.Context(), `
			SELECT s.network_id,n.organization_id FROM subnetworks s
			JOIN networks n ON n.id=s.network_id
			JOIN device_networks dn ON dn.network_id=s.network_id
			WHERE s.id=$1 AND dn.device_id=$2`, subnetworkID, deviceID).
			Scan(&networkID, &organizationID); err != nil {
			writeErr(w, http.StatusConflict, "uma sub-rede não pertence às redes do dispositivo")
			return
		}
		allowed, err := s.Authorizer.CanManageNetwork(r.Context(), claims, networkID)
		if err != nil || !allowed {
			writeErr(w, http.StatusForbidden, "sem permissão para uma das sub-redes")
			return
		}
		if seenOrganizations[organizationID] {
			writeErr(w, http.StatusConflict, "selecione apenas uma sub-rede por organizacao")
			return
		}
		seenOrganizations[organizationID] = true
		targetOrganizations = append(targetOrganizations, organizationID)
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar sub-redes")
		return
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(), `
		DELETE FROM device_subnetworks ds
		USING subnetworks s,networks n
		WHERE ds.device_id=$1 AND s.id=ds.subnetwork_id
		  AND n.id=s.network_id AND n.organization_id=ANY($2::uuid[])`,
		deviceID, targetOrganizations); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar sub-redes")
		return
	}
	for _, subnetworkID := range req.SubnetworkIDs {
		if _, err = tx.Exec(r.Context(), `
			INSERT INTO device_subnetworks(device_id,subnetwork_id) VALUES($1,$2)
			ON CONFLICT (device_id,subnetwork_id) DO NOTHING`, deviceID, subnetworkID); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao vincular sub-rede")
			return
		}
	}
	if _, err = tx.Exec(r.Context(), `
		UPDATE devices d SET subnetwork_id=(
			SELECT ds.subnetwork_id FROM device_subnetworks ds
			JOIN subnetworks s ON s.id=ds.subnetwork_id
			WHERE ds.device_id=d.id AND s.network_id=d.network_id
			ORDER BY ds.created_at LIMIT 1),updated_at=now()
		WHERE d.id=$1`, deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao definir sub-rede principal")
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir sub-redes")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "device_subnetwork_changed", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]any{"id": deviceID, "subnetwork_id": req.SubnetworkIDs[0], "subnetwork_ids": req.SubnetworkIDs})
}

func (s *Server) UpdateDeviceNetworks(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req updateDeviceNetworksRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || len(req.NetworkIDs) == 0 {
		writeErr(w, http.StatusBadRequest, "selecione ao menos uma rede")
		return
	}
	var exists bool
	if s.Pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM devices WHERE id=$1)`, deviceID).
		Scan(&exists) != nil || !exists {
		writeErr(w, http.StatusNotFound, "dispositivo nao encontrado")
		return
	}
	canManage, err := s.Authorizer.CanManageDevice(r.Context(), claims, deviceID)
	if err != nil || !canManage {
		writeErr(w, http.StatusForbidden, "sem permissao para alterar as redes deste dispositivo")
		return
	}
	// A rede de entrada não conta como organização natal: estar nela é a
	// intenção declarada pelo cliente na instalação, não um vínculo. Se
	// contasse, quem escolhesse o técnico errado ficaria preso naquela
	// organização — o 409 abaixo bloquearia a correção, e não há saída por
	// DELETE /admin/guest-devices/{id}, que só alcança dispositivo guest.
	var homeOrganizationID string
	_ = s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id
		FROM device_networks dn JOIN networks n ON n.id=dn.network_id
		WHERE dn.device_id=$1 AND n.system_key IS NULL AND NOT n.is_intake
		ORDER BY dn.created_at LIMIT 1`, deviceID).Scan(&homeOrganizationID)
	selectedSystemNetworks := map[string]string{}
	for _, networkID := range req.NetworkIDs {
		var organizationID string
		var systemKey *string
		if s.Pool.QueryRow(r.Context(),
			`SELECT organization_id,system_key FROM networks WHERE id=$1 AND status='ativa'`,
			networkID).Scan(&organizationID, &systemKey) != nil {
			writeErr(w, http.StatusBadRequest, "rede invalida ou suspensa")
			return
		}
		if systemKey == nil && homeOrganizationID != "" && organizationID != homeOrganizationID {
			writeErr(w, http.StatusConflict,
				"o dispositivo nao pode ser movido entre organizacoes")
			return
		}
		if systemKey != nil {
			selectedSystemNetworks[networkID] = *systemKey
		}
		// Check authorization using centralized authorizer
		ok, err := s.Authorizer.CanManageNetwork(r.Context(), claims, networkID)
		if err != nil || !ok {
			writeErr(w, http.StatusForbidden, "sem permissao para uma das redes")
			return
		}
	}
	if len(selectedSystemNetworks) > 1 {
		writeErr(w, http.StatusConflict, "selecione apenas uma rede TGDevs para o dispositivo")
		return
	}
	var requiredTGDevsNetworkID string
	var controlRole string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.id,coalesce(t.role,'') FROM networks n
		LEFT JOIN devices d ON d.id=$1
		LEFT JOIN technicians t ON t.id=d.control_technician_id
		WHERE n.system_key=CASE
			WHEN t.role='super_admin' THEN 'tgdevs.principal'
			WHEN t.role='supervisor' THEN 'tgdevs.supervisores'
			WHEN t.role IN ('tecnico','freelancer') THEN 'tgdevs.tecnicos'
			ELSE 'tgdevs.clientes' END`, deviceID).Scan(&requiredTGDevsNetworkID, &controlRole); err != nil {
		writeErr(w, http.StatusInternalServerError, "rede obrigatoria TGDevs indisponivel")
		return
	}
	hasRequired := false
	for networkID, systemKey := range selectedSystemNetworks {
		allowed := networkID == requiredTGDevsNetworkID
		if controlRole == models.RoleSupervisor {
			allowed = systemKey == "tgdevs.principal" || systemKey == "tgdevs.supervisores"
		}
		if !allowed {
			writeErr(w, http.StatusConflict, "rede TGDevs incompativel com a funcao do dispositivo")
			return
		}
		requiredTGDevsNetworkID = networkID
		hasRequired = true
	}
	if !hasRequired {
		req.NetworkIDs = append(req.NetworkIDs, requiredTGDevsNetworkID)
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar redes")
		return
	}
	defer tx.Rollback(r.Context())
	for _, networkID := range req.NetworkIDs {
		if _, err = tx.Exec(r.Context(), `
			INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
			ON CONFLICT (device_id,network_id) DO NOTHING`,
			deviceID, networkID); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao vincular rede")
			return
		}
	}
	if _, err = tx.Exec(r.Context(), `
		DELETE FROM device_networks
		WHERE device_id=$1 AND NOT (network_id = ANY($2::uuid[]))`,
		deviceID, req.NetworkIDs); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar redes")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		DELETE FROM device_subnetworks ds
		WHERE ds.device_id=$1
		  AND NOT EXISTS (
			SELECT 1
			FROM subnetworks s
			JOIN device_networks dn
			  ON dn.device_id=ds.device_id AND dn.network_id=s.network_id
			WHERE s.id=ds.subnetwork_id
		  )`, deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao conciliar sub-redes")
		return
	}
	// Entrar na rede é entrar na subrede Principal dela, como em Bind e nas
	// duas entradas de cliente. Sem isso o dispositivo movido fica em uma rede
	// e em subrede nenhuma — e como quem decide contato direto é a subrede
	// (0042), ele não enxergaria os da própria rede: seria promovido para
	// lugar nenhum.
	if _, err = tx.Exec(r.Context(), `
		UPDATE devices SET network_id=$1,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$1 ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			updated_at=now() WHERE id=$2`,
		req.NetworkIDs[0], deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao definir rede principal")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id)
		SELECT $1,id FROM subnetworks WHERE network_id=$2
		ORDER BY (name='Principal') DESC, created_at LIMIT 1
		ON CONFLICT DO NOTHING`, deviceID, req.NetworkIDs[0]); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao vincular sub-rede principal")
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir redes")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "bind", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]any{
		"id": deviceID, "network_ids": req.NetworkIDs,
	})
}

// UpdateDeviceDisplayName altera apenas o nome visual usado pelo TGDesk.
// O hostname informado pelo Windows permanece intacto.
func (s *Server) UpdateDeviceDisplayName(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req updateDeviceDisplayNameRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "nome de exibição inválido")
		return
	}
	req.DisplayName = strings.TrimSpace(req.DisplayName)
	if len([]rune(req.DisplayName)) > 80 {
		writeErr(w, http.StatusBadRequest, "nome de exibição deve ter no máximo 80 caracteres")
		return
	}
	var orgID, netID, controlRole string
	var controlTechnicianID *string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id,n.id,d.control_technician_id,coalesce(t.role,'')
		FROM devices d
		JOIN networks n ON n.id=d.network_id
		LEFT JOIN technicians t ON t.id=d.control_technician_id
		WHERE d.id=$1`, deviceID).
		Scan(&orgID, &netID, &controlTechnicianID, &controlRole); err != nil {
		writeErr(w, http.StatusNotFound, "dispositivo não encontrado")
		return
	}
	// Check authorization using centralized authorizer
	if controlTechnicianID != nil && controlRole == models.RoleSupervisor &&
		claims.Role != models.RoleSuperAdmin &&
		*controlTechnicianID != claims.TechnicianID {
		writeErr(w, http.StatusForbidden, "somente o próprio técnico ou o Admin pode alterar este nome")
		return
	}
	ok, err := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	if err != nil || !ok {
		writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
		return
	}
	if controlTechnicianID != nil && controlRole == models.RoleSupervisor && req.DisplayName == "" {
		writeErr(w, http.StatusBadRequest, "o nome do computador do técnico não pode ficar vazio")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao alterar nome do dispositivo")
		return
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(), `
		UPDATE devices SET display_name=nullif($1,''),updated_at=now() WHERE id=$2`,
		req.DisplayName, deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao alterar nome do dispositivo")
		return
	}
	if controlTechnicianID != nil && controlRole == models.RoleSupervisor {
		if _, err = tx.Exec(r.Context(),
			`UPDATE technicians SET username=$1 WHERE id=$2`,
			req.DisplayName, *controlTechnicianID); err != nil {
			writeErr(w, http.StatusConflict, "nome de técnico já utilizado")
			return
		}
		if _, err = tx.Exec(r.Context(),
			`UPDATE organizations SET name=$1 WHERE owner_technician_id=$2`,
			req.DisplayName, *controlTechnicianID); err != nil {
			writeErr(w, http.StatusConflict, "nome de organização já utilizado")
			return
		}
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir alteração do nome")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "device_renamed", TargetID: deviceID})
	if controlTechnicianID != nil && controlRole == models.RoleSupervisor {
		_ = presence.Publish(r.Context(), s.RDB,
			presence.Event{Type: "technician_renamed", TargetID: *controlTechnicianID})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"id": deviceID, "display_name": req.DisplayName,
	})
}

type wgKeyRequest struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
	PublicKey   string `json:"public_key"`
}

type wgKeyResponse struct {
	VirtualIP        string `json:"virtual_ip"`
	HubPublicKey     string `json:"hub_public_key"`
	HubEndpoint      string `json:"hub_endpoint"`
	HubVirtualIP     string `json:"hub_virtual_ip"`
	RendezvousHost   string `json:"rendezvous_host"`
	RendezvousPubkey string `json:"rendezvous_pubkey"`
	RemoteCredential string `json:"remote_credential"`
}

func (s *Server) remoteCredential(deviceID, deviceToken string) string {
	mac := hmac.New(sha256.New, []byte(s.Cfg.JWTSecret))
	_, _ = mac.Write([]byte("tgdesk-remote:" + deviceID + ":" + deviceToken))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

// WGKey implements the wg-orchestrator peer registration (Seção 8.A / Fase 1):
// a bound device submits its WireGuard public key and receives a virtual IP
// plus the hub's peer config. It is the only WireGuard peer added in Fase 1 —
// full device-to-device mesh (rendezvous/relay) is Fase 2.
func (s *Server) WGKey(w http.ResponseWriter, r *http.Request) {
	if s.Hub == nil {
		writeErr(w, http.StatusServiceUnavailable, "hub WireGuard indisponível neste servidor")
		return
	}
	var req wgKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PublicKey == "" {
		writeErr(w, http.StatusBadRequest, "public_key é obrigatório")
		return
	}

	var networkID, state, existingIP *string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT network_id, state, wg_virtual_ip FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken,
	).Scan(&networkID, &state, &existingIP)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}
	if state == nil || *state != models.DeviceStateAtivo || networkID == nil {
		writeErr(w, http.StatusForbidden, "dispositivo precisa estar vinculado e ativo")
		return
	}

	var virtualIP string
	if existingIP != nil && *existingIP != "" {
		virtualIP = *existingIP
	} else {
		// allocate_virtual_ip reaproveita endereços devolvidos por dispositivos
		// inativos e abre um octeto novo quando o atual lota — a rede deixou de
		// ser limitada a um único /24. Ver 0041_network_pools.sql.
		if err := s.Pool.QueryRow(r.Context(),
			`SELECT allocate_virtual_ip($1)`, *networkID).Scan(&virtualIP); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao alocar IP virtual")
			return
		}
	}

	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET wg_pubkey=$1, wg_virtual_ip=$2, updated_at=now() WHERE id=$3`,
		req.PublicKey, virtualIP, req.DeviceID,
	); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao salvar chave WireGuard")
		return
	}

	if err := s.Hub.AddPeer(req.PublicKey, virtualIP); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao registrar peer no hub: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, wgKeyResponse{
		VirtualIP:        virtualIP,
		HubPublicKey:     s.Hub.PublicKey.Base64(),
		HubEndpoint:      s.Cfg.HubPublicAddr,
		HubVirtualIP:     "10.70.0.1",
		RendezvousHost:   s.Cfg.RendezvousHost,
		RendezvousPubkey: readRendezvousKey(s.Cfg.RendezvousKeyFile),
		RemoteCredential: s.remoteCredential(req.DeviceID, req.DeviceToken),
	})
}

func (s *Server) DeviceRemoteCredential(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var state, deviceToken string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT state,device_token FROM devices WHERE id=$1`, deviceID).
		Scan(&state, &deviceToken)
	if err != nil {
		writeErr(w, http.StatusNotFound, "dispositivo não encontrado")
		return
	}
	if state != models.DeviceStateAtivo {
		writeErr(w, http.StatusConflict, "dispositivo não está ativo")
		return
	}
	// Check authorization using centralized authorizer
	allowed, accessErr := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	if accessErr != nil || !allowed {
		writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
		return
	}
	s.audit(r, "acesso_remoto", deviceID)
	writeJSON(w, http.StatusOK, map[string]string{
		"credential": s.remoteCredential(deviceID, deviceToken),
	})
}

// readRendezvousKey reads the hbbs public key from the read-only volume shared
// with the rendezvous container. Returns "" if not available yet (e.g. hbbs
// hasn't booted for the first time), which callers should treat as optional.
func readRendezvousKey(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

type rustdeskIDRequest struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
	RustdeskID  string `json:"rustdesk_id"`
}

// ReportRustdeskID lets a bound Host device tell the server which RustDesk ID
// it registered with our hbbs, so the Technician Hub can display/connect to
// it without a separate manual pairing step (Seção 8.B).
func (s *Server) ReportRustdeskID(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErr(w, http.StatusForbidden, "estado RustDesk disponível somente pela VPN")
		return
	}
	var req rustdeskIDRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.RustdeskID == "" {
		writeErr(w, http.StatusBadRequest, "rustdesk_id é obrigatório")
		return
	}
	res, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET rustdesk_id=$1, updated_at=now() WHERE id=$2 AND device_token=$3`,
		req.RustdeskID, req.DeviceID, req.DeviceToken)
	if err != nil || res.RowsAffected() == 0 {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"rustdesk_id": req.RustdeskID})
}

// technicianCanAccess grants the supervisor their own organization and only
// explicitly assigned networks outside it (for example their TGDevs network).
func (s *Server) technicianCanAccess(ctx context.Context, technicianID, organizationID, networkID string) (bool, error) {
	var orgArg, netArg any
	if organizationID != "" {
		orgArg = organizationID
	}
	if networkID != "" {
		netArg = networkID
	}
	var count int
	err := s.Pool.QueryRow(ctx, `
		SELECT count(*) WHERE
			EXISTS (SELECT 1 FROM organizations
				WHERE id=$2::uuid AND owner_technician_id=$1)
			OR EXISTS (
				SELECT 1 FROM networks n
				JOIN organizations o ON o.id=n.organization_id
				WHERE n.id=$3::uuid AND (
					o.owner_technician_id=$1 OR (
						lower(o.name)='tgdevs' AND EXISTS (
							SELECT 1 FROM technician_assignments ta
							WHERE ta.technician_id=$1 AND ta.network_id=n.id))))`,
		technicianID, orgArg, netArg,
	).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (s *Server) technicianCanAccessDevice(
	ctx context.Context, technicianID, deviceID string,
) (bool, error) {
	var allowed bool
	err := s.Pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM device_networks dn
			JOIN networks n ON n.id=dn.network_id
			WHERE dn.device_id=$2
			  AND EXISTS (SELECT 1 FROM organizations o
				WHERE o.id=n.organization_id AND (
					o.owner_technician_id=$1 OR (
						lower(o.name)='tgdevs' AND EXISTS (
							SELECT 1 FROM technician_assignments ta
							WHERE ta.technician_id=$1 AND ta.network_id=n.id))))
		)`, technicianID, deviceID).Scan(&allowed)
	return allowed, err
}
