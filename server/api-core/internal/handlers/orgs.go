package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

type createOrgRequest struct {
	Name string `json:"name"`
}

func (s *Server) CreateOrganization(w http.ResponseWriter, r *http.Request) {
	var req createOrgRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		writeErr(w, http.StatusBadRequest, "name é obrigatório")
		return
	}
	var org models.Organization
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO organizations (name) VALUES ($1)
		RETURNING id, name, status, created_at`, req.Name,
	).Scan(&org.ID, &org.Name, &org.Status, &org.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "organização já existe ou dados inválidos")
		return
	}
	writeJSON(w, http.StatusCreated, org)
}

func (s *Server) ListOrganizations(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())

	var query string
	var args []any
	if claims.Role == models.RoleSuperAdmin {
		query = `SELECT id, name, status, owner_technician_id, created_at FROM organizations ORDER BY created_at`
	} else {
		query = `
			SELECT DISTINCT o.id, o.name, o.status, o.owner_technician_id, o.created_at FROM organizations o
			LEFT JOIN networks n ON n.organization_id = o.id
			WHERE o.owner_technician_id=$1
			   OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL)
			ORDER BY o.created_at`
		args = append(args, claims.TechnicianID)
	}

	rs, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar organizações")
		return
	}
	defer rs.Close()

	orgs := []models.Organization{}
	for rs.Next() {
		var o models.Organization
		if err := rs.Scan(&o.ID, &o.Name, &o.Status, &o.OwnerTechnicianID, &o.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler organizações")
			return
		}
		o.CanManage = claims.Role == models.RoleSuperAdmin ||
			(o.OwnerTechnicianID != nil && *o.OwnerTechnicianID == claims.TechnicianID)
		orgs = append(orgs, o)
	}
	writeJSON(w, http.StatusOK, orgs)
}

type renameRequest struct {
	Name string `json:"name"`
}

// RenameOrganization renames only an extra organization. A technician-owned
// organization is named from its owner and can only change through that
// technician's control-device display name.
func (s *Server) RenameOrganization(w http.ResponseWriter, r *http.Request, id string) {
	var req renameRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "nome inválido")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || len([]rune(req.Name)) > 80 {
		writeErr(w, http.StatusBadRequest, "nome deve ter entre 1 e 80 caracteres")
		return
	}
	var ownerID *string
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT owner_technician_id FROM organizations WHERE id=$1`, id).
		Scan(&ownerID); err != nil {
		writeErr(w, http.StatusNotFound, "organização não encontrada")
		return
	}
	if ownerID != nil {
		writeErr(w, http.StatusConflict,
			"organização de técnico acompanha automaticamente o nome do técnico")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE organizations SET name=$1 WHERE id=$2`, req.Name, id); err != nil {
		writeErr(w, http.StatusConflict, "nome de organização já utilizado")
		return
	}
	s.audit(r, "renomear_organizacao", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "organization_renamed", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "name": req.Name})
}

func (s *Server) RenameNetwork(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageNetwork(r, id) {
		writeErr(w, http.StatusForbidden, "somente o criador da rede ou o Admin pode renomeá-la")
		return
	}
	var req renameRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "nome inválido")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || len([]rune(req.Name)) > 80 {
		writeErr(w, http.StatusBadRequest, "nome deve ter entre 1 e 80 caracteres")
		return
	}
	tag, err := s.Pool.Exec(r.Context(), `UPDATE networks SET name=$1 WHERE id=$2`,
		req.Name, id)
	if err != nil {
		writeErr(w, http.StatusConflict, "nome de rede já utilizado nessa organização")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "rede não encontrada")
		return
	}
	s.audit(r, "renomear_rede", id)
	_ = presence.Publish(r.Context(), s.RDB,
		presence.Event{Type: "network_renamed", TargetID: id})
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "name": req.Name})
}

type createNetworkRequest struct {
	OrganizationID string `json:"organization_id"`
	Name           string `json:"name"`
	CIDRVirtual    string `json:"cidr_virtual"`
}

func (s *Server) CreateNetwork(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	var req createNetworkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		writeErr(w, http.StatusBadRequest, "organization_id e name são obrigatórios")
		return
	}
	if claims.Role != models.RoleSuperAdmin {
		if err := s.Pool.QueryRow(r.Context(),
			`SELECT id FROM organizations WHERE owner_technician_id=$1`,
			claims.TechnicianID).Scan(&req.OrganizationID); err != nil {
			writeErr(w, http.StatusConflict, "organizacao pessoal indisponivel")
			return
		}
	}
	if req.OrganizationID == "" {
		writeErr(w, http.StatusBadRequest, "organization_id obrigatorio")
		return
	}
	var n models.Network
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO networks (organization_id, name, cidr_virtual, created_by_technician_id)
		VALUES ($1, $2, $3, $4)
		RETURNING id, organization_id, name, coalesce(cidr_virtual, ''), status,
		          created_by_technician_id, created_at`,
		req.OrganizationID, req.Name, req.CIDRVirtual, claims.TechnicianID,
	).Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status,
		&n.CreatedBy, &n.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "rede já existe ou dados inválidos")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO subnetworks(network_id,name,created_by_technician_id)
		VALUES ($1,'Principal',$2) ON CONFLICT (network_id,name) DO NOTHING`,
		n.ID, claims.TechnicianID)
	n.CanManage = true
	writeJSON(w, http.StatusCreated, n)
}

func (s *Server) ListNetworks(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	orgFilter := r.URL.Query().Get("organization_id")

	var query string
	var args []any
	if claims.Role == models.RoleSuperAdmin {
		if orgFilter != "" {
			query = `SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_by_technician_id, created_at FROM networks WHERE organization_id=$1 ORDER BY created_at`
			args = append(args, orgFilter)
		} else {
			query = `SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_by_technician_id, created_at FROM networks ORDER BY created_at`
		}
	} else {
		query = `
			SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_by_technician_id, created_at FROM networks n
			WHERE (organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1)
			   OR id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL))
			ORDER BY created_at`
		args = append(args, claims.TechnicianID)
	}

	rs, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar redes")
		return
	}
	defer rs.Close()

	nets := []models.Network{}
	for rs.Next() {
		var n models.Network
		if err := rs.Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedBy, &n.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler redes")
			return
		}
		n.CanManage = claims.Role == models.RoleSuperAdmin
		if !n.CanManage {
			_ = s.Pool.QueryRow(r.Context(), `
				SELECT EXISTS(SELECT 1 FROM organizations
					WHERE id=$1 AND owner_technician_id=$2)`,
				n.OrganizationID, claims.TechnicianID).Scan(&n.CanManage)
		}
		nets = append(nets, n)
	}
	writeJSON(w, http.StatusOK, nets)
}
