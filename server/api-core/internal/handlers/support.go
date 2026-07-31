package handlers

import (
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

func (s *Server) publishTicket(r *http.Request, ticketID, kind string, payload any) {
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: kind, TargetID: ticketID, Payload: payload,
	})
}

func (s *Server) ensureStandaloneScope(r *http.Request) (string, string, error) {
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		return "", "", err
	}
	defer tx.Rollback(r.Context())
	var orgID, netID string
	err = tx.QueryRow(r.Context(), `SELECT organization_id,network_id FROM standalone_scope WHERE singleton=true`).Scan(&orgID, &netID)
	if err == nil {
		_ = tx.Commit(r.Context())
		return orgID, netID, nil
	}
	if err != pgx.ErrNoRows {
		return "", "", err
	}
	if err = tx.QueryRow(r.Context(), `
		INSERT INTO organizations(name) VALUES('Atendimento Avulso TGDesk')
		ON CONFLICT(name) DO UPDATE SET name=excluded.name RETURNING id`).Scan(&orgID); err != nil {
		return "", "", err
	}
	if err = tx.QueryRow(r.Context(), `
		INSERT INTO networks(organization_id,name,cidr_virtual) VALUES($1,'Pública isolada',NULL)
		ON CONFLICT(organization_id,name) DO UPDATE SET name=excluded.name RETURNING id`, orgID).Scan(&netID); err != nil {
		return "", "", err
	}
	if _, err = tx.Exec(r.Context(), `INSERT INTO standalone_scope(singleton,organization_id,network_id) VALUES(true,$1,$2)`, orgID, netID); err != nil {
		return "", "", err
	}
	if err = tx.Commit(r.Context()); err != nil {
		return "", "", err
	}
	return orgID, netID, nil
}

type clientTicketRequest struct {
	DeviceID    string         `json:"device_id"`
	DeviceToken string         `json:"device_token"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Modality    string         `json:"modality"`
	Standalone  bool           `json:"standalone"`
	Location    map[string]any `json:"location"`
}

func (s *Server) ClientOpenTicket(w http.ResponseWriter, r *http.Request) {
	var req clientTicketRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" || strings.TrimSpace(req.Title) == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo, token e título são obrigatórios")
		return
	}
	if req.Modality == "" {
		req.Modality = "virtual"
	}
	if req.Location == nil {
		req.Location = map[string]any{}
	}
	if req.Modality != "virtual" && req.Modality != "onsite" {
		writeErr(w, 400, "modalidade inválida")
		return
	}
	var state string
	if s.Pool.QueryRow(r.Context(), `SELECT state FROM devices WHERE id=$1 AND device_token=$2`, req.DeviceID, req.DeviceToken).Scan(&state) != nil {
		writeErr(w, 401, "dispositivo inválido")
		return
	}
	var orgID, netID string
	var err error
	if req.Standalone {
		orgID, netID, err = s.ensureStandaloneScope(r)
	} else {
		err = s.Pool.QueryRow(r.Context(), `SELECT n.organization_id,n.id FROM devices d JOIN networks n ON n.id=d.network_id WHERE d.id=$1`, req.DeviceID).Scan(&orgID, &netID)
	}
	if err != nil {
		writeErr(w, 400, "dispositivo sem escopo autorizado")
		return
	}
	var id string
	err = s.Pool.QueryRow(r.Context(), `
		INSERT INTO support_tickets(organization_id,network_id,device_id,opened_by_device_id,title,description,modality,standalone,location)
		VALUES($1,$2,$3,$3,$4,$5,$6,$7,$8) RETURNING id`,
		orgID, netID, req.DeviceID, strings.TrimSpace(req.Title), req.Description, req.Modality, req.Standalone, req.Location).Scan(&id)
	if err != nil {
		writeErr(w, 500, "falha ao abrir chamado")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_device_id,event_type,payload) VALUES($1,$2,'opened',$3)`, id, req.DeviceID, map[string]any{"modality": req.Modality, "standalone": req.Standalone})
	s.publishTicket(r, id, "ticket_created", map[string]any{"status": "open", "standalone": req.Standalone})
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "status": "open", "confirmation": true, "organization_id": orgID, "network_id": netID})
}

func (s *Server) canManageTicket(r *http.Request, ticketID string) bool {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil {
		return false
	}
	ok, err := s.Authorizer.CanManageTicket(r.Context(), c, ticketID)
	return err == nil && ok
}

func (s *Server) ListTickets(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	// Get filtered query from authorizer
	query, args, err := s.Authorizer.CanListTickets(r.Context(), c)
	if err != nil {
		writeErr(w, 500, "falha ao construir query de chamados")
		return
	}
	rows, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErr(w, 500, "falha ao listar chamados")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, title, desc, modality, status, org string
		var priority int
		var standalone bool
		var net, dev, freelancer *string
		var created, updated time.Time
		if rows.Scan(&id, &title, &desc, &modality, &priority, &status, &standalone, &org, &net, &dev, &freelancer, &created, &updated) == nil {
			out = append(out, map[string]any{"id": id, "title": title, "description": desc, "modality": modality, "priority": priority, "status": status, "standalone": standalone, "organization_id": org, "network_id": net, "device_id": dev, "assigned_freelancer_id": freelancer, "created_at": created, "updated_at": updated})
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) AddTicketMessage(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var req struct {
		Message     string           `json:"message"`
		Attachments []map[string]any `json:"attachments"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || strings.TrimSpace(req.Message) == "" {
		writeErr(w, 400, "mensagem obrigatória")
		return
	}
	c := middleware.ClaimsFrom(r.Context())
	var eid string
	err := s.Pool.QueryRow(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'message',$3) RETURNING id`, id, c.TechnicianID, map[string]any{"message": req.Message, "attachments": req.Attachments}).Scan(&eid)
	if err != nil {
		writeErr(w, 500, "falha ao registrar mensagem")
		return
	}
	s.publishTicket(r, id, "ticket_message", map[string]any{"event_id": eid})
	writeJSON(w, 201, map[string]any{"id": eid})
}

func (s *Server) TransitionTicket(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var req struct {
		Status string `json:"status"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, 400, "estado obrigatório")
		return
	}
	valid := map[string]map[string]bool{"open": {"closed": true, "cancelled": true, "offered": true}, "offered": {"accepted": true, "cancelled": true, "expired": true}, "accepted": {"in_progress": true, "closed": true, "cancelled": true}, "in_progress": {"closed": true, "cancelled": true}, "closed": {"reopened": true}, "reopened": {"in_progress": true, "closed": true}}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var old string
	if tx.QueryRow(r.Context(), `SELECT status FROM support_tickets WHERE id=$1 FOR UPDATE`, id).Scan(&old) != nil {
		writeErr(w, 404, "chamado não encontrado")
		return
	}
	if !valid[old][req.Status] {
		writeErr(w, 409, "transição inválida")
		return
	}
	closed := req.Status == "closed" || req.Status == "cancelled" || req.Status == "expired"
	_, err = tx.Exec(r.Context(), `UPDATE support_tickets SET status=$2,updated_at=now(),closed_at=CASE WHEN $3 THEN now() ELSE NULL END WHERE id=$1`, id, req.Status, closed)
	if err == nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'transition',$3)`, id, middleware.ClaimsFrom(r.Context()).TechnicianID, map[string]any{"from": old, "to": req.Status})
	}
	if closed && err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE temporary_ticket_permissions SET status='revoked',revoked_at=now() WHERE ticket_id=$1 AND status='active'`, id)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErr(w, 500, "falha ao alterar estado")
		return
	}
	s.publishTicket(r, id, "ticket_state", map[string]any{"from": old, "to": req.Status})
	writeJSON(w, 200, map[string]any{"id": id, "status": req.Status, "permissions_revoked": closed})
}

func (s *Server) ConvertServiceOrder(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var req struct {
		Items  any `json:"items"`
		Values any `json:"values"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	var osID string
	err := s.Pool.QueryRow(r.Context(), `INSERT INTO service_orders(ticket_id,items,values) VALUES($1,$2,$3) ON CONFLICT(ticket_id) DO UPDATE SET items=excluded.items,values=excluded.values RETURNING id`, id, req.Items, req.Values).Scan(&osID)
	if err != nil {
		writeErr(w, 500, "falha ao converter OS")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'service_order',$3)`, id, middleware.ClaimsFrom(r.Context()).TechnicianID, map[string]any{"service_order_id": osID})
	s.publishTicket(r, id, "service_order", map[string]any{"id": osID})
	writeJSON(w, 201, map[string]any{"id": osID, "ticket_id": id, "history_preserved": true})
}

func (s *Server) TicketAudit(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `SELECT id,event_type,payload,actor_technician_id,actor_device_id,created_at FROM ticket_events WHERE ticket_id=$1 ORDER BY created_at,id`, id)
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var eid, typ string
		var payload []byte
		var tech, dev *string
		var at time.Time
		if rows.Scan(&eid, &typ, &payload, &tech, &dev, &at) == nil {
			var p any
			_ = json.Unmarshal(payload, &p)
			out = append(out, map[string]any{"id": eid, "type": typ, "payload": p, "actor_technician_id": tech, "actor_device_id": dev, "created_at": at})
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) CreateFreelancer(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name           string   `json:"name"`
		SupervisorID   string   `json:"supervisor_id"`
		OrganizationID string   `json:"organization_id"`
		Quality        float64  `json:"quality_score"`
		Latitude       *float64 `json:"latitude"`
		Longitude      *float64 `json:"longitude"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || strings.TrimSpace(req.Name) == "" || req.SupervisorID == "" || req.OrganizationID == "" {
		writeErr(w, 400, "dados obrigatórios")
		return
	}
	if req.Quality == 0 {
		req.Quality = 50
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var id string
	err = tx.QueryRow(r.Context(), `INSERT INTO technicians(username,password_hash,role) VALUES($1,'!key-only!','freelancer') RETURNING id`, strings.TrimSpace(req.Name)).Scan(&id)
	if err == nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO freelancer_profiles(technician_id,supervisor_id,organization_id,quality_score,latitude,longitude) VALUES($1,$2,$3,$4,$5,$6)`, id, req.SupervisorID, req.OrganizationID, req.Quality, req.Latitude, req.Longitude)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErr(w, 409, "falha ao criar freelancer")
		return
	}
	writeJSON(w, 201, map[string]any{"id": id, "role": "freelancer", "supervisor_id": req.SupervisorID, "organization_id": req.OrganizationID, "network_management": false, "client_tab": true})
}

func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	const radius = 6371.
	dLat := (lat2 - lat1) * math.Pi / 180
	dLon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * radius * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

func (s *Server) DispatchTicket(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var req struct {
		DeadlineAt *time.Time `json:"deadline_at"`
		Latitude   float64    `json:"latitude"`
		Longitude  float64    `json:"longitude"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	var orgID string
	var standalone bool
	if s.Pool.QueryRow(r.Context(), `SELECT organization_id,standalone FROM support_tickets WHERE id=$1`, id).Scan(&orgID, &standalone) != nil {
		writeErr(w, 404, "chamado não encontrado")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `SELECT technician_id,quality_score,coalesce(latitude,0),coalesce(longitude,0) FROM freelancer_profiles WHERE (organization_id=$1 OR $2) AND availability=true ORDER BY quality_score DESC,technician_id`, orgID, standalone)
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer rows.Close()
	type candidate struct {
		id          string
		score, dist float64
	}
	cs := []candidate{}
	for rows.Next() {
		var c candidate
		var lat, lon float64
		_ = rows.Scan(&c.id, &c.score, &lat, &lon)
		c.dist = haversine(req.Latitude, req.Longitude, lat, lon)
		c.score = c.score - c.dist/10
		cs = append(cs, c)
	}
	for i := 0; i < len(cs); i++ {
		for j := i + 1; j < len(cs); j++ {
			if cs[j].score > cs[i].score {
				cs[i], cs[j] = cs[j], cs[i]
			}
		}
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer tx.Rollback(r.Context())
	for rank, c := range cs {
		available := time.Now().UTC().Add(time.Duration(rank) * 30 * time.Second)
		_, err = tx.Exec(r.Context(), `INSERT INTO dispatch_offers(ticket_id,freelancer_id,rank,available_at,expires_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT(ticket_id,freelancer_id) DO UPDATE SET rank=excluded.rank,available_at=excluded.available_at,expires_at=excluded.expires_at`, id, c.id, rank+1, available, available.Add(15*time.Minute))
		if err != nil {
			break
		}
	}
	if err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE support_tickets SET status='offered',deadline_at=$2,updated_at=now() WHERE id=$1`, id, req.DeadlineAt)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErr(w, 500, "falha ao despachar")
		return
	}
	s.publishTicket(r, id, "dispatch_offered", map[string]any{"offers": len(cs)})
	writeJSON(w, 201, map[string]any{
		"ticket_id": id, "offers": len(cs), "stagger_seconds": 30,
		"ranking_factors": []string{"location", "availability", "quality", "expiration"},
		"request_data": map[string]any{"location": map[string]float64{
			"latitude": req.Latitude, "longitude": req.Longitude,
		}, "deadline_at": req.DeadlineAt},
	})
}

func (s *Server) FreelancerQueue(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role != models.RoleFreelancer && c.Role != models.RoleSuperAdmin {
		writeErr(w, 403, "fila exclusiva")
		return
	}
	fid := c.TechnicianID
	if c.Role == models.RoleSuperAdmin && r.URL.Query().Get("freelancer_id") != "" {
		fid = r.URL.Query().Get("freelancer_id")
	}
	rows, err := s.Pool.Query(r.Context(), `SELECT o.ticket_id,o.rank,o.available_at,o.expires_at,t.title,t.modality,t.location FROM dispatch_offers o JOIN support_tickets t ON t.id=o.ticket_id WHERE o.freelancer_id=$1 AND o.available_at<=now() AND o.expires_at>now() AND t.status='offered' ORDER BY o.rank,o.available_at`, fid)
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, title, mod string
		var rank int
		var av, ex time.Time
		var loc []byte
		if rows.Scan(&id, &rank, &av, &ex, &title, &mod, &loc) == nil {
			var location any
			_ = json.Unmarshal(loc, &location)
			out = append(out, map[string]any{"ticket_id": id, "rank": rank, "available_at": av, "expires_at": ex, "title": title, "modality": mod, "location": location})
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) AcceptDispatch(w http.ResponseWriter, r *http.Request, id string) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role != models.RoleFreelancer {
		writeErr(w, 403, "apenas freelancer")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErr(w, 500, "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var modality string
	var deviceID *string
	var standalone bool
	err = tx.QueryRow(r.Context(), `UPDATE support_tickets SET assigned_freelancer_id=$2,status='accepted',accepted_at=now(),updated_at=now() WHERE id=$1 AND status='offered' AND EXISTS(SELECT 1 FROM dispatch_offers WHERE ticket_id=$1 AND freelancer_id=$2 AND available_at<=now() AND expires_at>now()) RETURNING modality,device_id,standalone`, id, c.TechnicianID).Scan(&modality, &deviceID, &standalone)
	if err != nil {
		writeErr(w, 409, "chamado já aceito ou oferta indisponível")
		return
	}
	_, err = tx.Exec(r.Context(), `UPDATE dispatch_offers SET accepted_at=CASE WHEN freelancer_id=$2 THEN now() ELSE accepted_at END WHERE ticket_id=$1`, id, c.TechnicianID)
	if err == nil && standalone && modality == "virtual" && deviceID != nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO temporary_ticket_permissions(ticket_id,freelancer_id,device_id,allow_remote,allow_analysis,expires_at) VALUES($1,$2,$3,true,true,now()+interval '4 hours') ON CONFLICT(ticket_id,freelancer_id,device_id) DO UPDATE SET status='active',allow_remote=true,allow_analysis=true,expires_at=excluded.expires_at`, id, c.TechnicianID, *deviceID)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErr(w, 500, "falha ao aceitar")
		return
	}
	s.publishTicket(r, id, "dispatch_accepted", map[string]any{"freelancer_id": c.TechnicianID})
	writeJSON(w, 200, map[string]any{"ticket_id": id, "status": "accepted", "temporary_access": standalone && modality == "virtual"})
}

func (s *Server) TicketPermission(w http.ResponseWriter, r *http.Request, id string) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role == models.RoleSuperAdmin {
		writeJSON(w, 200, map[string]any{"remote": true, "analysis": true, "admin_superset": true})
		return
	}
	var remote, analysis bool
	err := s.Pool.QueryRow(r.Context(), `SELECT allow_remote,allow_analysis FROM temporary_ticket_permissions WHERE ticket_id=$1 AND freelancer_id=$2 AND status='active' AND expires_at>now()`, id, c.TechnicianID).Scan(&remote, &analysis)
	if err != nil {
		writeJSON(w, 200, map[string]any{"remote": false, "analysis": false})
		return
	}
	writeJSON(w, 200, map[string]any{"remote": remote, "analysis": analysis})
}

func (s *Server) AddOnsiteEvidence(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var req struct {
		Type           string         `json:"type"`
		IdempotencyKey string         `json:"idempotency_key"`
		ContentHash    string         `json:"content_hash"`
		Metadata       map[string]any `json:"metadata"`
		CapturedAt     time.Time      `json:"captured_at"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.Type == "" || req.IdempotencyKey == "" || req.ContentHash == "" || req.CapturedAt.IsZero() {
		writeErr(w, 400, "evidência incompleta")
		return
	}
	var eid string
	var created bool
	err := s.Pool.QueryRow(r.Context(), `WITH ins AS (INSERT INTO onsite_evidence(ticket_id,evidence_type,idempotency_key,content_hash,metadata,captured_at) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(ticket_id,idempotency_key) DO NOTHING RETURNING id) SELECT id,true FROM ins UNION ALL SELECT id,false FROM onsite_evidence WHERE ticket_id=$1 AND idempotency_key=$3 LIMIT 1`, id, req.Type, req.IdempotencyKey, req.ContentHash, req.Metadata, req.CapturedAt).Scan(&eid, &created)
	if err != nil {
		writeErr(w, 400, "tipo ou metadados inválidos")
		return
	}
	writeJSON(w, 200, map[string]any{"id": eid, "created": created, "deduplicated": !created, "integrity_hash": req.ContentHash})
}

func (s *Server) ExportServiceOrder(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, 403, "sem permissão")
		return
	}
	var osID, status string
	var items, values, acceptance []byte
	if s.Pool.QueryRow(r.Context(), `SELECT id,status,items,values,customer_acceptance FROM service_orders WHERE ticket_id=$1`, id).Scan(&osID, &status, &items, &values, &acceptance) != nil {
		writeErr(w, 404, "OS não encontrada")
		return
	}
	rows, _ := s.Pool.Query(r.Context(), `SELECT evidence_type,content_hash,metadata,captured_at FROM onsite_evidence WHERE ticket_id=$1 ORDER BY captured_at`, id)
	defer rows.Close()
	evidence := []map[string]any{}
	for rows.Next() {
		var typ, hash string
		var meta []byte
		var at time.Time
		_ = rows.Scan(&typ, &hash, &meta, &at)
		var m any
		_ = json.Unmarshal(meta, &m)
		evidence = append(evidence, map[string]any{"type": typ, "hash": hash, "metadata": m, "captured_at": at})
	}
	var i, v, a any
	_ = json.Unmarshal(items, &i)
	_ = json.Unmarshal(values, &v)
	_ = json.Unmarshal(acceptance, &a)
	writeJSON(w, 200, map[string]any{"format": "tgdesk-service-order-v1", "printable": true, "exportable": true, "service_order_id": osID, "ticket_id": id, "status": status, "items": i, "values": v, "customer_acceptance": a, "evidence": evidence})
}

func parseIntDefault(raw string, fallback int) int {
	n, e := strconv.Atoi(raw)
	if e != nil {
		return fallback
	}
	return n
}
