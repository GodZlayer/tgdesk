package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/presence"
)

// Superfície pública consumida pelo instalador, antes de existir dispositivo
// instalado e portanto antes de existir túnel — não pode passar por private().
//
// O instalador resolve o destino do cliente empresarial: busca o técnico pelo
// nome, baixa o branding dele e coloca o dispositivo na rede de entrada da
// organização daquele técnico. A rede de entrada é isolada por peer (0049), e
// entrar nela não é vínculo: é declaração de intenção do cliente. O vínculo
// real acontece quando um técnico promove o dispositivo para uma rede da
// organização, via PUT /devices/{id}/networks.

// Busca aberta na internet, então devolve o mínimo: id e nome. A query é fixa
// aqui — nenhuma coluna a mais escapa por engano.
const (
	minTechnicianQueryLen = 3
	maxTechnicianResults  = 20
)

// SearchPublicTechnicians responde à busca por nome do instalador.
//
// Dois freios contra enumeração do parque: exige um mínimo de caracteres, de
// forma que busca vazia nunca devolve catálogo, e limita o número de
// resultados. Só técnicos ativos que podem receber cliente aparecem.
func (s *Server) SearchPublicTechnicians(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if len([]rune(query)) < minTechnicianQueryLen {
		writeErr(w, http.StatusBadRequest, "informe ao menos 3 caracteres do nome")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT t.id,
		       CASE WHEN t.branding_enabled AND t.brand_name<>''
		            THEN t.brand_name ELSE t.username END
		FROM technicians t
		WHERE t.status='ativo'
		  AND t.role IN ('supervisor','tecnico','freelancer')
		  AND (t.username ILIKE '%'||$1||'%' OR t.brand_name ILIKE '%'||$1||'%')
		ORDER BY t.username
		LIMIT $2`, query, maxTechnicianResults)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha na busca")
		return
	}
	defer rows.Close()
	results := []map[string]string{}
	for rows.Next() {
		var id, name string
		if rows.Scan(&id, &name) != nil {
			continue
		}
		results = append(results, map[string]string{"id": id, "name": name})
	}
	writeJSON(w, http.StatusOK, map[string]any{"technicians": results})
}

// GetPublicTechnicianBranding entrega o pacote de branding que o instalador
// aplica ao ícone do app e do atalho. Mesma serialização do endpoint
// autenticado: o logo já é servido em runtime, aqui só muda quem pode pedir.
func (s *Server) GetPublicTechnicianBranding(w http.ResponseWriter, r *http.Request, technicianID string) {
	var active bool
	if s.Pool.QueryRow(r.Context(),
		`SELECT status='ativo' AND role IN ('supervisor','tecnico','freelancer')
		 FROM technicians WHERE id=$1`, technicianID).Scan(&active) != nil || !active {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	record, err := s.technicianBrand(r.Context(), technicianID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	writeJSON(w, http.StatusOK, brandJSON(record, true))
}

// intakeNetworkForTechnician resolve a rede de entrada da organização do
// técnico escolhido. A organização é a que ele possui (supervisor tem a sua,
// criada junto com a conta); não havendo, é a da sua lotação.
func (s *Server) intakeNetworkForTechnician(ctx context.Context, technicianID string) (string, string, error) {
	var orgID, netID string
	err := s.Pool.QueryRow(ctx, `
		SELECT n.organization_id,n.id
		FROM networks n
		JOIN organizations o ON o.id=n.organization_id
		WHERE n.is_intake AND n.status='ativa' AND o.status='ativa'
		  AND n.organization_id = COALESCE(
		        (SELECT id FROM organizations WHERE owner_technician_id=$1),
		        (SELECT ta.organization_id FROM technician_assignments ta
		         WHERE ta.technician_id=$1 AND ta.organization_id IS NOT NULL
		         ORDER BY ta.created_at LIMIT 1),
		        (SELECT n2.organization_id FROM technician_assignments ta
		         JOIN networks n2 ON n2.id=ta.network_id
		         WHERE ta.technician_id=$1 AND n2.system_key IS NULL
		         ORDER BY ta.created_at LIMIT 1))`,
		technicianID).Scan(&orgID, &netID)
	return orgID, netID, err
}

// ClientRenameDevice deixa o próprio cliente nomear o computador dele, pelo
// menu do TGDesk. É a mesma coluna que o técnico edita, mas por outra porta:
// aqui a credencial é a do dispositivo, e ela só alcança o próprio.
//
// Computador de técnico fica de fora: o nome dele é parte da identidade de
// controle, e quem manda nisso é o técnico dono ou o Admin.
func (s *Server) ClientRenameDevice(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DeviceID    string `json:"device_id"`
		DeviceToken string `json:"device_token"`
		DisplayName string `json:"display_name"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil ||
		req.DeviceID == "" || req.DeviceToken == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo e token são obrigatórios")
		return
	}
	name := strings.TrimSpace(req.DisplayName)
	if len([]rune(name)) > 80 {
		writeErr(w, http.StatusBadRequest, "o nome deve ter no máximo 80 caracteres")
		return
	}
	var controlTechnicianID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT control_technician_id FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&controlTechnicianID) != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo inválido")
		return
	}
	if controlTechnicianID != nil {
		writeErr(w, http.StatusForbidden,
			"o nome do computador de técnico é alterado pelo próprio técnico")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE devices SET display_name=NULLIF($2,''),updated_at=now() WHERE id=$1`,
		req.DeviceID, name); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao salvar o nome")
		return
	}
	// A lista do técnico é atualizada por push, como todo o resto.
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "device_renamed", TargetID: req.DeviceID,
		Payload: map[string]any{"display_name": name},
	})
	writeJSON(w, http.StatusOK, map[string]string{"display_name": name})
}

type orgIntakeBindRequest struct {
	DeviceID     string `json:"device_id"`
	DeviceToken  string `json:"device_token"`
	TechnicianID string `json:"technician_id"`
}

// OrgIntakeBindDevice é o irmão empresarial de StandaloneBindDevice: mesma
// autenticação por device_id + device_token no corpo (o dispositivo não tem
// sessão de técnico), mesmos efeitos, outra rede-alvo.
//
// Não exige state='guest' nem código de pareamento, mas recusa dispositivo já
// vinculado a outra rede — sem isso um dispositivo empresarial poderia se
// mudar de organização sozinho, apagando em silêncio o vínculo feito por um
// técnico.
func (s *Server) OrgIntakeBindDevice(w http.ResponseWriter, r *http.Request) {
	var req orgIntakeBindRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil ||
		req.DeviceID == "" || req.DeviceToken == "" || req.TechnicianID == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo, token e técnico são obrigatórios")
		return
	}
	var state string
	var networkID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT state,network_id FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&state, &networkID) != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo inválido")
		return
	}
	if state == "suspenso" {
		writeErr(w, http.StatusForbidden, "dispositivo suspenso")
		return
	}
	orgID, netID, err := s.intakeNetworkForTechnician(r.Context(), req.TechnicianID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "rede de entrada indisponível para esse técnico")
		return
	}
	if networkID != nil && *networkID != "" && *networkID != netID {
		writeErr(w, http.StatusConflict, "dispositivo já vinculado a uma rede")
		return
	}
	// Mesmo conjunto de efeitos de Bind e StandaloneBindDevice: rede, subrede
	// principal, consumo do código e as duas associações. device_subnetworks é
	// o que o modelo de visibilidade consulta; sem ela o dispositivo entra na
	// rede mas fica fora de qualquer subrede.
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET network_id=$2,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$2 ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			state='ativo', pairing_code=NULL, updated_at=now()
		WHERE id=$1`, req.DeviceID, netID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao vincular dispositivo")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id)
		SELECT $1,id FROM subnetworks WHERE network_id=$2
		ORDER BY (name='Principal') DESC, created_at LIMIT 1
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "bind", TargetID: req.DeviceID})
	writeJSON(w, http.StatusOK, map[string]any{
		"state": "ativo", "intake": true,
		"organization_id": orgID, "network_id": netID,
	})
}
