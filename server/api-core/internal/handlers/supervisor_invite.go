package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

// CreateSupervisorInvite gera o código que vincula outro supervisor a esta
// organização.
//
// Uma org pode ter vários supervisores: a fila de chamados sempre foi da
// organização, não do dono — todos os supervisores atribuídos a ela veem os
// mesmos chamados ao mesmo tempo.
func (s *Server) CreateSupervisorInvite(w http.ResponseWriter, r *http.Request, orgID string) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil || (c.Role != models.RoleSupervisor && c.Role != models.RoleSuperAdmin) {
		writeErrCode(w, http.StatusForbidden, "apenas_supervisor_admin", "apenas supervisor ou admin")
		return
	}
	ok, err := s.Authorizer.CanAccessOrganization(r.Context(), c, orgID)
	if err != nil || !ok {
		writeErrCode(w, http.StatusForbidden, "permissao_sobre_organizacao", "sem permissão sobre esta organização")
		return
	}
	code := genPairingCode(8)
	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO supervisor_invites(code,organization_id,created_by)
		VALUES($1,$2,$3)`, code, orgID, c.TechnicianID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_gerar_convite", "falha ao gerar convite")
		return
	}
	var orgNome string
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT name FROM organizations WHERE id=$1`, orgID).Scan(&orgNome)
	writeJSON(w, http.StatusCreated, map[string]any{
		"code": code, "organization_id": orgID, "organization_name": orgNome,
		"validade_dias": 7,
	})
}

// RedeemSupervisorInvite consome o código e passa a enxergar a fila da
// organização. Quem resgata precisa já ser supervisor: o convite adiciona
// alcance, não promove ninguém de papel.
func (s *Server) RedeemSupervisorInvite(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil || (c.Role != models.RoleSupervisor && c.Role != models.RoleSuperAdmin) {
		writeErrCode(w, http.StatusForbidden, "apenas_supervisor_admin_pode_resgatar", "apenas supervisor ou admin pode resgatar")
		return
	}
	var req struct {
		Code string `json:"code"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || strings.TrimSpace(req.Code) == "" {
		writeErrCode(w, http.StatusBadRequest, "codigo_obrigatorio", "código é obrigatório")
		return
	}
	var orgID string
	if s.Pool.QueryRow(r.Context(), `
		UPDATE supervisor_invites SET consumed_at=now(),consumed_by=$2
		WHERE code=$1 AND consumed_at IS NULL AND expires_at>now()
		RETURNING organization_id`,
		strings.ToUpper(strings.TrimSpace(req.Code)), c.TechnicianID).Scan(&orgID) != nil {
		writeErrCode(w, http.StatusNotFound, "codigo_invalido_expirado_ja_usado", "código inválido, expirado ou já usado")
		return
	}
	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO technician_assignments(technician_id,organization_id,assignment_scope,permissions_level)
		VALUES($1,$2,'organization','full') ON CONFLICT DO NOTHING`,
		c.TechnicianID, orgID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_vincular_supervisor", "falha ao vincular supervisor")
		return
	}
	var orgNome string
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT name FROM organizations WHERE id=$1`, orgID).Scan(&orgNome)
	writeJSON(w, http.StatusOK, map[string]any{
		"organization_id": orgID, "organization_name": orgNome, "vinculado": true,
	})
}

// ListOrganizationSupervisors mostra quem já supervisiona a organização.
func (s *Server) ListOrganizationSupervisors(w http.ResponseWriter, r *http.Request, orgID string) {
	c := middleware.ClaimsFrom(r.Context())
	ok, err := s.Authorizer.CanAccessOrganization(r.Context(), c, orgID)
	if err != nil || !ok {
		writeErrCode(w, http.StatusForbidden, "permissao_sobre_organizacao", "sem permissão sobre esta organização")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT DISTINCT t.id,t.username,t.role,(o.owner_technician_id=t.id) AS dono
		FROM technicians t
		JOIN organizations o ON o.id=$1
		WHERE t.id=o.owner_technician_id
		   OR EXISTS(SELECT 1 FROM technician_assignments ta
		             WHERE ta.technician_id=t.id AND ta.organization_id=$1)
		ORDER BY dono DESC, t.username`, orgID)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_supervisores", "falha ao listar supervisores")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, username, role string
		var dono bool
		if rows.Scan(&id, &username, &role, &dono) == nil {
			out = append(out, map[string]any{
				"id": id, "username": username, "role": role, "dono": dono,
			})
		}
	}
	writeJSON(w, http.StatusOK, out)
}
