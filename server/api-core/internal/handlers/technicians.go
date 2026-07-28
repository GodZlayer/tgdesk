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
	rs, err := s.Pool.Query(r.Context(), `SELECT id, username, role, created_via_env, status, created_at FROM technicians ORDER BY created_at`)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar técnicos")
		return
	}
	defer rs.Close()

	techs := []models.Technician{}
	for rs.Next() {
		var t models.Technician
		if err := rs.Scan(&t.ID, &t.Username, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao ler técnicos")
			return
		}
		techs = append(techs, t)
	}
	writeJSON(w, http.StatusOK, techs)
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
	var t models.Technician
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO technicians (username, password_hash, role, created_via_env) VALUES ($1, $2, $3, false)
		RETURNING id, username, role, created_via_env, status, created_at`,
		req.Name, "!key-only!", models.RoleTecnico,
	).Scan(&t.ID, &t.Username, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt)
	if err != nil {
		writeErr(w, http.StatusConflict, "usuário já existe")
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
