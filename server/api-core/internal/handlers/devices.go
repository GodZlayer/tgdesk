package handlers

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"

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
	Role     string `json:"role"` // host | tecnico
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
	if role != "tecnico" {
		role = "host"
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
	err := s.Pool.QueryRow(r.Context(), `
		SELECT state FROM devices WHERE id=$1 AND device_token=$2`, req.DeviceID, req.DeviceToken,
	).Scan(&state)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}
	if state == "suspenso" {
		writeErr(w, http.StatusForbidden, "dispositivo suspenso")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE devices SET last_seen_at=now() WHERE id=$1`, req.DeviceID)

	// No canal público, heartbeat é apenas descoberta de estado para bootstrap
	// ou recuperação. Presença online só nasce no canal privado da VPN.
	if state == "ativo" && requestFromVPN(r) {
		_ = presence.Heartbeat(r.Context(), s.RDB, req.DeviceID)
		_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "presence", TargetID: req.DeviceID})
	}
	writeJSON(w, http.StatusOK, map[string]string{"state": state})
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

	var netOrgID string
	if err := s.Pool.QueryRow(r.Context(), `SELECT organization_id FROM networks WHERE id=$1`, req.NetworkID).Scan(&netOrgID); err != nil {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}

	if claims.Role != models.RoleSuperAdmin {
		allowed, err := s.technicianCanAccess(r.Context(), claims.TechnicianID, netOrgID, req.NetworkID)
		if err != nil || !allowed {
			writeErr(w, http.StatusForbidden, "sem permissão para essa rede")
			return
		}
	}

	var deviceID string
	err := s.Pool.QueryRow(r.Context(), `
		UPDATE devices SET network_id=$1, state='ativo', pairing_code=NULL, updated_at=now()
		WHERE pairing_code=$2 AND state='guest'
		RETURNING id`, req.NetworkID, strings.ToUpper(req.PairingCode),
	).Scan(&deviceID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "código de pareamento inválido ou já usado")
		return
	}

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
		query = `SELECT id, network_id, hostname, coalesce(mac,''), coalesce(wg_pubkey,''), role, state, last_seen_at, created_at, updated_at, coalesce(rustdesk_id,'') FROM devices ORDER BY created_at DESC`
	} else {
		query = `
			SELECT d.id, d.network_id, d.hostname, coalesce(d.mac,''), coalesce(d.wg_pubkey,''), d.role, d.state, d.last_seen_at, d.created_at, d.updated_at, coalesce(d.rustdesk_id,'')
			FROM devices d
			JOIN networks n ON d.network_id = n.id
			WHERE n.organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL)
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
		if err := rs.Scan(&d.ID, &d.NetworkID, &d.Hostname, &d.MAC, &d.WGPubkey, &d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt, &d.RustdeskID); err != nil {
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
		devices = append(devices, d)
	}
	writeJSON(w, http.StatusOK, devices)
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

// technicianCanAccess checks whether a technician's assignments cover the given org/network.
// An empty organizationID or networkID is treated as "not applicable" rather than a literal match.
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
		SELECT count(*) FROM technician_assignments
		WHERE technician_id = $1
		  AND ((organization_id = $2::uuid) OR (network_id = $3::uuid))`,
		technicianID, orgArg, netArg,
	).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}
