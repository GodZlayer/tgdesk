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

// dropHubPeer removes a linked device from the private network immediately.
func (s *Server) dropHubPeer(deviceID string) {
	if s.Hub == nil {
		return
	}
	var pubkey *string
	if err := s.Pool.QueryRow(context.Background(), `SELECT wg_pubkey FROM devices WHERE id=$1`, deviceID).Scan(&pubkey); err != nil {
		return
	}
	s.removeHubPeerKey(pubkey)
}

func (s *Server) removeHubPeerKey(pubkey *string) {
	if s.Hub != nil && pubkey != nil && *pubkey != "" {
		_ = s.Hub.RemovePeer(*pubkey)
	}
}

func (s *Server) canManageNetwork(r *http.Request, networkID string) bool {
	claims := middleware.ClaimsFrom(r.Context())
	if claims.Role == models.RoleSuperAdmin {
		return true
	}
	var ownerID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT o.owner_technician_id FROM networks n
		 JOIN organizations o ON o.id=n.organization_id WHERE n.id=$1`,
		networkID).Scan(&ownerID) != nil {
		return false
	}
	return ownerID != nil && *ownerID == claims.TechnicianID
}

// dropTechnicianHubPeer removes the technician's own private-network identity.
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

// SuspendTechnician suspends the account and cascades through its personal
// organization, networks and linked devices.
func (s *Server) SuspendTechnician(w http.ResponseWriter, r *http.Request, id string) {
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar suspensão do técnico")
		return
	}
	defer tx.Rollback(r.Context())
	tag, err := tx.Exec(r.Context(),
		`UPDATE technicians SET status='suspenso' WHERE id=$1`, id)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	_, _ = tx.Exec(r.Context(),
		`UPDATE sessions SET fim=now() WHERE technician_id=$1 AND fim IS NULL`, id)
	_, _ = tx.Exec(r.Context(), `
		UPDATE technician_machine_credentials
		SET status='revogado',last_used_at=now()
		WHERE technician_id=$1 AND status='ativo'`, id)
	_, _ = tx.Exec(r.Context(), `
		UPDATE organizations SET status='suspensa',suspension_scope='technician'
		WHERE owner_technician_id=$1 AND status='ativa'`, id)
	_, _ = tx.Exec(r.Context(), `
		UPDATE networks SET status='suspensa',suspension_scope='technician'
		WHERE organization_id IN
			(SELECT id FROM organizations WHERE owner_technician_id=$1)
		  AND status='ativa'`, id)
	rows, err := tx.Query(r.Context(), `
		UPDATE devices SET state='suspenso',suspension_scope='technician',updated_at=now()
		WHERE state='ativo' AND EXISTS (
			SELECT 1 FROM device_networks dn
			JOIN networks n ON n.id=dn.network_id
			JOIN organizations o ON o.id=n.organization_id
			WHERE dn.device_id=devices.id AND o.owner_technician_id=$1)
		RETURNING id`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender dispositivos do técnico")
		return
	}
	var deviceIDs []string
	for rows.Next() {
		var deviceID string
		if rows.Scan(&deviceID) == nil {
			deviceIDs = append(deviceIDs, deviceID)
		}
	}
	rows.Close()
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir suspensão do técnico")
		return
	}
	for _, deviceID := range deviceIDs {
		_ = presence.Clear(r.Context(), s.RDB, deviceID)
		s.dropHubPeer(deviceID)
	}
	s.dropTechnicianHubPeer(id)
	s.audit(r, "suspender_supervisor", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "suspend_technician", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]string{
		"status": "suspenso", "devices_afetados": itoa(len(deviceIDs)),
	})
}

// SuspendDevice preserves the link but stops connectivity and monitoring.
func (s *Server) SuspendDevice(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE devices SET state='suspenso',
		suspension_scope='device', updated_at=now() WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender dispositivo")
		return
	}
	_ = presence.Clear(r.Context(), s.RDB, id)
	s.dropHubPeer(id)
	s.audit(r, "suspender_dispositivo", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "suspend_device", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"state": "suspenso"})
}

// SuspendNetwork suspends every active device belonging to the network.
func (s *Server) SuspendNetwork(w http.ResponseWriter, r *http.Request, id string) {
	if s.protectedSystemNetwork(r.Context(), id) {
		writeErr(w, http.StatusConflict, "rede obrigatoria TGDevs permanece sempre ativa")
		return
	}
	claims := middleware.ClaimsFrom(r.Context())
	allowed, err := s.Authorizer.CanManageNetwork(r.Context(), claims, id)
	if err != nil || !allowed {
		writeErr(w, http.StatusForbidden, "somente o criador da rede pode suspende-la")
		return
	}
	if _, err := s.Pool.Exec(r.Context(), `UPDATE networks SET status='suspensa',
		suspension_scope='network' WHERE id=$1 AND status='ativa'`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender rede")
		return
	}
	rows, _ := s.Pool.Query(r.Context(), `UPDATE devices SET state='suspenso',
		suspension_scope='network', updated_at=now()
		WHERE state='ativo' AND EXISTS (
			SELECT 1 FROM device_networks dn
			WHERE dn.device_id=devices.id AND dn.network_id=$1)
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
	s.audit(r, "suspender_rede", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "suspend_network", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]string{"status": "suspensa", "devices_afetados": itoa(len(deviceIDs))})
}

// SuspendOrganization cascades suspension across its active networks and devices.
func (s *Server) SuspendOrganization(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `UPDATE organizations SET status='suspensa',
		suspension_scope='organization' WHERE id=$1 AND status='ativa'`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender organização")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE networks SET status='suspensa',
		suspension_scope='organization'
		WHERE organization_id=$1 AND status='ativa'`, id)
	rows, _ := s.Pool.Query(r.Context(), `
		UPDATE devices SET state='suspenso', suspension_scope='organization', updated_at=now()
		WHERE state='ativo' AND EXISTS (
			SELECT 1 FROM device_networks dn JOIN networks n ON n.id=dn.network_id
			WHERE dn.device_id=devices.id AND n.organization_id=$1)
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
	s.audit(r, "suspender_organizacao", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "suspend_organization", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]string{"status": "suspensa", "devices_afetados": itoa(len(deviceIDs))})
}

func (s *Server) ResumeDevice(w http.ResponseWriter, r *http.Request, id string) {
	var networkStatus, organizationStatus string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.status,o.status FROM devices d JOIN networks n ON n.id=d.network_id
		JOIN organizations o ON o.id=n.organization_id WHERE d.id=$1`, id).
		Scan(&networkStatus, &organizationStatus); err != nil {
		writeErr(w, http.StatusNotFound, "dispositivo não encontrado")
		return
	}
	if networkStatus != "ativa" || organizationStatus != "ativa" {
		writeErr(w, http.StatusConflict, "reative primeiro a organização e a rede")
		return
	}
	_, err := s.Pool.Exec(r.Context(), `UPDATE devices SET state='ativo',
		suspension_scope=NULL,updated_at=now() WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao reativar dispositivo")
		return
	}
	s.audit(r, "reativar_dispositivo", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "resume_device", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"state": "ativo"})
}

func (s *Server) ResumeTechnician(w http.ResponseWriter, r *http.Request, id string) {
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar reativação do técnico")
		return
	}
	defer tx.Rollback(r.Context())
	tag, err := tx.Exec(r.Context(),
		`UPDATE technicians SET status='ativo' WHERE id=$1`, id)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	_, _ = tx.Exec(r.Context(), `
		UPDATE organizations SET status='ativa',suspension_scope=NULL
		WHERE owner_technician_id=$1 AND suspension_scope='technician'`, id)
	_, _ = tx.Exec(r.Context(), `
		UPDATE networks SET status='ativa',suspension_scope=NULL
		WHERE organization_id IN
			(SELECT id FROM organizations WHERE owner_technician_id=$1)
		  AND suspension_scope='technician'`, id)
	_, _ = tx.Exec(r.Context(), `
		UPDATE devices SET state='ativo',suspension_scope=NULL,updated_at=now()
		WHERE suspension_scope='technician' AND EXISTS (
			SELECT 1 FROM device_networks dn
			JOIN networks n ON n.id=dn.network_id
			JOIN organizations o ON o.id=n.organization_id
			WHERE dn.device_id=devices.id AND o.owner_technician_id=$1)`, id)
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir reativação do técnico")
		return
	}
	s.audit(r, "reativar_supervisor", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "resume_technician", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ativo"})
}

func (s *Server) ResumeNetwork(w http.ResponseWriter, r *http.Request, id string) {
	if s.protectedSystemNetwork(r.Context(), id) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ativa"})
		return
	}
	claims := middleware.ClaimsFrom(r.Context())
	allowed, err := s.Authorizer.CanManageNetwork(r.Context(), claims, id)
	if err != nil || !allowed {
		writeErr(w, http.StatusForbidden, "somente o criador da rede pode reativa-la")
		return
	}
	var organizationStatus string
	if err := s.Pool.QueryRow(r.Context(), `SELECT o.status FROM networks n
		JOIN organizations o ON o.id=n.organization_id WHERE n.id=$1`, id).
		Scan(&organizationStatus); err != nil {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}
	if organizationStatus != "ativa" {
		writeErr(w, http.StatusConflict, "reative primeiro a organização")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE networks SET status='ativa',
		suspension_scope=NULL WHERE id=$1`, id)
	_, _ = s.Pool.Exec(r.Context(), `UPDATE devices SET state='ativo',
		suspension_scope=NULL,updated_at=now()
		WHERE suspension_scope='network' AND EXISTS (
			SELECT 1 FROM device_networks dn
			WHERE dn.device_id=devices.id AND dn.network_id=$1)`, id)
	s.audit(r, "reativar_rede", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "resume_network", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ativa"})
}

func (s *Server) ResumeOrganization(w http.ResponseWriter, r *http.Request, id string) {
	var ownerStatus string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT coalesce(t.status,'ativo') FROM organizations o
		LEFT JOIN technicians t ON t.id=o.owner_technician_id
		WHERE o.id=$1`, id).Scan(&ownerStatus); err != nil {
		writeErr(w, http.StatusNotFound, "organização não encontrada")
		return
	}
	if ownerStatus != "ativo" {
		writeErr(w, http.StatusConflict, "reative primeiro o técnico responsável")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `UPDATE organizations SET status='ativa',
		suspension_scope=NULL WHERE id=$1`, id)
	_, _ = s.Pool.Exec(r.Context(), `UPDATE networks SET status='ativa',
		suspension_scope=NULL WHERE organization_id=$1 AND suspension_scope='organization'`, id)
	_, _ = s.Pool.Exec(r.Context(), `UPDATE devices SET state='ativo',
		suspension_scope=NULL,updated_at=now()
		WHERE suspension_scope='organization' AND EXISTS (
			SELECT 1 FROM device_networks dn JOIN networks n ON n.id=dn.network_id
			WHERE dn.device_id=devices.id AND n.organization_id=$1)`, id)
	s.audit(r, "reativar_organizacao", id)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "resume_organization", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ativa"})
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
