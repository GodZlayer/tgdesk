package handlers

import (
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
)

type telemetryRequest struct {
	DeviceID    string          `json:"device_id"`
	DeviceToken string          `json:"device_token"`
	Hardware    json.RawMessage `json:"hardware"`
}

// ReportTelemetry é o fallback HTTP do canal WebSocket. Recebe somente o
// instantâneo físico; todo valor histórico é calculado após a persistência.
func (s *Server) ReportTelemetry(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErrCode(w, http.StatusForbidden, "telemetria_disponivel_somente_vpn", "telemetria disponível somente pela VPN")
		return
	}
	var req telemetryRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || len(req.Hardware) == 0 {
		writeErrCode(w, http.StatusBadRequest, "snapshot_hardware_invalido", "snapshot de hardware inválido")
		return
	}
	var deviceOK bool
	if err := s.Pool.QueryRow(r.Context(),
		`SELECT true FROM devices WHERE id=$1 AND device_token=$2`,
		req.DeviceID, req.DeviceToken).Scan(&deviceOK); err != nil {
		writeErrCode(w, http.StatusUnauthorized, "dispositivo_token_invalido", "dispositivo/token inválido")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`INSERT INTO telemetry_snapshots (device_id,hardware) VALUES ($1,$2)`,
		req.DeviceID, req.Hardware); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_gravar_telemetria", "falha ao gravar telemetria")
		return
	}
	s.rollHardwareJSON(r.Context(), req.DeviceID, req.Hardware)
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok", "statistics": s.hardwareStatistics(r.Context(), req.DeviceID),
	})
}

type deviceHealthResponse struct {
	Hardware    any    `json:"hardware"`
	Statistics  any    `json:"statistics"`
	CollectedAt string `json:"collected_at"`
}

// DeviceHealth entrega o mesmo contrato novo usado pelo cliente: snapshot
// atual e agregados produzidos no servidor.
func (s *Server) DeviceHealth(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())
	var orgID, netID string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id,n.id FROM devices d JOIN networks n ON d.network_id=n.id
		WHERE d.id=$1`, deviceID).Scan(&orgID, &netID); err != nil {
		writeErrCode(w, http.StatusNotFound, "dispositivo_encontrado_vinculado", "dispositivo não encontrado ou não vinculado")
		return
	}
	// Check authorization using centralized authorizer
	ok, err := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	if err != nil || !ok {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	var raw []byte
	var resp deviceHealthResponse
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT hardware,coletado_em::text FROM telemetry_snapshots
		WHERE device_id=$1 ORDER BY coletado_em DESC LIMIT 1`, deviceID).
		Scan(&raw, &resp.CollectedAt); err != nil {
		writeJSON(w, http.StatusOK, deviceHealthResponse{
			Hardware: map[string]any{}, Statistics: map[string]any{},
		})
		return
	}
	_ = json.Unmarshal(raw, &resp.Hardware)
	resp.Statistics = s.hardwareStatistics(r.Context(), deviceID)
	writeJSON(w, http.StatusOK, resp)
}
