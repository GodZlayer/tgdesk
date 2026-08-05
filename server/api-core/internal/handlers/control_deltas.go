package handlers

import (
	"context"
	"encoding/json"
	"time"

	"tgdesk/api-core/internal/auth"
)

// Delta do canal de controle: o que mudou, e só isso.
//
// O canal do técnico reenviava o snapshot inteiro — organizações, redes,
// subredes e dispositivos, reconsultados no banco — a cada evento que não
// fosse presença ou telemetria. Uma mensagem de chat custava quatro consultas
// vezes o número de técnicos conectados, para entregar um punhado de bytes de
// informação nova.
//
// Aqui o snapshot volta a ser o que deveria: a abertura da sessão. Depois
// dela, cada evento carrega a linha que mudou. O desenho da tela — layout,
// rótulos, cores, ordem — é do cliente e não trafega.

// ticketDelta devolve o chamado que mudou, no mesmo formato de ListTickets,
// para que a tela aplique a linha sem precisar reler a lista.
func (s *Server) ticketDelta(ctx context.Context, ticketID string) map[string]any {
	var id, title, desc, modality, status, org string
	var priority int
	var standalone bool
	var protocol *string
	var net, dev, freelancer, supervisor *string
	var created, updated time.Time
	err := s.Pool.QueryRow(ctx, `
		SELECT id,title,description,modality,priority,status,standalone,
		       protocol,organization_id,network_id,device_id,
		       assigned_freelancer_id,supervisor_id,created_at,updated_at
		FROM support_tickets WHERE id=$1`, ticketID).
		Scan(&id, &title, &desc, &modality, &priority, &status, &standalone,
			&protocol, &org, &net, &dev, &freelancer, &supervisor,
			&created, &updated)
	if err != nil {
		return nil
	}
	return map[string]any{
		"id": id, "title": title, "description": desc, "modality": modality,
		"priority": priority, "status": status, "standalone": standalone,
		"protocol": protocol, "organization_id": org, "network_id": net,
		"device_id": dev, "assigned_freelancer_id": freelancer,
		"supervisor_id": supervisor, "created_at": created, "updated_at": updated,
	}
}

// ticketEventDelta devolve um evento do chamado — mensagem, etapa de OS,
// confirmação de fechamento. É a unidade da conversa e do histórico, que são
// a mesma lista vista de dois jeitos.
func (s *Server) ticketEventDelta(ctx context.Context, ticketID, eventID string) map[string]any {
	query := `SELECT id,ticket_id,event_type,payload,actor_technician_id,
	                 actor_device_id,created_at
	          FROM ticket_events WHERE `
	args := []any{}
	if eventID != "" {
		query += `id=$1`
		args = append(args, eventID)
	} else {
		// Sem id explícito vale o último do chamado: alguns eventos avisam da
		// mudança sem carregar qual linha a produziu.
		query += `ticket_id=$1 ORDER BY created_at DESC, id DESC LIMIT 1`
		args = append(args, ticketID)
	}
	var id, tid, kind string
	var payload []byte
	var tech, device *string
	var at time.Time
	if s.Pool.QueryRow(ctx, query, args...).
		Scan(&id, &tid, &kind, &payload, &tech, &device, &at) != nil {
		return nil
	}
	var body any
	_ = json.Unmarshal(payload, &body)
	return map[string]any{
		"id": id, "ticket_id": tid, "type": kind, "payload": body,
		"actor_technician_id": tech, "actor_device_id": device,
		"created_at": at,
	}
}

// deviceDelta devolve o dispositivo que mudou, no formato que a lista usa.
func (s *Server) deviceDelta(ctx context.Context, deviceID string) map[string]any {
	var id, hostname, displayName, mac, pubkey, role, state, rustdeskID string
	var networkID, subnetworkID *string
	var networks, subnetworks []string
	var lastSeen *time.Time
	var created, updated time.Time
	err := s.Pool.QueryRow(ctx, `
		SELECT d.id,d.network_id,
		       coalesce((SELECT array_agg(dn.network_id::text ORDER BY dn.created_at)
		                 FROM device_networks dn WHERE dn.device_id=d.id),ARRAY[]::text[]),
		       d.subnetwork_id,
		       coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at)
		                 FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),
		       d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),
		       coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,
		       d.created_at,d.updated_at,coalesce(d.rustdesk_id,'')
		FROM devices d WHERE d.id=$1`, deviceID).
		Scan(&id, &networkID, &networks, &subnetworkID, &subnetworks, &hostname,
			&displayName, &mac, &pubkey, &role, &state, &lastSeen,
			&created, &updated, &rustdeskID)
	if err != nil {
		return nil
	}
	return map[string]any{
		"id": id, "network_id": networkID, "network_ids": networks,
		"subnetwork_id": subnetworkID, "subnetwork_ids": subnetworks,
		"hostname": hostname, "display_name": displayName, "mac": mac,
		"wg_pubkey": pubkey, "role": role, "state": state,
		"last_seen_at": lastSeen, "created_at": created,
		"updated_at": updated, "rustdesk_id": rustdeskID,
	}
}

// deltaFor traduz um evento na mensagem que a tela precisa receber. Devolver
// nil significa que o evento não muda conteúdo nenhum e basta o aviso.
//
// Eventos de estrutura — suspender rede, renomear organização, criar subrede —
// continuam pedindo o estado inteiro, porque mexem em várias linhas de uma vez
// e recortá-los daria mais código do que economia.
func (s *Server) deltaFor(ctx context.Context, eventType, targetID string,
	payload map[string]any) (map[string]any, bool) {
	switch eventType {
	case "ticket_created", "ticket_state", "service_order", "dispatch_offered",
		"dispatch_accepted", "supervisor_offer_accepted", "os_started",
		"os_finished", "closure_confirmed":
		if ticket := s.ticketDelta(ctx, targetID); ticket != nil {
			return map[string]any{"type": "support_ticket", "payload": ticket}, true
		}
	case "ticket_message", "client_message", "os_step",
		"remote_access_requested", "remote_access_response":
		eventID := ""
		if payload != nil {
			if value, ok := payload["event_id"].(string); ok {
				eventID = value
			}
		}
		if entry := s.ticketEventDelta(ctx, targetID, eventID); entry != nil {
			return map[string]any{"type": "ticket_event", "payload": entry}, true
		}
	case "bind", "device_renamed", "suspend_device", "resume_device",
		"device_subnetwork_changed", "guest_rejected":
		if device := s.deviceDelta(ctx, targetID); device != nil {
			return map[string]any{"type": "device", "payload": device}, true
		}
	}
	return nil, false
}

// ticketsForSnapshot devolve os chamados visíveis a quem abriu a sessão,
// com o mesmo recorte de CanListTickets — admin vê tudo, supervisor vê a
// organização dele, freelancer vê o que lhe foi ofertado.
func (s *Server) ticketsForSnapshot(ctx context.Context, technicianID, role string) []map[string]any {
	query, args, err := s.Authorizer.CanListTickets(ctx,
		&auth.Claims{TechnicianID: technicianID, Role: role})
	if err != nil {
		return []map[string]any{}
	}
	rows, err := s.Pool.Query(ctx, query, args...)
	if err != nil {
		return []map[string]any{}
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, title, desc, modality, status, org string
		var priority int
		var standalone bool
		var net, dev, freelancer, supervisor *string
		var created, updated time.Time
		if rows.Scan(&id, &title, &desc, &modality, &priority, &status,
			&standalone, &org, &net, &dev, &freelancer, &supervisor,
			&created, &updated) != nil {
			continue
		}
		out = append(out, map[string]any{
			"id": id, "title": title, "description": desc,
			"modality": modality, "priority": priority, "status": status,
			"standalone": standalone, "organization_id": org,
			"network_id": net, "device_id": dev,
			"assigned_freelancer_id": freelancer, "supervisor_id": supervisor,
			"created_at": created, "updated_at": updated,
		})
	}
	return out
}
