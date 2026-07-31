package handlers

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
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

	detalhes, _ := json.Marshal(map[string]string{"network_id": req.NetworkID})
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO admin_actions (actor_id, tipo, alvo_id, detalhes)
		VALUES ($1, 'vinculacao', $2, $3::jsonb)`, claims.TechnicianID, deviceID, string(detalhes))

	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "bind", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]string{"device_id": deviceID, "state": "ativo"})
}

// ListDevices returns devices visible to the caller, RBAC-filtered by
// technician_assignments (super_admin sees everything, including unbound guests).
func (s *Server) ListDevices(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())

	var query string
	var args []any
	if claims.Role == models.RoleSuperAdmin {
		query = `SELECT id, network_id, subnetwork_id, hostname, coalesce(display_name,''), coalesce(mac,''), coalesce(wg_pubkey,''), role, state, last_seen_at, created_at, updated_at, coalesce(rustdesk_id,'') FROM devices ORDER BY created_at DESC`
	} else {
		query = `
			SELECT d.id, d.network_id, d.subnetwork_id, d.hostname, coalesce(d.display_name,''), coalesce(d.mac,''), coalesce(d.wg_pubkey,''), d.role, d.state, d.last_seen_at, d.created_at, d.updated_at, coalesce(d.rustdesk_id,'')
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
		if err := rs.Scan(&d.ID, &d.NetworkID, &d.SubnetworkID, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey, &d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt, &d.RustdeskID); err != nil {
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
		d.HealthLevel, _ = s.recentHardwareHealth(r.Context(), d.ID)["level"].(string)
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
	SubnetworkID string `json:"subnetwork_id"`
}

func (s *Server) UpdateDeviceSubnetwork(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req updateDeviceSubnetworkRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.SubnetworkID == "" {
		writeErr(w, http.StatusBadRequest, "subnetwork_id obrigatório")
		return
	}
	var networkID, organizationID string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT s.network_id,n.organization_id FROM subnetworks s
		JOIN networks n ON n.id=s.network_id
		JOIN device_networks dn ON dn.network_id=n.id
		WHERE s.id=$1 AND dn.device_id=$2`, req.SubnetworkID, deviceID).
		Scan(&networkID, &organizationID); err != nil {
		writeErr(w, http.StatusConflict, "a sub-rede não pertence a uma rede do dispositivo")
		return
	}
	// Check authorization using centralizer authorizer
	allowed, err := s.Authorizer.CanAccessNetwork(r.Context(), claims, networkID)
	if err != nil || !allowed {
		writeErr(w, http.StatusForbidden, "sem permissão para esta sub-rede")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE devices SET network_id=$1,subnetwork_id=$2,updated_at=now() WHERE id=$3`,
		networkID, req.SubnetworkID, deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao mover dispositivo")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "device_subnetwork_changed", TargetID: deviceID})
	writeJSON(w, http.StatusOK, map[string]any{"id": deviceID, "subnetwork_id": req.SubnetworkID})
}

func (s *Server) UpdateDeviceNetworks(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req updateDeviceNetworksRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || len(req.NetworkIDs) == 0 {
		writeErr(w, http.StatusBadRequest, "selecione ao menos uma rede")
		return
	}
	var ownerID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT control_technician_id FROM devices WHERE id=$1`, deviceID).
		Scan(&ownerID) != nil {
		writeErr(w, http.StatusNotFound, "dispositivo nao encontrado")
		return
	}
	if ownerID == nil {
		writeErr(w, http.StatusForbidden, "apenas computadores Admin ou Tech podem participar de varias redes")
		return
	}
	if claims.Role != models.RoleSuperAdmin && *ownerID != claims.TechnicianID {
		writeErr(w, http.StatusForbidden, "sem permissao para alterar este computador de controle")
		return
	}
	for _, networkID := range req.NetworkIDs {
		var organizationID string
		if s.Pool.QueryRow(r.Context(),
			`SELECT organization_id FROM networks WHERE id=$1 AND status='ativa'`,
			networkID).Scan(&organizationID) != nil {
			writeErr(w, http.StatusBadRequest, "rede invalida ou suspensa")
			return
		}
		// Check authorization using centralized authorizer
		ok, err := s.Authorizer.CanAccessNetwork(r.Context(), claims, networkID)
		if err != nil || !ok {
			writeErr(w, http.StatusForbidden, "sem permissao para uma das redes")
			return
		}
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar redes")
		return
	}
	defer tx.Rollback(r.Context())
	if _, err = tx.Exec(r.Context(),
		`DELETE FROM device_networks WHERE device_id=$1`, deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao atualizar redes")
		return
	}
	for _, networkID := range req.NetworkIDs {
		if _, err = tx.Exec(r.Context(), `
			INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)`,
			deviceID, networkID); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao vincular rede")
			return
		}
	}
	if _, err = tx.Exec(r.Context(), `
		UPDATE devices SET network_id=$1,updated_at=now() WHERE id=$2`,
		req.NetworkIDs[0], deviceID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao definir rede principal")
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
		var hostOctet, netOctet int
		err := s.Pool.QueryRow(r.Context(), `
			UPDATE networks SET next_host_octet = next_host_octet + 1
			WHERE id=$1
			RETURNING next_host_octet - 1, cidr_octet`, *networkID,
		).Scan(&hostOctet, &netOctet)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao alocar IP virtual")
			return
		}
		virtualIP = fmt.Sprintf("10.70.%d.%d", netOctet, hostOctet)
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
				WHERE n.id=$3::uuid AND o.owner_technician_id=$1)
			OR EXISTS (SELECT 1 FROM technician_assignments
				WHERE technician_id=$1 AND network_id=$3::uuid)`,
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
			  AND (
				n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1)
				OR n.id IN (SELECT network_id FROM technician_assignments
					WHERE technician_id=$1 AND network_id IS NOT NULL)
			  )
		)`, technicianID, deviceID).Scan(&allowed)
	return allowed, err
}
