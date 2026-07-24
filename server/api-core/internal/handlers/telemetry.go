package handlers

import (
	"encoding/json"
	"net/http"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

type telemetryRequest struct {
	DeviceID    string  `json:"device_id"`
	DeviceToken string  `json:"device_token"`
	CPU         float64 `json:"cpu"`
	Mem         float64 `json:"mem"`
	Disco       float64 `json:"disco"`
	Temp        float64 `json:"temp"`
	Disks       any     `json:"disks"`
}

// alertThresholds — Módulo D (Seção 8.D): regras simples de limiar. Sem
// driver de kernel, então sem SMART/temperatura de disco de verdade ainda —
// "temp" aqui é best-effort (0 se a fonte não tiver leitura).
const (
	cpuAlertThreshold   = 90.0
	memAlertThreshold   = 90.0
	discoAlertThreshold = 90.0
	tempAlertThreshold  = 80.0
)

// ReportTelemetry grava um snapshot e dispara alerta se algum limiar for
// ultrapassado — mas só um alerta não-resolvido por tipo por vez (evita
// inundar a tabela a cada 30s enquanto o problema persiste).
func (s *Server) ReportTelemetry(w http.ResponseWriter, r *http.Request) {
	if !requestFromVPN(r) {
		writeErr(w, http.StatusForbidden, "telemetria disponível somente pela VPN")
		return
	}
	var req telemetryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "corpo inválido")
		return
	}
	var deviceOK bool
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT true FROM devices WHERE id=$1 AND device_token=$2`, req.DeviceID, req.DeviceToken,
	).Scan(&deviceOK); err != nil {
		writeErr(w, http.StatusUnauthorized, "dispositivo/token inválido")
		return
	}

	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO telemetry_snapshots (device_id, cpu, mem, disco, temp, disks)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		req.DeviceID, req.CPU, req.Mem, req.Disco, req.Temp, req.Disks,
	); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao gravar telemetria")
		return
	}

	s.maybeAlert(r, req.DeviceID, "cpu_alto", req.CPU, cpuAlertThreshold, "Uso de CPU acima de 90%")
	s.maybeAlert(r, req.DeviceID, "memoria_alta", req.Mem, memAlertThreshold, "Uso de memória acima de 90%")
	s.maybeAlert(r, req.DeviceID, "disco_cheio", req.Disco, discoAlertThreshold, "Disco acima de 90% de uso")
	if req.Temp > 0 {
		s.maybeAlert(r, req.DeviceID, "temperatura_alta", req.Temp, tempAlertThreshold, "Temperatura acima de 80°C")
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) maybeAlert(r *http.Request, deviceID, tipo string, value, threshold float64, message string) {
	if value < threshold {
		// Abaixo do limiar de novo — resolve qualquer alerta pendente desse tipo.
		_, _ = s.Pool.Exec(r.Context(), `
			UPDATE alerts SET resolvido=true WHERE device_id=$1 AND tipo=$2 AND resolvido=false`, deviceID, tipo)
		return
	}
	var exists bool
	_ = s.Pool.QueryRow(r.Context(), `
		SELECT true FROM alerts WHERE device_id=$1 AND tipo=$2 AND resolvido=false`, deviceID, tipo,
	).Scan(&exists)
	if exists {
		return
	}
	severidade := "aviso"
	if value >= threshold+8 {
		severidade = "critico"
	}
	_, _ = s.Pool.Exec(r.Context(), `
		INSERT INTO alerts (device_id, tipo, severidade, mensagem) VALUES ($1, $2, $3, $4)`,
		deviceID, tipo, severidade, message)
}

type deviceHealthResponse struct {
	CPU        float64    `json:"cpu"`
	Mem        float64    `json:"mem"`
	Disco      float64    `json:"disco"`
	Temp       float64    `json:"temp"`
	ColetadoEm string     `json:"coletado_em"`
	AlertsOut  []alertOut `json:"alerts"`
}

type alertOut struct {
	Tipo       string `json:"tipo"`
	Severidade string `json:"severidade"`
	Mensagem   string `json:"mensagem"`
	CreatedAt  string `json:"created_at"`
}

// DeviceHealth expõe o último snapshot + alertas em aberto de um dispositivo
// pro Hub — RBAC igual ao ListDevices (super_admin vê tudo, técnico só o que
// está em technician_assignments).
func (s *Server) DeviceHealth(w http.ResponseWriter, r *http.Request, deviceID string) {
	claims := middleware.ClaimsFrom(r.Context())

	var orgID, netID string
	if err := s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id, n.id FROM devices d JOIN networks n ON d.network_id = n.id
		WHERE d.id=$1`, deviceID,
	).Scan(&orgID, &netID); err != nil {
		writeErr(w, http.StatusNotFound, "dispositivo não encontrado ou não vinculado")
		return
	}
	if claims.Role != models.RoleSuperAdmin {
		ok, err := s.technicianCanAccess(r.Context(), claims.TechnicianID, orgID, netID)
		if err != nil || !ok {
			writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
			return
		}
	}

	var resp deviceHealthResponse
	err := s.Pool.QueryRow(r.Context(), `
		SELECT cpu::float8, mem::float8, disco::float8, temp::float8, coletado_em::text FROM telemetry_snapshots
		WHERE device_id=$1 ORDER BY coletado_em DESC LIMIT 1`, deviceID,
	).Scan(&resp.CPU, &resp.Mem, &resp.Disco, &resp.Temp, &resp.ColetadoEm)
	if err != nil {
		resp = deviceHealthResponse{AlertsOut: []alertOut{}}
	}

	rows, err := s.Pool.Query(r.Context(), `
		SELECT tipo, severidade, mensagem, created_at::text FROM alerts
		WHERE device_id=$1 AND resolvido=false ORDER BY created_at DESC`, deviceID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var a alertOut
			if rows.Scan(&a.Tipo, &a.Severidade, &a.Mensagem, &a.CreatedAt) == nil {
				resp.AlertsOut = append(resp.AlertsOut, a)
			}
		}
	}
	if resp.AlertsOut == nil {
		resp.AlertsOut = []alertOut{}
	}
	writeJSON(w, http.StatusOK, resp)
}
