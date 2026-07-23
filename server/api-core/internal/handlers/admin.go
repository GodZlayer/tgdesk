package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

func (s *Server) audit(r *http.Request, tipo, alvoID string) {
	claims := middleware.ClaimsFrom(r.Context())
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO admin_actions (actor_id, tipo, alvo_id) VALUES ($1, $2, $3)`,
		claims.TechnicianID, tipo, alvoID)
}

// dropHubPeer is the real network-layer kill-switch: if the device already
// joined the WireGuard mesh, its peer is removed from the hub immediately,
// so its tunnel dies even if the agent process keeps running.
func (s *Server) dropHubPeer(deviceID string) {
	if s.Hub == nil {
		return
	}
	var pubkey *string
	if err := s.Pool.QueryRow(context.Background(), `SELECT wg_pubkey FROM devices WHERE id=$1`, deviceID).Scan(&pubkey); err != nil {
		return
	}
	if pubkey != nil && *pubkey != "" {
		_ = s.Hub.RemovePeer(*pubkey)
	}
}

// dropTechnicianHubPeer mirrors dropHubPeer but for the technician's own
// tunnel identity (Seção 3.4 kill-switch de técnico agora também é real na
// camada de rede, não só bloqueia login).
func (s *Server) dropTechnicianHubPeer(technicianID string) {
	if s.Hub == nil {
		return
	}
	var pubkey *string
	if err := s.Pool.QueryRow(context.Background(), `SELECT wg_pubkey FROM technicians WHERE id=$1`, technicianID).Scan(&pubkey); err != nil {
		return
	}
	if pubkey != nil && *pubkey != "" {
		_ = s.Hub.RemovePeer(*pubkey)
	}
}

// KillTechnician suspends the account and force-ends its active sessions.
func (s *Server) KillTechnician(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE technicians SET status='suspenso' WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender técnico")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE sessions SET fim=now() WHERE technician_id=$1 AND fim IS NULL`, id)
	s.dropTechnicianHubPeer(id)
	s.audit(r, "kill_switch_tecnico", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "kill_technician", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"status": "suspenso"})
}

// KillDevice drops the device back to a de-activated state: tunnel/sessions must stop, no new session accepted.
func (s *Server) KillDevice(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE devices SET state='suspenso', updated_at=now() WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender dispositivo")
		return
	}
	_ = presence.Clear(r.Context(), s.RDB, id)
	s.dropHubPeer(id)
	s.audit(r, "kill_switch_dispositivo", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "kill_device", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"state": "suspenso"})
}

// KillNetwork suspends every device belonging to the network.
func (s *Server) KillNetwork(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE networks SET status='suspensa' WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender rede")
		return
	}
	rows, _ := s.Pool.Query(r.Context(), `UPDATE devices SET state='suspenso', updated_at=now() WHERE network_id=$1 AND state='ativo' RETURNING id`, id)
	var deviceIDs []string
	for rows.Next() {
		var did string
		if err := rows.Scan(&did); err == nil {
			deviceIDs = append(deviceIDs, did)
		}
	}
	rows.Close()
	for _, did := range deviceIDs {
		_ = presence.Clear(r.Context(), s.RDB, did)
		s.dropHubPeer(did)
	}
	s.audit(r, "kill_switch_rede", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "kill_network", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]string{"status": "suspensa", "devices_afetados": itoa(len(deviceIDs))})
}

// KillOrganization cascades suspension across every network and device of the organization.
func (s *Server) KillOrganization(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE organizations SET status='suspensa' WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender organização")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE networks SET status='suspensa' WHERE organization_id=$1`, id)
	rows, _ := s.Pool.Query(r.Context(), `
		UPDATE devices SET state='suspenso', updated_at=now()
		WHERE state='ativo' AND network_id IN (SELECT id FROM networks WHERE organization_id=$1)
		RETURNING id`, id)
	var deviceIDs []string
	for rows.Next() {
		var did string
		if err := rows.Scan(&did); err == nil {
			deviceIDs = append(deviceIDs, did)
		}
	}
	rows.Close()
	for _, did := range deviceIDs {
		_ = presence.Clear(r.Context(), s.RDB, did)
		s.dropHubPeer(did)
	}
	s.audit(r, "kill_switch_organizacao", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "kill_organization", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]string{"status": "suspensa", "devices_afetados": itoa(len(deviceIDs))})
}

func (s *Server) ListAuditLog(w http.ResponseWriter, r *http.Request) {
	rs, err := s.Pool.Query(r.Context(), `
		SELECT id, actor_id, tipo, alvo_id, timestamp FROM admin_actions ORDER BY timestamp DESC LIMIT 500`)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar auditoria")
		return
	}
	defer rs.Close()

	actions := []models.AdminAction{}
	for rs.Next() {
		var a models.AdminAction
		if err := rs.Scan(&a.ID, &a.ActorID, &a.Tipo, &a.AlvoID, &a.Timestamp); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler auditoria")
			return
		}
		actions = append(actions, a)
	}
	writeJSON(w, http.StatusOK, actions)
}

func itoa(n int) string {
	b, _ := json.Marshal(n)
	return string(b)
}
