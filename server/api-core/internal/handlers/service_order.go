package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

// dispatchToFreelancers coloca a OS na fila dos técnicos (Fila B), ordenada por
// nota e proximidade, com a mesma oferta escalonada da Fila A.
//
// É chamada pela conversão em OS: no modelo, o que vai para a fila do técnico é
// a OS, não o chamado cru.
func (s *Server) dispatchToFreelancers(ctx context.Context, ticketID string) {
	var lat, lon float64
	_ = s.Pool.QueryRow(ctx, `
		SELECT coalesce((scheduled_location->>'latitude')::float8,0),
		       coalesce((scheduled_location->>'longitude')::float8,0)
		FROM service_orders WHERE ticket_id=$1`, ticketID).Scan(&lat, &lon)

	rows, err := s.Pool.Query(ctx, `
		SELECT technician_id,quality_score,coalesce(latitude,0),coalesce(longitude,0)
		FROM freelancer_profiles WHERE availability=true`)
	if err != nil {
		return
	}
	type candidato struct {
		id    string
		score float64
	}
	cs := []candidato{}
	for rows.Next() {
		var c candidato
		var clat, clon float64
		if rows.Scan(&c.id, &c.score, &clat, &clon) == nil {
			// Nota manda; distância desempata. Ambas na mesma escala de 1 a 5.
			c.score -= haversine(lat, lon, clat, clon) / 100
			cs = append(cs, c)
		}
	}
	rows.Close()
	for i := 0; i < len(cs); i++ {
		for j := i + 1; j < len(cs); j++ {
			if cs[j].score > cs[i].score {
				cs[i], cs[j] = cs[j], cs[i]
			}
		}
	}
	for rank, c := range cs {
		available := time.Now().UTC().Add(time.Duration(rank) * 30 * time.Second)
		_, _ = s.Pool.Exec(ctx, `
			INSERT INTO dispatch_offers(ticket_id,freelancer_id,rank,available_at,expires_at)
			VALUES($1,$2,$3,$4,$5)
			ON CONFLICT(ticket_id,freelancer_id) DO UPDATE
			SET rank=excluded.rank,available_at=excluded.available_at,expires_at=excluded.expires_at`,
			ticketID, c.id, rank+1, available, available.Add(15*time.Minute))
	}
	_, _ = s.Pool.Exec(ctx,
		`UPDATE support_tickets SET status='offered',updated_at=now() WHERE id=$1`, ticketID)
}

// StartServiceOrder marca o início da execução. Separado do aceite de
// propósito: o técnico aceita a OS quando decide atendê-la, e executa na data
// marcada — normalmente outro dia.
func (s *Server) StartServiceOrder(w http.ResponseWriter, r *http.Request, ticketID string) {
	c := middleware.ClaimsFrom(r.Context())
	var osStatus string
	if s.Pool.QueryRow(r.Context(), `
		SELECT status FROM service_orders
		WHERE ticket_id=$1 AND assigned_technician_id=$2`,
		ticketID, c.TechnicianID).Scan(&osStatus) != nil {
		writeErr(w, http.StatusForbidden, "esta OS não está atribuída a você")
		return
	}
	if osStatus != "assigned" {
		writeErr(w, http.StatusConflict, "a OS precisa estar atribuída para iniciar")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE service_orders SET status='in_progress',started_at=now() WHERE ticket_id=$1`, ticketID)
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE support_tickets SET status='in_progress',updated_at=now() WHERE id=$1`, ticketID)
	s.registrarEventoOS(r.Context(), ticketID, c.TechnicianID, "os_started", nil)
	s.publishTicket(r, ticketID, "os_started", map[string]any{"technician_id": c.TechnicianID})
	writeJSON(w, http.StatusOK, map[string]any{"status": "in_progress", "started_at": time.Now().UTC()})
}

// FinishServiceOrder encerra a parte do técnico e abre o período de
// confirmações. Não fecha nada sozinho: quem fecha é o conjunto das partes.
func (s *Server) FinishServiceOrder(w http.ResponseWriter, r *http.Request, ticketID string) {
	c := middleware.ClaimsFrom(r.Context())
	var req struct {
		Notas string `json:"notas"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	var osStatus string
	if s.Pool.QueryRow(r.Context(), `
		SELECT status FROM service_orders
		WHERE ticket_id=$1 AND assigned_technician_id=$2`,
		ticketID, c.TechnicianID).Scan(&osStatus) != nil {
		writeErr(w, http.StatusForbidden, "esta OS não está atribuída a você")
		return
	}
	if osStatus != "in_progress" {
		writeErr(w, http.StatusConflict, "a execução precisa ter sido iniciada")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE service_orders SET status='awaiting_confirmation',finished_at=now() WHERE ticket_id=$1`, ticketID)
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE support_tickets SET status='awaiting_confirmation',updated_at=now() WHERE id=$1`, ticketID)
	// Finalizar já é a confirmação do próprio técnico: ele declarou o serviço
	// concluído, não precisa declarar de novo.
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_closure_confirmations(ticket_id,role,actor_id)
		VALUES($1,'freelancer',$2) ON CONFLICT DO NOTHING`, ticketID, c.TechnicianID)
	s.registrarEventoOS(r.Context(), ticketID, c.TechnicianID, "os_finished",
		map[string]any{"notas": req.Notas})
	s.publishTicket(r, ticketID, "os_finished", map[string]any{"technician_id": c.TechnicianID})
	pendentes, _ := s.confirmacoesPendentes(r.Context(), ticketID)
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "awaiting_confirmation", "confirmacoes_pendentes": pendentes,
	})
}

// confirmacoesPendentes devolve quais papéis ainda precisam confirmar.
//
// Empresarial exige técnico e supervisor. Avulso exige também o cliente — é o
// dispositivo dele que foi atendido e ele não tem um supervisor próprio que o
// represente.
func (s *Server) confirmacoesPendentes(ctx context.Context, ticketID string) ([]string, error) {
	var standalone bool
	if err := s.Pool.QueryRow(ctx,
		`SELECT standalone FROM support_tickets WHERE id=$1`, ticketID).Scan(&standalone); err != nil {
		return nil, err
	}
	exigidos := []string{"freelancer", "supervisor"}
	if standalone {
		exigidos = append(exigidos, "cliente")
	}
	rows, err := s.Pool.Query(ctx,
		`SELECT role FROM ticket_closure_confirmations WHERE ticket_id=$1`, ticketID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	feitas := map[string]bool{}
	for rows.Next() {
		var papel string
		if rows.Scan(&papel) == nil {
			feitas[papel] = true
		}
	}
	pendentes := []string{}
	for _, papel := range exigidos {
		if !feitas[papel] {
			pendentes = append(pendentes, papel)
		}
	}
	return pendentes, nil
}

// fecharSeConfirmado encerra o chamado e a OS quando todas as partes
// confirmaram. Devolve se fechou.
func (s *Server) fecharSeConfirmado(ctx context.Context, ticketID string) bool {
	pendentes, err := s.confirmacoesPendentes(ctx, ticketID)
	if err != nil || len(pendentes) > 0 {
		return false
	}
	_, _ = s.Pool.Exec(ctx, `
		UPDATE service_orders SET status='completed',completed_at=now() WHERE ticket_id=$1`, ticketID)
	_, _ = s.Pool.Exec(ctx, `
		UPDATE support_tickets SET status='closed',closed_at=now(),updated_at=now() WHERE id=$1`, ticketID)
	_, _ = s.Pool.Exec(ctx, `
		UPDATE temporary_ticket_permissions SET status='revoked',revoked_at=now()
		WHERE ticket_id=$1 AND status='active'`, ticketID)
	// Apagar a subrede de sessão é o que revoga o alcance de rede, junto com o
	// pertencimento que o Authorizer consulta.
	_, _ = s.Pool.Exec(ctx, `DELETE FROM subnetworks WHERE ticket_id=$1`, ticketID)
	_ = s.ReconcileSessionIsolation(ctx)
	return true
}

// ConfirmClosure registra a confirmação de encerramento do staff.
func (s *Server) ConfirmClosure(w http.ResponseWriter, r *http.Request, ticketID string) {
	if !s.canManageTicket(r, ticketID) {
		writeErr(w, http.StatusForbidden, "sem permissão")
		return
	}
	c := middleware.ClaimsFrom(r.Context())
	var status string
	if s.Pool.QueryRow(r.Context(),
		`SELECT status FROM support_tickets WHERE id=$1`, ticketID).Scan(&status) != nil {
		writeErr(w, http.StatusNotFound, "chamado não encontrado")
		return
	}
	if status != "awaiting_confirmation" {
		writeErr(w, http.StatusConflict,
			"o técnico precisa finalizar a execução antes das confirmações")
		return
	}
	papel := "supervisor"
	if c.Role == models.RoleFreelancer {
		papel = "freelancer"
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_closure_confirmations(ticket_id,role,actor_id)
		VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, ticketID, papel, c.TechnicianID)
	fechou := s.fecharSeConfirmado(r.Context(), ticketID)
	pendentes, _ := s.confirmacoesPendentes(r.Context(), ticketID)
	s.publishTicket(r, ticketID, "closure_confirmed",
		map[string]any{"role": papel, "closed": fechou})
	writeJSON(w, http.StatusOK, map[string]any{
		"confirmado": papel, "chamado_fechado": fechou, "confirmacoes_pendentes": pendentes,
	})
}

// ClientConfirmClosure é a confirmação do cliente avulso, pelo dispositivo.
func (s *Server) ClientConfirmClosure(w http.ResponseWriter, r *http.Request) {
	var req standaloneBindRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo e token são obrigatórios")
		return
	}
	var ticketID, status string
	if s.Pool.QueryRow(r.Context(), `
		SELECT t.id,t.status FROM support_tickets t
		JOIN devices d ON d.id=t.opened_by_device_id
		WHERE d.id=$1 AND d.device_token=$2
		  AND t.status NOT IN ('closed','cancelled','expired')
		ORDER BY t.created_at DESC LIMIT 1`,
		req.DeviceID, req.DeviceToken).Scan(&ticketID, &status) != nil {
		writeErr(w, http.StatusNotFound, "nenhum chamado em aberto para este dispositivo")
		return
	}
	if status != "awaiting_confirmation" {
		writeErr(w, http.StatusConflict, "o atendimento ainda não foi finalizado pelo técnico")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_closure_confirmations(ticket_id,role,actor_id)
		VALUES($1,'cliente',$2) ON CONFLICT DO NOTHING`, ticketID, req.DeviceID)
	fechou := s.fecharSeConfirmado(r.Context(), ticketID)
	pendentes, _ := s.confirmacoesPendentes(r.Context(), ticketID)
	s.publishTicket(r, ticketID, "closure_confirmed",
		map[string]any{"role": "cliente", "closed": fechou})
	writeJSON(w, http.StatusOK, map[string]any{
		"confirmado": "cliente", "chamado_fechado": fechou, "confirmacoes_pendentes": pendentes,
	})
}

func (s *Server) registrarEventoOS(ctx context.Context, ticketID, technicianID, tipo string, payload map[string]any) {
	if payload == nil {
		payload = map[string]any{}
	}
	_, _ = s.Pool.Exec(ctx, `
		INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload)
		VALUES($1,$2,$3,$4)`, ticketID, technicianID, tipo, payload)
}
