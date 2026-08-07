package handlers

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type slideTemplate struct {
	Key         string `json:"key"`
	Label       string `json:"label"`
	Description string `json:"description"`
	Tone        string `json:"tone"`
}

var adminSlideTemplates = []slideTemplate{
	{Key: "investor", Label: "Investidor", Description: "Capa forte, m?tricas, risco, tra??o e leitura de oportunidade.", Tone: "executive"},
	{Key: "board", Label: "Conselho", Description: "Governan?a, auditoria, financeiro, opera??o e riscos.", Tone: "governance"},
	{Key: "operations", Label: "Opera??o", Description: "V?nculos, regi?es, t?cnicos, dispositivos e chamados.", Tone: "operational"},
	{Key: "commercial", Label: "Comercial", Description: "Valor do produto, cobertura, cat?logo, regi?es e argumentos de venda.", Tone: "commercial"},
}

func (s *Server) AdminSlideTemplates(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, adminSlideTemplates)
}

func (s *Server) ExportAdminSlideshowPDF(w http.ResponseWriter, r *http.Request) {
	template := strings.TrimSpace(r.URL.Query().Get("template"))
	if template == "" {
		template = "investor"
	}
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 30
	}
	since := time.Now().AddDate(0, 0, -days)
	metrics := s.auditInvestorMetrics(r.Context(), since)
	sections := s.slideshowSections(r.Context(), since)
	domainSlide := append([]string{"Dom?nios auditados"}, sections...)
	slides := [][]string{
		{"TGDesk", "Painel administrativo absoluto", "Template: " + template, "Período: últimos " + strconv.Itoa(days) + " dias"},
		{"Resumo executivo", "Chamados: " + fmt.Sprint(metrics["tickets_opened"]), "OS criadas: " + fmt.Sprint(metrics["service_orders_created"]), "Volume OS: " + centsText(metrics["service_orders_total_cents"]), "Dispositivos ativos: " + fmt.Sprint(metrics["active_devices"])},
		domainSlide,
		{"Vinculados", "Organiza??es: " + fmt.Sprint(metrics["organizations"]), "T?cnicos dispon?veis: " + fmt.Sprint(metrics["available_technicians"]), "Regi?es ativas: " + fmt.Sprint(metrics["active_regions"]), "Eventos de risco: " + fmt.Sprint(metrics["risk_events"])},
		{"Leitura de investidor", "Sistema com regras no servidor, cliente como apresenta??o.", "Regi?es e precifica??o din?mica j? estruturadas.", "Auditoria e v?nculos explicam opera??o e escala.", "Dados detalhados ficam no painel interativo."},
	}
	pdf := buildSimplePDF(slides)
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", `attachment; filename="tgdesk-admin-`+template+`.pdf"`)
	_, _ = w.Write(pdf)
}

func (s *Server) slideshowSections(ctx context.Context, since time.Time) []string {
	rows, err := s.Pool.Query(ctx, `SELECT d.label,count(e.id) FROM audit_domains d LEFT JOIN audit_events e ON e.domain_key=d.key AND e.created_at >= $1 GROUP BY d.label,d.position ORDER BY d.position LIMIT 8`, since)
	if err != nil {
		return []string{"Auditoria", "V?nculos", "Financeiro", "Regi?es"}
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var label string
		var count int64
		if rows.Scan(&label, &count) == nil {
			out = append(out, fmt.Sprintf("%s: %d eventos", label, count))
		}
	}
	return out
}

func centsText(value any) string {
	var cents int64
	switch v := value.(type) {
	case int64:
		cents = v
	case int:
		cents = int64(v)
	case float64:
		cents = int64(v)
	}
	return fmt.Sprintf("R$ %.2f", float64(cents)/100)
}

func buildSimplePDF(slides [][]string) []byte {
	objects := []string{"<< /Type /Catalog /Pages 2 0 R >>"}
	pageRefs := []string{}
	for i := range slides {
		pageObj := 3 + i*2
		pageRefs = append(pageRefs, fmt.Sprintf("%d 0 R", pageObj))
	}
	objects = append(objects, fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.Join(pageRefs, " "), len(slides)))
	for i, slide := range slides {
		contentObj := 4 + i*2
		stream := pdfTextStream(slide)
		objects = append(objects, fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Contents %d 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >> /F2 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>", contentObj))
		objects = append(objects, fmt.Sprintf("<< /Length %d >>\nstream\n%s\nendstream", len(stream), stream))
	}
	var buf bytes.Buffer
	buf.WriteString("%PDF-1.4\n")
	offsets := []int{0}
	for i, obj := range objects {
		offsets = append(offsets, buf.Len())
		buf.WriteString(fmt.Sprintf("%d 0 obj\n%s\nendobj\n", i+1, obj))
	}
	xref := buf.Len()
	buf.WriteString(fmt.Sprintf("xref\n0 %d\n0000000000 65535 f \n", len(objects)+1))
	for i := 1; i < len(offsets); i++ {
		buf.WriteString(fmt.Sprintf("%010d 00000 n \n", offsets[i]))
	}
	buf.WriteString(fmt.Sprintf("trailer << /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF", len(objects)+1, xref))
	return buf.Bytes()
}

func pdfTextStream(lines []string) string {
	var b strings.Builder
	b.WriteString("0.08 0.12 0.20 rg 0 0 842 595 re f\n")
	b.WriteString("1 1 1 rg BT /F1 34 Tf 60 520 Td (")
	b.WriteString(pdfEscape(first(lines)))
	b.WriteString(") Tj ET\n")
	y := 455
	for _, line := range lines[1:] {
		b.WriteString(fmt.Sprintf("0.88 0.92 1 rg BT /F2 20 Tf 78 %d Td (%s) Tj ET\n", y, pdfEscape(line)))
		y -= 42
	}
	b.WriteString("0.20 0.70 1 rg 60 52 720 5 re f\n")
	return b.String()
}

func first(lines []string) string {
	if len(lines) == 0 {
		return "TGDesk"
	}
	return lines[0]
}

func pdfEscape(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "(", "\\(")
	s = strings.ReplaceAll(s, ")", "\\)")
	return s
}
