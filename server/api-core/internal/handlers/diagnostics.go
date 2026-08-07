package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

// O catálogo carrega o que é dado: identidade, agrupamento e impacto. Nome e
// descrição são texto de interface e vivem no cliente, indexados pelo id —
// é o que permite que um cliente Android ou web escreva os seus.
var diagnosticCatalog = []map[string]any{
	{"id": "all_tests", "category": "Completo", "impact": "high"},
	{"id": "system_overview", "category": "Sistema", "impact": "low"},
	{"id": "cpu_stress", "category": "Processamento", "impact": "high"},
	{"id": "memory_integrity", "category": "Memória", "impact": "medium"},
	{"id": "memory_extended", "category": "Memória", "impact": "high"},
	{"id": "internet_quality", "category": "Rede", "impact": "low"},
	{"id": "network_latency_series", "category": "Rede", "impact": "medium"},
	{"id": "disk_performance", "category": "Armazenamento", "impact": "medium"},
	{"id": "disk_random_performance", "category": "Armazenamento", "impact": "medium"},
	{"id": "smart_extended", "category": "Armazenamento", "impact": "low"},
	{"id": "badblocks-read", "category": "Armazenamento", "impact": "low"},
	{"id": "storage_surface_read", "category": "Armazenamento", "impact": "high"},
	{"id": "filesystem_scan", "category": "Armazenamento", "impact": "low"},
	{"id": "filesystem_deep_scan", "category": "Armazenamento", "impact": "high"},
	{"id": "gpu_stress", "category": "Vídeo", "impact": "medium"},
	{"id": "battery_health", "category": "Energia", "impact": "low"},
	{"id": "driver_errors", "category": "Sistema", "impact": "low"},
	{"id": "critical_events", "category": "Sistema", "impact": "low"},
	{"id": "service_failures", "category": "Sistema", "impact": "low"},
	{"id": "startup_inventory", "category": "Sistema", "impact": "low"},
	{"id": "network_adapters", "category": "Rede", "impact": "low"},
	{"id": "dns_diagnostics", "category": "Rede", "impact": "low"},
	{"id": "route_table", "category": "Rede", "impact": "low"},
	{"id": "windows_integrity", "category": "Sistema", "impact": "medium"},
	{"id": "update_status", "category": "Sistema", "impact": "low"},
	{"id": "security_posture", "category": "Segurança", "impact": "low"},
	{"id": "defender_quick_scan", "category": "Segurança", "impact": "high"},
	{"id": "temperature_sensors", "category": "Hardware", "impact": "low"},
	{"id": "storage_volumes", "category": "Armazenamento", "impact": "low"},
	{"id": "process_pressure", "category": "Desempenho", "impact": "low"},
	{"id": "process_gpu_pressure", "category": "Desempenho", "impact": "medium"},
	{"id": "reboot_lag_history", "category": "Sistema", "impact": "low"},
	{"id": "resource_pressure_series", "category": "Desempenho", "impact": "medium"},
}

func (s *Server) diagnosticDeviceAccess(r *http.Request, deviceID string) bool {
	claims := middleware.ClaimsFrom(r.Context())
	ok, err := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	return err == nil && ok
}

func (s *Server) DiagnosticCatalog(w http.ResponseWriter, r *http.Request) {
	for _, item := range diagnosticCatalog {
		item["destructive"] = false
		item["requirements"] = []string{}
	}
	writeJSON(w, http.StatusOK, diagnosticCatalog)
}

func (s *Server) StartDiagnostic(w http.ResponseWriter, r *http.Request, deviceID string) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	var req struct {
		Test  string   `json:"test"`
		Tests []string `json:"tests"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, http.StatusBadRequest, "selecione_teste", "selecione um teste")
		return
	}
	selected := req.Tests
	if len(selected) == 0 && req.Test != "" {
		selected = []string{req.Test}
	}
	if len(selected) == 0 {
		writeErrCode(w, http.StatusBadRequest, "selecione_menos_teste", "selecione ao menos um teste")
		return
	}
	allowed := map[string]bool{}
	for _, item := range diagnosticCatalog {
		allowed[item["id"].(string)] = true
	}
	seen := map[string]bool{}
	for _, test := range selected {
		if !allowed[test] || test == "all_tests" && len(selected) > 1 {
			writeErrCode(w, http.StatusBadRequest, "teste_desconhecido", "teste desconhecido ou combinação inválida: "+test)
			return
		}
		if seen[test] {
			writeErrCode(w, http.StatusBadRequest, "teste_repetido", "teste repetido: "+test)
			return
		}
		seen[test] = true
	}
	claims := middleware.ClaimsFrom(r.Context())
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO diagnostic_runs(device_id,requested_by,tests)
		VALUES($1,$2,$3) RETURNING id`, deviceID, claims.TechnicianID, selected).Scan(&id)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_criar_diagnostico", "falha ao criar diagnóstico")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"id": id, "device_id": deviceID, "status": "queued", "tests": selected,
		"progress": 0, "created_at": time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) ListDiagnostics(w http.ResponseWriter, r *http.Request, deviceID string) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT id,status,tests,progress,coalesce(current_test,''),results,
		       coalesce(error,''),created_at,started_at,finished_at
		FROM diagnostic_runs WHERE device_id=$1
		ORDER BY created_at DESC LIMIT 30`, deviceID)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_diagnosticos", "falha ao listar diagnósticos")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, status, current, error string
		var tests, results []byte
		var progress int
		var created time.Time
		var started, finished *time.Time
		if rows.Scan(&id, &status, &tests, &progress, &current, &results,
			&error, &created, &started, &finished) != nil {
			continue
		}
		var testData, resultData any
		_ = json.Unmarshal(tests, &testData)
		_ = json.Unmarshal(results, &resultData)
		out = append(out, map[string]any{
			"id": id, "device_id": deviceID, "status": status, "tests": testData,
			"progress": progress, "current_test": current, "results": resultData,
			"error": error, "created_at": created, "started_at": started, "finished_at": finished,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

// CancelDiagnostic is scoped through the same device authorization as start/list.
// Queued work is finalized immediately; running work is marked cancelled and the
// device control channel delivers an idempotent cancellation signal.
func (s *Server) CancelDiagnostic(w http.ResponseWriter, r *http.Request, deviceID, runID string) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	var status string
	var running bool
	err := s.Pool.QueryRow(r.Context(), `
		UPDATE diagnostic_runs
		SET status='cancelled',
		    error='cancelado pelo técnico',
		    finished_at=CASE WHEN status='queued' THEN now() ELSE finished_at END
		WHERE id=$1 AND device_id=$2
		  AND status IN ('queued','running','paused','cancelled')
		RETURNING status,started_at IS NOT NULL AND finished_at IS NULL`,
		runID, deviceID).Scan(&status, &running)
	if err != nil {
		writeErrCode(w, http.StatusNotFound, "diagnostico_encontrado_ja_concluido", "diagnóstico não encontrado ou já concluído")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "diagnostic_result", TargetID: deviceID,
		Payload: map[string]any{"id": runID, "status": status, "cancel_pending": running},
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"id": runID, "device_id": deviceID, "status": status,
		"cancel_pending": running, "idempotent": true,
	})
}

func (s *Server) setDiagnosticPause(w http.ResponseWriter, r *http.Request, deviceID, runID string, paused bool) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErrCode(w, http.StatusForbidden, "permissao_dispositivo", "sem permissão para esse dispositivo")
		return
	}
	from, to := "running", "paused"
	if !paused {
		from, to = "paused", "running"
	}
	result, err := s.Pool.Exec(r.Context(), `
		UPDATE diagnostic_runs SET status=$1
		WHERE id=$2 AND device_id=$3 AND status=$4`, to, runID, deviceID, from)
	if err != nil || result.RowsAffected() != 1 {
		writeErrCode(w, http.StatusConflict, "diagnostico_estado_permita_acao", "o diagnóstico não está em um estado que permita essa ação")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "diagnostic_progress", TargetID: deviceID,
		Payload: map[string]any{"id": runID, "status": to, "queue_paused": paused},
	})
	writeJSON(w, http.StatusOK, map[string]any{
		"id": runID, "device_id": deviceID, "status": to, "queue_paused": paused,
	})
}

// PauseDiagnostic conclui o teste individual atual e bloqueia o início do
// próximo item da suíte. Nenhum processo é congelado no meio de I/O.
func (s *Server) PauseDiagnostic(w http.ResponseWriter, r *http.Request, deviceID, runID string) {
	s.setDiagnosticPause(w, r, deviceID, runID, true)
}

func (s *Server) ResumeDiagnostic(w http.ResponseWriter, r *http.Request, deviceID, runID string) {
	s.setDiagnosticPause(w, r, deviceID, runID, false)
}
