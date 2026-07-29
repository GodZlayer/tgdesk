package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"time"

	"github.com/gorilla/websocket"
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
func runDeviceControlLoop(cfg *agentConfig, remoteReady bool) error {
	conn, _, err := websocket.DefaultDialer.Dial(privateControlURL(cfg), nil)
	if err != nil {
		return fmt.Errorf("conectar controle privado: %w", err)
	}
	defer conn.Close()

	readErr := make(chan error, 1)
	statsCh := make(chan any, 1)
	brandingCh := make(chan BrandingState, 1)
	diagnosticCh := make(chan diagnosticRequest, 1)
	diagnosticProgressCh := make(chan diagnosticProgress, 8)
	diagnosticResultCh := make(chan diagnosticResult, 1)
	go func() {
		for {
			var msg deviceControlMessage
			if err := conn.ReadJSON(&msg); err != nil {
				readErr <- err
				return
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
					Test string `json:"test"`
				}
				if json.Unmarshal(raw, &payload) == nil && payload.Test != "" {
					select {
					case diagnosticCh <- diagnosticRequest{ID: msg.ID, Test: payload.Test}:
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
		case statistics = <-statsCh:
			writeCurrentStatus()
		case branding = <-brandingCh:
			writeCurrentStatus()
		case request := <-diagnosticCh:
			go runDiagnostic(request, diagnosticProgressCh, diagnosticResultCh)
		case progress := <-diagnosticProgressCh:
			if err := conn.WriteJSON(deviceControlMessage{
				Type: "diagnostic_progress", ID: progress.ID, Payload: progress,
			}); err != nil {
				return err
			}
		case result := <-diagnosticResultCh:
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
