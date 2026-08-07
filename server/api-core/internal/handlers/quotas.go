package handlers

import (
	"context"
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

// Cotas: quanto cada organização pode usar do que será cobrado.
//
// O admin edita quase tudo no TGDesk — percentuais por classe, taxa, promoção,
// piso e teto do valor, quem está ativo — e a cota entra nessa mesma família:
// é decisão do dono do produto, não de quem usa. Hoje ela limita supervisores
// vinculados; o dia em que houver cobrança, é daqui que o financeiro lê.
//
// Fica separada de pricing_rules de propósito. Lá é dinheiro; aqui é direito de
// uso. Misturar obrigaria toda leitura de preço a saber sobre cota, e são dois
// assuntos que mudam por motivos diferentes.

type organizationQuota struct {
	OrganizationID   string `json:"organization_id"`
	OrganizationName string `json:"organization_name"`

	MaxAffiliatedSupervisors int `json:"max_affiliated_supervisors"`

	// Quantas vagas já estão comprometidas — técnicos afiliados mais chaves
	// vinculadas emitidas e ainda não usadas. Vai junto porque um teto sem o
	// consumo ao lado não diz nada a quem está editando.
	UsedAffiliatedSupervisors int `json:"used_affiliated_supervisors"`

	MaxTechnicians *int   `json:"max_technicians"`
	MaxDevices     *int   `json:"max_devices"`
	Note           string `json:"note"`

	// Verdadeiro quando a organização não tem linha própria e está herdando o
	// padrão do produto. A tela precisa distinguir "definido como 2" de "usando
	// o padrão, que hoje é 2" — a segunda muda sozinha se o padrão mudar.
	UsingDefault bool `json:"using_default"`
}

// organizationQuotas lê a cota de cada organização já resolvida contra o
// padrão, para a tela do admin mostrar o efetivo e não o cru.
func (s *Server) organizationQuotas(ctx context.Context) []organizationQuota {
	out := []organizationQuota{}
	rows, err := s.Pool.Query(ctx, `
		SELECT o.id, o.name,
		       COALESCE(q.max_affiliated_supervisors, d.max_affiliated_supervisors),
		       affiliated_supervisors_used(o.id),
		       q.max_technicians, q.max_devices,
		       COALESCE(q.note,''), (q.organization_id IS NULL)
		FROM organizations o
		CROSS JOIN product_defaults d
		LEFT JOIN organization_quotas q ON q.organization_id = o.id
		WHERE o.status='ativa' AND d.singleton
		ORDER BY o.name`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var q organizationQuota
		if rows.Scan(&q.OrganizationID, &q.OrganizationName,
			&q.MaxAffiliatedSupervisors, &q.UsedAffiliatedSupervisors,
			&q.MaxTechnicians, &q.MaxDevices, &q.Note, &q.UsingDefault) == nil {
			out = append(out, q)
		}
	}
	return out
}

func (s *Server) ListQuotas(w http.ResponseWriter, r *http.Request) {
	var padrao int
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT max_affiliated_supervisors FROM product_defaults WHERE singleton`).
		Scan(&padrao)
	writeJSON(w, 200, map[string]any{
		"default_max_affiliated_supervisors": padrao,
		"organizations":                      s.organizationQuotas(r.Context()),
	})
}

func (s *Server) publishQuotas(ctx context.Context) {
	_ = presence.Publish(ctx, s.RDB, presence.Event{
		Type: "quotas", TargetID: "quotas",
	})
}

type quotaRequest struct {
	OrganizationID           string `json:"organization_id"`
	MaxAffiliatedSupervisors *int   `json:"max_affiliated_supervisors"`
	MaxTechnicians           *int   `json:"max_technicians"`
	MaxDevices               *int   `json:"max_devices"`
	Note                     string `json:"note"`
}

// SaveQuota grava a cota de uma organização.
//
// Não recusa teto abaixo do que já está em uso: o admin pode querer justamente
// impedir novas emissões sem desfazer as que existem. O limite é conferido na
// emissão da próxima chave, e lá "já passou do teto" simplesmente não deixa
// emitir mais.
func (s *Server) SaveQuota(w http.ResponseWriter, r *http.Request) {
	var req quotaRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.OrganizationID == "" {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	c := middleware.ClaimsFrom(r.Context())
	var editor *string
	if c != nil {
		editor = &c.TechnicianID
	}
	teto := 0
	if req.MaxAffiliatedSupervisors != nil && *req.MaxAffiliatedSupervisors >= 0 {
		teto = *req.MaxAffiliatedSupervisors
	}
	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO organization_quotas
			(organization_id, max_affiliated_supervisors, max_technicians,
			 max_devices, note, updated_by, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,now())
		ON CONFLICT (organization_id) DO UPDATE SET
			max_affiliated_supervisors=excluded.max_affiliated_supervisors,
			max_technicians=excluded.max_technicians,
			max_devices=excluded.max_devices,
			note=excluded.note, updated_by=excluded.updated_by,
			updated_at=now()`,
		req.OrganizationID, teto, req.MaxTechnicians, req.MaxDevices,
		req.Note, editor); err != nil {
		writeErrCode(w, 400, "falha_salvar_cota", "falha ao salvar a cota")
		return
	}
	s.publishQuotas(r.Context())
	writeJSON(w, 200, map[string]any{"organization_id": req.OrganizationID})
}

type productDefaultsRequest struct {
	MaxAffiliatedSupervisors int `json:"max_affiliated_supervisors"`
}

// SaveProductDefaults muda o padrão que vale para quem não tem cota própria.
//
// Mudar aqui move todas as organizações que estão herdando — que é o ponto de
// existir um padrão. Quem não quiser ser movido ganha linha própria.
func (s *Server) SaveProductDefaults(w http.ResponseWriter, r *http.Request) {
	var req productDefaultsRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.MaxAffiliatedSupervisors < 0 {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	c := middleware.ClaimsFrom(r.Context())
	var editor *string
	if c != nil {
		editor = &c.TechnicianID
	}
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE product_defaults
		SET max_affiliated_supervisors=$1, updated_by=$2, updated_at=now()
		WHERE singleton`, req.MaxAffiliatedSupervisors, editor); err != nil {
		writeErrCode(w, 400, "falha_salvar_padrao", "falha ao salvar o padrão")
		return
	}
	s.publishQuotas(r.Context())
	writeJSON(w, 200, map[string]any{
		"max_affiliated_supervisors": req.MaxAffiliatedSupervisors})
}
