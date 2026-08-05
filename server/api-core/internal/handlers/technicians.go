package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

func (s *Server) ListTechnicians(w http.ResponseWriter, r *http.Request) {
	rs, err := s.Pool.Query(r.Context(), `
		SELECT t.id, t.username, t.role, t.created_via_env, t.status, t.created_at,
		       t.branding_enabled,t.brand_name,t.brand_logo_file<>'',
		       t.name_style, tc.template, tc.active
		FROM technicians t
		LEFT JOIN technician_name_styles tc ON tc.key = t.name_style
		ORDER BY t.created_at`)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_tecnicos", "falha ao listar técnicos")
		return
	}
	defer rs.Close()

	techs := []map[string]any{}
	for rs.Next() {
		var t models.Technician
		var brandingEnabled, hasBrandLogo bool
		var brandName string
		var nameStyle *string
		var styleTemplate *string
		var styleActive *bool
		if err := rs.Scan(&t.ID, &t.Username, &t.Role, &t.CreatedViaEnv, &t.Status,
			&t.CreatedAt, &brandingEnabled, &brandName, &hasBrandLogo,
			&nameStyle, &styleTemplate, &styleActive); err != nil {
			writeErrCode(w, http.StatusInternalServerError, "falha_ler_tecnicos", "falha ao ler técnicos")
			return
		}
		item, _ := json.Marshal(t)
		var data map[string]any
		_ = json.Unmarshal(item, &data)
		data["branding_enabled"] = brandingEnabled
		data["brand_name"] = brandName
		data["has_brand_logo"] = hasBrandLogo
		// Nome de exibição montado em cima do username. Sem estilo, ou com um
		// estilo que não está mais ativo, cai para "só o nome" — nunca quebra.
		resolved := t.Username
		if nameStyle != nil && styleTemplate != nil &&
			(styleActive == nil || *styleActive) {
			data["name_style"] = *nameStyle
			resolved = strings.ReplaceAll(*styleTemplate, "{nome}", t.Username)
		}
		data["display_name"] = resolved
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
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_atribuicoes", "falha ao listar atribuições")
		return
	}
	defer rs.Close()
	items := []map[string]any{}
	for rs.Next() {
		var id, technicianID, username, organizationName, networkName string
		var organizationID, networkID *string
		if err := rs.Scan(&id, &technicianID, &username, &organizationID,
			&organizationName, &networkID, &networkName); err != nil {
			writeErrCode(w, http.StatusInternalServerError, "falha_ler_atribuicoes", "falha ao ler atribuições")
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
		writeErrCode(w, http.StatusBadRequest, "username_password_sao_obrigatorios", "username e password são obrigatórios")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeErrCode(w, http.StatusBadRequest, "nome_obrigatorio", "nome é obrigatório")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_criar_supervisor", "falha ao criar supervisor")
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
		writeErrCode(w, http.StatusConflict, "usuario_ja_existe", "usuário já existe")
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
		writeErrCode(w, http.StatusConflict, "falha_criar_organizacao_pessoal", "falha ao criar organizacao pessoal")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		INSERT INTO technician_assignments(technician_id, organization_id)
		VALUES ($1, $2)`, t.ID, organizationID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_vincular_organizacao_pessoal", "falha ao vincular organizacao pessoal")
		return
	}
	if _, err = tx.Exec(r.Context(), `
		INSERT INTO supervisor_profiles(technician_id, rating_avg, rating_count)
		VALUES ($1, 5.00, 0) ON CONFLICT (technician_id) DO NOTHING`, t.ID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_criar_perfil_supervisor", "falha ao criar perfil de supervisor")
		return
	}
	if err = tx.Commit(r.Context()); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_concluir_criacao_supervisor", "falha ao concluir criacao do supervisor")
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
		writeErrCode(w, http.StatusBadRequest, "technician_id_organization_id_network", "technician_id e (organization_id ou network_id) são obrigatórios")
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
		writeErrCode(w, http.StatusBadRequest, "falha_criar_atribuicao", "falha ao criar atribuição")
		return
	}
	writeJSON(w, http.StatusCreated, a)
}

func (s *Server) DeleteTechnicianAssignment(w http.ResponseWriter, r *http.Request) {
	tag, err := s.Pool.Exec(r.Context(),
		`DELETE FROM technician_assignments WHERE id=$1`, r.PathValue("id"))
	if err != nil || tag.RowsAffected() == 0 {
		writeErrCode(w, http.StatusNotFound, "atribuicao_encontrada", "atribuição não encontrada")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type technicianWGKeyRequest struct {
	PublicKey string `json:"public_key"`
}

// TechnicianWGKey devolve ao Hub os dados do túnel da máquina do técnico.
//
// Não existe mais identidade de rede separada para o papel Técnico: há UM
// adaptador por dispositivo, e o papel vem da credencial apresentada, nunca da
// rede. O endpoint é mantido porque o Hub ainda o consulta, mas não aloca
// endereço nem registra peer — o peer do dispositivo já está no hub.
func (s *Server) TechnicianWGKey(w http.ResponseWriter, r *http.Request) {
	if s.Hub == nil {
		writeErrCode(w, http.StatusServiceUnavailable, "hub_wireguard_indisponivel_neste_servidor", "hub WireGuard indisponível neste servidor")
		return
	}
	claims := middleware.ClaimsFrom(r.Context())
	var req technicianWGKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PublicKey == "" {
		writeErrCode(w, http.StatusBadRequest, "public_key_obrigatorio", "public_key é obrigatório")
		return
	}

	var status string
	var existingIP *string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT status, wg_virtual_ip FROM technicians WHERE id=$1`, claims.TechnicianID,
	).Scan(&status, &existingIP); err != nil {
		writeErrCode(w, http.StatusUnauthorized, "tecnico_encontrado", "técnico não encontrado")
		return
	}
	if status == models.StatusSuspenso {
		writeErrCode(w, http.StatusForbidden, "conta_suspensa", "conta suspensa")
		return
	}

	// O técnico não tem mais endereço próprio na VPN: existe UM adaptador por
	// dispositivo, e o papel vem da credencial apresentada, não da rede. Este
	// endpoint devolve o endereço da máquina do técnico para que clientes
	// antigos continuem funcionando, mas não aloca nada nem registra peer — o
	// peer do dispositivo já existe.
	//
	// Antes cada técnico subia um segundo adaptador ("TGDesk-Tech", 10.70.1.x),
	// deixando duas rotas para 10.70.0.0/16 na mesma máquina.
	var virtualIP string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT coalesce(wg_virtual_ip,'') FROM devices
		WHERE control_technician_id=$1 AND state='ativo'
		  AND coalesce(wg_virtual_ip,'') <> ''
		ORDER BY created_at LIMIT 1`, claims.TechnicianID).Scan(&virtualIP); err != nil {
		writeErrCode(w, http.StatusConflict, "dispositivo_desta_maquina_precisa_estar", "o dispositivo desta máquina precisa estar vinculado e ativo")
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

// desativado: alocação de endereço próprio para o técnico.
