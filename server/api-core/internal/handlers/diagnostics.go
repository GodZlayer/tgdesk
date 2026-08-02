package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

var diagnosticCatalog = []map[string]any{
	{"id": "system_overview", "name": "Inspeção completa", "category": "Sistema", "impact": "low", "duration_seconds": 10, "description": "Inventário, serviços, eventos críticos e estado geral."},
	{"id": "cpu_stress", "name": "Carga do processador", "category": "Processamento", "impact": "high", "duration_seconds": 30, "description": "Mantém todos os núcleos ocupados e mede estabilidade e resposta."},
	{"id": "memory_integrity", "name": "Integridade da memória", "category": "Memória", "impact": "medium", "duration_seconds": 30, "description": "Reserva blocos de memória e verifica padrões de leitura e escrita."},
	{"id": "internet_quality", "name": "Qualidade da Internet", "category": "Rede", "impact": "low", "duration_seconds": 25, "description": "Mede DNS, perda de pacotes, latência e acesso externo."},
	{"id": "disk_performance", "name": "Desempenho do armazenamento", "category": "Armazenamento", "impact": "medium", "duration_seconds": 45, "description": "Executa leitura e escrita temporária e remove o arquivo ao terminar."},
	{"id": "smart_extended", "name": "Saúde física dos discos", "category": "Armazenamento", "impact": "low", "duration_seconds": 20, "description": "Consulta SMART, temperatura, desgaste e erros registrados."},
	{"id": "badblocks-read", "name": "Setores defeituosos (somente leitura)", "category": "Armazenamento", "impact": "low", "duration_seconds": 30, "description": "Consulta contadores de confiabilidade do disco (erros de leitura corrigidos e não corrigidos) sem escrever nem apagar dados."},
	{"id": "filesystem_scan", "name": "Setores e sistema de arquivos", "category": "Armazenamento", "impact": "high", "duration_seconds": 300, "description": "Executa verificação online somente leitura, sem reparar ou alterar dados."},
	{"id": "gpu_stress", "name": "Carga gráfica", "category": "Vídeo", "impact": "high", "duration_seconds": 30, "description": "Executa carga gráfica do Windows e registra estabilidade e desempenho."},
	{"id": "battery_health", "name": "Saúde da bateria", "category": "Energia", "impact": "low", "duration_seconds": 10, "description": "Compara capacidade projetada, carga atual e estado da bateria."},
	{"id": "driver_errors", "name": "Falhas de drivers", "category": "Sistema", "impact": "low", "duration_seconds": 15, "description": "Lista dispositivos PnP com erro ou driver ausente."},
	{"id": "critical_events", "name": "Eventos críticos", "category": "Sistema", "impact": "low", "duration_seconds": 20, "description": "Consolida eventos críticos e erros recentes do Windows."},
	{"id": "service_failures", "name": "Serviços com falha", "category": "Sistema", "impact": "low", "duration_seconds": 10, "description": "Detecta serviços automáticos parados e falhas de inicialização."},
	{"id": "startup_inventory", "name": "Inicialização do Windows", "category": "Sistema", "impact": "low", "duration_seconds": 10, "description": "Inventaria programas e tarefas iniciados com o Windows."},
	{"id": "network_adapters", "name": "Adaptadores de rede", "category": "Rede", "impact": "low", "duration_seconds": 10, "description": "Verifica link, velocidade, erros e configuração IP."},
	{"id": "dns_diagnostics", "name": "Diagnóstico DNS", "category": "Rede", "impact": "low", "duration_seconds": 15, "description": "Testa servidores DNS configurados e resolução externa."},
	{"id": "route_table", "name": "Rotas e gateways", "category": "Rede", "impact": "low", "duration_seconds": 10, "description": "Analisa rotas, gateways e métricas de interface."},
	{"id": "windows_integrity", "name": "Integridade do Windows", "category": "Sistema", "impact": "medium", "duration_seconds": 180, "description": "Executa DISM ScanHealth sem reparar ou alterar arquivos."},
	{"id": "update_status", "name": "Atualizações do Windows", "category": "Sistema", "impact": "low", "duration_seconds": 20, "description": "Lista hotfixes e reinicializações pendentes."},
	{"id": "security_posture", "name": "Postura de segurança", "category": "Segurança", "impact": "low", "duration_seconds": 15, "description": "Consulta Defender, firewall, Secure Boot e criptografia."},
	{"id": "temperature_sensors", "name": "Sensores térmicos", "category": "Hardware", "impact": "low", "duration_seconds": 10, "description": "Lê sensores térmicos expostos por WMI e GPU."},
	{"id": "storage_volumes", "name": "Volumes e espaço", "category": "Armazenamento", "impact": "low", "duration_seconds": 10, "description": "Verifica capacidade, espaço livre e estado dos volumes."},
	{"id": "process_pressure", "name": "Pressão de processos", "category": "Desempenho", "impact": "low", "duration_seconds": 10, "description": "Lista maiores consumidores de CPU, memória e I/O."},
}

func (s *Server) diagnosticDeviceAccess(r *http.Request, deviceID string) bool {
	claims := middleware.ClaimsFrom(r.Context())
	ok, err := s.Authorizer.CanAccessDevice(r.Context(), claims, deviceID)
	return err == nil && ok
}

func (s *Server) DiagnosticCatalog(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, diagnosticCatalog)
}

func (s *Server) StartDiagnostic(w http.ResponseWriter, r *http.Request, deviceID string) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
		return
	}
	var req struct {
		Test string `json:"test"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.Test == "" {
		writeErr(w, http.StatusBadRequest, "selecione um teste")
		return
	}
	allowed := map[string]bool{}
	for _, item := range diagnosticCatalog {
		allowed[item["id"].(string)] = true
	}
	if !allowed[req.Test] {
		writeErr(w, http.StatusBadRequest, "teste desconhecido: "+req.Test)
		return
	}
	claims := middleware.ClaimsFrom(r.Context())
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO diagnostic_runs(device_id,requested_by,tests)
		VALUES($1,$2,$3) RETURNING id`, deviceID, claims.TechnicianID, []string{req.Test}).Scan(&id)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao criar diagnóstico")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"id": id, "device_id": deviceID, "status": "queued", "test": req.Test,
		"progress": 0, "created_at": time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) ListDiagnostics(w http.ResponseWriter, r *http.Request, deviceID string) {
	if !s.diagnosticDeviceAccess(r, deviceID) {
		writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
		return
	}
	rows, err := s.Pool.Query(r.Context(), `
		SELECT id,status,tests,progress,coalesce(current_test,''),results,
		       coalesce(error,''),created_at,started_at,finished_at
		FROM diagnostic_runs WHERE device_id=$1
		ORDER BY created_at DESC LIMIT 30`, deviceID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao listar diagnósticos")
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
		writeErr(w, http.StatusForbidden, "sem permissão para esse dispositivo")
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
		  AND status IN ('queued','running','cancelled')
		RETURNING status,started_at IS NOT NULL AND finished_at IS NULL`,
		runID, deviceID).Scan(&status, &running)
	if err != nil {
		writeErr(w, http.StatusNotFound, "diagnóstico não encontrado ou já concluído")
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
