package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"tgdesk/api-core/internal/middleware"
)

type paymentRulesRequest struct {
	UpfrontPercent              float64 `json:"upfront_percent"`
	UpfrontBasis                string  `json:"upfront_basis"`
	ServiceMinimumMarginPercent float64 `json:"service_minimum_margin_percent"`
	Note                        string  `json:"note"`
}

func (s *Server) PaymentRules(w http.ResponseWriter, r *http.Request) {
	var raw []byte
	err := s.Pool.QueryRow(r.Context(), `
		SELECT jsonb_build_object(
			'upfront_percent', upfront_percent,
			'upfront_basis', upfront_basis,
			'service_minimum_margin_percent', service_minimum_margin_percent,
			'note', note,
			'updated_at', updated_at)
		FROM product_payment_rules WHERE singleton`).Scan(&raw)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"upfront_percent":                100,
			"upfront_basis":                  "services_parts_consumables",
			"service_minimum_margin_percent": 0,
			"note":                           "",
		})
		return
	}
	var out map[string]any
	if json.Unmarshal(raw, &out) != nil {
		out = map[string]any{}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) SavePaymentRules(w http.ResponseWriter, r *http.Request) {
	var req paymentRulesRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, http.StatusBadRequest, "dados_invalidos", "dados inválidos")
		return
	}
	req.UpfrontBasis = strings.TrimSpace(req.UpfrontBasis)
	if req.UpfrontBasis == "" {
		req.UpfrontBasis = "services_parts_consumables"
	}
	if req.UpfrontPercent < 0 || req.UpfrontPercent > 100 ||
		req.ServiceMinimumMarginPercent < 0 || req.ServiceMinimumMarginPercent > 100 ||
		(req.UpfrontBasis != "services_parts_consumables" && req.UpfrontBasis != "services_only") {
		writeErrCode(w, http.StatusBadRequest, "regra_pagamento_invalida", "regra de pagamento inválida")
		return
	}
	var editor *string
	if claims := middleware.ClaimsFrom(r.Context()); claims != nil {
		editor = &claims.TechnicianID
	}
	_, err := s.Pool.Exec(r.Context(), `
		INSERT INTO product_payment_rules(singleton,upfront_percent,upfront_basis,
			service_minimum_margin_percent,note,updated_by,updated_at)
		VALUES(true,$1,$2,$3,$4,$5,now())
		ON CONFLICT(singleton) DO UPDATE SET
			upfront_percent=excluded.upfront_percent,
			upfront_basis=excluded.upfront_basis,
			service_minimum_margin_percent=excluded.service_minimum_margin_percent,
			note=excluded.note,
			updated_by=excluded.updated_by,
			updated_at=now()`,
		req.UpfrontPercent, req.UpfrontBasis, req.ServiceMinimumMarginPercent,
		strings.TrimSpace(req.Note), editor)
	if err != nil {
		writeErrCode(w, http.StatusBadRequest, "falha_salvar_regra_pagamento", "falha ao salvar regra de pagamento")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"saved": true})
}
