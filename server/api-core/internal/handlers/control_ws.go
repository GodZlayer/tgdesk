package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	tgauth "tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

var controlUpgrader = websocket.Upgrader{
	ReadBufferSize:  16 * 1024,
	WriteBufferSize: 16 * 1024,
	CheckOrigin:     func(*http.Request) bool { return true },
}

type controlMessage struct {
	Type    string          `json:"type"`
	ID      string          `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Path    string          `json:"path,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

func requestFromVPN(r *http.Request) bool {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.To4() != nil && ip.To4()[0] == 10 && ip.To4()[1] == 70
}

// DeviceControlWS é o canal operacional do Host. Ele deliberadamente só
// aceita tráfego originado da interface WireGuard.
func (s *Server) DeviceControlWS(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErrCode(w, http.StatusForbidden, "canal_controle_disponivel_somente_vpn", "canal de controle disponível somente pela VPN")
		return
	}
	deviceID := r.URL.Query().Get("device_id")
	token := r.URL.Query().Get("device_token")
	var state string
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT state FROM devices WHERE id=$1 AND device_token=$2`,
		deviceID, token).Scan(&state); err != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_token_invalido", "dispositivo/token inválido")
		return
	}
	if state != models.DeviceStateAtivo {
		writeErrCode(w, http.StatusForbidden, "dispositivo_ativo", "dispositivo não está ativo")
		return
	}
	conn, err := controlUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	_, _ = s.Pool.Exec(r.Context(), `
		UPDATE diagnostic_runs SET status='failed',error='execução interrompida',
			finished_at=now()
		WHERE device_id=$1 AND status='running'
		  AND started_at < now()-interval '15 minutes'`, deviceID)
	branding, brandSignature := s.deviceBranding(r.Context(), deviceID)
	_ = conn.WriteJSON(map[string]any{
		"type": "ready", "state": state,
		"version": os.Getenv("CLIENT_VERSION"),
		"payload": map[string]any{"branding": branding},
	})

	// Dado no TGDesk é tempo real. O chat do cliente e o aviso de acesso remoto
	// chegam por push neste mesmo canal, em vez de a tela ficar perguntando ao
	// servidor de tempos em tempos.
	//
	// WriteJSON não é seguro para uso concorrente, e este canal já escreve do
	// laço principal — daí o mutex.
	var writeMu sync.Mutex
	pushWrite := func(v any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(v)
	}
	chatSub := presence.Subscribe(r.Context(), s.RDB)
	defer chatSub.Close()
	go func() {
		for raw := range chatSub.Channel() {
			var evt presence.Event
			if json.Unmarshal([]byte(raw.Payload), &evt) != nil {
				continue
			}
			switch evt.Type {
			case "client_message", "remote_access_requested", "remote_access_response":
			default:
				continue
			}
			// TargetID é o chamado; só interessa se for um chamado deste
			// dispositivo.
			var pertence bool
			if s.Pool.QueryRow(context.Background(), `
				SELECT true FROM support_tickets
				WHERE id=$1 AND opened_by_device_id=$2`,
				evt.TargetID, deviceID).Scan(&pertence) != nil {
				continue
			}
			// Empurra a conversa INTEIRA, não um aviso de "vá buscar". Mandar
			// um sinalizador que dispara uma requisição de leitura é polling
			// disfarçado — a informação viaja por aqui, completa.
			thread := s.clientThreadPayload(context.Background(), evt.TargetID)
			if pushWrite(map[string]any{
				"type": "ticket_thread", "id": evt.TargetID, "payload": thread,
			}) != nil {
				return
			}
		}
	}()

	for {
		_ = conn.SetReadDeadline(time.Now().Add(45 * time.Second))
		var msg controlMessage
		if err := conn.ReadJSON(&msg); err != nil {
			_ = presence.Clear(context.Background(), s.RDB, deviceID)
			_ = presence.Publish(context.Background(), s.RDB,
				presence.Event{Type: "presence", TargetID: deviceID,
					Payload: map[string]any{"presence": "offline"}})
			return
		}
		switch msg.Type {
		case "rpc":
			// Mesma primitiva de RPC do canal com credencial de técnico. O
			// TGDesk é uma base só: o transporte é sempre este canal, e a
			// credencial apresentada é que define o que pode ser feito nele.
			// Aqui a credencial é a do dispositivo, então o que se libera são
			// as operações do próprio dispositivo — pedir atendimento,
			// conversar no chamado, responder o pedido de acesso remoto.
			if msg.ID == "" || !deviceRPCPath(msg.Path) {
				continue
			}
			body := mergeDeviceCredential(msg.Payload, deviceID, token)
			req := httptest.NewRequest(msg.Method, "http://10.70.0.1"+msg.Path,
				bytes.NewReader(body))
			req.RemoteAddr = "10.70.0.2:1"
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			NewRouter(s).ServeHTTP(rec, req)
			var payload any
			if rec.Body.Len() != 0 {
				if json.Unmarshal(rec.Body.Bytes(), &payload) != nil {
					payload = rec.Body.String()
				}
			}
			if pushWrite(map[string]any{"type": "rpc_response", "id": msg.ID,
				"status": rec.Code, "payload": payload}) != nil {
				return
			}
		case "heartbeat":
			var capabilities presence.Capabilities
			_ = json.Unmarshal(msg.Payload, &capabilities)
			if err := s.Pool.QueryRow(r.Context(),
				`SELECT state FROM devices WHERE id=$1`, deviceID).Scan(&state); err != nil {
				return
			}
			_, _ = s.Pool.Exec(r.Context(),
				`UPDATE devices SET last_seen_at=now() WHERE id=$1`, deviceID)
			_ = presence.Heartbeat(r.Context(), s.RDB, deviceID)
			_ = presence.SetCapabilities(r.Context(), s.RDB, deviceID, capabilities)
			_ = presence.Publish(r.Context(), s.RDB,
				presence.Event{Type: "presence", TargetID: deviceID,
					Payload: map[string]any{
						"presence":     "online",
						"remote_ready": capabilities.RemoteReady,
						"files_ready":  capabilities.FilesReady,
					}})
			_ = pushWrite(map[string]any{
				"type": "heartbeat_ack", "state": state,
				"version": os.Getenv("CLIENT_VERSION"),
			})
			// Atualização é decisão do servidor. O dispositivo informa a
			// versão que roda e recebe a ordem quando chegar a vez dele — um
			// por vez, porque a banda é do próprio servidor.
			s.enqueueDeviceUpdate(r.Context(), deviceID, capabilities.ClientVersion)
			if claimed, throttle, target := s.claimUpdateSlot(r.Context(), deviceID); claimed {
				_ = pushWrite(map[string]any{
					"type": "update_now", "version": target,
					"payload": map[string]any{
						"version":       target,
						"throttle_kbps": throttle,
					},
				})
			}
			if latestBranding, latestSignature := s.deviceBranding(r.Context(), deviceID); brandingChanged(brandSignature, latestSignature) {
				brandSignature = latestSignature
				_ = pushWrite(map[string]any{
					"type": "branding", "payload": latestBranding,
				})
			}
			var cancelledRunID string
			if s.Pool.QueryRow(r.Context(), `
				SELECT id FROM diagnostic_runs
				WHERE device_id=$1 AND status='cancelled'
				  AND started_at IS NOT NULL AND finished_at IS NULL
				ORDER BY created_at LIMIT 1`, deviceID).Scan(&cancelledRunID) == nil {
				_ = pushWrite(map[string]any{
					"type": "diagnostic_cancel", "id": cancelledRunID,
				})
			}
			var activeRunID, activeRunStatus string
			if s.Pool.QueryRow(r.Context(), `
				SELECT id,status FROM diagnostic_runs
				WHERE device_id=$1 AND status IN ('running','paused')
				ORDER BY created_at LIMIT 1`, deviceID).Scan(&activeRunID, &activeRunStatus) == nil {
				_ = pushWrite(map[string]any{
					"type": "diagnostic_pause", "id": activeRunID,
					"payload": map[string]any{"paused": activeRunStatus == "paused"},
				})
			}
			var runID string
			var tests []byte
			if s.Pool.QueryRow(r.Context(), `
				WITH next AS (
					SELECT id FROM diagnostic_runs
					WHERE device_id=$1 AND status='queued'
					  AND NOT EXISTS (
						SELECT 1 FROM diagnostic_runs active
						WHERE active.device_id=$1 AND active.status IN ('running','paused')
					  )
					ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED
				)
				UPDATE diagnostic_runs d SET status='running',started_at=now()
				FROM next WHERE d.id=next.id
				RETURNING d.id,d.tests`, deviceID).Scan(&runID, &tests) == nil {
				var selected []string
				_ = json.Unmarshal(tests, &selected)
				if len(selected) > 0 {
					_ = pushWrite(map[string]any{
						"type": "diagnostic_run", "id": runID,
						"payload": map[string]any{"tests": selected},
					})
				}
			}
			if state != models.DeviceStateAtivo {
				return
			}
		case "update_result":
			// Fecha a vez deste dispositivo. Enquanto esta linha não sair de
			// 'em_andamento', ninguém mais na fila anda — por isso o
			// resultado vem por aqui e não é inferido de silêncio.
			var payload struct {
				OK    bool   `json:"ok"`
				Error string `json:"error"`
			}
			_ = json.Unmarshal(msg.Payload, &payload)
			s.finishUpdate(r.Context(), deviceID, payload.OK, payload.Error)
		case "telemetry":
			var payload struct {
				Hardware any `json:"hardware"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil {
				_, _ = s.Pool.Exec(r.Context(), `
					WITH inserted AS (
						INSERT INTO telemetry_snapshots (device_id,hardware)
						VALUES ($1,$2)
						RETURNING 1
					)
					DELETE FROM telemetry_snapshots
					WHERE coletado_em < now()-interval '30 days'`,
					deviceID, payload.Hardware)
				if encoded, mErr := json.Marshal(payload.Hardware); mErr == nil {
					s.rollHardwareJSON(r.Context(), deviceID, encoded)
				}
				stats := s.hardwareStatistics(r.Context(), deviceID)
				_ = pushWrite(map[string]any{"type": "telemetry_stats", "payload": stats})
				_ = presence.Publish(r.Context(), s.RDB,
					presence.Event{Type: "telemetry", TargetID: deviceID, Payload: map[string]any{
						"hardware": payload.Hardware, "statistics": stats,
						"collected_at": time.Now().UTC().Format(time.RFC3339),
					}})
			}
		case "rustdesk_status":
			var payload struct {
				ID string `json:"rustdesk_id"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && payload.ID != "" {
				_, _ = s.Pool.Exec(r.Context(),
					`UPDATE devices SET rustdesk_id=$1,updated_at=now() WHERE id=$2`,
					payload.ID, deviceID)
			}
		case "diagnostic_progress":
			var payload struct {
				Progress       int      `json:"progress"`
				Test           string   `json:"test"`
				Group          string   `json:"group"`
				TestProgress   int      `json:"test_progress"`
				GroupProgress  int      `json:"group_progress"`
				CompletedTests int      `json:"completed_tests"`
				TotalTests     int      `json:"total_tests"`
				Message        string   `json:"message"`
				Results        any      `json:"results"`
				Order          []string `json:"order"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && msg.ID != "" {
				_, _ = s.Pool.Exec(r.Context(), `
					UPDATE diagnostic_runs SET progress=$1,current_test=$2
					WHERE id=$3 AND device_id=$4 AND status IN ('running','paused')`,
					payload.Progress, payload.Test, msg.ID, deviceID)
				if payload.Results != nil {
					partialResults := map[string]any{"test": "all_tests", "tests": payload.Results, "order": payload.Order}
					_, _ = s.Pool.Exec(r.Context(), `
						UPDATE diagnostic_runs SET results=$1
						WHERE id=$2 AND device_id=$3 AND status IN ('running','paused')`,
						partialResults, msg.ID, deviceID)
				}
				// Grava a serie temporal de amostras em paralelo ao "resultado final"
				// acima (que continua sendo sobrescrito a cada atualizacao). O payload
				// de progresso hoje so traz uma metrica numerica estruturada
				// (Progress); test/message sao texto, entao gravamos 1 amostra por
				// atualizacao com metric fixo "progress".
				_, _ = s.Pool.Exec(r.Context(), `
					INSERT INTO diagnostic_samples (run_id,metric,value)
					VALUES ($1,$2,$3)`,
					msg.ID, "progress", float64(payload.Progress))
				progressPayload := map[string]any{
					"id": msg.ID, "status": "running", "progress": payload.Progress,
					"test": payload.Test, "group": payload.Group, "message": payload.Message,
					"test_progress": payload.TestProgress, "group_progress": payload.GroupProgress,
					"completed_tests": payload.CompletedTests, "total_tests": payload.TotalTests,
				}
				if payload.Results != nil {
					progressPayload["results"] = map[string]any{"test": "all_tests", "tests": payload.Results, "order": payload.Order}
				}
				_ = presence.Publish(r.Context(), s.RDB, presence.Event{
					Type: "diagnostic_progress", TargetID: deviceID,
					Payload: progressPayload,
				})
			}
		case "diagnostic_result":
			var payload struct {
				Status  string `json:"status"`
				Results any    `json:"results"`
				Error   string `json:"error"`
			}
			if json.Unmarshal(msg.Payload, &payload) == nil && msg.ID != "" {
				status := payload.Status
				if status != "completed" && status != "failed" && status != "cancelled" {
					status = "failed"
				}
				_, _ = s.Pool.Exec(r.Context(), `
					UPDATE diagnostic_runs SET status=$1,progress=100,results=$2,
						error=$3,finished_at=now()
					WHERE id=$4 AND device_id=$5 AND status IN ('running','paused','cancelled')`,
					status, payload.Results, payload.Error, msg.ID, deviceID)
				_ = presence.Publish(r.Context(), s.RDB, presence.Event{
					Type: "diagnostic_result", TargetID: deviceID,
					Payload: map[string]any{"id": msg.ID, "status": status,
						"progress": 100, "results": payload.Results, "error": payload.Error},
				})
			}
		}
	}
}

func (s *Server) TechnicianControlWS(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErrCode(w, http.StatusForbidden, "canal_controle_disponivel_somente_vpn", "canal de controle disponível somente pela VPN")
		return
	}
	token := r.URL.Query().Get("token")
	if token == "" {
		if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
			token = strings.TrimPrefix(h, "Bearer ")
		}
	}
	conn, err := controlUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer conn.Close()
	var writeMu sync.Mutex
	write := func(value any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(value)
	}

	if token == "" {
		_ = conn.SetReadDeadline(time.Now().Add(15 * time.Second))
		var authMessage controlMessage
		if conn.ReadJSON(&authMessage) != nil || authMessage.Type != "authenticate" {
			_ = write(map[string]any{"type": "auth_result", "status": http.StatusUnauthorized,
				"error": "credencial de controle ausente"})
			return
		}
		req := httptest.NewRequest(http.MethodPost,
			"http://10.70.0.1/api/v1/auth/technician/refresh",
			bytes.NewReader(authMessage.Payload))
		req.RemoteAddr = "10.70.1.1:1"
		rec := httptest.NewRecorder()
		s.RefreshTechnicianMachine(rec, req)
		var response map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &response)
		if rec.Code != http.StatusOK {
			_ = write(map[string]any{"type": "auth_result", "status": rec.Code,
				"error": response["error"]})
			return
		}
		token, _ = response["token"].(string)
		if err := write(map[string]any{"type": "auth_result", "status": rec.Code,
			"payload": response}); err != nil {
			return
		}
	}
	claims, err := tgauth.ParseToken(s.Cfg.JWTSecret, token)
	if err != nil {
		_ = write(map[string]any{"type": "auth_result", "status": http.StatusUnauthorized,
			"error": "token inválido"})
		return
	}
	_ = conn.SetReadDeadline(time.Time{})
	if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
		_ = write(snapshot)
	}

	sub := presence.Subscribe(r.Context(), s.RDB)
	defer sub.Close()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			var msg controlMessage
			if conn.ReadJSON(&msg) != nil {
				return
			}
			if msg.Type != "rpc" || msg.ID == "" || !privateRPCPath(msg.Path) {
				continue
			}
			req := httptest.NewRequest(msg.Method, "http://10.70.0.1"+msg.Path,
				bytes.NewReader(msg.Payload))
			req.RemoteAddr = "10.70.1.1:1"
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()
			NewRouter(s).ServeHTTP(rec, req)
			var payload any
			if rec.Body.Len() != 0 {
				if json.Unmarshal(rec.Body.Bytes(), &payload) != nil {
					payload = rec.Body.String()
				}
			}
			if write(map[string]any{"type": "rpc_response", "id": msg.ID,
				"status": rec.Code, "payload": payload}) != nil {
				return
			}
		}
	}()

	for {
		select {
		case <-done:
			return
		case message, ok := <-sub.Channel():
			if !ok {
				return
			}
			var evt presence.Event
			if json.Unmarshal([]byte(message.Payload), &evt) != nil {
				continue
			}
			if claims.Role != models.RoleSuperAdmin &&
				!s.eventVisibleTo(r.Context(), claims, evt) {
				continue
			}
			if evt.Type == "suspend_technician" &&
				evt.TargetID == claims.TechnicianID {
				_ = write(map[string]any{"type": "session_revoked"})
				return
			}
			if err := write(map[string]any{"type": "event", "event": evt}); err != nil {
				return
			}
			if evt.Type == "presence" || evt.Type == "telemetry" {
				continue
			}
			// O que mudou vai como delta: uma linha, não o mundo. O snapshot
			// inteiro era reconsultado e reenviado a cada evento — quatro
			// consultas vezes o número de técnicos conectados para entregar
			// uma mensagem de chat.
			// O catálogo vai inteiro — ele é pequeno, e mexer num tipo
			// costuma mexer em vários campos de uma vez. Vai daqui, e não
			// de deltaFor, porque o recorte depende de quem está do outro
			// lado: só o admin enxerga o que está desativado, que é o que
			// permite a ele religar um tipo.
			if evt.Type == "ticket_catalog" {
				if write(map[string]any{"type": "ticket_catalog",
					"payload": s.ticketCatalog(r.Context(),
						claims.Role == models.RoleSuperAdmin)}) != nil {
					return
				}
				continue
			}
			// Preço é configuração do dono do produto: só a tela dele
			// recebe, e por isso não passa por deltaFor.
			if evt.Type == "pricing_rules" {
				if claims.Role == models.RoleSuperAdmin {
					if write(map[string]any{"type": "pricing_rules",
						"payload": s.pricingRules(r.Context())}) != nil {
						return
					}
				}
				continue
			}
			// A fila de ofertas depende de quem está do outro lado: a mesma
			// oferta existe para um técnico e não para outro. deltaFor não
			// conhece a conexão, então esta é a parte que se resolve aqui.
			//
			// É o que substitui o Timer de 10s que a aba Fila mantinha: a
			// oferta chega quando acontece, e some quando expira — o próprio
			// card sabe a hora pelo expires_at, sem perguntar ao servidor.
			if claims.Role == models.RoleFreelancer {
				switch evt.Type {
				case "dispatch_offered", "dispatch_accepted", "ticket_created",
					"ticket_state", "service_order":
					if write(map[string]any{"type": "dispatch_offers",
						"payload": s.freelancerOffers(r.Context(),
							claims.TechnicianID)}) != nil {
						return
					}
				}
			}
			eventPayload, _ := evt.Payload.(map[string]any)
			if delta, ok := s.deltaFor(r.Context(), evt.Type, evt.TargetID,
				eventPayload); ok {
				if write(delta) != nil {
					return
				}
				continue
			}
			// Evento de estrutura mexe em várias linhas de uma vez; aí o
			// estado inteiro ainda é o caminho honesto.
			if snapshot, err := s.controlSnapshot(r.Context(), claims.TechnicianID, claims.Role); err == nil {
				if write(snapshot) != nil {
					return
				}
			}
		}
	}
}

// deviceRPCPath são as operações que a credencial de dispositivo libera no
// canal. É o mesmo mecanismo de privateRPCPath, com o alcance que este nível
// de permissão concede.
func deviceRPCPath(path string) bool {
	return strings.HasPrefix(path, "/api/v1/support/client/")
}

// mergeDeviceCredential injeta a identidade do dispositivo no corpo da chamada.
//
// Quem já provou quem é ao abrir o canal não precisa repetir a credencial a
// cada mensagem — e, mais importante, não deve poder informar OUTRA: sem isso,
// um dispositivo poderia agir em nome de outro simplesmente escrevendo outro
// device_id no corpo.
func mergeDeviceCredential(payload json.RawMessage, deviceID, token string) []byte {
	body := map[string]any{}
	if len(payload) > 0 {
		_ = json.Unmarshal(payload, &body)
	}
	body["device_id"] = deviceID
	body["device_token"] = token
	encoded, err := json.Marshal(body)
	if err != nil {
		return []byte("{}")
	}
	return encoded
}

func privateRPCPath(path string) bool {
	for _, prefix := range []string{
		"/api/v1/pairing/", "/api/v1/devices", "/api/v1/organizations",
		"/api/v1/networks", "/api/v1/subnetworks", "/api/v1/technicians", "/api/v1/branding/",
		"/api/v1/diagnostics/",
		"/api/v1/admin/",
		"/api/v1/support/",
	} {
		if path == strings.TrimSuffix(prefix, "/") || strings.HasPrefix(path, prefix) {
			return true
		}
	}
	return false
}

// PairingContext expõe publicamente apenas os dados mínimos necessários para
// consumir um código de pareamento antes do túnel do Técnico estar pronto.
func (s *Server) PairingContext(w http.ResponseWriter, r *http.Request) {
	// Usa as mesmas claims instaladas pelo middleware e o mesmo filtro do
	// snapshot; dispositivos e telemetria não fazem parte deste bootstrap.
	authClaims := middleware.ClaimsFrom(r.Context())
	snapshot, err := s.controlSnapshot(r.Context(), authClaims.TechnicianID, authClaims.Role)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_carregar_redes_pareamento", "falha ao carregar redes de pareamento")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"organizations": snapshot["organizations"],
		"networks":      snapshot["networks"],
		"subnetworks":   snapshot["subnetworks"],
	})
}

func (s *Server) controlSnapshot(ctx context.Context, technicianID, role string) (map[string]any, error) {
	orgQuery := `SELECT id,name,status,owner_technician_id,created_at FROM organizations ORDER BY created_at`
	netQuery := `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_by_technician_id,created_at FROM networks ORDER BY created_at`
	subnetQuery := `SELECT id,network_id,name,status,created_by_technician_id,created_at FROM subnetworks ORDER BY created_at`
	devQuery := `SELECT d.id,d.network_id,coalesce((SELECT array_agg(dn.network_id::text ORDER BY dn.created_at) FROM device_networks dn WHERE dn.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d ORDER BY d.created_at DESC`
	args := []any{}
	if role == models.RoleSupervisor {
		args = []any{technicianID}
		orgQuery = `SELECT DISTINCT o.id,o.name,o.status,o.owner_technician_id,o.created_at FROM organizations o WHERE o.owner_technician_id=$1 OR (lower(o.name)='tgdevs' AND EXISTS (SELECT 1 FROM networks n JOIN technician_assignments ta ON ta.network_id=n.id WHERE n.organization_id=o.id AND ta.technician_id=$1)) ORDER BY o.created_at`
		netQuery = `SELECT n.id,n.organization_id,n.name,coalesce(n.cidr_virtual,''),n.status,n.created_by_technician_id,n.created_at FROM networks n JOIN organizations o ON o.id=n.organization_id WHERE o.owner_technician_id=$1 OR (lower(o.name)='tgdevs' AND EXISTS (SELECT 1 FROM technician_assignments ta WHERE ta.technician_id=$1 AND ta.network_id=n.id)) ORDER BY n.created_at`
		subnetQuery = `SELECT s.id,s.network_id,s.name,s.status,s.created_by_technician_id,s.created_at FROM subnetworks s JOIN networks n ON n.id=s.network_id JOIN organizations o ON o.id=n.organization_id WHERE o.owner_technician_id=$1 OR (lower(o.name)='tgdevs' AND EXISTS (SELECT 1 FROM technician_assignments ta WHERE ta.technician_id=$1 AND ta.network_id=n.id)) ORDER BY s.created_at`
		devQuery = `SELECT DISTINCT d.id,d.network_id,coalesce((SELECT array_agg(dn2.network_id::text ORDER BY dn2.created_at) FROM device_networks dn2 WHERE dn2.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d JOIN device_networks dn ON dn.device_id=d.id JOIN networks n ON dn.network_id=n.id JOIN organizations o ON o.id=n.organization_id WHERE o.owner_technician_id=$1 OR (lower(o.name)='tgdevs' AND EXISTS (SELECT 1 FROM technician_assignments ta WHERE ta.technician_id=$1 AND ta.network_id=n.id) AND (NOT n.peer_isolation OR d.control_technician_id=$1)) ORDER BY d.created_at DESC`
	} else if role != models.RoleSuperAdmin {
		args = []any{technicianID}
		orgQuery = `SELECT DISTINCT o.id,o.name,o.status,o.owner_technician_id,o.created_at FROM organizations o LEFT JOIN networks n ON n.organization_id=o.id WHERE o.owner_technician_id=$1 OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY o.created_at`
		netQuery = `SELECT id,organization_id,name,coalesce(cidr_virtual,''),status,created_by_technician_id,created_at FROM networks WHERE organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY created_at`
		subnetQuery = `SELECT s.id,s.network_id,s.name,s.status,s.created_by_technician_id,s.created_at FROM subnetworks s JOIN networks n ON n.id=s.network_id WHERE n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY s.created_at`
		devQuery = `SELECT DISTINCT d.id,d.network_id,coalesce((SELECT array_agg(dn2.network_id::text ORDER BY dn2.created_at) FROM device_networks dn2 WHERE dn2.device_id=d.id),ARRAY[]::text[]),d.subnetwork_id,coalesce((SELECT array_agg(ds.subnetwork_id::text ORDER BY ds.created_at) FROM device_subnetworks ds WHERE ds.device_id=d.id),ARRAY[]::text[]),d.hostname,coalesce(d.display_name,''),coalesce(d.mac,''),coalesce(d.wg_pubkey,''),d.role,d.state,d.last_seen_at,d.created_at,d.updated_at,coalesce(d.rustdesk_id,'') FROM devices d JOIN device_networks dn ON dn.device_id=d.id JOIN networks n ON dn.network_id=n.id WHERE n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1) OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id=$1 AND network_id IS NOT NULL) ORDER BY d.created_at DESC`
	}
	orgs := []models.Organization{}
	rows, err := s.Pool.Query(ctx, orgQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var o models.Organization
		if rows.Scan(&o.ID, &o.Name, &o.Status, &o.OwnerTechnicianID, &o.CreatedAt) == nil {
			o.CanManage = role == models.RoleSuperAdmin ||
				(o.OwnerTechnicianID != nil && *o.OwnerTechnicianID == technicianID)
			orgs = append(orgs, o)
		}
	}
	rows.Close()
	nets := []models.Network{}
	rows, err = s.Pool.Query(ctx, netQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var n models.Network
		if rows.Scan(&n.ID, &n.OrganizationID, &n.Name, &n.CIDRVirtual, &n.Status, &n.CreatedBy, &n.CreatedAt) == nil {
			n.CanManage = role == models.RoleSuperAdmin
			if !n.CanManage {
				_ = s.Pool.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM organizations
						WHERE id=$1 AND owner_technician_id=$2)`,
					n.OrganizationID, technicianID).Scan(&n.CanManage)
			}
			if s.protectedSystemNetwork(ctx, n.ID) {
				n.CanManage = false
			}
			nets = append(nets, n)
		}
	}
	rows.Close()
	subnets := []models.Subnetwork{}
	rows, err = s.Pool.Query(ctx, subnetQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var sn models.Subnetwork
		if rows.Scan(&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt) == nil {
			sn.CanManage = role == models.RoleSuperAdmin
			if !sn.CanManage {
				_ = s.Pool.QueryRow(ctx, `
					SELECT EXISTS(SELECT 1 FROM subnetworks s
						JOIN networks n ON n.id=s.network_id
						JOIN organizations o ON o.id=n.organization_id
						WHERE s.id=$1 AND o.owner_technician_id=$2)`,
					sn.ID, technicianID).Scan(&sn.CanManage)
			}
			subnets = append(subnets, sn)
		}
	}
	rows.Close()
	devices := []models.Device{}
	rows, err = s.Pool.Query(ctx, devQuery, args...)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var d models.Device
		if rows.Scan(&d.ID, &d.NetworkID, &d.NetworkIDs, &d.SubnetworkID, &d.SubnetworkIDs, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey, &d.Role, &d.State, &d.LastSeenAt, &d.CreatedAt, &d.UpdatedAt, &d.RustdeskID) == nil {
			if d.State == models.DeviceStateAtivo && presence.IsOnline(ctx, s.RDB, d.ID) {
				d.Presence = "online"
			} else if d.State == models.DeviceStateAtivo {
				d.Presence = "offline"
			} else {
				d.Presence = d.State
			}
			capabilities := presence.GetCapabilities(ctx, s.RDB, d.ID)
			d.RemoteReady = capabilities.RemoteReady
			d.FilesReady = capabilities.FilesReady
			d.HealthLevel = s.readHealthLevel(ctx, d.ID)
			d.CanManage, _ = s.Authorizer.CanManageDevice(ctx, &tgauth.Claims{
				TechnicianID: technicianID,
				Role:         role,
			}, d.ID)
			devices = append(devices, d)
		}
	}
	rows.Close()
	// Os chamados vão no snapshot de abertura pelo mesmo motivo que as redes:
	// a tela se monta a partir do canal, nunca de uma busca própria. Sem isto
	// a tela de Chamados consultava o servidor ao montar, e quem abrisse a
	// aba antes de um chamado existir ficava sem ele até remontar a tela.
	tickets := s.ticketsForSnapshot(ctx, technicianID, role)
	ids := make([]string, 0, len(tickets))
	for _, ticket := range tickets {
		if id, ok := ticket["id"].(string); ok {
			ids = append(ids, id)
		}
	}
	// O catálogo de tipos entra na abertura pela mesma razão dos chamados: a
	// tela que abre um chamado monta o formulário a partir do esquema, e ela
	// se monta do canal, nunca de uma busca própria.
	// A fila de ofertas do técnico entra na abertura pelo mesmo motivo. Para
	// quem não é freelancer ela é vazia, e a aba nem existe.
	offers := []map[string]any{}
	if role == models.RoleFreelancer {
		offers = s.freelancerOffers(ctx, technicianID)
	}
	// As regras de preço vão só para o admin, que é quem as edita.
	pricing := []map[string]any{}
	if role == models.RoleSuperAdmin {
		pricing = s.pricingRules(ctx)
	}
	return map[string]any{"type": "snapshot", "organizations": orgs,
		"networks": nets, "subnetworks": subnets, "devices": devices,
		"tickets": tickets, "ticket_events": s.ticketEventsForSnapshot(ctx, ids),
		"ticket_types": s.ticketCatalog(ctx, role == models.RoleSuperAdmin),
		"dispatch_offers": offers, "pricing_rules": pricing}, nil
}
