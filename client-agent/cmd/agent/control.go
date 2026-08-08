package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"time"

	"github.com/gorilla/websocket"

	"tgdesk/agent/internal/updatecore"
)

type deviceControlMessage struct {
	Type    string `json:"type"`
	ID      string `json:"id,omitempty"`
	State   string `json:"state,omitempty"`
	Version string `json:"version,omitempty"`
	Payload any    `json:"payload,omitempty"`
}

func privateControlURL(cfg *agentConfig) string {
	q := url.Values{}
	q.Set("device_id", cfg.DeviceID)
	q.Set("device_token", cfg.DeviceToken)
	return "ws://10.70.0.1:8080/ws/control/device?" + q.Encode()
}

// runDeviceControlLoop substitui heartbeat e telemetria HTTP depois que a
// VPN está disponível. O retorno sempre significa que o canal privado caiu.
// uiChannel é a ponte com as telas desta máquina. Vive fora do laço porque o
// canal com o servidor pode cair e reconectar, e a tela não deve perceber.
var uiChannel = newUIBridge()

// UIBridgePort é a porta local onde a tela encontra o agente.
const UIBridgePort = 47615

func runDeviceControlLoop(cfg *agentConfig, remoteReady bool) error {
	_ = uiChannel.Listen(UIBridgePort)
	conn, _, err := websocket.DefaultDialer.Dial(privateControlURL(cfg), nil)
	if err != nil {
		return fmt.Errorf("conectar controle privado: %w", err)
	}
	defer conn.Close()

	readErr := make(chan error, 1)
	statsCh := make(chan any, 1)
	brandingCh := make(chan BrandingState, 1)
	diagnosticCh := make(chan diagnosticRequest, 1)
	diagnosticCancelCh := make(chan string, 1)
	diagnosticPauseCh := make(chan struct {
		ID     string
		Paused bool
	}, 2)
	diagnosticProgressCh := make(chan diagnosticProgress, 8)
	diagnosticResultCh := make(chan diagnosticResult, 1)
	updateOrderCh := make(chan updateOrder, 1)
	updateProgressCh := make(chan updatecore.Progress, 8)
	updateResultCh := make(chan updateOutcome, 1)
	go func() {
		for {
			var msg deviceControlMessage
			if err := conn.ReadJSON(&msg); err != nil {
				readErr <- err
				return
			}
			// Respostas de RPC e eventos do chamado seguem para a tela pela
			// ponte local: um canal só com o servidor, várias telas possíveis.
			if msg.Type == "rpc_response" || msg.Type == "ticket_thread" {
				uiChannel.Broadcast(msg)
			}
			if msg.Type == "heartbeat_ack" {
				uiChannel.Broadcast(msg)
			}
			if msg.Type == "telemetry_stats" {
				select {
				case statsCh <- msg.Payload:
				default:
				}
			}
			if msg.Type == "ready" || msg.Type == "branding" {
				raw, _ := json.Marshal(msg.Payload)
				var branding BrandingState
				if msg.Type == "ready" {
					var payload struct {
						Branding BrandingState `json:"branding"`
					}
					if json.Unmarshal(raw, &payload) == nil {
						branding = payload.Branding
					}
				} else {
					_ = json.Unmarshal(raw, &branding)
				}
				if branding.Name == "" {
					branding.Name = "TGDesk"
				}
				syncBrandFavicon(branding)
				select {
				case brandingCh <- branding:
				default:
				}
			}
			if msg.Type == "diagnostic_run" && msg.ID != "" {
				raw, _ := json.Marshal(msg.Payload)
				var payload struct {
					Test  string   `json:"test"`
					Tests []string `json:"tests"`
				}
				if json.Unmarshal(raw, &payload) == nil {
					if len(payload.Tests) == 0 && payload.Test != "" {
						payload.Tests = []string{payload.Test}
					}
					if len(payload.Tests) == 0 {
						continue
					}
					select {
					case diagnosticCh <- diagnosticRequest{ID: msg.ID, Tests: payload.Tests}:
					default:
					}
				}
			}
			if msg.Type == "diagnostic_cancel" && msg.ID != "" {
				select {
				case diagnosticCancelCh <- msg.ID:
				default:
				}
			}
			if msg.Type == "diagnostic_pause" && msg.ID != "" {
				paused := true
				if payload, ok := msg.Payload.(map[string]any); ok {
					if value, exists := payload["paused"].(bool); exists {
						paused = value
					}
				}
				select {
				case diagnosticPauseCh <- struct {
					ID     string
					Paused bool
				}{msg.ID, paused}:
				default:
				}
			}
			if msg.Type == "update_now" {
				raw, _ := json.Marshal(msg.Payload)
				var order updateOrder
				if json.Unmarshal(raw, &order) == nil && order.Version != "" {
					uiChannel.Broadcast(map[string]any{
						"type": "update_status",
						"payload": map[string]any{
							"updating": true,
							"update_progress": map[string]any{
								"version":       order.Version,
								"throttle_kbps": order.ThrottleKbps,
							},
						},
					})
					select {
					case updateOrderCh <- order:
					default:
					}
				}
			}
			if msg.Version != "" {
				setServerUpdateVersion(msg.Version)
			}
			if msg.State == "suspenso" {
				readErr <- fmt.Errorf("dispositivo suspenso")
				return
			}
		}
	}()

	heartbeatTick := time.NewTicker(5 * time.Second)
	telemetryTick := time.NewTicker(30 * time.Second)
	remoteRetryTick := time.NewTicker(15 * time.Second)
	defer heartbeatTick.Stop()
	defer telemetryTick.Stop()
	defer remoteRetryTick.Stop()

	sendHeartbeat := func() error {
		return conn.WriteJSON(deviceControlMessage{
			Type: "heartbeat",
			Payload: map[string]any{
				"remote_ready": remoteReady,
				"files_ready":  remoteReady,
				// A versão que roda de fato vai no heartbeat porque é o
				// servidor quem decide quem atualiza — ele não pergunta.
				"client_version": updatecore.CurrentClientVersion(),
			},
		})
	}
	if err := sendHeartbeat(); err != nil {
		return err
	}
	if cfg.RustdeskID != "" {
		_ = conn.WriteJSON(deviceControlMessage{
			Type:    "rustdesk_status",
			Payload: map[string]string{"rustdesk_id": cfg.RustdeskID},
		})
	}

	var hardware HardwareSnapshot
	var statistics any
	var collectedAt string
	var remoteError string
	branding := BrandingState{Name: "TGDesk"}
	type activeDiagnostic struct {
		cancel context.CancelFunc
		pause  *diagnosticPauseGate
	}
	activeDiagnostics := map[string]activeDiagnostic{}
	writeCurrentStatus := func() {
		writeStatus(tgdeskStatus{
			State: "ativo", Hostname: localHostname(), DeviceID: cfg.DeviceID,
			VirtualIP: cfg.VirtualIP, RustdeskID: cfg.RustdeskID, TunnelUp: true,
			Hardware: hardware, Statistics: statistics, CollectedAt: collectedAt,
			RemoteReady: remoteReady, FilesReady: remoteReady,
			RemoteError: remoteError,
			Branding:    branding,
		})
	}
	for {
		select {
		case err := <-readErr:
			return err
		case fromUI := <-uiChannel.outbound:
			// A tela fala com o servidor por este canal — nunca por fora dele.
			if conn.WriteMessage(websocket.TextMessage, fromUI) != nil {
				return fmt.Errorf("canal privado caiu ao encaminhar a tela")
			}
		case statistics = <-statsCh:
			writeCurrentStatus()
		case branding = <-brandingCh:
			writeCurrentStatus()
		case request := <-diagnosticCh:
			ctx, cancel := context.WithCancel(context.Background())
			gate := newDiagnosticPauseGate()
			activeDiagnostics[request.ID] = activeDiagnostic{cancel: cancel, pause: gate}
			go runDiagnostic(ctx, request, gate, diagnosticProgressCh, diagnosticResultCh)
		case order := <-updateOrderCh:
			startForcedUpdate(order,
				func(progress updatecore.Progress) {
					select {
					case updateProgressCh <- progress:
					default:
					}
				},
				func(outcome updateOutcome) {
					select {
					case updateResultCh <- outcome:
					default:
					}
				})
			uiChannel.Broadcast(map[string]any{
				"type": "update_status",
				"payload": map[string]any{
					"updating": true,
					"update_progress": map[string]any{
						"version":       order.Version,
						"throttle_kbps": order.ThrottleKbps,
					},
				},
			})
			writeCurrentStatus()
		case progress := <-updateProgressCh:
			// O andamento vai para a tela pelo status; o servidor só precisa
			// saber quando terminou, para liberar o próximo da fila.
			writeCurrentStatus()
			uiChannel.Broadcast(map[string]any{
				"type": "update_status",
				"payload": map[string]any{
					"updating":        true,
					"update_progress": progress,
				},
			})
		case outcome := <-updateResultCh:
			writeCurrentStatus()
			uiChannel.Broadcast(map[string]any{
				"type":    "update_status",
				"payload": map[string]any{"updating": false, "outcome": outcome},
			})
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "update_result", Payload: outcome,
			}); err != nil {
				return err
			}
		case id := <-diagnosticCancelCh:
			if active, exists := activeDiagnostics[id]; exists {
				active.cancel()
			}
		case request := <-diagnosticPauseCh:
			if active, exists := activeDiagnostics[request.ID]; exists {
				active.pause.set(request.Paused)
			}
		case progress := <-diagnosticProgressCh:
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "diagnostic_progress", ID: progress.ID, Payload: progress,
			}); err != nil {
				return err
			}
		case result := <-diagnosticResultCh:
			if active, exists := activeDiagnostics[result.ID]; exists {
				active.cancel()
				delete(activeDiagnostics, result.ID)
			}
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "diagnostic_result", ID: result.ID, Payload: result,
			}); err != nil {
				return err
			}
		case <-heartbeatTick.C:
			if err := sendHeartbeat(); err != nil {
				return err
			}
			writeCurrentStatus()
		case <-remoteRetryTick.C:
			if !remoteReady {
				if err := setupRemoteAccess(cfg); err != nil {
					remoteError = err.Error()
				} else {
					remoteReady = true
					remoteError = ""
					if cfg.RustdeskID != "" {
						_ = conn.WriteJSON(deviceControlMessage{
							Type:    "rustdesk_status",
							Payload: map[string]string{"rustdesk_id": cfg.RustdeskID},
						})
					}
					if err := sendHeartbeat(); err != nil {
						return err
					}
				}
				writeCurrentStatus()
			}
		case <-telemetryTick.C:
			hardware = collectHardwareSnapshot()
			collectedAt = time.Now().UTC().Format(time.RFC3339)
			writeCurrentStatus()
			payload, _ := json.Marshal(map[string]any{"hardware": hardware})
			var body any
			_ = json.Unmarshal(payload, &body)
			if err := conn.WriteJSON(deviceControlMessage{Type: "telemetry", Payload: body}); err != nil {
				return err
			}
		}
	}
}
