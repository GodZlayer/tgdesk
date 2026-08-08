package handlers

import "net/http"

// AdminConfigDescriptors descreve o editor único do admin.
//
// O cliente usa isto para apresentar textos, agrupamento e intenção da tela.
// Valores, cálculos, limites e persistência continuam nas rotas específicas do
// servidor: pricing_rules, quotas, ticket_types, regions e catálogo da OS.
func (s *Server) AdminConfigDescriptors(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"version": 1,
		"sections": []map[string]any{
			{
				"key":           "audit",
				"title":         "Auditoria",
				"kind":          "live_pdf_log",
				"description":   "Log separado por domínio e relação para relatório live, PDF interativo, compliance e captação.",
				"read":          "/api/v1/admin/audit",
				"live_report":   "/api/v1/admin/audit/live-report",
				"event_detail":  "/api/v1/admin/audit/events/{id}",
				"domain_events": "/api/v1/admin/audit/domains/{domain}/events",
				"relations":     []string{"conexões", "vínculos", "financeiro", "OS", "diagnóstico", "território", "segurança"},
			},
			{
				"key":         "territory",
				"title":       "Regiões",
				"kind":        "territory_catalog",
				"description": "Cadastro territorial oficial e regiões comerciais usadas pela precificação.",
				"read":        "/api/v1/support/regions",
				"write":       "/api/v1/admin/regions",
				"official_sources": []map[string]string{
					{"name": "IBGE Localidades", "url": "https://servicodados.ibge.gov.br/api/docs/localidades"},
					{"name": "IBGE Recortes Metropolitanos", "url": "https://www.ibge.gov.br/geociencias/organizacao-do-territorio/estrutura-territorial/18354-recortes-metropolitanos-e-aglomeracoes-urbanas.html"},
				},
			},
			{
				"key":         "os_catalog",
				"title":       "Serviços, peças e consumíveis",
				"kind":        "catalog",
				"description": "Catálogo sem marca e sem preço final; peças e consumíveis exigem evidência fiscal na OS.",
				"read":        "/api/v1/support/os-catalog",
				"write":       []string{"/api/v1/admin/parts", "/api/v1/admin/services"},
			},
			{
				"key":                 "pricing",
				"title":               "Percentuais e precificação",
				"kind":                "rules",
				"description":         "Percentuais por papel, mínimo/máximo, taxas, promoções, escopo e vigência.",
				"read":                "/api/v1/admin/pricing-rules",
				"write":               "/api/v1/admin/pricing-rules",
				"payment_rules":       "/api/v1/admin/payment-rules",
				"regional_cost_index": "/api/v1/admin/regional-cost-index",
				"roles":               []string{"technician", "supervisor", "tgdesk", "referrer_supervisor"},
				"server_owned":        []string{"pagamento inicial", "mínimos regionais", "cálculo da OS", "grade de pagamento", "vigência"},
			},
			{
				"key":         "ticket_types",
				"title":       "Tipos de chamado",
				"kind":        "schema_catalog",
				"description": "Tipificação e campos estruturados dos chamados.",
				"read":        "/api/v1/support/ticket-types",
				"write":       []string{"/api/v1/admin/ticket-types", "/api/v1/admin/ticket-type-fields"},
			},
			{
				"key":         "linked",
				"title":       "Vinculados",
				"kind":        "relationship_editor",
				"description": "Organizações, redes, supervisores, técnicos e dispositivos no mesmo mapa lógico.",
				"read":        []string{"/api/v1/organizations", "/api/v1/networks", "/api/v1/technicians", "/api/v1/devices"},
			},
			{
				"key":         "quotas",
				"title":       "Cotas e direito de uso",
				"kind":        "entitlement_rules",
				"description": "Limites comerciais por organização, separados de dinheiro e precificação.",
				"read":        "/api/v1/admin/quotas",
				"write":       []string{"/api/v1/admin/quotas", "/api/v1/admin/product-defaults"},
			},
		},
	})
}
