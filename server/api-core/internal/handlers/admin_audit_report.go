package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (s *Server) AuditLiveReport(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 30
	}
	since := time.Now().AddDate(0, 0, -days)

	sections := []map[string]any{}
	rows, err := s.Pool.Query(ctx, `
		SELECT d.key,d.label,d.description,d.position,d.investor_visible,
		       count(e.id) AS total,
		       count(e.id) FILTER (WHERE e.created_at >= $1) AS recent,
		       count(e.id) FILTER (WHERE e.severity IN ('warning','critical')) AS risks,
		       coalesce(sum(e.amount_cents),0) AS amount_cents,
		       max(e.created_at) AS last_event
		FROM audit_domains d
		LEFT JOIN audit_events e ON e.domain_key=d.key
		GROUP BY d.key,d.label,d.description,d.position,d.investor_visible
		ORDER BY d.position,d.label`, since)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var key, label, description string
			var position int
			var investorVisible bool
			var total, recent, risks, amount int64
			var last *time.Time
			if rows.Scan(&key, &label, &description, &position, &investorVisible,
				&total, &recent, &risks, &amount, &last) != nil {
				continue
			}
			sections = append(sections, map[string]any{
				"key": key, "label": label, "description": description,
				"position": position, "investor_visible": investorVisible,
				"total_events": total, "recent_events": recent,
				"risk_events": risks, "amount_cents": amount,
				"last_event_at": last,
			})
		}
	}

	metrics := s.auditInvestorMetrics(ctx, since)
	recentEvents := s.auditEvents(ctx, since, "", 80)
	writeJSON(w, 200, map[string]any{
		"kind":         "tgdesk.audit.executive_presentation",
		"title":        "Auditoria executiva TGDesk",
		"subtitle":     "Painel corporativo com gráficos, detalhes e leitura de investidor sobre operação, vínculos e finanças.",
		"generated_at": time.Now(),
		"period_days":  days,
		"presentation_mode": map[string]any{
			"render":                 "client",
			"slide_feeling":          true,
			"interactive_drill_down": true,
			"charts":                 []string{"pizza", "barra", "cards", "timeline"},
			"detail_endpoint":        "/api/v1/admin/audit/events/{id}",
		},
		"metrics":       metrics,
		"sections":      sections,
		"recent_events": recentEvents,
	})
}

func (s *Server) AuditDomainEvents(w http.ResponseWriter, r *http.Request, domain string) {
	domain = strings.TrimSpace(domain)
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 30
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	writeJSON(w, 200, s.auditEvents(r.Context(), time.Now().AddDate(0, 0, -days), domain, limit))
}

func (s *Server) AuditEventDetail(w http.ResponseWriter, r *http.Request, id string) {
	var payload []byte
	var out = map[string]any{}
	err := s.Pool.QueryRow(r.Context(), `
		SELECT e.id,e.domain_key,d.label,e.severity,e.relation_degree,e.event_type,
		       e.entity_type,e.entity_id,e.actor_technician_id,e.actor_device_id,
		       e.organization_id,e.network_id,e.ticket_id,e.region_id,e.amount_cents,
		       e.payload,e.source_table,e.source_id,e.investor_visible,e.created_at
		FROM audit_events e
		JOIN audit_domains d ON d.key=e.domain_key
		WHERE e.id=$1`, id).Scan(
		field(&out, "id"), field(&out, "domain_key"), field(&out, "domain_label"),
		field(&out, "severity"), field(&out, "relation_degree"), field(&out, "event_type"),
		field(&out, "entity_type"), field(&out, "entity_id"), field(&out, "actor_technician_id"),
		field(&out, "actor_device_id"), field(&out, "organization_id"), field(&out, "network_id"),
		field(&out, "ticket_id"), field(&out, "region_id"), field(&out, "amount_cents"),
		&payload, field(&out, "source_table"), field(&out, "source_id"),
		field(&out, "investor_visible"), field(&out, "created_at"))
	if err != nil {
		writeErrCode(w, 404, "evento_nao_encontrado", "evento não encontrado")
		return
	}
	var data any
	_ = json.Unmarshal(payload, &data)
	out["payload"] = data
	out["popup"] = map[string]any{
		"title":    out["event_type"],
		"sections": []string{"Resumo", "Atores", "Entidades", "Payload bruto", "Origem"},
	}
	writeJSON(w, 200, out)
}

func (s *Server) auditEvents(ctx context.Context, since time.Time, domain string, limit int) []map[string]any {
	where := "WHERE e.created_at >= $1"
	args := []any{since, limit}
	if domain != "" {
		where += " AND e.domain_key=$3"
		args = []any{since, limit, domain}
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT e.id,e.domain_key,d.label,e.severity,e.relation_degree,e.event_type,
		       e.entity_type,e.entity_id,e.ticket_id,e.organization_id,e.region_id,
		       e.amount_cents,e.investor_visible,e.created_at
		FROM audit_events e
		JOIN audit_domains d ON d.key=e.domain_key
		`+where+`
		ORDER BY e.created_at DESC,e.id DESC LIMIT $2`, args...)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		row := map[string]any{}
		if rows.Scan(field(&row, "id"), field(&row, "domain_key"), field(&row, "domain_label"),
			field(&row, "severity"), field(&row, "relation_degree"), field(&row, "event_type"),
			field(&row, "entity_type"), field(&row, "entity_id"), field(&row, "ticket_id"),
			field(&row, "organization_id"), field(&row, "region_id"), field(&row, "amount_cents"),
			field(&row, "investor_visible"), field(&row, "created_at")) == nil {
			out = append(out, row)
		}
	}
	return out
}

func (s *Server) auditInvestorMetrics(ctx context.Context, since time.Time) map[string]any {
	metrics := map[string]any{}
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM support_tickets WHERE created_at >= $1`, since).
		Scan(field(&metrics, "tickets_opened"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM service_orders WHERE created_at >= $1`, since).
		Scan(field(&metrics, "service_orders_created"))
	_ = s.Pool.QueryRow(ctx, `SELECT coalesce(sum(total_cents),0) FROM service_orders WHERE created_at >= $1`, since).
		Scan(field(&metrics, "service_orders_total_cents"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM devices WHERE state='ativo'`).
		Scan(field(&metrics, "active_devices"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM freelancer_profiles WHERE availability`).
		Scan(field(&metrics, "available_technicians"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM organizations`).
		Scan(field(&metrics, "organizations"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM regions WHERE active`).
		Scan(field(&metrics, "active_regions"))
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE severity IN ('warning','critical') AND created_at >= $1`, since).
		Scan(field(&metrics, "risk_events"))
	return metrics
}

func field(target *map[string]any, key string) any {
	var value any
	return scannerFunc(func(src any) error {
		value = src
		(*target)[key] = value
		return nil
	})
}

type scannerFunc func(any) error

func (f scannerFunc) Scan(src any) error { return f(src) }
