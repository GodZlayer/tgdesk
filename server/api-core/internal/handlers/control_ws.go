package handlers

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"strings"
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
	_ = conn.WriteJSON(map[string]any{"type": "ready", "state": state})

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
			if err := s.Pool.QueryRow(r.Context(),
				`SELECT state FROM devices WHERE id=$1`, deviceID).Scan(&state); err != nil {
				return
			}
			_, _ = s.Pool.Exec(r.Context(),
				`UPDATE devices SET last_seen_at=now() WHERE id=$1`, deviceID)
			_ = presence.Heartbeat(r.Context(), s.RDB, deviceID)
			_ = presence.Publish(r.Context(), s.RDB,
				presence.Event{Type: "presence", TargetID: deviceID,
					Payload: map[string]any{"presence": "online"}})
			_ = conn.WriteJSON(map[string]any{"type": "heartbeat_ack", "state": state})
			if state != models.DeviceStateAtivo {
				return
			}
		case "telemetry":
			var payload struct {
				CPU   float64 `json:"cpu"`
				Mem   float64 `json:"mem"`
				Disco float64 `json:"disco"`
				Temp  float64 `json:"temp"`
				Disks any     `json:"disks"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil {
				_, _ = s.Pool.Exec(r.Context(), `
					INSERT INTO telemetry_snapshots (device_id,cpu,mem,disco,temp,disks)
					VALUES ($1,$2,$3,$4,$5,$6)`,
					deviceID, payload.CPU, payload.Mem, payload.Disco, payload.Temp, payload.Disks)
				_ = presence.Publish(r.Context(), s.RDB,
					presence.Event{Type: "telemetry", TargetID: deviceID, Payload: payload})
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
	claims, err := tgauth.ParseToken(s.Cfg.JWTSecret, token)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "token inválido")
		return
	}
	conn, err := controlUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
		_ = conn.WriteJSON(snapshot)
	}

	sub := presence.Subscribe(r.Context(), s.RDB)
	defer sub.Close()
	for msg := range sub.Channel() {
		var evt presence.Event
		if json.Unmarshal([]byte(msg.Payload), &evt) != nil {
			continue
		}
		if claims.Role != models.RoleSuperAdmin &&
			!s.eventVisibleTo(r.Context(), claims.TechnicianID, evt) {
			continue
		}
		if err := conn.WriteJSON(map[string]any{"type": "event", "event": evt}); err != nil {
			return
		}
		if evt.Type != "presence" && evt.Type != "telemetry" {
			if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
				if conn.WriteJSON(snapshot) != nil {
					return
				}
			}
		}
	}
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
	})
}

func (s *Server) controlSnapshot(ctx context.Context, technicianID, role string) (map[string]any, error) {
	orgQuery := `SELECT id,name,status,created_at FROM organizations ORDER BY created_at`
	netQuery := `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_at FROM networks ORDER BY created_at`
	devQuery := `SELECT id,network_id,hostname,coalesce(mac,''),coalesce(wg_pubkey,''),role,state,last_seen_at,created_at,updated_at,coalesce(rustdesk_id,'') FROM devices ORDER BY created_at DESC`
	args := []any{}
	if role != models.RoleSuperAdmin {
		args = []any{technicianID}
		orgQuery = `SELECT DISTINCT o.id,o.name,o.status,o.created_at FROM organizations o LEFT JOIN networks n ON n.organization_id=o.id WHERE o.id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY o.created_at`
		netQuery = `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_at FROM networks WHERE organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL) OR id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY created_at`
		devQuery = `SELECT d.id,d.network_id,d.hostname,coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d JOIN networks n ON d.network_id=n.id WHERE n.organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY d.created_at DESC`
	}
	orgs := []models.Organization{}
	rows, err := s.Pool.Query(ctx, orgQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var o models.Organization
		if rows.Scan(&o.ID, &o.Name, &o.Status, &o.CreatedAt) == nil {
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
		if rows.Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedAt) == nil {
			nets = append(nets, n)
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
		if rows.Scan(&d.ID, &d.NetworkID, &d.Hostname, &d.MAC, &d.WGPubkey, &d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt, &d.RustdeskID) == nil {
			if d.State == models.DeviceStateAtivo && presence.IsOnline(ctx, s.RDB, d.ID) {
				d.Presence = "online"
			} else if d.State == models.DeviceStateAtivo {
				d.Presence = "offline"
			} else {
				d.Presence = d.State
			}
			devices = append(devices, d)
		}
	}
	rows.Close()
	return map[string]any{"type": "snapshot", "organizations": orgs, "networks": nets, "devices": devices}, nil
}
