package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
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

// standaloneNetwork devolve a rede-base "sem organização" (MODELO-PRODUTO.md,
// "Rede pública da VPN"): a rede de sistema tgdevs.clientes_avulsos, criada em
// 0035 com peer_isolation=true e invisível fora do super_admin. É onde o
// dispositivo avulso vive enquanto não tem supervisor dono.
//
// Substitui ensureStandaloneScope, que criava uma org/rede paralela
// ("Atendimento Avulso TGDesk"/"Pública isolada") anterior ao plano de
// controle TGDevs e sem peer_isolation.
func (s *Server) standaloneNetwork(ctx context.Context) (string, string, error) {
	var orgID, netID string
	err := s.Pool.QueryRow(ctx, `
		SELECT organization_id,id FROM networks
		WHERE system_key='tgdevs.clientes_avulsos' AND status='ativa'`).Scan(&orgID, &netID)
	return orgID, netID, err
}

// Deprecated: mantido apenas enquanto houver dispositivos na rede avulsa
// legada. Use standaloneNetwork.
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

type standaloneBindRequest struct {
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
}

// StandaloneBindDevice vincula um dispositivo à rede avulsa da TGDevs sem
// exigir código de pareamento nem credencial de técnico — é a porta de entrada
// do usuário particular, que instala o TGDesk por conta própria.
//
// Antes essa ativação só acontecia como efeito colateral de ClientOpenTicket,
// o que obrigava o particular a abrir um chamado para entrar no sistema e
// fazia o histórico de saúde começar depois do problema. Aqui ela é uma ação
// de primeira classe: o dispositivo entra, recebe IP virtual e passa a
// participar da telemetria; pedir ajuda é um passo separado e posterior.
func (s *Server) StandaloneBindDevice(w http.ResponseWriter, r *http.Request) {
	var req standaloneBindRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" {
		writeErrCode(w, http.StatusBadRequest, "dispositivo_token_sao_obrigatorios", "dispositivo e token são obrigatórios")
		return
	}
	var state string
	var networkID *string
	if s.Pool.QueryRow(r.Context(),
		`SELECT state,network_id FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&state, &networkID) != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_invalido", "dispositivo inválido")
		return
	}
	if state == "suspenso" {
		writeErrCode(w, http.StatusForbidden, "dispositivo_suspenso", "dispositivo suspenso")
		return
	}
	orgID, netID, err := s.standaloneNetwork(r.Context())
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "rede_clientes_avulsos_indisponivel", "rede de clientes avulsos indisponível")
		return
	}
	// Já vinculado a outra rede: é um dispositivo empresarial, e trocá-lo de
	// escopo aqui apagaria silenciosamente o vínculo feito pelo técnico.
	if networkID != nil && *networkID != "" && *networkID != netID {
		writeErrCode(w, http.StatusConflict, "dispositivo_ja_vinculado_rede", "dispositivo já vinculado a uma rede")
		return
	}
	// Mesmo conjunto de efeitos do pareamento por código (Bind): rede, subrede
	// principal, consumo do código e a associação em device_networks — é ela
	// que as listagens e o Authorizer consultam, não só devices.network_id.
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE devices SET network_id=$2,
			subnetwork_id=(SELECT id FROM subnetworks WHERE network_id=$2 ORDER BY (name='Principal') DESC,created_at LIMIT 1),
			state='ativo', pairing_code=NULL, updated_at=now()
		WHERE id=$1`, req.DeviceID, netID); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_vincular_dispositivo", "falha ao vincular dispositivo")
		return
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_networks(device_id,network_id) VALUES ($1,$2)
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	// device_subnetworks é o que o modelo de visibilidade consulta; sem esta
	// linha o dispositivo entra na rede mas fica fora de qualquer subrede.
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO device_subnetworks(device_id,subnetwork_id)
		SELECT $1,id FROM subnetworks WHERE network_id=$2
		ORDER BY (name='Principal') DESC, created_at LIMIT 1
		ON CONFLICT DO NOTHING`, req.DeviceID, netID)
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{Type: "bind", TargetID: req.DeviceID})
	writeJSON(w, http.StatusOK, map[string]any{
		"state": "ativo", "standalone": true,
		"organization_id": orgID, "network_id": netID,
	})
}

type clientTicketRequest struct {
	DeviceID    string         `json:"device_id"`
	DeviceToken string         `json:"device_token"`
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Location    map[string]any `json:"location"`
}

// ClientOpenTicket é o pedido de ajuda do cliente. Ele não informa nada: o
// cliente leigo não sabe além do que o próprio TGDesk diagnosticou, então
// título e descrição são sintetizados aqui a partir da análise de saúde do
// dispositivo. Modalidade (virtual/presencial) é decisão do supervisor na
// triagem, não do cliente, e por isso deixou de ser um campo do pedido.
//
// standalone também deixou de vir do cliente: é derivado de o dispositivo
// estar na rede-base de avulsos. Antes um device empresarial podia enviar
// standalone=true e ser silenciosamente arrastado para a rede avulsa.
func (s *Server) ClientOpenTicket(w http.ResponseWriter, r *http.Request) {
	var req clientTicketRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" {
		writeErrCode(w, http.StatusBadRequest, "dispositivo_token_sao_obrigatorios", "dispositivo e token são obrigatórios")
		return
	}
	if req.Location == nil {
		req.Location = map[string]any{}
	}
	var state string
	if s.Pool.QueryRow(r.Context(), `SELECT state FROM devices WHERE id=$1 AND device_token=$2`, req.DeviceID, req.DeviceToken).Scan(&state) != nil {
		writeErrCode(w, 401, "dispositivo_invalido", "dispositivo inválido")
		return
	}
	if state != "ativo" {
		writeErrCode(w, http.StatusConflict, "dispositivo_precisa_estar_vinculado_pedir", "dispositivo precisa estar vinculado para pedir atendimento")
		return
	}
	var orgID, netID string
	var systemKey *string
	if s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id,n.id,n.system_key FROM devices d
		JOIN networks n ON n.id=d.network_id WHERE d.id=$1`,
		req.DeviceID).Scan(&orgID, &netID, &systemKey) != nil {
		writeErrCode(w, 400, "dispositivo_escopo_autorizado", "dispositivo sem escopo autorizado")
		return
	}
	standalone := systemKey != nil && *systemKey == "tgdevs.clientes_avulsos"

	// Pedido já aberto: devolve o existente em vez de duplicar. O cliente que
	// clica de novo quer saber do chamado dele, não abrir outro.
	var existingID, existingProtocol, existingStatus string
	if s.Pool.QueryRow(r.Context(), `
		SELECT id,protocol,status FROM support_tickets
		WHERE opened_by_device_id=$1 AND status NOT IN ('closed','cancelled','expired')
		ORDER BY created_at DESC LIMIT 1`, req.DeviceID).
		Scan(&existingID, &existingProtocol, &existingStatus) == nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"id": existingID, "protocol": existingProtocol, "status": existingStatus,
			"confirmation": true, "already_open": true, "standalone": standalone,
			"organization_id": orgID, "network_id": netID,
		})
		return
	}

	// O título carrega o dado que identifica o chamado: o computador. A frase
	// que a pessoa lê é montada no cliente, a partir do diagnóstico que segue
	// como evento estruturado.
	hostname, diagnosis := s.ticketDiagnosis(r.Context(), req.DeviceID)
	title := hostname
	// Texto livre do cliente continua texto livre: é o que a pessoa
	// escreveu, e ninguém além dela pode redigir.
	description := strings.TrimSpace(req.Title + "\n" + req.Description)

	var id, protocol string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO support_tickets(organization_id,network_id,device_id,opened_by_device_id,title,description,modality,standalone,location)
		VALUES($1,$2,$3,$3,$4,$5,'virtual',$6,$7) RETURNING id,protocol`,
		orgID, netID, req.DeviceID, title, description, standalone, req.Location).Scan(&id, &protocol)
	if err != nil {
		writeErrCode(w, 500, "falha_abrir_chamado", "falha ao abrir chamado")
		return
	}
	// A região é congelada agora, na abertura, e não lida da organização na
	// hora de cobrar: a empresa pode mudar de região amanhã, mas o que
	// precificou este chamado foi onde ele nasceu.
	s.StampTicketRegion(r.Context(), id)
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_device_id,event_type,payload) VALUES($1,$2,'opened',$3)`, id, req.DeviceID, map[string]any{"standalone": standalone})
	// O diagnóstico entra como evento estruturado em vez de parágrafo na
	// descrição: quem exibe decide como dizer, e o chamado já nasce com o
	// dado que o supervisor precisa sem o cliente ter que redigir nada.
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_device_id,event_type,payload) VALUES($1,$2,'diagnosis',$3)`, id, req.DeviceID, diagnosis)
	// Avulso vai para a Fila A (oferta concorrente aos supervisores por nota);
	// o vinculado fica na fila exclusiva do supervisor da própria org e não é
	// ofertado a ninguém. Ver MODELO-PRODUTO.md, "Duas filas dinâmicas".
	status := "open"
	if standalone {
		s.DispatchToSupervisors(r.Context(), id)
		status = "offered_supervisor"
	}
	s.publishTicket(r, id, "ticket_created", map[string]any{"status": status, "standalone": standalone})
	writeJSON(w, http.StatusCreated, map[string]any{
		"id": id, "protocol": protocol, "status": status, "confirmation": true,
		"standalone": standalone, "organization_id": orgID, "network_id": netID,
	})
}

// ClientOpenTicketStatus devolve o pedido em aberto do próprio dispositivo,
// para que a tela do cliente mostre o protocolo em vez de reoferecer o botão
// depois de reiniciar o app. POST (e não GET) porque o device_token não pode
// viajar em query string.
func (s *Server) ClientOpenTicketStatus(w http.ResponseWriter, r *http.Request) {
	var req standaloneBindRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || req.DeviceToken == "" {
		writeErrCode(w, http.StatusBadRequest, "dispositivo_token_sao_obrigatorios", "dispositivo e token são obrigatórios")
		return
	}
	var ok bool
	if s.Pool.QueryRow(r.Context(), `SELECT true FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&ok) != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_invalido", "dispositivo inválido")
		return
	}
	var id, protocol, status string
	if s.Pool.QueryRow(r.Context(), `
		SELECT id,protocol,status FROM support_tickets
		WHERE opened_by_device_id=$1 AND status NOT IN ('closed','cancelled','expired')
		ORDER BY created_at DESC LIMIT 1`, req.DeviceID).
		Scan(&id, &protocol, &status) != nil {
		writeJSON(w, http.StatusOK, map[string]any{"open": false})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"open": true, "id": id, "protocol": protocol, "status": status,
	})
}

// ticketDiagnosis devolve o hostname do dispositivo e o diagnóstico dele em
// forma de dado: severidade, condições e a janela avaliada.
//
// Antes daqui saíam título e descrição em prosa, montados no servidor. O
// cliente recebia o parágrafo pronto e não podia traduzi-lo, encurtá-lo para
// tela pequena nem reordená-lo — o que fecharia a porta para qualquer cliente
// que não fosse o desktop em português.
func (s *Server) ticketDiagnosis(ctx context.Context, deviceID string) (string, map[string]any) {
	var hostname string
	_ = s.Pool.QueryRow(ctx, `SELECT coalesce(nullif(display_name,''),hostname) FROM devices WHERE id=$1`, deviceID).Scan(&hostname)
	health := s.persistedHealth(ctx, deviceID)
	issues, _ := health["issues"].([]map[string]any)
	level, _ := health["level"].(string)
	if level == "" {
		level = "normal"
	}
	return hostname, map[string]any{
		"level":          level,
		"issues":         issues,
		"window_minutes": health["recent_window_minutes"],
		"samples":        health["recent_samples"],
	}
}

// DispatchToSupervisors mirrors DispatchTicket (Fila B) but targets supervisors
// (Fila A) instead of freelancers, ranking by supervisor_profiles.rating_avg
// (no geolocation involved). See MODELO-PRODUTO.md, "Fila A".
func (s *Server) DispatchToSupervisors(ctx context.Context, ticketID string) {
	rows, err := s.Pool.Query(ctx, `
		SELECT t.id FROM technicians t
		JOIN supervisor_profiles sp ON sp.technician_id=t.id
		WHERE t.role='supervisor'
		ORDER BY sp.rating_avg DESC, t.id`)
	if err != nil {
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()

	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return
	}
	defer tx.Rollback(ctx)
	for rank, sid := range ids {
		available := time.Now().UTC().Add(time.Duration(rank) * 30 * time.Second)
		_, err = tx.Exec(ctx, `INSERT INTO supervisor_offers(ticket_id,supervisor_id,rank,available_at,expires_at) VALUES($1,$2,$3,$4,$5) ON CONFLICT(ticket_id,supervisor_id) DO UPDATE SET rank=excluded.rank,available_at=excluded.available_at,expires_at=excluded.expires_at`, ticketID, sid, rank+1, available, available.Add(15*time.Minute))
		if err != nil {
			return
		}
	}
	if _, err = tx.Exec(ctx, `UPDATE support_tickets SET status='offered_supervisor',updated_at=now() WHERE id=$1`, ticketID); err != nil {
		return
	}
	_ = tx.Commit(ctx)
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
		writeErrCode(w, 500, "falha_construir_query_chamados", "falha ao construir query de chamados")
		return
	}
	rows, err := s.Pool.Query(r.Context(), query, args...)
	if err != nil {
		writeErrCode(w, 500, "falha_listar_chamados", "falha ao listar chamados")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, title, desc, modality, status, org, typeKey string
		var priority int
		var standalone bool
		var net, dev, freelancer, supervisor *string
		var created, updated time.Time
		var structured []byte
		if rows.Scan(&id, &title, &desc, &modality, &priority, &status, &standalone, &org, &net, &dev, &freelancer, &supervisor, &created, &updated, &typeKey, &structured) == nil {
			var dados any
			_ = json.Unmarshal(structured, &dados)
			out = append(out, map[string]any{"id": id, "title": title, "description": desc, "modality": modality, "priority": priority, "status": status, "standalone": standalone, "organization_id": org, "network_id": net, "device_id": dev, "assigned_freelancer_id": freelancer, "supervisor_id": supervisor, "created_at": created, "updated_at": updated, "type_key": typeKey, "structured_data": dados})
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) AddTicketMessage(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req struct {
		Message     string           `json:"message"`
		Attachments []map[string]any `json:"attachments"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || strings.TrimSpace(req.Message) == "" {
		writeErrCode(w, 400, "mensagem_obrigatoria", "mensagem obrigatória")
		return
	}
	var status string
	if s.Pool.QueryRow(r.Context(), `SELECT status FROM support_tickets WHERE id=$1`, id).Scan(&status) != nil {
		writeErrCode(w, 404, "chamado_encontrado", "chamado não encontrado")
		return
	}
	// O chat existe a partir do momento em que o chamado tem dono. Antes disso
	// não há com quem conversar — o dispositivo do avulso ainda não é de
	// ninguém. 'open' com supervisor_id preenchido É um chamado adotado (o
	// aceite da Fila A devolve o ticket a 'open' com dono), então checar o
	// status sozinho recusava justamente o supervisor que acabou de assumir.
	var temDono bool
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT supervisor_id IS NOT NULL OR assigned_freelancer_id IS NOT NULL
		 FROM support_tickets WHERE id=$1`, id).Scan(&temDono)
	if !temDono {
		writeErrCode(w, 403, "chat_disponivel_apenas_apos_alguem", "chat disponível apenas após alguém assumir o chamado")
		return
	}
	c := middleware.ClaimsFrom(r.Context())
	var eid string
	err := s.Pool.QueryRow(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'message',$3) RETURNING id`, id, c.TechnicianID, map[string]any{"message": req.Message, "attachments": req.Attachments}).Scan(&eid)
	if err != nil {
		writeErrCode(w, 500, "falha_registrar_mensagem", "falha ao registrar mensagem")
		return
	}
	s.publishTicket(r, id, "ticket_message", map[string]any{"event_id": eid})
	writeJSON(w, 201, map[string]any{"id": eid})
}

func (s *Server) TransitionTicket(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req struct {
		Status string `json:"status"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "estado_obrigatorio", "estado obrigatório")
		return
	}
	valid := map[string]map[string]bool{"open": {"closed": true, "cancelled": true, "offered": true, "offered_supervisor": true}, "offered_supervisor": {"open": true, "expired": true, "cancelled": true}, "offered": {"accepted": true, "cancelled": true, "expired": true}, "accepted": {"in_progress": true, "closed": true, "cancelled": true}, "in_progress": {"closed": true, "cancelled": true}, "closed": {"reopened": true}, "reopened": {"in_progress": true, "closed": true}}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var old string
	if tx.QueryRow(r.Context(), `SELECT status FROM support_tickets WHERE id=$1 FOR UPDATE`, id).Scan(&old) != nil {
		writeErrCode(w, 404, "chamado_encontrado", "chamado não encontrado")
		return
	}
	if !valid[old][req.Status] {
		writeErrCode(w, 409, "transicao_invalida", "transição inválida")
		return
	}
	closed := req.Status == "closed" || req.Status == "cancelled" || req.Status == "expired"
	_, err = tx.Exec(r.Context(), `UPDATE support_tickets SET status=$2,updated_at=now(),closed_at=CASE WHEN $3 THEN now() ELSE NULL END WHERE id=$1`, id, req.Status, closed)
	if err == nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'transition',$3)`, id, middleware.ClaimsFrom(r.Context()).TechnicianID, map[string]any{"from": old, "to": req.Status})
	}
	if closed && err == nil {
		_, err = tx.Exec(r.Context(), `UPDATE temporary_ticket_permissions SET status='revoked',revoked_at=now() WHERE ticket_id=$1 AND status='active'`, id)
		// Apagar a subrede temporária é o que revoga o acesso: corta a rota
		// direta na VPN e o pertencimento que o Authorizer consulta, no mesmo
		// ato. Substitui o RemovePeer que era feito aqui sobre a pubkey do
		// DISPOSITIVO DO CLIENTE — aquilo não revogava o acesso do técnico,
		// removia o cliente da VPN inteira, derrubando telemetria e controle
		// dele até reconectar.
		if err == nil {
			_, err = tx.Exec(r.Context(), `DELETE FROM subnetworks WHERE ticket_id=$1`, id)
		}
		// Fecha a rota sem esperar a passada periódica.
		defer func() { _ = s.ReconcileSessionIsolation(context.Background()) }()
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErrCode(w, 500, "falha_alterar_estado", "falha ao alterar estado")
		return
	}
	s.publishTicket(r, id, "ticket_state", map[string]any{"from": old, "to": req.Status})
	writeJSON(w, 200, map[string]any{"id": id, "status": req.Status, "permissions_revoked": closed})
}

func (s *Server) ConvertServiceOrder(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req struct {
		Items             any            `json:"items"`
		Values            any            `json:"values"`
		ScopeNotes        string         `json:"scope_notes"`
		OsType            string         `json:"os_type"`
		OsTypeKey         string         `json:"os_type_key"`
		OsStructuredData  map[string]any `json:"os_structured_data"`
		ScheduledAt       *time.Time     `json:"scheduled_at"`
		ScheduledLocation map[string]any `json:"scheduled_location"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if strings.TrimSpace(req.ScopeNotes) == "" {
		writeErrCode(w, 400, "escopo_obrigatorio", "escopo obrigatório")
		return
	}
	if req.OsType != "virtual" && req.OsType != "onsite" {
		writeErrCode(w, 400, "tipo_invalido", "tipo de OS inválido")
		return
	}
	if req.OsTypeKey != "" && req.OsStructuredData != nil {
		ambient := map[string]string{
			"modality":   req.OsType,
			"standalone": "false",
			"priority":   "2",
		}
		if err := s.validateStructuredData(r.Context(), req.OsTypeKey, req.OsStructuredData, ambient); err != nil {
			writeErrCode(w, 400, "dados_os_invalidos", err.Error())
			return
		}
	}
	var status string
	if s.Pool.QueryRow(r.Context(), `SELECT status FROM support_tickets WHERE id=$1`, id).Scan(&status) != nil {
		writeErrCode(w, 404, "chamado_encontrado", "chamado não encontrado")
		return
	}
	if status != "accepted" && status != "in_progress" && status != "open" {
		writeErrCode(w, 409, "chamado_estado_permita_gerar", "chamado não está em estado que permita gerar OS")
		return
	}
	var temDono bool
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT supervisor_id IS NOT NULL FROM support_tickets WHERE id=$1`, id).Scan(&temDono)
	if !temDono {
		writeErrCode(w, 409, "chamado_precisa_ter_supervisor_responsavel", "o chamado precisa ter um supervisor responsável antes de virar OS")
		return
	}
	if req.ScheduledLocation == nil {
		req.ScheduledLocation = map[string]any{}
	}
	var osID string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO service_orders(ticket_id,items,values,os_type,scope_notes,scheduled_at,scheduled_location,status)
		VALUES($1,$2,$3,$4,$5,$6,$7,'offered')
		ON CONFLICT(ticket_id) DO UPDATE SET items=excluded.items,values=excluded.values,
			os_type=excluded.os_type,scope_notes=excluded.scope_notes,
			scheduled_at=excluded.scheduled_at,scheduled_location=excluded.scheduled_location
		RETURNING id`,
		id, req.Items, req.Values, req.OsType, strings.TrimSpace(req.ScopeNotes),
		req.ScheduledAt, req.ScheduledLocation).Scan(&osID)
	if err != nil {
		writeErrCode(w, 500, "falha_converter", "falha ao converter OS")
		return
	}
	s.dispatchToFreelancers(r.Context(), id)
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'service_order',$3)`, id, middleware.ClaimsFrom(r.Context()).TechnicianID, map[string]any{"service_order_id": osID, "os_type_key": req.OsTypeKey})
	s.publishTicket(r, id, "service_order", map[string]any{"id": osID, "os_type_key": req.OsTypeKey})
	writeJSON(w, 201, map[string]any{"id": osID, "ticket_id": id, "history_preserved": true})
}

func (s *Server) TicketAudit(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `SELECT id,event_type,payload,actor_technician_id,actor_device_id,created_at FROM ticket_events WHERE ticket_id=$1 ORDER BY created_at,id`, id)
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
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
		writeErrCode(w, 400, "dados_obrigatorios", "dados obrigatórios")
		return
	}
	if req.Quality == 0 {
		req.Quality = 50
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var id string
	err = tx.QueryRow(r.Context(), `INSERT INTO technicians(username,password_hash,role) VALUES($1,'!key-only!','freelancer') RETURNING id`, strings.TrimSpace(req.Name)).Scan(&id)
	if err == nil {
		// O técnico informa onde fica, então a região dele sai da coordenada —
		// não precisa de atribuição. Sem coordenada, fica sem região até
		// alguém pô-lo numa, e ele não entra em contagem nenhuma.
		var regiao *string
		if req.Latitude != nil && req.Longitude != nil {
			regiao = s.regionAt(r.Context(), *req.Latitude, *req.Longitude)
		}
		_, err = tx.Exec(r.Context(), `INSERT INTO freelancer_profiles(technician_id,supervisor_id,organization_id,quality_score,latitude,longitude,region_id) VALUES($1,$2,$3,$4,$5,$6,$7)`, id, req.SupervisorID, req.OrganizationID, req.Quality, req.Latitude, req.Longitude, regiao)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErrCode(w, 409, "falha_criar_freelancer", "falha ao criar freelancer")
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
		writeErrCode(w, 403, "permissao", "sem permissão")
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
	var supervisorID *string
	if s.Pool.QueryRow(r.Context(), `SELECT organization_id,standalone,supervisor_id FROM support_tickets WHERE id=$1`, id).Scan(&orgID, &standalone, &supervisorID) != nil {
		writeErrCode(w, 404, "chamado_encontrado", "chamado não encontrado")
		return
	}
	if supervisorID == nil {
		writeErrCode(w, 409, "chamado_precisa_supervisor_responsavel_antes", "chamado precisa de supervisor responsável antes de despachar pra técnico")
		return
	}
	// O vínculo freelancer -> supervisor é metadado comercial. Ele não
	// restringe a fila: todo freelancer disponível participa do ranking.
	rows, err := s.Pool.Query(r.Context(), `SELECT technician_id,quality_score,coalesce(latitude,0),coalesce(longitude,0) FROM freelancer_profiles WHERE availability=true ORDER BY quality_score DESC,technician_id`)
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
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
		writeErrCode(w, 500, "falha", "falha")
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
		writeErrCode(w, 500, "falha_despachar", "falha ao despachar")
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
		writeErrCode(w, 403, "fila_exclusiva", "fila exclusiva")
		return
	}
	fid := c.TechnicianID
	if c.Role == models.RoleSuperAdmin && r.URL.Query().Get("freelancer_id") != "" {
		fid = r.URL.Query().Get("freelancer_id")
	}
	writeJSON(w, 200, s.freelancerOffers(r.Context(), fid))
}

// freelancerOffers é a fila do técnico. Vive separada do handler porque a tela
// não a busca: ela chega no snapshot de abertura e volta a cada evento de
// despacho, como todo o resto. A rota HTTP continua existindo para o
// super_admin inspecionar a fila de outro técnico.
func (s *Server) freelancerOffers(ctx context.Context, freelancerID string) []map[string]any {
	out := []map[string]any{}
	rows, err := s.Pool.Query(ctx, `
		SELECT o.ticket_id,o.rank,o.available_at,o.expires_at,
		       t.title,t.modality,t.location,t.structured_data,t.type_key
		FROM dispatch_offers o JOIN support_tickets t ON t.id=o.ticket_id
		WHERE o.freelancer_id=$1 AND o.available_at<=now() AND o.expires_at>now()
		  AND t.status='offered'
		ORDER BY o.rank,o.available_at`, freelancerID)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, title, mod, typeKey string
		var rank int
		var av, ex time.Time
		var loc, sd []byte
		if rows.Scan(&id, &rank, &av, &ex, &title, &mod, &loc, &sd, &typeKey) == nil {
			var location, structuredData any
			_ = json.Unmarshal(loc, &location)
			_ = json.Unmarshal(sd, &structuredData)
			out = append(out, map[string]any{"ticket_id": id, "rank": rank,
				"available_at": av, "expires_at": ex, "title": title,
				"modality": mod, "location": location,
				"structured_data": structuredData, "type_key": typeKey})
		}
	}
	return out
}

func (s *Server) AcceptDispatch(w http.ResponseWriter, r *http.Request, id string) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role != models.RoleFreelancer {
		writeErrCode(w, 403, "apenas_freelancer", "apenas freelancer")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var modality string
	var deviceID *string
	var standalone bool
	err = tx.QueryRow(r.Context(), `UPDATE support_tickets SET assigned_freelancer_id=$2,status='accepted',accepted_at=now(),updated_at=now() WHERE id=$1 AND status='offered' AND EXISTS(SELECT 1 FROM dispatch_offers WHERE ticket_id=$1 AND freelancer_id=$2 AND available_at<=now() AND expires_at>now()) RETURNING modality,device_id,standalone`, id, c.TechnicianID).Scan(&modality, &deviceID, &standalone)
	if err != nil {
		writeErrCode(w, 409, "chamado_ja_aceito_oferta_indisponivel", "chamado já aceito ou oferta indisponível")
		return
	}
	// O aceite tira a OS da fila dos outros: quem pegou, pegou. Sem isso a
	// oferta continuava listada para todo mundo até expirar.
	_, err = tx.Exec(r.Context(), `UPDATE dispatch_offers SET accepted_at=now() WHERE ticket_id=$1 AND freelancer_id=$2`, id, c.TechnicianID)
	if err == nil {
		_, err = tx.Exec(r.Context(), `DELETE FROM dispatch_offers WHERE ticket_id=$1 AND freelancer_id<>$2`, id, c.TechnicianID)
	}
	if err == nil {
		// A OS passa a ter dono e fica aguardando a data marcada: aceitar não
		// é executar.
		_, err = tx.Exec(r.Context(), `UPDATE service_orders SET status='assigned',assigned_technician_id=$2 WHERE ticket_id=$1`, id, c.TechnicianID)
	}
	// Este ramo é o do cliente AVULSO, onde o acesso remoto do técnico depende
	// de duas condições: o chamado ser virtual (já garantido aqui) e o cliente
	// permitir. Por isso o aceite entrega diagnóstico, e allow_remote só é
	// ligado quando a permissão chega pelo chat.
	//
	// No empresarial é diferente: o supervisor é o responsável pelos
	// dispositivos da sua rede e acessa sem depender do cliente — esse caminho
	// não passa por aqui, é resolvido pelo Authorizer via organização/rede.
	//
	// O prazo deixou de ser de 4 horas: um atendimento pode levar dias, e quem
	// encerra o acesso é o fechamento do chamado.
	if err == nil && standalone && modality == "virtual" && deviceID != nil {
		_, err = tx.Exec(r.Context(), `INSERT INTO temporary_ticket_permissions(ticket_id,freelancer_id,device_id,allow_remote,allow_analysis,exclusive,expires_at) VALUES($1,$2,$3,false,true,true,now()+interval '30 days') ON CONFLICT(ticket_id,freelancer_id,device_id) DO UPDATE SET status='active',allow_remote=false,allow_analysis=true,exclusive=true,expires_at=excluded.expires_at`, id, c.TechnicianID, *deviceID)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErrCode(w, 500, "falha_aceitar", "falha ao aceitar")
		return
	}
	if standalone && modality == "virtual" && deviceID != nil {
		if err := s.createSessionSubnetwork(r.Context(), id, *deviceID, c.TechnicianID); err != nil {
			log.Printf("subrede de sessão não criada para o chamado %s: %v", id, err)
		}
	}
	// Abre a rota direta da sessão imediatamente; a passada periódica apenas
	// confirma, e depois a apaga quando o chamado fecha ou a subrede expira.
	_ = s.ReconcileSessionIsolation(r.Context())
	s.publishTicket(r, id, "dispatch_accepted", map[string]any{"freelancer_id": c.TechnicianID})
	writeJSON(w, 200, map[string]any{"ticket_id": id, "status": "accepted", "temporary_access": standalone && modality == "virtual"})
}

// createSessionSubnetwork monta a subrede temporária do chamado: o dispositivo
// atendido, o técnico que aceitou e o supervisor dono, se houver. Enquanto ela
// existir, esses participantes se alcançam diretamente pela VPN; ao ser
// apagada no fechamento, o acesso some — sem mover ninguém de rede e sem
// trocar endereço, porque o pertencimento a subrede é M:N.
//
// A subrede vive na mesma rede do dispositivo, para não deslocá-lo do seu
// escopo, e dura enquanto o chamado estiver aberto — não por um prazo fixo. Um
// atendimento pode legitimamente levar dias, então expirar por tempo cortaria
// a sessão no meio do trabalho. O ciclo é fechado pelo encerramento do
// chamado/OS, não pelo relógio.
func (s *Server) createSessionSubnetwork(ctx context.Context, ticketID, deviceID, technicianID string) error {
	// O identificador entra duas vezes com tipos diferentes — uuid na coluna e
	// text no nome — então vai como dois parâmetros. Reaproveitar $1 nos dois
	// papéis faz o Postgres fixar o tipo em text por causa do cast, e a
	// inserção na coluna uuid falha.
	var subnetID string
	if err := s.Pool.QueryRow(ctx, `
		INSERT INTO subnetworks(network_id,name,peer_isolation,ticket_id)
		SELECT d.network_id,'Sessão '||left($3,8),false,$1
		FROM devices d WHERE d.id=$2 AND d.network_id IS NOT NULL
		ON CONFLICT (network_id,name) DO UPDATE SET ticket_id=excluded.ticket_id
		RETURNING id`, ticketID, deviceID, ticketID).Scan(&subnetID); err != nil {
		return err
	}
	if _, err := s.Pool.Exec(ctx, `
		INSERT INTO device_subnetworks(device_id,subnetwork_id) VALUES($1,$2)
		ON CONFLICT DO NOTHING`, deviceID, subnetID); err != nil {
		return err
	}
	// Técnico que aceitou e supervisor dono entram pela identidade de técnico.
	_, err := s.Pool.Exec(ctx, `
		INSERT INTO technician_assignments(technician_id,subnetwork_id,assignment_scope,permissions_level)
		SELECT tid,$2,'subnetwork','full' FROM (
			SELECT $1::uuid AS tid
			UNION
			SELECT supervisor_id FROM support_tickets WHERE id=$3 AND supervisor_id IS NOT NULL
		) participantes
		ON CONFLICT DO NOTHING`, technicianID, subnetID, ticketID)
	return err
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
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req struct {
		Type           string         `json:"type"`
		IdempotencyKey string         `json:"idempotency_key"`
		ContentHash    string         `json:"content_hash"`
		ContentBase64  string         `json:"content_base64"`
		Metadata       map[string]any `json:"metadata"`
		CapturedAt     time.Time      `json:"captured_at"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 12<<20))
	if decoder.Decode(&req) != nil || req.Type == "" || req.IdempotencyKey == "" || req.ContentHash == "" || req.ContentBase64 == "" || req.CapturedAt.IsZero() {
		writeErrCode(w, 400, "evidencia_incompleta", "evidência incompleta")
		return
	}
	content, err := base64.StdEncoding.DecodeString(req.ContentBase64)
	if err != nil || len(content) == 0 || len(content) > 8<<20 {
		writeErrCode(w, 400, "arquivo_evidencia_invalido_maior_8", "arquivo de evidência inválido ou maior que 8 MB")
		return
	}
	digest := sha256.Sum256(content)
	if !strings.EqualFold(hex.EncodeToString(digest[:]), req.ContentHash) {
		writeErrCode(w, 400, "hash_evidencia_confere", "hash da evidência não confere")
		return
	}
	allowedTypes := map[string]bool{
		"geolocation": true, "arrival_photo": true, "execution_photo": true,
		"completion_photo": true, "signature": true, "signed_document": true,
	}
	if !allowedTypes[req.Type] {
		writeErrCode(w, 400, "tipo_evidencia_invalido", "tipo de evidência inválido")
		return
	}
	evidenceDir := strings.TrimSpace(os.Getenv("EVIDENCE_DIR"))
	if evidenceDir == "" {
		evidenceDir = "/evidence"
	}
	if err := os.MkdirAll(evidenceDir, 0750); err != nil {
		writeErrCode(w, 500, "falha_preparar_armazenamento_evidencias", "falha ao preparar armazenamento de evidências")
		return
	}
	fileName := id + "-" + req.IdempotencyKey + "-" + strings.ToLower(req.ContentHash[:16]) + ".bin"
	fileName = strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' ||
			r >= '0' && r <= '9' || r == '-' || r == '_' || r == '.' {
			return r
		}
		return '_'
	}, fileName)
	target := filepath.Join(evidenceDir, fileName)
	temporary := target + ".tmp"
	var existingID, existingHash, existingFile string
	existingErr := s.Pool.QueryRow(r.Context(), `SELECT id,content_hash,storage_file FROM onsite_evidence WHERE ticket_id=$1 AND idempotency_key=$2`, id, req.IdempotencyKey).Scan(&existingID, &existingHash, &existingFile)
	if existingErr == nil {
		if !strings.EqualFold(existingHash, req.ContentHash) {
			writeErrCode(w, 409, "chave_idempotencia_ja_usada_conteudo", "chave de idempotência já usada com conteúdo diferente")
			return
		}
		if existingFile != "" {
			writeJSON(w, 200, map[string]any{"id": existingID, "created": false, "deduplicated": true, "integrity_hash": existingHash})
			return
		}
	}
	if err := os.WriteFile(temporary, content, 0640); err != nil {
		writeErrCode(w, 500, "falha_salvar_evidencia", "falha ao salvar evidência")
		return
	}
	if err := os.Rename(temporary, target); err != nil {
		_ = os.Remove(temporary)
		writeErrCode(w, 500, "falha_concluir_evidencia", "falha ao concluir evidência")
		return
	}
	var eid string
	var created bool
	err = s.Pool.QueryRow(r.Context(), `WITH ins AS (INSERT INTO onsite_evidence(ticket_id,evidence_type,idempotency_key,content_hash,storage_file,metadata,captured_at) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(ticket_id,idempotency_key) DO NOTHING RETURNING id) SELECT id,true FROM ins UNION ALL SELECT id,false FROM onsite_evidence WHERE ticket_id=$1 AND idempotency_key=$3 LIMIT 1`, id, req.Type, req.IdempotencyKey, req.ContentHash, fileName, req.Metadata, req.CapturedAt).Scan(&eid, &created)
	if err != nil {
		_ = os.Remove(target)
		writeErrCode(w, 400, "tipo_metadados_invalidos", "tipo ou metadados inválidos")
		return
	}
	if !created {
		var storedHash string
		if s.Pool.QueryRow(r.Context(), `SELECT content_hash FROM onsite_evidence WHERE id=$1`, eid).Scan(&storedHash) != nil || !strings.EqualFold(storedHash, req.ContentHash) {
			_ = os.Remove(target)
			writeErrCode(w, 409, "chave_idempotencia_ja_usada_conteudo", "chave de idempotência já usada com conteúdo diferente")
			return
		}
	}
	writeJSON(w, 200, map[string]any{"id": eid, "created": created, "deduplicated": !created, "integrity_hash": req.ContentHash})
}

func (s *Server) ExportServiceOrder(w http.ResponseWriter, r *http.Request, id string) {
	if !s.canManageTicket(r, id) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var osID, status string
	var items, values, acceptance []byte
	if s.Pool.QueryRow(r.Context(), `SELECT id,status,items,values,customer_acceptance FROM service_orders WHERE ticket_id=$1`, id).Scan(&osID, &status, &items, &values, &acceptance) != nil {
		writeErrCode(w, 404, "encontrada", "OS não encontrada")
		return
	}
	rows, _ := s.Pool.Query(r.Context(), `SELECT evidence_type,content_hash,storage_file,metadata,captured_at FROM onsite_evidence WHERE ticket_id=$1 ORDER BY captured_at`, id)
	defer rows.Close()
	evidence := []map[string]any{}
	for rows.Next() {
		var typ, hash, storageFile string
		var meta []byte
		var at time.Time
		_ = rows.Scan(&typ, &hash, &storageFile, &meta, &at)
		var m any
		_ = json.Unmarshal(meta, &m)
		evidence = append(evidence, map[string]any{"type": typ, "hash": hash, "stored": storageFile != "", "metadata": m, "captured_at": at})
	}
	var i, v, a any
	_ = json.Unmarshal(items, &i)
	_ = json.Unmarshal(values, &v)
	_ = json.Unmarshal(acceptance, &a)
	writeJSON(w, 200, map[string]any{"format": "tgdesk-service-order-v1", "printable": true, "exportable": true, "service_order_id": osID, "ticket_id": id, "status": status, "items": i, "values": v, "customer_acceptance": a, "evidence": evidence})
}

// SupervisorQueue mirrors FreelancerQueue but for the Fila A (supervisor_offers).
func (s *Server) SupervisorQueue(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role != models.RoleSupervisor && c.Role != models.RoleSuperAdmin {
		writeErrCode(w, 403, "fila_exclusiva", "fila exclusiva")
		return
	}
	sid := c.TechnicianID
	if c.Role == models.RoleSuperAdmin && r.URL.Query().Get("supervisor_id") != "" {
		sid = r.URL.Query().Get("supervisor_id")
	}
	rows, err := s.Pool.Query(r.Context(), `SELECT o.ticket_id,o.rank,o.available_at,o.expires_at,t.title,t.modality,t.location FROM supervisor_offers o JOIN support_tickets t ON t.id=o.ticket_id WHERE o.supervisor_id=$1 AND o.available_at<=now() AND o.expires_at>now() AND t.status='offered_supervisor' ORDER BY o.rank,o.available_at`, sid)
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
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

// AcceptSupervisorOffer mirrors AcceptDispatch but for the Fila A offer to
// supervisors: atomically claims the ticket, excluding all other offerees.
func (s *Server) AcceptSupervisorOffer(w http.ResponseWriter, r *http.Request, id string) {
	c := middleware.ClaimsFrom(r.Context())
	if c.Role != models.RoleSupervisor {
		writeErrCode(w, 403, "apenas_supervisor", "apenas supervisor")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	defer tx.Rollback(r.Context())
	var ticketID string
	err = tx.QueryRow(r.Context(), `UPDATE support_tickets SET supervisor_id=$2,status='open',updated_at=now() WHERE id=$1 AND status='offered_supervisor' AND EXISTS(SELECT 1 FROM supervisor_offers WHERE ticket_id=$1 AND supervisor_id=$2 AND available_at<=now() AND expires_at>now()) RETURNING id`, id, c.TechnicianID).Scan(&ticketID)
	if err != nil {
		writeErrCode(w, 409, "chamado_ja_aceito_oferta_indisponivel", "chamado já aceito ou oferta indisponível")
		return
	}
	// Mesma regra da Fila B: aceito, sai da fila dos demais.
	_, err = tx.Exec(r.Context(), `UPDATE supervisor_offers SET accepted_at=now() WHERE ticket_id=$1 AND supervisor_id=$2`, id, c.TechnicianID)
	if err == nil {
		_, err = tx.Exec(r.Context(), `DELETE FROM supervisor_offers WHERE ticket_id=$1 AND supervisor_id<>$2`, id, c.TechnicianID)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErrCode(w, 500, "falha_aceitar", "falha ao aceitar")
		return
	}
	// O supervisor que adota o chamado ganha testes e diagnóstico para
	// determinar a causa real antes de decidir pela OS — e a subrede de sessão
	// para que isso funcione pela VPN. Acesso remoto não vem junto: é pedido no
	// chat e depende do cliente.
	var deviceID *string
	if s.Pool.QueryRow(r.Context(), `SELECT device_id FROM support_tickets WHERE id=$1`, id).
		Scan(&deviceID) == nil && deviceID != nil {
		s.grantAnalysisOnly(r.Context(), id, c.TechnicianID, *deviceID)
		if err := s.createSessionSubnetwork(r.Context(), id, *deviceID, c.TechnicianID); err != nil {
			log.Printf("subrede de sessão não criada para o chamado %s: %v", id, err)
		}
		_ = s.ReconcileSessionIsolation(r.Context())
	}
	s.publishTicket(r, id, "supervisor_offer_accepted", map[string]any{"supervisor_id": c.TechnicianID})
	writeJSON(w, 200, map[string]any{"ticket_id": id, "status": "open", "supervisor_id": c.TechnicianID})
}

// ratingParticipant reports whether (role,id) is one of the ticket's known
// participants: supervisor, assigned freelancer, or the device that opened /
// is the ticket's device (acting as the "cliente"/"cliente_avulso" role).
func (s *Server) ratingParticipant(ctx context.Context, ticketID, role, id string) (bool, error) {
	var ok bool
	switch role {
	case "supervisor":
		err := s.Pool.QueryRow(ctx, `SELECT supervisor_id=$2 FROM support_tickets WHERE id=$1`, ticketID, id).Scan(&ok)
		return ok, err
	case "freelancer":
		err := s.Pool.QueryRow(ctx, `SELECT assigned_freelancer_id=$2 FROM support_tickets WHERE id=$1`, ticketID, id).Scan(&ok)
		return ok, err
	case "cliente", "cliente_avulso":
		err := s.Pool.QueryRow(ctx, `SELECT device_id=$2 OR opened_by_device_id=$2 FROM support_tickets WHERE id=$1`, ticketID, id).Scan(&ok)
		return ok, err
	default:
		return false, nil
	}
}

// RateTicket registers a cross-rating between two participants of a closed
// ticket and recalculates the ratee's running average (supervisor_profiles,
// freelancer_profiles, or devices, depending on the ratee's role).
func (s *Server) RateTicket(w http.ResponseWriter, r *http.Request, id string) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req struct {
		RateeRole string  `json:"ratee_role"`
		RateeID   string  `json:"ratee_id"`
		Stars     float64 `json:"stars"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.RateeID == "" || req.Stars < 1 || req.Stars > 5 {
		writeErrCode(w, 400, "avaliacao_invalida", "avaliação inválida")
		return
	}
	switch req.RateeRole {
	case "supervisor", "freelancer", "cliente", "cliente_avulso":
	default:
		writeErrCode(w, 400, "papel_avaliado_invalido", "papel avaliado inválido")
		return
	}
	var status string
	if s.Pool.QueryRow(r.Context(), `SELECT status FROM support_tickets WHERE id=$1`, id).Scan(&status) != nil {
		writeErrCode(w, 404, "chamado_encontrado", "chamado não encontrado")
		return
	}
	if status != "closed" {
		writeErrCode(w, 409, "avaliacao_disponivel_apenas_apos_encerramento", "avaliação disponível apenas após o encerramento do chamado")
		return
	}
	raterOK, err := s.ratingParticipant(r.Context(), id, c.Role, c.TechnicianID)
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	if !raterOK {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	rateeOK, err := s.ratingParticipant(r.Context(), id, req.RateeRole, req.RateeID)
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	if !rateeOK {
		writeErrCode(w, 400, "avaliado_participa_deste_chamado", "avaliado não participa deste chamado")
		return
	}
	tx, err := s.Pool.Begin(r.Context())
	if err != nil {
		writeErrCode(w, 500, "falha", "falha")
		return
	}
	defer tx.Rollback(r.Context())
	_, err = tx.Exec(r.Context(), `INSERT INTO ticket_ratings(ticket_id,rater_role,rater_id,ratee_role,ratee_id,stars) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(ticket_id,rater_id,ratee_id) DO NOTHING`, id, c.Role, c.TechnicianID, req.RateeRole, req.RateeID, req.Stars)
	if err != nil {
		writeErrCode(w, 500, "falha_registrar_avaliacao", "falha ao registrar avaliação")
		return
	}
	switch req.RateeRole {
	case "supervisor":
		_, err = tx.Exec(r.Context(), `
			INSERT INTO supervisor_profiles(technician_id,rating_avg,rating_count)
			SELECT $1,AVG(stars),COUNT(*) FROM ticket_ratings WHERE ratee_role='supervisor' AND ratee_id=$1
			ON CONFLICT(technician_id) DO UPDATE SET
				rating_avg=(SELECT AVG(stars) FROM ticket_ratings WHERE ratee_role='supervisor' AND ratee_id=$1),
				rating_count=(SELECT COUNT(*) FROM ticket_ratings WHERE ratee_role='supervisor' AND ratee_id=$1)`, req.RateeID)
	case "freelancer":
		_, err = tx.Exec(r.Context(), `
			UPDATE freelancer_profiles SET quality_score=LEAST(5,GREATEST(1,
				(SELECT AVG(stars) FROM ticket_ratings WHERE ratee_role='freelancer' AND ratee_id=$1)))
			WHERE technician_id=$1`, req.RateeID)
	case "cliente", "cliente_avulso":
		_, err = tx.Exec(r.Context(), `
			UPDATE devices SET
				client_rating_avg=(SELECT AVG(stars) FROM ticket_ratings WHERE ratee_role IN ('cliente','cliente_avulso') AND ratee_id=$1),
				client_rating_count=(SELECT COUNT(*) FROM ticket_ratings WHERE ratee_role IN ('cliente','cliente_avulso') AND ratee_id=$1)
			WHERE id=$1`, req.RateeID)
	}
	if err != nil || tx.Commit(r.Context()) != nil {
		writeErrCode(w, 500, "falha_atualizar_media", "falha ao atualizar média")
		return
	}
	writeJSON(w, 201, map[string]any{"ticket_id": id, "ratee_role": req.RateeRole, "ratee_id": req.RateeID, "stars": req.Stars})
}

// MyFreelancerProfile returns the calling freelancer's own profile summary:
// quality score, availability, supervisor and rating count.
func (s *Server) MyFreelancerProfile(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil || c.Role != models.RoleFreelancer {
		writeErrCode(w, 403, "apenas_freelancer", "apenas freelancer")
		return
	}
	var quality float64
	var availability bool
	var supervisorID string
	if s.Pool.QueryRow(r.Context(), `SELECT quality_score,availability,supervisor_id FROM freelancer_profiles WHERE technician_id=$1`, c.TechnicianID).Scan(&quality, &availability, &supervisorID) != nil {
		writeErrCode(w, 404, "perfil_freelancer_encontrado", "perfil de freelancer não encontrado")
		return
	}
	var supervisorName string
	_ = s.Pool.QueryRow(r.Context(), `SELECT username FROM technicians WHERE id=$1`, supervisorID).Scan(&supervisorName)
	var ratingCount int
	_ = s.Pool.QueryRow(r.Context(), `SELECT COUNT(*) FROM ticket_ratings WHERE ratee_id=$1 AND ratee_role='freelancer'`, c.TechnicianID).Scan(&ratingCount)
	writeJSON(w, 200, map[string]any{
		"quality_score":   quality,
		"availability":    availability,
		"supervisor_id":   supervisorID,
		"supervisor_name": supervisorName,
		"rating_count":    ratingCount,
	})
}

// SetFreelancerAvailability toggles the calling freelancer's availability
// flag used by DispatchTicket's candidate ranking.
func (s *Server) SetFreelancerAvailability(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil || c.Role != models.RoleFreelancer {
		writeErrCode(w, 403, "apenas_freelancer", "apenas freelancer")
		return
	}
	var req struct {
		Available bool `json:"available"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	if _, err := s.Pool.Exec(r.Context(), `UPDATE freelancer_profiles SET availability=$1 WHERE technician_id=$2`, req.Available, c.TechnicianID); err != nil {
		writeErrCode(w, 500, "falha_atualizar_disponibilidade", "falha ao atualizar disponibilidade")
		return
	}
	writeJSON(w, 200, map[string]any{"availability": req.Available})
}

type supervisorTicketRequest struct {
	DeviceID string `json:"device_id"`
	Title    string `json:"title"`
	Modality string `json:"modality"`
	// Qual tipo de chamado é este. Vazio significa 'computador', que é o único
	// tipo que existia antes de o tipo virar dado — o parque atual inteiro.
	TypeKey        string         `json:"type_key"`
	StructuredData map[string]any `json:"structured_data"`
	// Chamado aberto pelo supervisor já nasce como OS: se ele está abrindo, é
	// porque o caso precisa de um técnico em campo. Estes campos definem a OS
	// que vai direto para a fila dos técnicos.
	ScopeNotes        string         `json:"scope_notes"`
	ScheduledAt       *time.Time     `json:"scheduled_at"`
	ScheduledLocation map[string]any `json:"scheduled_location"`
}

// SupervisorOpenTicket lets a supervisor open a ticket directly against a
// device they have access to ("Origem 3"), bypassing Fila A: the ticket is
// born with supervisor_id already set and status 'open'.
func (s *Server) SupervisorOpenTicket(w http.ResponseWriter, r *http.Request) {
	c := middleware.ClaimsFrom(r.Context())
	if c == nil || (c.Role != models.RoleSupervisor && c.Role != models.RoleSuperAdmin) {
		writeErrCode(w, 403, "apenas_supervisor", "apenas supervisor")
		return
	}
	var req supervisorTicketRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.DeviceID == "" || strings.TrimSpace(req.Title) == "" {
		writeErrCode(w, 400, "dispositivo_titulo_sao_obrigatorios", "dispositivo e título são obrigatórios")
		return
	}
	if req.Modality == "" {
		req.Modality = "virtual"
	}
	if req.Modality != "virtual" && req.Modality != "onsite" {
		writeErrCode(w, 400, "modalidade_invalida", "modalidade inválida")
		return
	}
	if req.StructuredData == nil {
		req.StructuredData = map[string]any{}
	}
	if strings.TrimSpace(req.TypeKey) == "" {
		req.TypeKey = "computador"
	}
	// O esquema do tipo é o contrato: chave que ele não declara é recusada aqui,
	// e não descoberta depois por quem lê o chamado e não acha o que procurava.
	if err := s.validateStructuredData(r.Context(), req.TypeKey, req.StructuredData,
		map[string]string{"modality": req.Modality, "standalone": "false"}); err != nil {
		writeErrCode(w, 400, "dados_do_tipo_invalidos", err.Error())
		return
	}
	allowed, err := s.Authorizer.CanAccessDevice(r.Context(), c, req.DeviceID)
	if err != nil {
		writeErrCode(w, 500, "falha_verificar_acesso_dispositivo", "falha ao verificar acesso ao dispositivo")
		return
	}
	if !allowed {
		writeErrCode(w, 403, "acesso_dispositivo", "sem acesso ao dispositivo")
		return
	}
	var orgID, netID string
	if s.Pool.QueryRow(r.Context(), `SELECT n.organization_id,n.id FROM devices d JOIN networks n ON n.id=d.network_id WHERE d.id=$1`, req.DeviceID).Scan(&orgID, &netID) != nil {
		writeErrCode(w, 400, "dispositivo_escopo_autorizado", "dispositivo sem escopo autorizado")
		return
	}
	var id string
	err = s.Pool.QueryRow(r.Context(), `
		INSERT INTO support_tickets(organization_id,network_id,device_id,supervisor_id,title,structured_data,modality,type_key,standalone,status)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,false,'accepted') RETURNING id`,
		orgID, netID, req.DeviceID, c.TechnicianID, strings.TrimSpace(req.Title),
		req.StructuredData, req.Modality, req.TypeKey).Scan(&id)
	if err != nil {
		writeErrCode(w, 500, "falha_abrir_chamado", "falha ao abrir chamado")
		return
	}
	s.StampTicketRegion(r.Context(), id)
	_, _ = s.Pool.Exec(r.Context(), `INSERT INTO ticket_events(ticket_id,actor_technician_id,event_type,payload) VALUES($1,$2,'opened',$3)`, id, c.TechnicianID, map[string]any{"modality": req.Modality, "standalone": false, "origem": "supervisor"})

	// Já vira OS e entra na fila dos técnicos: um chamado aberto pelo
	// supervisor pressupõe atendimento em campo, então esperar um segundo
	// comando para converter seria só uma etapa vazia.
	if req.ScheduledLocation == nil {
		req.ScheduledLocation = map[string]any{}
	}
	escopo := strings.TrimSpace(req.ScopeNotes)
	if escopo == "" {
		escopo = strings.TrimSpace(req.Title)
	}
	var osID string
	if s.Pool.QueryRow(r.Context(), `
		INSERT INTO service_orders(ticket_id,os_type,scope_notes,scheduled_at,scheduled_location,status)
		VALUES($1,$2,$3,$4,$5,'offered') RETURNING id`,
		id, req.Modality, escopo, req.ScheduledAt, req.ScheduledLocation).Scan(&osID) == nil {
		s.dispatchToFreelancers(r.Context(), id)
	}
	s.publishTicket(r, id, "ticket_created", map[string]any{"status": "offered", "standalone": false, "service_order_id": osID})
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "status": "offered", "service_order_id": osID})
}

func parseIntDefault(raw string, fallback int) int {
	n, e := strconv.Atoi(raw)
	if e != nil {
		return fallback
	}
	return n
}
