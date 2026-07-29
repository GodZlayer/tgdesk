package handlers

import (
	"encoding/json"
	"net/http"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
)

var diagnosticCatalog = []map[string]any{
	{"id": "system_overview", "name": "Inspeção completa", "category": "Sistema", "impact": "low", "duration_seconds": 10, "description": "Inventário, serviços, eventos críticos e estado geral."},
	{"id": "cpu_stress", "name": "Carga do processador", "category": "Processamento", "impact": "high", "duration_seconds": 30, "description": "Mantém todos os núcleos ocupados e mede estabilidade e resposta."},
	{"id": "memory_integrity", "name": "Integridade da memória", "category": "Memória", "impact": "medium", "duration_seconds": 30, "description": "Reserva blocos de memória e verifica padrões de leitura e escrita."},
	{"id": "internet_quality", "name": "Qualidade da Internet", "category": "Rede", "impact": "low", "duration_seconds": 25, "description": "Mede DNS, perda de pacotes, latência e acesso externo."},
	{"id": "disk_performance", "name": "Desempenho do armazenamento", "category": "Armazenamento", "impact": "medium", "duration_seconds": 45, "description": "Executa leitura e escrita temporária e remove o arquivo ao terminar."},
	{"id": "smart_extended", "name": "Saúde física dos discos", "category": "Armazenamento", "impact": "low", "duration_seconds": 20, "description": "Consulta SMART, temperatura, desgaste e erros registrados."},
	{"id": "filesystem_scan", "name": "Setores e sistema de arquivos", "category": "Armazenamento", "impact": "high", "duration_seconds": 300, "description": "Executa verificação online somente leitura, sem reparar ou alterar dados."},
	{"id": "gpu_stress", "name": "Carga gráfica", "category": "Vídeo", "impact": "high", "duration_seconds": 30, "description": "Executa carga gráfica do Windows e registra estabilidade e desempenho."},
}

func (s *Server) diagnosticDeviceAccess(r *http.Request, deviceID string) bool {
	claims := middleware.ClaimsFrom(r.Context())
	if claims.Role == models.RoleSuperAdmin {
		return true
	}
	var orgID, networkID string
	if s.Pool.QueryRow(r.Context(), `
		SELECT n.organization_id,n.id FROM devices d
		JOIN networks n ON n.id=d.network_id WHERE d.id=$1`, deviceID).
		Scan(&orgID, &networkID) != nil {
		return false
	}
	ok, _ := s.technicianCanAccess(r.Context(), claims.TechnicianID, orgID, networkID)
	return ok
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
