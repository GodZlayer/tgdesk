package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

// Catálogo de tipos de chamado e a precificação, ambos como dado.
//
// O tipo do chamado não é ramo de código: é linha em ticket_types, com os
// campos que ele exige em ticket_type_fields. O formulário se monta a partir
// desse esquema e o leitor renderiza a partir do mesmo esquema, então
// acrescentar impressora, rede, TV, som ou celular é cadastro pela tela do
// admin — não release.
//
// A precificação segue a mesma regra em pricing_rules: percentual por classe,
// taxa do admin, promoção, vigência e os limites entre os quais o valor
// dinâmico varia são todos editáveis, e a escolha de qual regra vale é uma só
// consulta por especificidade, não código espalhado por chamada.

type ticketTypeField struct {
	ID           string `json:"id"`
	FieldKey     string `json:"field_key"`
	Label        string `json:"label"`
	Help         string `json:"help"`
	Kind         string `json:"kind"`
	Options      any    `json:"options"`
	Required     bool   `json:"required"`
	DependsOn    string `json:"depends_on,omitempty"`
	DependsValue string `json:"depends_value,omitempty"`
	Position     int    `json:"position"`
	Active       bool   `json:"active"`
}

type ticketType struct {
	Key      string            `json:"key"`
	Label    string            `json:"label"`
	Icon     string            `json:"icon"`
	Position int               `json:"position"`
	Active   bool              `json:"active"`
	Fields   []ticketTypeField `json:"fields"`
}

// ticketCatalog lê o catálogo inteiro. Ele é pequeno por natureza — uma dezena
// de tipos com meia dúzia de campos cada — e é lido junto do snapshot, então
// vale uma consulta só com os campos agregados no tipo.
func (s *Server) ticketCatalog(ctx context.Context, includeInactive bool) []ticketType {
	out := []ticketType{}
	filter := "WHERE active"
	if includeInactive {
		filter = ""
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT key,label,icon,position,active FROM ticket_types
		`+filter+` ORDER BY position,key`)
	if err != nil {
		return out
	}
	defer rows.Close()
	index := map[string]int{}
	for rows.Next() {
		var t ticketType
		if rows.Scan(&t.Key, &t.Label, &t.Icon, &t.Position, &t.Active) != nil {
			continue
		}
		t.Fields = []ticketTypeField{}
		index[t.Key] = len(out)
		out = append(out, t)
	}
	if len(out) == 0 {
		return out
	}

	fieldFilter := "WHERE active"
	if includeInactive {
		fieldFilter = ""
	}
	fieldRows, err := s.Pool.Query(ctx, `
		SELECT id,type_key,field_key,label,help,kind,options,required,
		       depends_on,depends_value,position,active
		FROM ticket_type_fields `+fieldFilter+` ORDER BY type_key,position,field_key`)
	if err != nil {
		return out
	}
	defer fieldRows.Close()
	for fieldRows.Next() {
		var f ticketTypeField
		var typeKey string
		var options []byte
		var dependsOn, dependsValue *string
		if fieldRows.Scan(&f.ID, &typeKey, &f.FieldKey, &f.Label, &f.Help, &f.Kind,
			&options, &f.Required, &dependsOn, &dependsValue, &f.Position, &f.Active) != nil {
			continue
		}
		_ = json.Unmarshal(options, &f.Options)
		if dependsOn != nil {
			f.DependsOn = *dependsOn
		}
		if dependsValue != nil {
			f.DependsValue = *dependsValue
		}
		if pos, ok := index[typeKey]; ok {
			out[pos].Fields = append(out[pos].Fields, f)
		}
	}
	return out
}

// ticketAmbientFields são atributos do próprio chamado, não campos do tipo. Uma
// condição pode apontar para eles — 'address' só existe quando modality é
// 'onsite' — sem que precisem ser declarados como campo, o que criaria uma
// segunda verdade sobre um dado que já é coluna.
var ticketAmbientFields = map[string]bool{
	"modality": true, "standalone": true, "priority": true,
}

// validateStructuredData confere os dados do chamado contra o esquema do tipo.
//
// É aqui que o contrato deixa de ser combinado e passa a ser verificado: chave
// que o tipo não declara é recusada, e obrigatório ausente também. Campo com
// condição só é exigido quando a condição está satisfeita — campo que nem
// aparece no formulário não pode barrar o envio.
//
// 'ambient' carrega os atributos do chamado que as condições podem consultar.
func (s *Server) validateStructuredData(ctx context.Context, typeKey string,
	data map[string]any, ambient map[string]string) error {
	if data == nil {
		data = map[string]any{}
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT field_key,label,required,depends_on,depends_value
		FROM ticket_type_fields WHERE type_key=$1 AND active
		ORDER BY position,field_key`, typeKey)
	if err != nil {
		return fmt.Errorf("falha ao ler o esquema do tipo")
	}
	defer rows.Close()

	declared := map[string]bool{}
	type pending struct {
		key, label, dependsOn, dependsValue string
		required                            bool
	}
	fields := []pending{}
	for rows.Next() {
		var p pending
		var dependsOn, dependsValue *string
		if rows.Scan(&p.key, &p.label, &p.required, &dependsOn, &dependsValue) != nil {
			continue
		}
		if dependsOn != nil {
			p.dependsOn = *dependsOn
		}
		if dependsValue != nil {
			p.dependsValue = *dependsValue
		}
		declared[p.key] = true
		fields = append(fields, p)
	}
	if len(fields) == 0 {
		return fmt.Errorf("tipo de chamado sem campos declarados")
	}

	for key := range data {
		if !declared[key] {
			return fmt.Errorf("campo %q não pertence ao tipo %q", key, typeKey)
		}
	}
	for _, f := range fields {
		if !f.required {
			continue
		}
		if f.dependsOn != "" {
			current := ""
			if raw, ok := data[f.dependsOn]; ok && raw != nil {
				current = fmt.Sprint(raw)
			} else if raw, ok := ambient[f.dependsOn]; ok {
				current = raw
			}
			if current != f.dependsValue {
				continue
			}
		}
		raw, ok := data[f.key]
		if !ok || raw == nil || strings.TrimSpace(fmt.Sprint(raw)) == "" {
			return fmt.Errorf("preencha %q", f.label)
		}
	}
	return nil
}

// TicketCatalog entrega o catálogo por requisição. A tela do técnico o recebe
// pelo canal, junto do snapshot; esta rota existe para o dispositivo do
// cliente, que fala com o servidor pelo próprio canal dele e não participa do
// snapshot do técnico.
func (s *Server) TicketCatalog(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, map[string]any{"types": s.ticketCatalog(r.Context(), false)})
}

// publishCatalog avisa as telas de que o catálogo mudou. O delta carrega o
// catálogo inteiro porque ele é pequeno e porque um tipo alterado costuma
// mexer em vários campos de uma vez — recortar daria mais código do que
// economia, pela mesma razão registrada em deltaFor.
func (s *Server) publishCatalog(ctx context.Context) {
	_ = presence.Publish(ctx, s.RDB, presence.Event{
		Type: "ticket_catalog", TargetID: "catalog",
	})
}

type ticketTypeRequest struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Icon     string `json:"icon"`
	Position *int   `json:"position"`
	Active   *bool  `json:"active"`
}

// SaveTicketType cria ou atualiza um tipo. A chave é imutável depois de criada
// porque os chamados já abertos apontam para ela; o que muda é rótulo, ícone,
// ordem e se está ativo.
func (s *Server) SaveTicketType(w http.ResponseWriter, r *http.Request) {
	var req ticketTypeRequest
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
		writeErrCode(w, 400, "chave_invalida", "a chave não pode conter espaços nem barras")
		return
	}
	icon := strings.TrimSpace(req.Icon)
	if icon == "" {
		icon = "devices_other"
	}
	position := 100
	if req.Position != nil {
		position = *req.Position
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	_, err := s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_types(key,label,icon,position,active)
		VALUES($1,$2,$3,$4,$5)
		ON CONFLICT (key) DO UPDATE SET
			label=EXCLUDED.label, icon=EXCLUDED.icon,
			position=EXCLUDED.position, active=EXCLUDED.active,
			updated_at=now()`,
		req.Key, req.Label, icon, position, active)
	if err != nil {
		writeErrCode(w, 500, "falha_salvar_tipo", "falha ao salvar o tipo")
		return
	}
	s.publishCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"key": req.Key})
}

// DeleteTicketType só remove tipo que nunca foi usado. Com chamado apontando
// para ele, apagar reescreveria história: o certo é desativar, e o tipo some
// dos formulários sem levar junto o que já aconteceu.
func (s *Server) DeleteTicketType(w http.ResponseWriter, r *http.Request, key string) {
	var usados int
	if s.Pool.QueryRow(r.Context(),
		`SELECT count(*) FROM support_tickets WHERE type_key=$1`, key).Scan(&usados) != nil {
		writeErrCode(w, 500, "falha_verificar_tipo", "falha ao verificar o tipo")
		return
	}
	if usados > 0 {
		writeErrCode(w, 409, "tipo_em_uso",
			fmt.Sprintf("%d chamado(s) usam este tipo; desative em vez de excluir", usados))
		return
	}
	if _, err := s.Pool.Exec(r.Context(), `DELETE FROM ticket_types WHERE key=$1`, key); err != nil {
		writeErrCode(w, 500, "falha_excluir_tipo", "falha ao excluir o tipo")
		return
	}
	s.publishCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": key})
}

type ticketFieldRequest struct {
	TypeKey      string  `json:"type_key"`
	FieldKey     string  `json:"field_key"`
	Label        string  `json:"label"`
	Help         string  `json:"help"`
	Kind         string  `json:"kind"`
	Options      any     `json:"options"`
	Required     *bool   `json:"required"`
	DependsOn    *string `json:"depends_on"`
	DependsValue *string `json:"depends_value"`
	Position     *int    `json:"position"`
	Active       *bool   `json:"active"`
}

// SaveTicketTypeField cria ou atualiza um campo do tipo.
func (s *Server) SaveTicketTypeField(w http.ResponseWriter, r *http.Request) {
	var req ticketFieldRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	req.TypeKey = strings.ToLower(strings.TrimSpace(req.TypeKey))
	req.FieldKey = strings.ToLower(strings.TrimSpace(req.FieldKey))
	req.Label = strings.TrimSpace(req.Label)
	if req.TypeKey == "" || req.FieldKey == "" || req.Label == "" {
		writeErrCode(w, 400, "tipo_campo_rotulo_obrigatorios",
			"tipo, chave do campo e rótulo são obrigatórios")
		return
	}
	if req.Kind == "" {
		req.Kind = "text"
	}
	// A condição precisa apontar para um campo que existe no mesmo tipo, senão
	// o campo condicional some do formulário sem que ninguém entenda por quê.
	if req.DependsOn != nil && strings.TrimSpace(*req.DependsOn) != "" {
		alvo := strings.TrimSpace(*req.DependsOn)
		if alvo == req.FieldKey {
			writeErrCode(w, 400, "condicao_circular", "o campo não pode depender de si mesmo")
			return
		}
		if !ticketAmbientFields[alvo] {
			var existe bool
			if s.Pool.QueryRow(r.Context(),
				`SELECT EXISTS(SELECT 1 FROM ticket_type_fields WHERE type_key=$1 AND field_key=$2)`,
				req.TypeKey, alvo).Scan(&existe) != nil || !existe {
				writeErrCode(w, 400, "condicao_sem_campo",
					fmt.Sprintf("o campo %q não existe neste tipo", alvo))
				return
			}
		}
	}
	if req.Options == nil {
		req.Options = []any{}
	}
	required := false
	if req.Required != nil {
		required = *req.Required
	}
	position := 100
	if req.Position != nil {
		position = *req.Position
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	_, err := s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_type_fields
			(type_key,field_key,label,help,kind,options,required,
			 depends_on,depends_value,position,active)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		ON CONFLICT (type_key,field_key) DO UPDATE SET
			label=EXCLUDED.label, help=EXCLUDED.help, kind=EXCLUDED.kind,
			options=EXCLUDED.options, required=EXCLUDED.required,
			depends_on=EXCLUDED.depends_on, depends_value=EXCLUDED.depends_value,
			position=EXCLUDED.position, active=EXCLUDED.active`,
		req.TypeKey, req.FieldKey, req.Label, strings.TrimSpace(req.Help), req.Kind,
		req.Options, required, req.DependsOn, req.DependsValue, position, active)
	if err != nil {
		writeErrCode(w, 500, "falha_salvar_campo", "falha ao salvar o campo")
		return
	}
	s.publishCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"type_key": req.TypeKey, "field_key": req.FieldKey})
}

// DeleteTicketTypeField recusa apagar campo do qual outro campo depende: sem
// isso a condição do outro apontaria para o vazio e ele sumiria em silêncio.
func (s *Server) DeleteTicketTypeField(w http.ResponseWriter, r *http.Request, id string) {
	var typeKey, fieldKey string
	if s.Pool.QueryRow(r.Context(),
		`SELECT type_key,field_key FROM ticket_type_fields WHERE id=$1`, id).
		Scan(&typeKey, &fieldKey) != nil {
		writeErrCode(w, 404, "campo_nao_encontrado", "campo não encontrado")
		return
	}
	var dependentes int
	if s.Pool.QueryRow(r.Context(),
		`SELECT count(*) FROM ticket_type_fields WHERE type_key=$1 AND depends_on=$2`,
		typeKey, fieldKey).Scan(&dependentes) == nil && dependentes > 0 {
		writeErrCode(w, 409, "campo_com_dependentes",
			fmt.Sprintf("%d campo(s) dependem deste; ajuste-os antes", dependentes))
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`DELETE FROM ticket_type_fields WHERE id=$1`, id); err != nil {
		writeErrCode(w, 500, "falha_excluir_campo", "falha ao excluir o campo")
		return
	}
	s.publishCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": id})
}

// ---------------------------------------------------------------------------
// Precificação
// ---------------------------------------------------------------------------

type pricingRuleRequest struct {
	ID             string     `json:"id"`
	Kind           string     `json:"kind"`
	Role           *string    `json:"role"`
	TicketTypeKey  *string    `json:"ticket_type_key"`
	OrganizationID *string    `json:"organization_id"`
	NetworkID      *string    `json:"network_id"`
	SubnetworkID   *string    `json:"subnetwork_id"`
	TechnicianID   *string    `json:"technician_id"`
	Standalone     *bool      `json:"standalone"`
	Percent        *float64   `json:"percent"`
	AmountCents    *int64     `json:"amount_cents"`
	MinCents       *int64     `json:"min_cents"`
	MaxCents       *int64     `json:"max_cents"`
	ValidFrom      *time.Time `json:"valid_from"`
	ValidUntil     *time.Time `json:"valid_until"`
	Note           string     `json:"note"`
	Active         *bool      `json:"active"`
}

// ListPricingRules devolve as regras na ordem em que a resolução as consulta —
// a mais específica primeiro — para que a tela do admin mostre exatamente a
// precedência que vale na prática.
func (s *Server) ListPricingRules(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, s.pricingRules(r.Context()))
}

func (s *Server) pricingRules(ctx context.Context) []map[string]any {
	out := []map[string]any{}
	rows, err := s.Pool.Query(ctx, `
		SELECT id,kind,role,ticket_type_key,organization_id,network_id,
		       subnetwork_id,technician_id,standalone,percent,amount_cents,
		       min_cents,max_cents,valid_from,valid_until,note,active,
		       specificity,created_at,updated_at
		FROM pricing_rules ORDER BY kind,specificity DESC,updated_at DESC`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, kind, note string
		var role, typeKey, org, net, sub, tech *string
		var standalone, active *bool
		var percent *float64
		var amount, minC, maxC *int64
		var from, until *time.Time
		var specificity int
		var created, updated time.Time
		if rows.Scan(&id, &kind, &role, &typeKey, &org, &net, &sub, &tech,
			&standalone, &percent, &amount, &minC, &maxC, &from, &until,
			&note, &active, &specificity, &created, &updated) != nil {
			continue
		}
		out = append(out, map[string]any{
			"id": id, "kind": kind, "role": role, "ticket_type_key": typeKey,
			"organization_id": org, "network_id": net, "subnetwork_id": sub,
			"technician_id": tech, "standalone": standalone, "percent": percent,
			"amount_cents": amount, "min_cents": minC, "max_cents": maxC,
			"valid_from": from, "valid_until": until, "note": note,
			"active": active, "specificity": specificity,
			"created_at": created, "updated_at": updated,
		})
	}
	return out
}

// publishPricing avisa a tela do admin de que as regras mudaram. Só ela
// recebe: preço é configuração do dono do produto.
func (s *Server) publishPricing(ctx context.Context) {
	_ = presence.Publish(ctx, s.RDB, presence.Event{
		Type: "pricing_rules", TargetID: "pricing",
	})
}

// SavePricingRule grava uma regra. As coerências que a tabela já garante —
// percentual exigido por 'share', piso menor que teto, vigência com início
// antes do fim — ficam no banco, e não repetidas aqui: repetir seria criar uma
// segunda verdade que pode divergir da primeira.
func (s *Server) SavePricingRule(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	var req pricingRuleRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	switch req.Kind {
	case "share", "fee", "promo", "bounds":
	default:
		writeErrCode(w, 400, "tipo_de_regra_invalido",
			"a regra deve ser share, fee, promo ou bounds")
		return
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	var criador *string
	if c != nil {
		criador = &c.TechnicianID
	}

	var id string
	var err error
	if strings.TrimSpace(req.ID) != "" {
		err = s.Pool.QueryRow(r.Context(), `
			UPDATE pricing_rules SET
				kind=$2,role=$3,ticket_type_key=$4,organization_id=$5,network_id=$6,
				subnetwork_id=$7,technician_id=$8,standalone=$9,percent=$10,
				amount_cents=$11,min_cents=$12,max_cents=$13,valid_from=$14,
				valid_until=$15,note=$16,active=$17,updated_at=now()
			WHERE id=$1 RETURNING id`,
			req.ID, req.Kind, req.Role, req.TicketTypeKey, req.OrganizationID,
			req.NetworkID, req.SubnetworkID, req.TechnicianID, req.Standalone,
			req.Percent, req.AmountCents, req.MinCents, req.MaxCents,
			req.ValidFrom, req.ValidUntil, strings.TrimSpace(req.Note), active).Scan(&id)
	} else {
		err = s.Pool.QueryRow(r.Context(), `
			INSERT INTO pricing_rules
				(kind,role,ticket_type_key,organization_id,network_id,subnetwork_id,
				 technician_id,standalone,percent,amount_cents,min_cents,max_cents,
				 valid_from,valid_until,note,active,created_by)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
			RETURNING id`,
			req.Kind, req.Role, req.TicketTypeKey, req.OrganizationID, req.NetworkID,
			req.SubnetworkID, req.TechnicianID, req.Standalone, req.Percent,
			req.AmountCents, req.MinCents, req.MaxCents, req.ValidFrom,
			req.ValidUntil, strings.TrimSpace(req.Note), active, criador).Scan(&id)
	}
	if err != nil {
		// A promoção única por escopo é a violação que o admin mais vai
		// encontrar, e "erro interno" não diria a ele o que fazer.
		if strings.Contains(err.Error(), "pricing_rules_promo_unica_por_escopo") {
			writeErrCode(w, 409, "promocao_duplicada",
				"já existe uma promoção ativa para esta especificação")
			return
		}
		writeErrCode(w, 400, "falha_salvar_regra", "falha ao salvar a regra: "+err.Error())
		return
	}
	s.publishPricing(r.Context())
	writeJSON(w, 200, map[string]any{"id": id})
}

func (s *Server) DeletePricingRule(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `DELETE FROM pricing_rules WHERE id=$1`, id); err != nil {
		writeErrCode(w, 500, "falha_excluir_regra", "falha ao excluir a regra")
		return
	}
	s.publishPricing(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": id})
}

// pricingScope é o recorte de um chamado para efeito de preço.
type pricingScope struct {
	TicketType     string
	OrganizationID *string
	NetworkID      *string
	SubnetworkID   *string
	TechnicianID   *string
	Standalone     bool
	At             time.Time
}

// ResolvedPricing é o que sobra depois da disputa entre as regras: um valor por
// papel e um conjunto único de taxa, promoção e limites.
type ResolvedPricing struct {
	Shares      map[string]float64 `json:"shares"`
	FeePercent  *float64           `json:"fee_percent,omitempty"`
	FeeCents    *int64             `json:"fee_cents,omitempty"`
	PromoPercnt *float64           `json:"promo_percent,omitempty"`
	PromoCents  *int64             `json:"promo_cents,omitempty"`
	MinCents    *int64             `json:"min_cents,omitempty"`
	MaxCents    *int64             `json:"max_cents,omitempty"`
}

// resolvePricing escolhe, para cada natureza de regra, a linha mais específica
// que casa com o chamado e está vigente. DISTINCT ON faz a disputa dentro do
// banco: subir todas as candidatas para decidir em Go daria o mesmo resultado
// com uma segunda cópia da regra de precedência para manter.
func (s *Server) resolvePricing(ctx context.Context, scope pricingScope) ResolvedPricing {
	out := ResolvedPricing{Shares: map[string]float64{}}
	at := scope.At
	if at.IsZero() {
		at = time.Now()
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT DISTINCT ON (kind,coalesce(role,''))
		       kind,role,percent,amount_cents,min_cents,max_cents
		FROM pricing_rules
		WHERE active
		  AND (valid_from  IS NULL OR valid_from  <= $7)
		  AND (valid_until IS NULL OR valid_until >  $7)
		  AND (ticket_type_key IS NULL OR ticket_type_key = $1)
		  AND (organization_id IS NULL OR organization_id = $2)
		  AND (network_id      IS NULL OR network_id      = $3)
		  AND (subnetwork_id   IS NULL OR subnetwork_id   = $4)
		  AND (technician_id   IS NULL OR technician_id   = $5)
		  AND (standalone      IS NULL OR standalone      = $6)
		ORDER BY kind,coalesce(role,''),specificity DESC,updated_at DESC`,
		scope.TicketType, scope.OrganizationID, scope.NetworkID,
		scope.SubnetworkID, scope.TechnicianID, scope.Standalone, at)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var kind string
		var role *string
		var percent *float64
		var amount, minC, maxC *int64
		if rows.Scan(&kind, &role, &percent, &amount, &minC, &maxC) != nil {
			continue
		}
		switch kind {
		case "share":
			if role != nil && percent != nil {
				out.Shares[*role] = *percent
			}
		case "fee":
			out.FeePercent, out.FeeCents = percent, amount
		case "promo":
			out.PromoPercnt, out.PromoCents = percent, amount
		case "bounds":
			out.MinCents, out.MaxCents = minC, maxC
		}
	}
	return out
}
