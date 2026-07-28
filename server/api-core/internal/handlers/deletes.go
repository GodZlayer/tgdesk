package handlers

import (
	"context"
	"net/http"

	"github.com/jackc/pgx/v5"
	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

type unlinkedDevice struct {
	id     string
	pubkey *string
}

func (s *Server) resetDevicesForPairing(ctx context.Context, tx pgx.Tx, networkQuery string, scopeID string) ([]unlinkedDevice, error) {
	rows, err := tx.Query(ctx, networkQuery, scopeID)
	if err != nil {
		return nil, err
	}
	var devices []unlinkedDevice
	for rows.Next() {
		var device unlinkedDevice
		if rows.Scan(&device.id, &device.pubkey) == nil {
			devices = append(devices, device)
		}
	}
	rows.Close()
	for _, device := range devices {
		if _, err := tx.Exec(ctx, `UPDATE devices SET network_id=NULL,state='guest',
			pairing_code=$1,wg_pubkey=NULL,wg_virtual_ip=NULL,suspension_scope=NULL,
			updated_at=now() WHERE id=$2`, genPairingCode(6), device.id); err != nil {
			return nil, err
		}
	}
	return devices, nil
}

func (s *Server) finishDeviceUnlink(ctx context.Context, devices []unlinkedDevice) {
	ids := make([]string, 0, len(devices))
	for _, device := range devices {
		ids = append(ids, device.id)
		_ = presence.Clear(ctx, s.RDB, device.id)
		s.removeHubPeerKey(device.pubkey)
	}
	_ = presence.Publish(ctx, s.RDB,
		presence.Event{Type: "devices_unlinked", Payload: ids})
}

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
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar exclusão")
		return
	}
	defer tx.Rollback(r.Context())
	deviceIDs, err := s.resetDevicesForPairing(r.Context(), tx,
		`SELECT id,wg_pubkey FROM devices WHERE network_id=$1 FOR UPDATE`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao desvincular dispositivos")
		return
	}
	tag, err := tx.Exec(r.Context(), `DELETE FROM networks WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao apagar rede")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir exclusão")
		return
	}
	s.finishDeviceUnlink(r.Context(), deviceIDs)
	s.audit(r, "delete_rede", id)
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "apagada", "devices_desvinculados": len(deviceIDs),
	})
}

// DeleteOrganization removes the organization and cascades to its networks
// (ON DELETE CASCADE) and technician_assignments; devices are detached, not
// deleted, same as DeleteNetwork.
func (s *Server) DeleteOrganization(w http.ResponseWriter, r *http.Request, id string) {
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao iniciar exclusão")
		return
	}
	defer tx.Rollback(r.Context())
	deviceIDs, err := s.resetDevicesForPairing(r.Context(), tx, `
		SELECT id,wg_pubkey FROM devices WHERE network_id IN
		(SELECT id FROM networks WHERE organization_id=$1) FOR UPDATE`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao desvincular dispositivos")
		return
	}
	tag, err := tx.Exec(r.Context(), `DELETE FROM organizations WHERE id=$1`, id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao apagar organização")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "organização não encontrada")
		return
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir exclusão")
		return
	}
	s.finishDeviceUnlink(r.Context(), deviceIDs)
	s.audit(r, "delete_organizacao", id)
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "apagada", "devices_desvinculados": len(deviceIDs),
	})
}
