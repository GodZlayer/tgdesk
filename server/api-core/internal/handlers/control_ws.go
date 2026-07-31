package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	tgauth "tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

var controlUpgrader = websocket.Upgrader{
	ReadBufferSize:  16 * 1024,
	WriteBufferSize: 16 * 1024,
	CheckOrigin:     func(*http.Request) bool { return true },
}

type controlMessage struct {
	Type    string          `json:"type"`
	ID      string          `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Path    string          `json:"path,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

func requestFromVPN(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.To4() != nil && ip.To4()[0] == 10 && ip.To4()[1] == 70
}

// DeviceControlWS é o canal operacional do Host. Ele deliberadamente só
// aceita tráfego originado da interface WireGuard.
func (s *Server) DeviceControlWS(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErr(w, http.StatusForbidden, "canal de controle disponível somente pela VPN")
		return
	}
	deviceID := r.URL.Query().Get("device_id")
	token := r.URL.Query().Get("device_token")
	var state string
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT state FROM devices WHERE id=$1 AND device_token=$2`,
		deviceID, token).Scan(&state); err != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}
	if state != models.DeviceStateAtivo {
		writeErr(w, http.StatusForbidden, "dispositivo não está ativo")
		return
	}
	conn, err := controlUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE diagnostic_runs SET status='failed',error='execução interrompida',
			finished_at=now()
		WHERE device_id=$1 AND status='running'
		  AND started_at < now()-interval '15 minutes'`, deviceID)
	branding, brandSignature := s.deviceBranding(r.Context(), deviceID)
	_ = conn.WriteJSON(map[string]any{
		"type": "ready", "state": state,
		"version": os.Getenv("CLIENT_VERSION"),
		"payload": map[string]any{"branding": branding},
	})

	for {
		_ = conn.SetReadDeadline(time.Now().Add(45 * time.Second))
		var msg controlMessage
		if err := conn.ReadJSON(&msg); err != nil {
			_ = presence.Clear(context.Background(), s.RDB, deviceID)
			_ = presence.Publish(context.Background(), s.RDB,
				presence.Event{Type: "presence", TargetID: deviceID,
					Payload: map[string]any{"presence": "offline"}})
			return
		}
		switch msg.Type {
		case "heartbeat":
			var capabilities presence.Capabilities
			_ = json.Unmarshal(msg.Payload, &capabilities)
			if err := s.Pool.QueryRow(r.Context(),
				`SELECT state FROM devices WHERE id=$1`, deviceID).Scan(&state); err != nil {
				return
			}
			_, _ = s.Pool.Exec(r.Context(),
				`UPDATE devices SET last_seen_at=now() WHERE id=$1`, deviceID)
			_ = presence.Heartbeat(r.Context(), s.RDB, deviceID)
			_ = presence.SetCapabilities(r.Context(), s.RDB, deviceID, capabilities)
			_ = presence.Publish(r.Context(), s.RDB,
				presence.Event{Type: "presence", TargetID: deviceID,
					Payload: map[string]any{
						"presence":     "online",
						"remote_ready": capabilities.RemoteReady,
						"files_ready":  capabilities.FilesReady,
					}})
			_ = conn.WriteJSON(map[string]any{
				"type": "heartbeat_ack", "state": state,
				"version": os.Getenv("CLIENT_VERSION"),
			})
			if latestBranding, latestSignature := s.deviceBranding(r.Context(), deviceID); brandingChanged(brandSignature, latestSignature) {
				brandSignature = latestSignature
				_ = conn.WriteJSON(map[string]any{
					"type": "branding", "payload": latestBranding,
				})
			}
			var cancelledRunID string
			if s.Pool.QueryRow(r.Context(), `
				SELECT id FROM diagnostic_runs
				WHERE device_id=$1 AND status='cancelled'
				  AND started_at IS NOT NULL AND finished_at IS NULL
				ORDER BY created_at LIMIT 1`, deviceID).Scan(&cancelledRunID) == nil {
				_ = conn.WriteJSON(map[string]any{
					"type": "diagnostic_cancel", "id": cancelledRunID,
				})
			}
			var runID string
			var tests []byte
			if s.Pool.QueryRow(r.Context(), `
				WITH next AS (
					SELECT id FROM diagnostic_runs
					WHERE device_id=$1 AND status='queued'
					  AND NOT EXISTS (
						SELECT 1 FROM diagnostic_runs active
						WHERE active.device_id=$1 AND active.status='running'
					  )
					ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED
				)
				UPDATE diagnostic_runs d SET status='running',started_at=now()
				FROM next WHERE d.id=next.id
				RETURNING d.id,d.tests`, deviceID).Scan(&runID, &tests) == nil {
				var selected []string
				_ = json.Unmarshal(tests, &selected)
				if len(selected) == 1 {
					_ = conn.WriteJSON(map[string]any{
						"type": "diagnostic_run", "id": runID,
						"payload": map[string]any{"test": selected[0]},
					})
				}
			}
			if state != models.DeviceStateAtivo {
				return
			}
		case "telemetry":
			var payload struct {
				Hardware any `json:"hardware"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil {
				_, _ = s.Pool.Exec(r.Context(), `
					WITH inserted AS (
						INSERT INTO telemetry_snapshots (device_id,hardware)
						VALUES ($1,$2)
						RETURNING 1
					)
					DELETE FROM telemetry_snapshots
					WHERE coletado_em < now()-interval '30 days'`,
					deviceID, payload.Hardware)
				stats := s.hardwareStatistics(r.Context(), deviceID)
				_ = conn.WriteJSON(map[string]any{"type": "telemetry_stats", "payload": stats})
				_ = presence.Publish(r.Context(), s.RDB,
					presence.Event{Type: "telemetry", TargetID: deviceID, Payload: map[string]any{
						"hardware": payload.Hardware, "statistics": stats,
						"collected_at": time.Now().UTC().Format(time.RFC3339),
					}})
			}
		case "rustdesk_status":
			var payload struct {
				ID string `json:"rustdesk_id"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && payload.ID != "" {
				_, _ = s.Pool.Exec(r.Context(),
					`UPDATE devices SET rustdesk_id=$1,updated_at=now() WHERE id=$2`,
					payload.ID, deviceID)
			}
		case "diagnostic_progress":
			var payload struct {
				Progress int    `json:"progress"`
				Test     string `json:"test"`
				Message  string `json:"message"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && msg.ID != "" {
				_, _ = s.Pool.Exec(r.Context(), `
					UPDATE diagnostic_runs SET progress=$1,current_test=$2
					WHERE id=$3 AND device_id=$4 AND status='running'`,
					payload.Progress, payload.Test, msg.ID, deviceID)
				_ = presence.Publish(r.Context(), s.RDB, presence.Event{
					Type: "diagnostic_progress", TargetID: deviceID,
					Payload: map[string]any{"id": msg.ID, "status": "running",
						"progress": payload.Progress, "test": payload.Test, "message": payload.Message},
				})
			}
		case "diagnostic_result":
			var payload struct {
				Status  string `json:"status"`
				Results any    `json:"results"`
				Error   string `json:"error"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && msg.ID != "" {
				status := payload.Status
				if status != "completed" && status != "failed" && status != "cancelled" {
					status = "failed"
				}
				_, _ = s.Pool.Exec(r.Context(), `
					UPDATE diagnostic_runs SET status=$1,progress=100,results=$2,
						error=$3,finished_at=now()
					WHERE id=$4 AND device_id=$5 AND status IN ('running','cancelled')`,
					status, payload.Results, payload.Error, msg.ID, deviceID)
				_ = presence.Publish(r.Context(), s.RDB, presence.Event{
					Type: "diagnostic_result", TargetID: deviceID,
					Payload: map[string]any{"id": msg.ID, "status": status,
						"progress": 100, "results": payload.Results, "error": payload.Error},
				})
			}
		}
	}
}

func (s *Server) TechnicianControlWS(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErr(w, http.StatusForbidden, "canal de controle disponível somente pela VPN")
		return
	}
	token := r.URL.Query().Get("token")
	if token == "" {
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
	}
	conn, err := controlUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	var writeMu sync.Mutex
	write := func(value any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(value)
	}

	if token == "" {
		_ = conn.SetReadDeadline(time.Now().Add(15 * time.Second))
		var authMessage controlMessage
		if conn.ReadJSON(&authMessage) != nil || authMessage.Type != "authenticate" {
			_ = write(map[string]any{"type": "auth_result", "status": http.StatusUnauthorized,
				"error": "credencial de controle ausente"})
			return
		}
		req := httptest.NewRequest(http.MethodPost,
			"http://10.70.0.1/api/v1/auth/technician/refresh",
			bytes.NewReader(authMessage.Payload))
		req.RemoteAddr = "10.70.1.1:1"
		rec := httptest.NewRecorder()
		s.RefreshTechnicianMachine(rec, req)
		var response map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &response)
		if rec.Code != http.StatusOK {
			_ = write(map[string]any{"type": "auth_result", "status": rec.Code,
				"error": response["error"]})
			return
		}
		token, _ = response["token"].(string)
		if err := write(map[string]any{"type": "auth_result", "status": rec.Code,
			"payload": response}); err != nil {
			return
		}
	}
	claims, err := tgauth.ParseToken(s.Cfg.JWTSecret, token)
	if err != nil {
		_ = write(map[string]any{"type": "auth_result", "status": http.StatusUnauthorized,
			"error": "token inválido"})
		return
	}
	_ = conn.SetReadDeadline(time.Time{})
	if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
		_ = write(snapshot)
	}

	sub := presence.Subscribe(r.Context(), s.RDB)
	defer sub.Close()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			var msg controlMessage
			if conn.ReadJSON(&msg) != nil {
				return
			}
			if msg.Type != "rpc" || msg.ID == "" || !privateRPCPath(msg.Path) {
				continue
			}
			req := httptest.NewRequest(msg.Method, "http://10.70.0.1"+msg.Path,
				bytes.NewReader(msg.Payload))
			req.RemoteAddr = "10.70.1.1:1"
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			NewRouter(s).ServeHTTP(rec, req)
			var payload any
			if rec.Body.Len() != 0 {
				if json.Unmarshal(rec.Body.Bytes(), &payload) != nil {
					payload = rec.Body.String()
				}
			}
			if write(map[string]any{"type": "rpc_response", "id": msg.ID,
				"status": rec.Code, "payload": payload}) != nil {
				return
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case message, ok := <-sub.Channel():
			if !ok {
				return
			}
			var evt presence.Event
			if json.Unmarshal([]byte(message.Payload), &evt) != nil {
				continue
			}
			if claims.Role != models.RoleSuperAdmin &&
				!s.eventVisibleTo(r.Context(), claims, evt) {
				continue
			}
			if evt.Type == "suspend_technician" &&
				evt.TargetID == claims.TechnicianID {
				_ = write(map[string]any{"type": "session_revoked"})
				return
			}
			if err := write(map[string]any{"type": "event", "event": evt}); err != nil {
				return
			}
			if evt.Type != "presence" && evt.Type != "telemetry" {
				if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
					if write(snapshot) != nil {
						return
					}
				}
			}
		}
	}
}

func privateRPCPath(path string) bool {
	for _, prefix := range []string{
		"/api/v1/pairing/", "/api/v1/devices", "/api/v1/organizations",
		"/api/v1/networks", "/api/v1/subnetworks", "/api/v1/technicians", "/api/v1/branding/",
		"/api/v1/admin/",
		"/api/v1/support/",
	} {
		if path == strings.TrimSuffix(prefix, "/") || strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

// PairingContext expõe publicamente apenas os dados mínimos necessários para
// consumir um código de pareamento antes do túnel do Técnico estar pronto.
func (s *Server) PairingContext(w http.ResponseWriter, r *http.Request) {
	// Usa as mesmas claims instaladas pelo middleware e o mesmo filtro do
	// snapshot; dispositivos e telemetria não fazem parte deste bootstrap.
	authClaims := middleware.ClaimsFrom(r.Context())
	snapshot, err := s.controlSnapshot(r.Context(), authClaims.TechnicianID, authClaims.Role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao carregar redes de pareamento")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"organizations": snapshot["organizations"],
		"networks":      snapshot["networks"],
		"subnetworks":   snapshot["subnetworks"],
	})
}

func (s *Server) controlSnapshot(ctx context.Context, technicianID, role string) (map[string]any, error) {
	orgQuery := `SELECT id,name,status,owner_technician_id,created_at FROM organizations ORDER BY created_at`
	netQuery := `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_by_technician_id,created_at FROM networks ORDER BY created_at`
	subnetQuery := `SELECT id,network_id,name,status,created_by_technician_id,created_at FROM subnetworks ORDER BY created_at`
	devQuery := `SELECT d.id,d.network_id,coalesce((SELECT array_agg(dn.network_id::text ORDER BY dn.created_at) FROM device_networks dn WHERE dn.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d ORDER BY d.created_at DESC`
	args := []any{}
	if role != models.RoleSuperAdmin {
		args = []any{technicianID}
		orgQuery = `SELECT DISTINCT o.id,o.name,o.status,o.owner_technician_id,o.created_at FROM organizations o LEFT JOIN networks n ON n.organization_id=o.id WHERE o.owner_technician_id=$1 OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY o.created_at`
		netQuery = `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_by_technician_id,created_at FROM networks WHERE organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY created_at`
		subnetQuery = `SELECT s.id,s.network_id,s.name,s.status,s.created_by_technician_id,s.created_at FROM subnetworks s JOIN networks n ON n.id=s.network_id WHERE n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY s.created_at`
		devQuery = `SELECT DISTINCT d.id,d.network_id,coalesce((SELECT array_agg(dn2.network_id::text ORDER BY dn2.created_at) FROM device_networks dn2 WHERE dn2.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d JOIN device_networks dn ON dn.device_id=d.id JOIN networks n ON dn.network_id=n.id WHERE n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY d.created_at DESC`
	}
	orgs := []models.Organization{}
	rows, err := s.Pool.Query(ctx, orgQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var o models.Organization
		if rows.Scan(&o.ID, &o.Name, &o.Status, &o.OwnerTechnicianID, &o.CreatedAt) == nil {
			o.CanManage = role == models.RoleSuperAdmin ||
				(o.OwnerTechnicianID != nil && *o.OwnerTechnicianID == technicianID)
			orgs = append(orgs, o)
		}
	}
	rows.Close()
	nets := []models.Network{}
	rows, err = s.Pool.Query(ctx, netQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var n models.Network
		if rows.Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedBy, &n.CreatedAt) == nil {
			n.CanManage = role == models.RoleSuperAdmin
			if !n.CanManage {
				_ = s.Pool.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM organizations
						WHERE id=$1 AND owner_technician_id=$2)`,
					n.OrganizationID, technicianID).Scan(&n.CanManage)
			}
			nets = append(nets, n)
		}
	}
	rows.Close()
	subnets := []models.Subnetwork{}
	rows, err = s.Pool.Query(ctx, subnetQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var sn models.Subnetwork
		if rows.Scan(&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt) == nil {
			sn.CanManage = role == models.RoleSuperAdmin
			if !sn.CanManage {
				_ = s.Pool.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM subnetworks s
						JOIN networks n ON n.id=s.network_id
						JOIN organizations o ON o.id=n.organization_id
						WHERE s.id=$1 AND o.owner_technician_id=$2)`,
					sn.ID, technicianID).Scan(&sn.CanManage)
			}
			subnets = append(subnets, sn)
		}
	}
	rows.Close()
	devices := []models.Device{}
	rows, err = s.Pool.Query(ctx, devQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var d models.Device
		if rows.Scan(&d.ID, &d.NetworkID, &d.NetworkIDs, &d.SubnetworkID, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey, &d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt, &d.RustdeskID) == nil {
			if d.State == models.DeviceStateAtivo && presence.IsOnline(ctx, s.RDB, d.ID) {
				d.Presence = "online"
			} else if d.State == models.DeviceStateAtivo {
				d.Presence = "offline"
			} else {
				d.Presence = d.State
			}
			capabilities := presence.GetCapabilities(ctx, s.RDB, d.ID)
			d.RemoteReady = capabilities.RemoteReady
			d.FilesReady = capabilities.FilesReady
			d.HealthLevel, _ = s.recentHardwareHealth(ctx, d.ID)["level"].(string)
			devices = append(devices, d)
		}
	}
	rows.Close()
	return map[string]any{"type": "snapshot", "organizations": orgs, "networks": nets, "subnetworks": subnets, "devices": devices}, nil
}
