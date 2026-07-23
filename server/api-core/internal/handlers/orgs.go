package handlers

import (
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
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
		query = `SELECT id, name, status, created_at FROM organizations ORDER BY created_at`
	} else {
		query = `
			SELECT DISTINCT o.id, o.name, o.status, o.created_at FROM organizations o
			LEFT JOIN networks n ON n.organization_id = o.id
			WHERE o.id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL)
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
		if err := rs.Scan(&o.ID, &o.Name, &o.Status, &o.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler organizações")
			return
		}
		orgs = append(orgs, o)
	}
	writeJSON(w, http.StatusOK, orgs)
}

type createNetworkRequest struct {
	OrganizationID string `json:"organization_id"`
	Name           string `json:"name"`
	CIDRVirtual    string `json:"cidr_virtual"`
}

func (s *Server) CreateNetwork(w http.ResponseWriter, r *http.Request) {
	var req createNetworkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" || req.OrganizationID == "" {
		writeErr(w, http.StatusBadRequest, "organization_id e name são obrigatórios")
		return
	}
	var n models.Network
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO networks (organization_id, name, cidr_virtual) VALUES ($1, $2, $3)
		RETURNING id, organization_id, name, coalesce(cidr_virtual, ''), status, created_at`,
		req.OrganizationID, req.Name, req.CIDRVirtual,
	).Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "rede já existe ou dados inválidos")
		return
	}
	writeJSON(w, http.StatusCreated, n)
}

func (s *Server) ListNetworks(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	orgFilter := r.URL.Query().Get("organization_id")

	var query string
	var args []any
	if claims.Role == models.RoleSuperAdmin {
		if orgFilter != "" {
			query = `SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_at FROM networks WHERE organization_id=$1 ORDER BY created_at`
			args = append(args, orgFilter)
		} else {
			query = `SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_at FROM networks ORDER BY created_at`
		}
	} else {
		query = `
			SELECT id, organization_id, name, coalesce(cidr_virtual,''), status, created_at FROM networks n
			WHERE (organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 AND organization_id IS NOT NULL)
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
		if err := rs.Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler redes")
			return
		}
		nets = append(nets, n)
	}
	writeJSON(w, http.StatusOK, nets)
}
