package handlers

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/presence"
)

// Localidade: a região como coisa contável.
//
// O preço dinâmico do TGDesk não olha para uma fila global. Ele olha para um
// lugar, e pergunta três coisas sobre ele: quantos chamados estão esperando,
// quantos técnicos existem para atendê-los, e quantos clientes o lugar tem.
// Sem região, o recorte disponível era a rede — que é fronteira administrativa,
// não geográfica: duas redes da mesma empresa podem estar em cidades
// diferentes, e dois avulsos da mesma rua não compartilham rede nenhuma.
//
// A região é cadastro do admin. Quem pertence a ela é resolvido por coordenada
// quando há coordenada, e por atribuição quando não há — o avulso que abre
// chamado informando endereço cai pela primeira via; a empresa que o admin
// cadastrou numa região cai pela segunda.

type region struct {
	ID        string   `json:"id"`
	Key       string   `json:"key"`
	Label     string   `json:"label"`
	CenterLat *float64 `json:"center_lat"`
	CenterLon *float64 `json:"center_lon"`
	RadiusKm  float64  `json:"radius_km"`
	Position  int      `json:"position"`
	Active    bool     `json:"active"`
}

func (s *Server) regionCatalog(ctx context.Context, includeInactive bool) []region {
	out := []region{}
	filter := "WHERE active"
	if includeInactive {
		filter = ""
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT id,key,label,center_lat,center_lon,radius_km,position,active
		FROM regions `+filter+` ORDER BY position,label`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var r region
		if rows.Scan(&r.ID, &r.Key, &r.Label, &r.CenterLat, &r.CenterLon,
			&r.RadiusKm, &r.Position, &r.Active) == nil {
			out = append(out, r)
		}
	}
	return out
}

func (s *Server) Regions(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, s.regionCatalog(r.Context(), true))
}

func (s *Server) publishRegions(ctx context.Context) {
	_ = presence.Publish(ctx, s.RDB, presence.Event{
		Type: "regions", TargetID: "regions",
	})
}

type regionRequest struct {
	Key       string   `json:"key"`
	Label     string   `json:"label"`
	CenterLat *float64 `json:"center_lat"`
	CenterLon *float64 `json:"center_lon"`
	RadiusKm  *float64 `json:"radius_km"`
	Position  *int     `json:"position"`
	Active    *bool    `json:"active"`
}

// SaveRegion cria ou atualiza uma região. A chave é imutável depois de criada,
// como a do tipo de chamado, porque o que já foi atribuído aponta para ela.
func (s *Server) SaveRegion(w http.ResponseWriter, r *http.Request) {
	var req regionRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	req.Key = strings.ToLower(strings.TrimSpace(req.Key))
	req.Label = strings.TrimSpace(req.Label)
	if req.Key == "" || req.Label == "" {
		writeErrCode(w, 400, "chave_rotulo_obrigatorios", "chave e rótulo são obrigatórios")
		return
	}
	if strings.ContainsAny(req.Key, " \t/") {
		writeErrCode(w, 400, "chave_invalida", "a chave não pode ter espaço nem barra")
		return
	}
	// Meio centro não é centro: a tabela já recusa, mas recusar aqui devolve
	// uma mensagem que explica, em vez do erro cru do banco.
	if (req.CenterLat == nil) != (req.CenterLon == nil) {
		writeErrCode(w, 400, "centro_incompleto",
			"informe latitude e longitude, ou nenhuma das duas")
		return
	}
	radius, position, active := 50.0, 100, true
	if req.RadiusKm != nil && *req.RadiusKm > 0 {
		radius = *req.RadiusKm
	}
	if req.Position != nil {
		position = *req.Position
	}
	if req.Active != nil {
		active = *req.Active
	}
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO regions(key,label,center_lat,center_lon,radius_km,position,active)
		VALUES($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT(key) DO UPDATE SET label=excluded.label,
			center_lat=excluded.center_lat,center_lon=excluded.center_lon,
			radius_km=excluded.radius_km,position=excluded.position,
			active=excluded.active,updated_at=now()
		RETURNING id`,
		req.Key, req.Label, req.CenterLat, req.CenterLon, radius, position,
		active).Scan(&id)
	if err != nil {
		writeErrCode(w, 400, "falha_salvar_regiao", "falha ao salvar a região")
		return
	}
	s.publishRegions(r.Context())
	writeJSON(w, 200, map[string]any{"id": id, "key": req.Key})
}

// DeleteRegion apaga a região. As referências são ON DELETE SET NULL, então
// técnico, dispositivo e chamado sobrevivem sem região — e o preço deles volta
// ao escopo global, que é o comportamento correto para um lugar que deixou de
// existir no cadastro.
func (s *Server) DeleteRegion(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(),
		`DELETE FROM regions WHERE id=$1`, id); err != nil {
		writeErrCode(w, 500, "falha_apagar", "falha ao apagar a região")
		return
	}
	s.publishRegions(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": id})
}

type regionAssignRequest struct {
	// 'organization', 'device' ou 'technician'.
	Target   string  `json:"target"`
	TargetID string  `json:"target_id"`
	RegionID *string `json:"region_id"`
}

// AssignRegion põe uma entidade numa região à mão.
//
// Existe porque nem tudo tem coordenada: a empresa não tem, e o dispositivo
// dela também não. O técnico tem — e para ele a atribuição é correção, não
// regra: quem informou lat/long já foi posto na região certa sozinho.
//
// Atribuir a organização propaga para os dispositivos dela que ainda não têm
// região própria. Os que já têm ficam como estão: uma máquina posta à mão numa
// região é uma decisão, e mudar a empresa de lugar não pode desfazê-la em
// silêncio.
func (s *Server) AssignRegion(w http.ResponseWriter, r *http.Request) {
	var req regionAssignRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	if strings.TrimSpace(req.TargetID) == "" {
		writeErrCode(w, 400, "alvo_obrigatorio", "informe o alvo")
		return
	}
	var table, column string
	switch req.Target {
	case "organization":
		table, column = "organizations", "id"
	case "device":
		table, column = "devices", "id"
	case "technician":
		table, column = "freelancer_profiles", "technician_id"
	default:
		writeErrCode(w, 400, "alvo_invalido",
			"o alvo deve ser organization, device ou technician")
		return
	}
	tag, err := s.Pool.Exec(r.Context(),
		`UPDATE `+table+` SET region_id=$2 WHERE `+column+`=$1`,
		req.TargetID, req.RegionID)
	if err != nil {
		writeErrCode(w, 400, "falha_atribuir", "falha ao atribuir a região")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErrCode(w, 404, "alvo_nao_encontrado", "alvo não encontrado")
		return
	}
	if req.Target == "organization" {
		s.propagateOrgRegion(r.Context(), req.TargetID)
	}
	s.publishRegions(r.Context())
	writeJSON(w, 200, map[string]any{"target": req.Target, "id": req.TargetID})
}

// propagateOrgRegion faz os dispositivos de uma organização herdarem a região
// dela — só os que ainda não têm uma própria.
//
// É o que faz a contagem de clientes por região existir sem exigir que alguém
// ponha máquina por máquina no lugar certo: cadastrar a empresa numa cidade
// põe o parque dela lá junto.
func (s *Server) propagateOrgRegion(ctx context.Context, orgID string) {
	_, _ = s.Pool.Exec(ctx, `
		UPDATE devices d SET region_id = o.region_id
		FROM networks n JOIN organizations o ON o.id = n.organization_id
		WHERE d.network_id = n.id AND o.id = $1 AND d.region_id IS NULL`, orgID)
}

// regionAt encontra a região a que um ponto pertence: a de centro mais próximo
// entre as que o contêm no raio.
//
// "Mais próximo entre as que contêm" e não "a primeira que contém": regiões
// podem se sobrepor — uma cidade dentro de uma área metropolitana é o caso
// normal — e nesse caso o lugar mais específico é o de centro mais perto.
//
// A conta é feita em Go, com o mesmo haversine que o despacho já usa, e não em
// SQL: são poucas regiões, e ter duas implementações da mesma distância seria
// ter duas respostas possíveis para a mesma pergunta.
func (s *Server) regionAt(ctx context.Context, lat, lon float64) *string {
	if lat == 0 && lon == 0 {
		return nil
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT id,center_lat,center_lon,radius_km FROM regions
		WHERE active AND center_lat IS NOT NULL`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var melhor string
	menor := math.Inf(1)
	for rows.Next() {
		var id string
		var clat, clon, raio float64
		if rows.Scan(&id, &clat, &clon, &raio) != nil {
			continue
		}
		d := haversine(lat, lon, clat, clon)
		if d <= raio && d < menor {
			melhor, menor = id, d
		}
	}
	if melhor == "" {
		return nil
	}
	return &melhor
}

// regionForTicket decide a região de um chamado, na ordem em que a informação
// é confiável.
//
// A coordenada do próprio chamado manda: é onde o atendimento vai acontecer. Só
// depois vem o dispositivo, e por último a organização — que é o lugar da
// empresa, não necessariamente o da máquina que quebrou.
//
// O avulso não tem organização, então para ele a cadeia é coordenada e depois
// dispositivo; se nenhum dos dois disser onde é, ele fica sem região, e o preço
// dele é o global. Chutar uma região seria pior do que não ter: cobraria pelo
// mercado de um lugar em que ele não está.
func (s *Server) regionForTicket(ctx context.Context, ticketID string) *string {
	var lat, lon float64
	var deviceRegion, orgRegion *string
	err := s.Pool.QueryRow(ctx, `
		SELECT coalesce((t.location->>'latitude')::float8,0),
		       coalesce((t.location->>'longitude')::float8,0),
		       d.region_id, o.region_id
		FROM support_tickets t
		LEFT JOIN devices d       ON d.id = t.device_id
		LEFT JOIN organizations o ON o.id = t.organization_id
		WHERE t.id=$1`, ticketID).Scan(&lat, &lon, &deviceRegion, &orgRegion)
	if err != nil {
		return nil
	}
	if byPoint := s.regionAt(ctx, lat, lon); byPoint != nil {
		return byPoint
	}
	if deviceRegion != nil {
		return deviceRegion
	}
	return orgRegion
}

// StampTicketRegion congela a região do chamado. É chamada na abertura, e o
// valor gravado é o que a precificação usa dali em diante: a empresa pode mudar
// de região amanhã, mas o que precificou este chamado foi onde ele nasceu.
func (s *Server) StampTicketRegion(ctx context.Context, ticketID string) {
	regionID := s.regionForTicket(ctx, ticketID)
	if regionID == nil {
		return
	}
	_, _ = s.Pool.Exec(ctx,
		`UPDATE support_tickets SET region_id=$2 WHERE id=$1 AND region_id IS NULL`,
		ticketID, *regionID)
}
