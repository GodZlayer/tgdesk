package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

type createSubnetworkRequest struct {
	NetworkID string `json:"network_id"`
	Name      string `json:"name"`
}

func (s *Server) CreateSubnetwork(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	var req createSubnetworkRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "network_id e name são obrigatórios")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.NetworkID == "" || req.Name == "" || len([]rune(req.Name)) > 80 {
		writeErr(w, http.StatusBadRequest, "dados da sub-rede inválidos")
		return
	}
	if claims.Role != models.RoleSuperAdmin {
		var allowed bool
		err := s.Pool.QueryRow(r.Context(), `
			SELECT EXISTS(
				SELECT 1 FROM networks n JOIN organizations o ON o.id=n.organization_id
				WHERE n.id=$1 AND o.owner_technician_id=$2
			)`, req.NetworkID, claims.TechnicianID).Scan(&allowed)
		if err != nil || !allowed {
			writeErr(w, http.StatusForbidden, "sub-redes só podem ser criadas na sua organização")
			return
		}
	}
	var sn models.Subnetwork
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO subnetworks(network_id,name,created_by_technician_id)
		VALUES ($1,$2,$3)
		RETURNING id,network_id,name,status,created_by_technician_id,created_at`,
		req.NetworkID, req.Name, claims.TechnicianID).
		Scan(&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "sub-rede já existe ou dados inválidos")
		return
	}
	sn.CanManage = true
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "subnetwork_created", TargetID: sn.ID})
	writeJSON(w, http.StatusCreated, sn)
}

func (s *Server) ListSubnetworks(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	query := `SELECT s.id,s.network_id,s.name,s.status,s.created_by_technician_id,s.created_at
		FROM subnetworks s ORDER BY s.created_at`
	args := []any{}
	if claims.Role != models.RoleSuperAdmin {
		query = `SELECT s.id,s.network_id,s.name,s.status,s.created_by_technician_id,s.created_at
			FROM subnetworks s JOIN networks n ON n.id=s.network_id
			WHERE n.organization_id IN (
				SELECT id FROM organizations WHERE owner_technician_id=$1
			) OR n.id IN (
				SELECT network_id FROM technician_assignments
				WHERE technician_id=$1 AND network_id IS NOT NULL
			) ORDER BY s.created_at`
		args = append(args, claims.TechnicianID)
	}
	rows, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar sub-redes")
		return
	}
	defer rows.Close()
	result := []models.Subnetwork{}
	for rows.Next() {
		var sn models.Subnetwork
		if rows.Scan(&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt) != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler sub-redes")
			return
		}
		sn.CanManage = claims.Role == models.RoleSuperAdmin
		if !sn.CanManage {
			_ = s.Pool.QueryRow(r.Context(), `
				SELECT EXISTS(SELECT 1 FROM subnetworks s
					JOIN networks n ON n.id=s.network_id
					JOIN organizations o ON o.id=n.organization_id
					WHERE s.id=$1 AND o.owner_technician_id=$2)`,
				sn.ID, claims.TechnicianID).Scan(&sn.CanManage)
		}
		result = append(result, sn)
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) RenameSubnetwork(w http.ResponseWriter, r *http.Request, id string) {
	claims := middleware.ClaimsFrom(r.Context())
	var req renameRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "nome inválido")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	var ownerID *string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT o.owner_technician_id FROM subnetworks s
		JOIN networks n ON n.id=s.network_id
		JOIN organizations o ON o.id=n.organization_id WHERE s.id=$1`, id).Scan(&ownerID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "sub-rede não encontrada")
		return
	}
	if claims.Role != models.RoleSuperAdmin &&
		(ownerID == nil || *ownerID != claims.TechnicianID) {
		writeErr(w, http.StatusForbidden, "sem permissão para alterar esta sub-rede")
		return
	}
	if req.Name == "" || len([]rune(req.Name)) > 80 {
		writeErr(w, http.StatusBadRequest, "nome inválido")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE subnetworks SET name=$1 WHERE id=$2`, req.Name, id); err != nil {
		writeErr(w, http.StatusConflict, "nome de sub-rede já utilizado")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "subnetwork_renamed", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "name": req.Name})
}

func (s *Server) subnetworkNetworkID(ctx context.Context, id string) (string, error) {
	var networkID string
	err := s.Pool.QueryRow(ctx,
		`SELECT network_id FROM subnetworks WHERE id=$1`, id).Scan(&networkID)
	return networkID, err
}

func (s *Server) SuspendSubnetwork(w http.ResponseWriter, r *http.Request, id string) {
	networkID, err := s.subnetworkNetworkID(r.Context(), id)
	if err != nil {
		writeErr(w, http.StatusNotFound, "sub-rede não encontrada")
		return
	}
	if !s.canManageNetwork(r, networkID) {
		writeErr(w, http.StatusForbidden, "sem permissão para suspender esta sub-rede")
		return
	}

	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar suspensão")
		return
	}
	defer tx.Rollback(r.Context())
	tag, err := tx.Exec(r.Context(), `
		UPDATE subnetworks SET status='suspensa',suspension_scope='subnetwork'
		WHERE id=$1 AND status='ativa'`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender sub-rede")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "sub-rede já está suspensa")
		return
	}
	rows, err := tx.Query(r.Context(), `
		UPDATE devices SET state='suspenso',suspension_scope='subnetwork',updated_at=now()
		WHERE subnetwork_id=$1 AND state='ativo'
		RETURNING id`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao suspender dispositivos")
		return
	}
	var deviceIDs []string
	for rows.Next() {
		var deviceID string
		if rows.Scan(&deviceID) == nil {
			deviceIDs = append(deviceIDs, deviceID)
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		writeErr(w, http.StatusInternalServerError, "falha ao suspender dispositivos")
		return
	}
	rows.Close()
	if err := tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir suspensão")
		return
	}
	for _, deviceID := range deviceIDs {
		_ = presence.Clear(r.Context(), s.RDB, deviceID)
		s.dropHubPeer(deviceID)
	}
	s.audit(r, "suspender_subrede", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "suspend_subnetwork", TargetID: id, Payload: deviceIDs})
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "suspensa", "devices_afetados": len(deviceIDs),
	})
}

func (s *Server) ResumeSubnetwork(w http.ResponseWriter, r *http.Request, id string) {
	networkID, err := s.subnetworkNetworkID(r.Context(), id)
	if err != nil {
		writeErr(w, http.StatusNotFound, "sub-rede não encontrada")
		return
	}
	if !s.canManageNetwork(r, networkID) {
		writeErr(w, http.StatusForbidden, "sem permissão para reativar esta sub-rede")
		return
	}
	var networkStatus, organizationStatus string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.status,o.status FROM networks n
		JOIN organizations o ON o.id=n.organization_id WHERE n.id=$1`,
		networkID).Scan(&networkStatus, &organizationStatus); err != nil {
		writeErr(w, http.StatusNotFound, "rede da sub-rede não encontrada")
		return
	}
	if networkStatus != models.StatusAtiva || organizationStatus != models.StatusAtiva {
		writeErr(w, http.StatusConflict, "reative primeiro a organização e a rede")
		return
	}

	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar reativação")
		return
	}
	defer tx.Rollback(r.Context())
	_, err = tx.Exec(r.Context(), `
		UPDATE subnetworks SET status='ativa',suspension_scope=NULL WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao reativar sub-rede")
		return
	}
	tag, err := tx.Exec(r.Context(), `
		UPDATE devices SET state='ativo',suspension_scope=NULL,updated_at=now()
		WHERE subnetwork_id=$1 AND suspension_scope='subnetwork'`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao reativar dispositivos")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir reativação")
		return
	}
	s.audit(r, "reativar_subrede", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "resume_subnetwork", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ativa", "devices_reativados": tag.RowsAffected(),
	})
}

func (s *Server) DeleteSubnetwork(w http.ResponseWriter, r *http.Request, id string) {
	var networkID, name string
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT network_id,name FROM subnetworks WHERE id=$1`, id).
		Scan(&networkID, &name); err != nil {
		writeErr(w, http.StatusNotFound, "sub-rede não encontrada")
		return
	}
	if !s.canManageNetwork(r, networkID) {
		writeErr(w, http.StatusForbidden, "sem permissão para excluir esta sub-rede")
		return
	}
	if strings.EqualFold(strings.TrimSpace(name), "Principal") {
		writeErr(w, http.StatusConflict, "a sub-rede Principal não pode ser excluída")
		return
	}

	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar exclusão")
		return
	}
	defer tx.Rollback(r.Context())
	var principalID string
	if err := tx.QueryRow(r.Context(), `
		SELECT id FROM subnetworks
		WHERE network_id=$1 AND lower(name)=lower('Principal')`, networkID).
		Scan(&principalID); err != nil {
		writeErr(w, http.StatusConflict, "sub-rede Principal não encontrada")
		return
	}
	tag, err := tx.Exec(r.Context(), `
		UPDATE devices SET subnetwork_id=$1,updated_at=now()
		WHERE subnetwork_id=$2`, principalID, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao transferir dispositivos")
		return
	}
	if _, err := tx.Exec(r.Context(), `DELETE FROM subnetworks WHERE id=$1`, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao excluir sub-rede")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir exclusão")
		return
	}
	s.audit(r, "excluir_subrede", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "delete_subnetwork", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "excluida", "reassigned_to": principalID,
		"devices_reassigned": tag.RowsAffected(),
	})
}
