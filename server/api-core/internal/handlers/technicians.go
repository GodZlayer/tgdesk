package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

func (s *Server) ListTechnicians(w http.ResponseWriter, r *http.Request) {
	rs, err := s.Pool.Query(r.Context(), `
		SELECT id, username, role, created_via_env, status, created_at,
		       branding_enabled,brand_name,brand_logo_file<>''
		FROM technicians ORDER BY created_at`)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar técnicos")
		return
	}
	defer rs.Close()

	techs := []map[string]any{}
	for rs.Next() {
		var t models.Technician
		var brandingEnabled, hasBrandLogo bool
		var brandName string
		if err := rs.Scan(&t.ID, &t.Username, &t.Role, &t.CreatedViaEnv, &t.Status,
			&t.CreatedAt, &brandingEnabled, &brandName, &hasBrandLogo); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler técnicos")
			return
		}
		item, _ := json.Marshal(t)
		var data map[string]any
		_ = json.Unmarshal(item, &data)
		data["branding_enabled"] = brandingEnabled
		data["brand_name"] = brandName
		data["has_brand_logo"] = hasBrandLogo
		techs = append(techs, data)
	}
	writeJSON(w, http.StatusOK, techs)
}

func (s *Server) ListTechnicianAssignments(w http.ResponseWriter, r *http.Request) {
	rs, err := s.Pool.Query(r.Context(), `
		SELECT a.id, a.technician_id, t.username,
		       a.organization_id, coalesce(o.name, ''),
		       a.network_id, coalesce(n.name, '')
		FROM technician_assignments a
		JOIN technicians t ON t.id=a.technician_id
		LEFT JOIN networks n ON n.id=a.network_id
		LEFT JOIN organizations o ON o.id=coalesce(a.organization_id, n.organization_id)
		ORDER BY t.username, o.name, n.name`)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar atribuições")
		return
	}
	defer rs.Close()
	items := []map[string]any{}
	for rs.Next() {
		var id, technicianID, username, organizationName, networkName string
		var organizationID, networkID *string
		if err := rs.Scan(&id, &technicianID, &username, &organizationID,
			&organizationName, &networkID, &networkName); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler atribuições")
			return
		}
		items = append(items, map[string]any{
			"id": id, "technician_id": technicianID, "technician_name": username,
			"organization_id": organizationID, "organization_name": organizationName,
			"network_id": networkID, "network_name": networkName,
		})
	}
	writeJSON(w, http.StatusOK, items)
}

type createTechnicianRequest struct {
	Name string `json:"name"`
}

func (s *Server) CreateTechnician(w http.ResponseWriter, r *http.Request) {
	var req createTechnicianRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "username e password são obrigatórios")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeErr(w, http.StatusBadRequest, "nome é obrigatório")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao criar supervisor")
		return
	}
	defer tx.Rollback(r.Context())
	var t models.Technician
	err = tx.QueryRow(r.Context(), `
		INSERT INTO technicians (username, password_hash, role, created_via_env) VALUES ($1, $2, $3, false)
		RETURNING id, username, role, created_via_env, status, created_at`,
		req.Name, "!key-only!", models.RoleSupervisor,
	).Scan(&t.ID, &t.Username, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "usuário já existe")
		return
	}
	var organizationID string
	err = tx.QueryRow(r.Context(), `
		INSERT INTO organizations(name, owner_technician_id)
		VALUES ($1, $2) RETURNING id`, t.Username, t.ID).Scan(&organizationID)
	if err != nil {
		err = tx.QueryRow(r.Context(), `
			INSERT INTO organizations(name, owner_technician_id)
			VALUES ($1 || ' - Supervisor', $2) RETURNING id`,
			t.Username, t.ID).Scan(&organizationID)
	}
	if err != nil {
		writeErr(w, http.StatusConflict, "falha ao criar organizacao pessoal")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		INSERT INTO technician_assignments(technician_id, organization_id)
		VALUES ($1, $2)`, t.ID, organizationID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao vincular organizacao pessoal")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		INSERT INTO supervisor_profiles(technician_id, rating_avg, rating_count)
		VALUES ($1, 5.00, 0) ON CONFLICT (technician_id) DO NOTHING`, t.ID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao criar perfil de supervisor")
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao concluir criacao do supervisor")
		return
	}
	writeJSON(w, http.StatusCreated, t)
}

type createAssignmentRequest struct {
	TechnicianID   string `json:"technician_id"`
	OrganizationID string `json:"organization_id"`
	NetworkID      string `json:"network_id"`
}

func (s *Server) CreateAssignment(w http.ResponseWriter, r *http.Request) {
	var req createAssignmentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.TechnicianID == "" || (req.OrganizationID == "" && req.NetworkID == "") {
		writeErr(w, http.StatusBadRequest, "technician_id e (organization_id ou network_id) são obrigatórios")
		return
	}
	var orgID, netID any
	if req.OrganizationID != "" {
		orgID = req.OrganizationID
	}
	if req.NetworkID != "" {
		netID = req.NetworkID
	}
	var a models.TechnicianAssignment
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO technician_assignments (technician_id, organization_id, network_id) VALUES ($1, $2, $3)
		ON CONFLICT (technician_id, organization_id, network_id) DO UPDATE SET technician_id = EXCLUDED.technician_id
		RETURNING id, technician_id, organization_id, network_id`,
		req.TechnicianID, orgID, netID,
	).Scan(&a.ID, &a.TechnicianID, &a.OrganizationID, &a.NetworkID)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "falha ao criar atribuição")
		return
	}
	writeJSON(w, http.StatusCreated, a)
}

func (s *Server) DeleteTechnicianAssignment(w http.ResponseWriter, r *http.Request) {
	tag, err := s.Pool.Exec(r.Context(),
		`DELETE FROM technician_assignments WHERE id=$1`, r.PathValue("id"))
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "atribuição não encontrada")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type technicianWGKeyRequest struct {
	PublicKey string `json:"public_key"`
}

// TechnicianWGKey gives the logged-in technician their own WireGuard tunnel
// identity — independent of any Host device that might be installed on the
// same physical machine. Reserved octet 10.70.1.x, allocated via
// technician_host_octet_seq (see 0005_technician_wg.sql). Sem isso, o Hub não
// teria como alcançar o hbbs/hbbr agora que eles só respondem dentro da VPN.
func (s *Server) TechnicianWGKey(w http.ResponseWriter, r *http.Request) {
	if s.Hub == nil {
		writeErr(w, http.StatusServiceUnavailable, "hub WireGuard indisponível neste servidor")
		return
	}
	claims := middleware.ClaimsFrom(r.Context())
	var req technicianWGKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PublicKey == "" {
		writeErr(w, http.StatusBadRequest, "public_key é obrigatório")
		return
	}

	var status string
	var existingIP *string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT status, wg_virtual_ip FROM technicians WHERE id=$1`, claims.TechnicianID,
	).Scan(&status, &existingIP); err != nil {
		writeErr(w, http.StatusUnauthorized, "técnico não encontrado")
		return
	}
	if status == models.StatusSuspenso {
		writeErr(w, http.StatusForbidden, "conta suspensa")
		return
	}

	var virtualIP string
	if existingIP != nil && *existingIP != "" {
		virtualIP = *existingIP
	} else {
		var hostOctet int
		if err := s.Pool.QueryRow(r.Context(),
			`SELECT nextval('technician_host_octet_seq')`,
		).Scan(&hostOctet); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao alocar IP virtual do técnico")
			return
		}
		virtualIP = fmt.Sprintf("10.70.1.%d", hostOctet)
	}

	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE technicians SET wg_pubkey=$1, wg_virtual_ip=$2 WHERE id=$3`,
		req.PublicKey, virtualIP, claims.TechnicianID,
	); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao salvar chave WireGuard")
		return
	}

	if err := s.Hub.AddPeer(req.PublicKey, virtualIP); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao registrar peer no hub: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, wgKeyResponse{
		VirtualIP:        virtualIP,
		HubPublicKey:     s.Hub.PublicKey.Base64(),
		HubEndpoint:      s.Cfg.HubPublicAddr,
		HubVirtualIP:     "10.70.0.1",
		RendezvousHost:   s.Cfg.RendezvousHost,
		RendezvousPubkey: readRendezvousKey(s.Cfg.RendezvousKeyFile),
	})
}
