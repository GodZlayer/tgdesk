package handlers

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"

	"github.com/gorilla/websocket"

	tgauth "tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// PresenceWS streams real-time presence/suspension/bind events to the connected
// technician, filtered by their organization/network scope (Seção 3.1/3.4).
func (s *Server) PresenceWS(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErr(w, http.StatusForbidden, "presença disponível somente pela VPN")
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
		http.Error(w, "token inválido", http.StatusUnauthorized)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("ws upgrade error: %v", err)
		return
	}
	defer conn.Close()

	sub := presence.Subscribe(r.Context(), s.RDB)
	defer sub.Close()
	ch := sub.Channel()

	// pump close detection: read (and discard) client frames so we notice disconnects.
	go func() {
		for {
			if _, _, err := conn.NextReader(); err != nil {
				sub.Close()
				return
			}
		}
	}()

	for msg := range ch {
		var evt presence.Event
		if err := json.Unmarshal([]byte(msg.Payload), &evt); err != nil {
			continue
		}
		if claims.Role != models.RoleSuperAdmin && !s.eventVisibleTo(r.Context(), claims.TechnicianID, evt) {
			continue
		}
		if err := conn.WriteJSON(evt); err != nil {
			return
		}
	}
}

// eventVisibleTo resolves the event's device (directly, or via its network for
// network/organization-level events) and checks it against technician_assignments.
func (s *Server) eventVisibleTo(ctx context.Context, technicianID string, evt presence.Event) bool {
	switch evt.Type {
	case "presence", "telemetry", "bind", "suspend_device", "resume_device", "device_renamed":
		var orgID, netID string
		err := s.Pool.QueryRow(ctx, `
			SELECT n.organization_id, n.id FROM devices d
			JOIN networks n ON d.network_id = n.id
			WHERE d.id = $1`, evt.TargetID).Scan(&orgID, &netID)
		if err != nil {
			return false
		}
		ok, _ := s.technicianCanAccess(ctx, technicianID, orgID, netID)
		return ok
	case "suspend_network", "resume_network":
		ok, _ := s.technicianCanAccess(ctx, technicianID, "", evt.TargetID)
		return ok
	case "suspend_organization", "resume_organization":
		ok, _ := s.technicianCanAccess(ctx, technicianID, evt.TargetID, "")
		return ok
	default:
		return false
	}
}
