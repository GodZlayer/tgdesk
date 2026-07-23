package handlers

import (
	"net/http"

	"tgdesk/api-core/internal/middleware"
)

// DeleteTechnician removes the account entirely (not just suspends it).
// technician_assignments and sessions cascade via FK; admin_actions keeps
// the historical rows with actor_id set to NULL (migration 0007).
func (s *Server) DeleteTechnician(w http.ResponseWriter, r *http.Request, id string) {
	claims := middleware.ClaimsFrom(r.Context())
	if claims.TechnicianID == id {
		writeErr(w, http.StatusBadRequest, "não é possível apagar a própria conta")
		return
	}
	s.dropTechnicianHubPeer(id)
	tag, err := s.Pool.Exec(r.Context(), `DELETE FROM technicians WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao apagar técnico")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	s.audit(r, "delete_tecnico", id)
	writeJSON(w, http.StatusOK, map[string]string{"status": "apagado"})
}

// DeleteNetwork removes the network. Devices under it are kept (history,
// telemetry) but detached — network_id is set to NULL via FK (ON DELETE
// SET NULL) instead of being deleted along with the network.
func (s *Server) DeleteNetwork(w http.ResponseWriter, r *http.Request, id string) {
	rows, _ := s.Pool.Query(r.Context(), `SELECT id FROM devices WHERE network_id=$1`, id)
	var deviceIDs []string
	for rows.Next() {
		var did string
		if err := rows.Scan(&did); err == nil {
			deviceIDs = append(deviceIDs, did)
		}
	}
	rows.Close()
	for _, did := range deviceIDs {
		s.dropHubPeer(did)
	}

	tag, err := s.Pool.Exec(r.Context(), `DELETE FROM networks WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao apagar rede")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}
	s.audit(r, "delete_rede", id)
	writeJSON(w, http.StatusOK, map[string]string{"status": "apagada"})
}

// DeleteOrganization removes the organization and cascades to its networks
// (ON DELETE CASCADE) and technician_assignments; devices are detached, not
// deleted, same as DeleteNetwork.
func (s *Server) DeleteOrganization(w http.ResponseWriter, r *http.Request, id string) {
	rows, _ := s.Pool.Query(r.Context(), `
		SELECT id FROM devices WHERE network_id IN (SELECT id FROM networks WHERE organization_id=$1)`, id)
	var deviceIDs []string
	for rows.Next() {
		var did string
		if err := rows.Scan(&did); err == nil {
			deviceIDs = append(deviceIDs, did)
		}
	}
	rows.Close()
	for _, did := range deviceIDs {
		s.dropHubPeer(did)
	}

	tag, err := s.Pool.Exec(r.Context(), `DELETE FROM organizations WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao apagar organização")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "organização não encontrada")
		return
	}
	s.audit(r, "delete_organizacao", id)
	writeJSON(w, http.StatusOK, map[string]string{"status": "apagada"})
}
