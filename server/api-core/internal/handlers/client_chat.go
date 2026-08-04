package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

// clientTicketAuth valida device_id + device_token e devolve o chamado aberto
// do dispositivo. Todo endpoint de chat do cliente passa por aqui: o cliente
// não tem sessão de técnico, sua credencial é a identidade do dispositivo.
func (s *Server) clientTicketAuth(r *http.Request, req *standaloneBindRequest) (string, error) {
	var ticketID string
	err := s.Pool.QueryRow(r.Context(), `
		SELECT t.id FROM support_tickets t
		JOIN devices d ON d.id = t.opened_by_device_id
		WHERE d.id=$1 AND d.device_token=$2
		  AND t.status NOT IN ('closed','cancelled','expired')
		ORDER BY t.created_at DESC LIMIT 1`,
		req.DeviceID, req.DeviceToken).Scan(&ticketID)
	return ticketID, err
}

type clientThreadRequest struct {
	standaloneBindRequest
	Message string `json:"message"`
}

// ClientTicketThread devolve a conversa do chamado e os pedidos de acesso
// remoto aguardando resposta. Se vier `message`, publica a mensagem do cliente
// antes de responder — assim a tela faz uma chamada só.
//
// O cliente entra no chat como actor_device_id: quem fala é o dispositivo, que
// é como o modelo já representa o cliente.
func (s *Server) ClientTicketThread(w http.ResponseWriter, r *http.Request) {
	var req clientThreadRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo e token são obrigatórios")
		return
	}
	ticketID, err := s.clientTicketAuth(r, &req.standaloneBindRequest)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{"open": false})
		return
	}
	if texto := strings.TrimSpace(req.Message); texto != "" {
		var eventID string
		if s.Pool.QueryRow(r.Context(), `
			INSERT INTO ticket_events(ticket_id,actor_device_id,event_type,payload)
			VALUES($1,$2,'client_message',$3) RETURNING id`,
			ticketID, req.DeviceID,
			map[string]any{"message": texto, "from": "cliente"}).Scan(&eventID) == nil {
			s.publishTicket(r, ticketID, "client_message", map[string]any{"event_id": eventID})
		}
	}

	writeJSON(w, http.StatusOK, s.clientThreadPayload(r.Context(), ticketID))
}

// clientThreadPayload monta a conversa do cliente. É o mesmo conteúdo que o
// canal WebSocket empurra ao dispositivo — a tela nunca precisa pedir.
func (s *Server) clientThreadPayload(ctx context.Context, ticketID string) map[string]any {
	mensagens := []map[string]any{}
	// SÓ 'client_message'. O event_type 'message' é o canal INTERNO entre
	// supervisor e técnico — são dois chats distintos, e o cliente não tem
	// nada que ver a conversa que os dois têm sobre o caso dele.
	rows, err := s.Pool.Query(ctx, `
		SELECT e.payload->>'message', e.actor_device_id IS NOT NULL,
		       coalesce(t.username,''), e.created_at
		FROM ticket_events e
		LEFT JOIN technicians t ON t.id = e.actor_technician_id
		WHERE e.ticket_id=$1 AND e.event_type='client_message'
		ORDER BY e.created_at`, ticketID)
	if err == nil {
		for rows.Next() {
			var texto *string
			var doCliente bool
			var autor string
			var em time.Time
			if rows.Scan(&texto, &doCliente, &autor, &em) == nil && texto != nil {
				mensagens = append(mensagens, map[string]any{
					"message": *texto, "from_client": doCliente,
					"author": autor, "at": em.UTC().Format(time.RFC3339),
				})
			}
		}
		rows.Close()
	}

	pedidos := []map[string]any{}
	consentRows, err := s.Pool.Query(ctx, `
		SELECT c.id, coalesce(t.username,'técnico'), c.motivo, c.requested_at
		FROM remote_access_consents c
		JOIN technicians t ON t.id = c.technician_id
		WHERE c.ticket_id=$1 AND c.status='pending'
		ORDER BY c.requested_at`, ticketID)
	if err == nil {
		for consentRows.Next() {
			var id, autor, motivo string
			var em time.Time
			if consentRows.Scan(&id, &autor, &motivo, &em) == nil {
				pedidos = append(pedidos, map[string]any{
					"id": id, "requested_by": autor, "motivo": motivo,
					"at": em.UTC().Format(time.RFC3339),
				})
			}
		}
		consentRows.Close()
	}

	var protocol, status string
	_ = s.Pool.QueryRow(ctx,
		`SELECT protocol,status FROM support_tickets WHERE id=$1`, ticketID).
		Scan(&protocol, &status)
	return map[string]any{
		"open": true, "id": ticketID, "protocol": protocol, "status": status,
		"messages": mensagens, "remote_access_requests": pedidos,
	}
}

type clientConsentRequest struct {
	standaloneBindRequest
	ConsentID string `json:"consent_id"`
	Grant     bool   `json:"grant"`
}

// ClientRespondRemoteAccess registra a decisão do cliente sobre um pedido de
// acesso remoto. Só a concessão do cliente liga allow_remote.
func (s *Server) ClientRespondRemoteAccess(w http.ResponseWriter, r *http.Request) {
	var req clientConsentRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" ||
		req.DeviceToken == "" || req.ConsentID == "" {
		writeErr(w, http.StatusBadRequest, "dispositivo, token e pedido são obrigatórios")
		return
	}
	ticketID, err := s.clientTicketAuth(r, &req.standaloneBindRequest)
	if err != nil {
		writeErr(w, http.StatusNotFound, "nenhum chamado em aberto para este dispositivo")
		return
	}
	novo := "denied"
	if req.Grant {
		novo = "granted"
	}
	var technicianID string
	// O device_id do consentimento tem que bater com o dispositivo que está
	// respondendo: ninguém autoriza acesso à máquina de outra pessoa.
	if s.Pool.QueryRow(r.Context(), `
		UPDATE remote_access_consents SET status=$3, responded_at=now()
		WHERE id=$1 AND ticket_id=$2 AND device_id=$4 AND status='pending'
		RETURNING technician_id`,
		req.ConsentID, ticketID, novo, req.DeviceID).Scan(&technicianID) != nil {
		writeErr(w, http.StatusConflict, "pedido não encontrado ou já respondido")
		return
	}
	if req.Grant {
		_, _ = s.Pool.Exec(r.Context(), `
			INSERT INTO temporary_ticket_permissions
				(ticket_id,freelancer_id,device_id,allow_remote,allow_analysis,exclusive,expires_at)
			VALUES($1,$2,$3,true,true,true,now()+interval '30 days')
			ON CONFLICT(ticket_id,freelancer_id,device_id) DO UPDATE
			SET status='active', allow_remote=true, allow_analysis=true`,
			ticketID, technicianID, req.DeviceID)
	} else {
		_, _ = s.Pool.Exec(r.Context(), `
			UPDATE temporary_ticket_permissions SET allow_remote=false
			WHERE ticket_id=$1 AND freelancer_id=$2 AND device_id=$3`,
			ticketID, technicianID, req.DeviceID)
	}
	texto := "O cliente não autorizou o acesso remoto."
	if req.Grant {
		texto = "O cliente autorizou o acesso remoto."
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_events(ticket_id,actor_device_id,event_type,payload)
		VALUES($1,$2,'client_message',$3)`,
		ticketID, req.DeviceID, map[string]any{"message": texto, "from": "cliente"})
	s.publishTicket(r, ticketID, "remote_access_response",
		map[string]any{"granted": req.Grant, "technician_id": technicianID})
	writeJSON(w, http.StatusOK, map[string]any{"status": novo})
}

// RequestRemoteAccess é o pedido do staff para controlar a máquina do cliente.
// Não concede nada: cria o pedido e o publica no chat, onde o cliente decide.
func (s *Server) RequestRemoteAccess(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErr(w, http.StatusForbidden, "sem permissão")
		return
	}
	var req struct {
		Motivo string `json:"motivo"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	c := middleware.ClaimsFrom(r.Context())
	var deviceID *string
	var standalone bool
	var modality string
	if s.Pool.QueryRow(r.Context(),
		`SELECT device_id,standalone,modality FROM support_tickets WHERE id=$1`, id).
		Scan(&deviceID, &standalone, &modality) != nil || deviceID == nil {
		writeErr(w, http.StatusConflict, "chamado sem dispositivo alvo")
		return
	}
	// Regras de acesso remoto ao cliente avulso:
	//   - supervisor: só com a permissão do cliente;
	//   - técnico: só se o chamado for virtual E o cliente permitir.
	// Presencial não tem acesso remoto para pedir, então o pedido é recusado
	// aqui em vez de chegar ao cliente como uma escolha que não existe.
	if standalone && c.Role != models.RoleSupervisor &&
		c.Role != models.RoleSuperAdmin && modality != "virtual" {
		writeErr(w, http.StatusConflict,
			"acesso remoto só se aplica a chamado virtual")
		return
	}
	var consentID string
	if s.Pool.QueryRow(r.Context(), `
		INSERT INTO remote_access_consents(ticket_id,technician_id,device_id,motivo)
		VALUES($1,$2,$3,$4)
		ON CONFLICT (ticket_id,technician_id) WHERE status='pending'
		DO UPDATE SET motivo=excluded.motivo, requested_at=now()
		RETURNING id`, id, c.TechnicianID, *deviceID,
		strings.TrimSpace(req.Motivo)).Scan(&consentID) != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao registrar pedido")
		return
	}
	mensagem := "Pedido de acesso remoto ao seu computador."
	if m := strings.TrimSpace(req.Motivo); m != "" {
		mensagem += " Motivo: " + m
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload)
		VALUES($1,$2,'client_message',$3)`,
		id, c.TechnicianID, map[string]any{"message": mensagem})
	s.publishTicket(r, id, "remote_access_requested", map[string]any{"consent_id": consentID})
	writeJSON(w, http.StatusCreated, map[string]any{"id": consentID, "status": "pending"})
}

// grantAnalysisOnly dá a quem assume o chamado acesso a testes e diagnóstico,
// e explicitamente NÃO a acesso remoto. É o que permite ao supervisor
// investigar a causa real antes de decidir se abre uma OS.
func (s *Server) grantAnalysisOnly(ctx context.Context, ticketID, technicianID, deviceID string) {
	_, _ = s.Pool.Exec(ctx, `
		INSERT INTO temporary_ticket_permissions
			(ticket_id,freelancer_id,device_id,allow_remote,allow_analysis,exclusive,expires_at)
		VALUES($1,$2,$3,false,true,false,now()+interval '30 days')
		ON CONFLICT(ticket_id,freelancer_id,device_id) DO UPDATE
		SET status='active', allow_analysis=true`,
		ticketID, technicianID, deviceID)
}
