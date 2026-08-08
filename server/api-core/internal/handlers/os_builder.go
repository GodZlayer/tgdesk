package handlers

import (
	"context"
	"encoding/json"
	"math"
	"net/http"
	"strings"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/presence"
)

// Construtor de OS: catálogo de peças e serviços, e o orçamento que sai deles.
//
// A OS deixa de ser texto livre. O técnico monta o orçamento escolhendo linhas
// de um catálogo que o admin cadastra, e o valor final não é digitado: sai de
// resolvePricing — que até aqui existia sem ser chamado por ninguém — ajustado
// pela demanda do recorte e travado pelos limites cadastrados.
//
// O catálogo segue o mesmo princípio dos tipos de chamado: peça nova e serviço
// novo são linha de tabela, não release.

type catalogPart struct {
	ID                   string  `json:"id"`
	SKU                  string  `json:"sku"`
	Label                string  `json:"label"`
	Description          string  `json:"description"`
	Unit                 string  `json:"unit"`
	ItemKind             string  `json:"item_kind"`
	RequiresInvoicePhoto bool    `json:"requires_invoice_photo"`
	TicketTypeKey        *string `json:"ticket_type_key"`
	Active               bool    `json:"active"`
	Position             int     `json:"position"`
}

type catalogService struct {
	ID              string   `json:"id"`
	Key             string   `json:"key"`
	Label           string   `json:"label"`
	Description     string   `json:"description"`
	DurationMin     int      `json:"duration_min"`
	TicketTypeKey   *string  `json:"ticket_type_key"`
	ServiceTypeKeys []string `json:"service_type_keys"`
	OsType          *string  `json:"os_type"`
	ManualURL       string   `json:"manual_url"`
	Active          bool     `json:"active"`
	Position        int      `json:"position"`
}

// osCatalog lê peças e serviços de uma vez. Como o catálogo de tipos, ele é
// pequeno o bastante para viajar inteiro no snapshot: recortar por tipo aqui
// obrigaria a tela a pedir de novo a cada troca de tipo, que é exatamente a
// busca ao montar que o produto não faz.
func (s *Server) osCatalog(ctx context.Context, includeInactive bool) map[string]any {
	parts := []catalogPart{}
	services := []catalogService{}

	filter := "WHERE active"
	if includeInactive {
		filter = ""
	}
	serviceFilter := "WHERE service_catalog.active"
	if includeInactive {
		serviceFilter = ""
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT id,sku,label,description,unit,item_kind,requires_invoice_photo,
		       ticket_type_key,active,position
		FROM part_catalog `+filter+`
		ORDER BY position,label`); err == nil {
		for rows.Next() {
			var p catalogPart
			if rows.Scan(&p.ID, &p.SKU, &p.Label, &p.Description, &p.Unit,
				&p.ItemKind, &p.RequiresInvoicePhoto, &p.TicketTypeKey,
				&p.Active, &p.Position) == nil {
				parts = append(parts, p)
			}
		}
		rows.Close()
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT id,key,label,description,duration_min,
		       ticket_type_key,
		       COALESCE(array_agg(DISTINCT option.type_key)
		         FILTER (WHERE option.type_key IS NOT NULL), '{}'::text[]),
		       os_type,manual_url,active,position
		FROM service_catalog
		LEFT JOIN ticket_type_service_options option
		  ON option.service_key=service_catalog.key AND option.active
		`+serviceFilter+`
		GROUP BY id,key,label,description,duration_min,
		         ticket_type_key,os_type,manual_url,active,position
		ORDER BY position,label`); err == nil {
		for rows.Next() {
			var c catalogService
			if rows.Scan(&c.ID, &c.Key, &c.Label, &c.Description, &c.DurationMin,
				&c.TicketTypeKey, &c.ServiceTypeKeys, &c.OsType, &c.ManualURL,
				&c.Active, &c.Position) == nil {
				if c.TicketTypeKey != nil && !containsString(c.ServiceTypeKeys, *c.TicketTypeKey) {
					c.ServiceTypeKeys = append([]string{*c.TicketTypeKey}, c.ServiceTypeKeys...)
				}
				services = append(services, c)
			}
		}
		rows.Close()
	}

	return map[string]any{"parts": parts, "services": services}
}

func containsString(items []string, value string) bool {
	for _, item := range items {
		if item == value {
			return true
		}
	}
	return false
}

// OsCatalog entrega o catálogo por requisição, para quem chega antes do
// snapshot ou precisa reler depois de editar.
func (s *Server) OsCatalog(w http.ResponseWriter, r *http.Request) {
	// Só o admin vê o que está desativado: para o técnico, item inativo não
	// existe, e mostrá-lo só criaria a escolha que o cadastro já negou.
	admin := middleware.ClaimsFrom(r.Context()).Role == models.RoleSuperAdmin
	writeJSON(w, 200, s.osCatalog(r.Context(), admin))
}

// publishOsCatalog avisa as telas de que peças ou serviços mudaram, pelo mesmo
// motivo e do mesmo jeito que publishCatalog.
func (s *Server) publishOsCatalog(ctx context.Context) {
	_ = presence.Publish(ctx, s.RDB, presence.Event{
		Type: "os_catalog", TargetID: "os_catalog",
	})
}

type partRequest struct {
	ID                   string  `json:"id"`
	SKU                  string  `json:"sku"`
	Label                string  `json:"label"`
	Description          string  `json:"description"`
	Unit                 string  `json:"unit"`
	ItemKind             string  `json:"item_kind"`
	RequiresInvoicePhoto *bool   `json:"requires_invoice_photo"`
	TicketTypeKey        *string `json:"ticket_type_key"`
	Active               *bool   `json:"active"`
	Position             *int    `json:"position"`
}

// SavePart cria ou atualiza uma peça. O SKU é a identidade de negócio e por
// isso resolve o conflito: recadastrar o mesmo SKU corrige a linha existente em
// vez de criar uma segunda com o mesmo código.
func (s *Server) SavePart(w http.ResponseWriter, r *http.Request) {
	var req partRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	req.SKU = strings.TrimSpace(req.SKU)
	req.Label = strings.TrimSpace(req.Label)
	if req.SKU == "" || req.Label == "" {
		writeErrCode(w, 400, "sku_rotulo_obrigatorios", "SKU e rótulo são obrigatórios")
		return
	}
	if req.Unit == "" {
		req.Unit = "un"
	}
	if req.ItemKind == "" {
		req.ItemKind = "part"
	}
	if req.ItemKind != "part" && req.ItemKind != "consumable" {
		writeErrCode(w, 400, "tipo_item_invalido", "o item deve ser peça ou consumível")
		return
	}
	active, position := true, 100
	requiresInvoice := true
	if req.Active != nil {
		active = *req.Active
	}
	if req.Position != nil {
		position = *req.Position
	}
	if req.RequiresInvoicePhoto != nil {
		requiresInvoice = *req.RequiresInvoicePhoto
	}
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO part_catalog(sku,label,description,unit,ticket_type_key,
		                         active,position,item_kind,requires_invoice_photo)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT(sku) DO UPDATE SET label=excluded.label,
			description=excluded.description,unit=excluded.unit,
			ticket_type_key=excluded.ticket_type_key,active=excluded.active,
			position=excluded.position,item_kind=excluded.item_kind,
			requires_invoice_photo=excluded.requires_invoice_photo,updated_at=now()
		RETURNING id`,
		req.SKU, req.Label, req.Description, req.Unit, req.TicketTypeKey,
		active, position, req.ItemKind,
		requiresInvoice).Scan(&id)
	if err != nil {
		writeErrCode(w, 400, "falha_salvar_peca", "falha ao salvar a peça")
		return
	}
	s.publishOsCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"id": id, "sku": req.SKU})
}

// DeletePart desativa em vez de apagar quando a peça já foi usada: apagar
// levaria junto a referência das OS que a compraram. O rótulo e o preço ficam
// congelados na linha da OS, então o histórico sobrevive de qualquer forma —
// mas a peça some do catálogo sem sumir do passado.
func (s *Server) DeletePart(w http.ResponseWriter, r *http.Request, id string) {
	var usada bool
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM service_order_items WHERE part_id=$1)`,
		id).Scan(&usada)
	if usada {
		if _, err := s.Pool.Exec(r.Context(),
			`UPDATE part_catalog SET active=false,updated_at=now() WHERE id=$1`,
			id); err != nil {
			writeErrCode(w, 500, "falha_desativar", "falha ao desativar a peça")
			return
		}
		s.publishOsCatalog(r.Context())
		writeJSON(w, 200, map[string]any{"deactivated": id})
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`DELETE FROM part_catalog WHERE id=$1`, id); err != nil {
		writeErrCode(w, 500, "falha_apagar", "falha ao apagar a peça")
		return
	}
	s.publishOsCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": id})
}

type serviceRequest struct {
	Key           string  `json:"key"`
	Label         string  `json:"label"`
	Description   string  `json:"description"`
	DurationMin   *int    `json:"duration_min"`
	TicketTypeKey *string `json:"ticket_type_key"`
	OsType        *string `json:"os_type"`
	ManualURL     string  `json:"manual_url"`
	Active        *bool   `json:"active"`
	Position      *int    `json:"position"`
}

// SaveService cria ou atualiza uma classificação de serviço. A existência da
// chave é validada aqui; preço é resolvido exclusivamente pela região da OS.
func (s *Server) SaveService(w http.ResponseWriter, r *http.Request) {
	var req serviceRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	req.Key = strings.ToLower(strings.TrimSpace(req.Key))
	req.Label = strings.TrimSpace(req.Label)
	if req.Key == "" || req.Label == "" {
		writeErrCode(w, 400, "chave_rotulo_obrigatorios", "chave e rótulo são obrigatórios")
		return
	}
	if strings.ContainsAny(req.Key, " \t/") {
		writeErrCode(w, 400, "chave_invalida", "a chave não pode ter espaço nem barra")
		return
	}
	if req.OsType != nil && *req.OsType != "virtual" && *req.OsType != "onsite" {
		writeErrCode(w, 400, "tipo_invalido", "o tipo de OS deve ser virtual ou onsite")
		return
	}
	duration, active, position := 60, true, 100
	if req.DurationMin != nil && *req.DurationMin > 0 {
		duration = *req.DurationMin
	}
	if req.Active != nil {
		active = *req.Active
	}
	if req.Position != nil {
		position = *req.Position
	}
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO service_catalog(key,label,description,duration_min,
		            ticket_type_key,os_type,manual_url,active,position)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)
		ON CONFLICT(key) DO UPDATE SET label=excluded.label,
			description=excluded.description,
			duration_min=excluded.duration_min,
			ticket_type_key=excluded.ticket_type_key,os_type=excluded.os_type,
			manual_url=excluded.manual_url,active=excluded.active,
			position=excluded.position,updated_at=now()
		RETURNING id`,
		req.Key, req.Label, req.Description, duration, req.TicketTypeKey,
		req.OsType, req.ManualURL, active, position).Scan(&id)
	if err != nil {
		writeErrCode(w, 400, "falha_salvar_servico", "falha ao salvar o serviço")
		return
	}
	if req.TicketTypeKey != nil && strings.TrimSpace(*req.TicketTypeKey) != "" {
		_, _ = s.Pool.Exec(r.Context(), `
			INSERT INTO ticket_type_service_options
				(type_key,service_key,relation_kind,default_pick,position,active)
			VALUES($1,$2,'possible',true,$3,true)
			ON CONFLICT(type_key,service_key) DO UPDATE SET
				default_pick=true, position=excluded.position,
				active=true, updated_at=now()`,
			*req.TicketTypeKey, req.Key, position)
	}
	s.publishOsCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"id": id, "key": req.Key})
}

// DeleteService segue a mesma regra da peça: desativa se já foi usado.
func (s *Server) DeleteService(w http.ResponseWriter, r *http.Request, id string) {
	var usado bool
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM service_order_items WHERE service_id=$1)`,
		id).Scan(&usado)
	if usado {
		if _, err := s.Pool.Exec(r.Context(),
			`UPDATE service_catalog SET active=false,updated_at=now() WHERE id=$1`,
			id); err != nil {
			writeErrCode(w, 500, "falha_desativar", "falha ao desativar o serviço")
			return
		}
		s.publishOsCatalog(r.Context())
		writeJSON(w, 200, map[string]any{"deactivated": id})
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`DELETE FROM service_catalog WHERE id=$1`, id); err != nil {
		writeErrCode(w, 500, "falha_apagar", "falha ao apagar o serviço")
		return
	}
	s.publishOsCatalog(r.Context())
	writeJSON(w, 200, map[string]any{"deleted": id})
}

// ---------------------------------------------------------------------------
// O orçamento.
// ---------------------------------------------------------------------------

// As constantes da fórmula do preço dinâmico.
//
// Estas NÃO são configuração do admin, e a separação é deliberada: o admin
// edita os percentuais das classes, a taxa, a promoção e o piso e o teto do
// VALOR — tudo isso é pricing_rules. O que ele não edita é a fórmula e os
// números que a fazem funcionar. São decisão de produto: mudá-los muda como o
// TGDesk se comporta como mercado, não quanto uma empresa paga.
//
// Estão todos aqui, juntos, para que essa decisão tenha um lugar só.
const (
	// Preço cheio, sem ajuste. É de onde a conta parte.
	multiplicadorBase = 100.0

	// Até onde o ajuste pode ir, para baixo e para cima. O piso existe para
	// que região parada não zere o valor do trabalho; o teto, para que um pico
	// não vire preço extorsivo — que é o erro que este modelo comete quando
	// ninguém o freia.
	multiplicadorPiso = 70.0
	multiplicadorTeto = 250.0

	// Quantos clientes por técnico o produto considera saudável. É o ponto em
	// que a pressão estrutural vale 1 — nem sobra nem falta técnico para o
	// tamanho do lugar.
	clientesPorTecnicoAlvo = 40.0

	// Como as duas pressões se dividem no ajuste. A imediata pesa mais porque
	// é a que o cliente sente: fila grande agora encarece agora. A estrutural
	// é o pano de fundo — um lugar cronicamente mal atendido é caro mesmo num
	// dia calmo.
	pesoPressaoImediata   = 0.6
	pesoPressaoEstrutural = 0.4
)

// demandMultiplier é o quanto o mercado da região empurra o preço, em
// centésimos — 100 é preço cheio.
//
// As três entradas são as que definem o lugar: quantos chamados estão
// esperando, quantos técnicos existem para atendê-los, e quantos clientes
// (empresariais e avulsos) a região tem.
//
// Delas saem duas pressões:
//
//	imediata   = chamados esperando / técnicos disponíveis
//	estrutural = (clientes / técnicos) / clientesPorTecnicoAlvo
//
// Ambas valem 1 no equilíbrio. O ajuste é a média ponderada do quanto cada uma
// se afasta de 1, e o resultado é travado entre o piso e o teto.
//
// A distinção entre as duas importa: a imediata é volátil e responde à fila de
// agora; a estrutural é lenta e descreve se o lugar tem gente suficiente para
// dar conta de si. Um lugar com dois chamados abertos e um técnico para
// duzentos clientes não é barato só porque hoje está calmo.
//
// Nada disto é guardado, de propósito: as contagens mudam em minutos, e um
// número gravado ontem descreveria um mercado que não existe mais. O que se
// guarda é o resultado, no orçamento fechado — porque aí ele virou compromisso.
func (s *Server) demandMultiplier(ctx context.Context, scope pricingScope) int64 {
	// Sem região não há mercado a medir. Cobrar pela demanda de um lugar que
	// não se sabe qual é seria pior do que não ajustar: o avulso que não
	// informou onde está pagaria pelo mercado de outra pessoa.
	if scope.RegionID == nil {
		return int64(multiplicadorBase)
	}

	var esperando, tecnicos, clientes int64

	// Chamados esperando atendimento na região.
	_ = s.Pool.QueryRow(ctx, `
		SELECT count(*) FROM support_tickets
		WHERE region_id=$1 AND status IN ('open','accepted','offered')`,
		*scope.RegionID).Scan(&esperando)

	// Técnicos disponíveis na região.
	_ = s.Pool.QueryRow(ctx, `
		SELECT count(*) FROM freelancer_profiles
		WHERE region_id=$1 AND availability`, *scope.RegionID).Scan(&tecnicos)

	// Clientes na região: empresariais e avulsos na mesma contagem, porque
	// para o mercado local os dois são a mesma coisa — máquina que pode
	// precisar de atendimento.
	_ = s.Pool.QueryRow(ctx, `
		SELECT count(*) FROM devices
		WHERE region_id=$1 AND state='ativo'`, *scope.RegionID).Scan(&clientes)

	return ajusteDeDemanda(esperando, tecnicos, clientes)
}

// ajusteDeDemanda é a fórmula em si, separada das consultas.
//
// Fica separada para poder ser conferida com números na mão: é a linha que
// decide quanto alguém paga, e uma conta dessas não deve depender de subir um
// banco para se saber se está certa.
func ajusteDeDemanda(esperando, tecnicos, clientes int64) int64 {
	if tecnicos == 0 {
		// Nenhum técnico na região. Se também não há fila, não há mercado a
		// precificar e o preço é o cheio; se há fila, é escassez completa, e
		// escassez completa é o teto — sem o freio, a divisão por zero viraria
		// preço infinito.
		if esperando == 0 {
			return int64(multiplicadorBase)
		}
		return int64(multiplicadorTeto)
	}

	imediata := float64(esperando) / float64(tecnicos)
	estrutural := (float64(clientes) / float64(tecnicos)) / clientesPorTecnicoAlvo

	ajuste := pesoPressaoImediata*(imediata-1) + pesoPressaoEstrutural*(estrutural-1)
	mult := multiplicadorBase * (1 + ajuste)

	if mult < multiplicadorPiso {
		mult = multiplicadorPiso
	}
	if mult > multiplicadorTeto {
		mult = multiplicadorTeto
	}
	return int64(math.Round(mult))
}

// osQuote é o orçamento fechado: o que cada linha somou, o que a demanda
// ajustou, o que o admin reteve e o que sobra para cada classe.
type osQuote struct {
	SubtotalCents    int64            `json:"subtotal_cents"`
	ServiceCents     int64            `json:"service_cents"`
	PassThroughCents int64            `json:"pass_through_cents"`
	CostCents        int64            `json:"cost_cents"`
	DemandMultiple   int64            `json:"demand_multiple"`
	AdjustedCents    int64            `json:"adjusted_cents"`
	PromoCents       int64            `json:"promo_cents"`
	FeeCents         int64            `json:"fee_cents"`
	TotalCents       int64            `json:"total_cents"`
	UpfrontCents     int64            `json:"upfront_cents"`
	DistributedCent  map[string]int64 `json:"distributed_cents"`
	ResolvedAt       time.Time        `json:"resolved_at"`
	Pricing          ResolvedPricing  `json:"pricing"`
}

// buildQuote fecha o orçamento de uma OS a partir das linhas já gravadas.
//
// A ordem das operações é a que o negócio descreve, e ela importa: a demanda
// ajusta o preço de venda, a promoção desconta do preço ajustado, a taxa do
// admin sai do que sobrou, e só então o resto se divide entre as classes. Fazer
// a taxa incidir antes da promoção daria outro número — e o cliente veria um
// desconto que não é o que ele recebeu.
func (s *Server) buildQuote(ctx context.Context, osID string,
	scope pricingScope) (osQuote, error) {
	q := osQuote{DistributedCent: map[string]int64{}, ResolvedAt: time.Now()}

	if err := s.Pool.QueryRow(ctx, `
		SELECT coalesce(sum(total_cents),0),
		       coalesce(sum(total_cents) FILTER (WHERE service_id IS NOT NULL),0),
		       coalesce(sum(total_cents) FILTER (WHERE part_id IS NOT NULL),0),
		       coalesce(sum(round(cost_cents * quantity)),0)
		FROM service_order_items WHERE service_order_id=$1`,
		osID).Scan(&q.SubtotalCents, &q.ServiceCents, &q.PassThroughCents,
		&q.CostCents); err != nil {
		return q, err
	}

	price := s.resolvePricing(ctx, scope)
	q.Pricing = price
	q.DemandMultiple = s.demandMultiplier(ctx, scope)
	q.AdjustedCents = q.ServiceCents * q.DemandMultiple / 100

	// Os limites de 'bounds' travam o valor do chamado, não o multiplicador:
	// são o piso e o teto que o cliente pode ver, independentemente do que a
	// demanda calculou.
	if price.MinCents != nil && q.AdjustedCents < *price.MinCents {
		q.AdjustedCents = *price.MinCents
	}
	if price.MaxCents != nil && q.AdjustedCents > *price.MaxCents {
		q.AdjustedCents = *price.MaxCents
	}

	if price.PromoPercnt != nil {
		q.PromoCents += int64(math.Round(
			float64(q.AdjustedCents) * *price.PromoPercnt / 100))
	}
	if price.PromoCents != nil {
		q.PromoCents += *price.PromoCents
	}
	if q.PromoCents > q.AdjustedCents {
		q.PromoCents = q.AdjustedCents
	}
	liquido := q.AdjustedCents - q.PromoCents

	if price.FeePercent != nil {
		q.FeeCents += int64(math.Round(float64(liquido) * *price.FeePercent / 100))
	}
	if price.FeeCents != nil {
		q.FeeCents += *price.FeeCents
	}
	if q.FeeCents > liquido {
		q.FeeCents = liquido
	}

	// O total é o que o cliente paga: a taxa do admin sai de dentro dele, não
	// por cima.
	q.TotalCents = liquido + q.PassThroughCents
	// A taxa do gateway sai primeiro. As participações configuradas são
	// calculadas sobre o líquido do serviço; o técnico nunca é editável e
	// recebe exatamente o saldo depois das demais participações.
	restante := liquido - q.FeeCents
	q.DistributedCent["payment_system"] = q.FeeCents
	var distribuido int64
	for role, percent := range price.Shares {
		if role == "technician" || role == "super_admin" || role == "tgdesk_fee" {
			continue
		}
		amount := int64(math.Round(float64(restante) * percent / 100))
		if amount < 0 {
			amount = 0
		}
		if distribuido+amount > restante {
			amount = restante - distribuido
		}
		q.DistributedCent[role] += amount
		distribuido += amount
	}
	if restante > distribuido {
		q.DistributedCent["technician"] = restante - distribuido
	}
	q.UpfrontCents = s.upfrontCents(ctx, q.ServiceCents, q.PassThroughCents)
	return q, nil
}

func (s *Server) upfrontCents(ctx context.Context, serviceCents, passThroughCents int64) int64 {
	var percent float64
	var basis string
	if s.Pool.QueryRow(ctx, `
		SELECT upfront_percent,upfront_basis
		FROM product_payment_rules WHERE singleton`).Scan(&percent, &basis) != nil {
		percent, basis = 100, "services_parts_consumables"
	}
	base := serviceCents
	if basis == "services_parts_consumables" {
		base += passThroughCents
	}
	return int64(math.Round(float64(base) * percent / 100))
}

// osScope monta o recorte de preço de uma OS a partir do chamado que a
// originou. É uma consulta só porque o recorte é sempre o mesmo conjunto de
// colunas — deixar cada chamador montá-lo daria tantas versões da regra quantos
// forem os chamadores.
func (s *Server) osScope(ctx context.Context, ticketID string) (pricingScope, error) {
	var scope pricingScope
	err := s.Pool.QueryRow(ctx, `
		SELECT t.type_key, t.organization_id, t.region_id, t.network_id,
		       t.standalone, d.subnetwork_id, o.assigned_technician_id
		FROM support_tickets t
		LEFT JOIN devices d        ON d.id = t.device_id
		LEFT JOIN service_orders o ON o.ticket_id = t.id
		WHERE t.id=$1`, ticketID).Scan(&scope.TicketType, &scope.OrganizationID,
		&scope.RegionID, &scope.NetworkID, &scope.Standalone,
		&scope.SubnetworkID, &scope.TechnicianID)
	if err != nil {
		return scope, err
	}
	// Chamado aberto antes de a região existir, ou antes de o admin cadastrar
	// a dele: resolve agora e congela, para que a próxima conta não precise
	// refazer o mesmo caminho.
	if scope.RegionID == nil {
		s.StampTicketRegion(ctx, ticketID)
		_ = s.Pool.QueryRow(ctx,
			`SELECT region_id FROM support_tickets WHERE id=$1`,
			ticketID).Scan(&scope.RegionID)
	}
	return scope, nil
}

// OsQuote devolve o orçamento de uma OS sem gravá-lo — é o que a tela mostra
// enquanto o técnico monta as linhas. Gravar só acontece no fechamento, porque
// só aí o número vira compromisso.
func (s *Server) OsQuote(w http.ResponseWriter, r *http.Request, ticketID string) {
	if !s.canManageTicket(r, ticketID) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var osID string
	if s.Pool.QueryRow(r.Context(),
		`SELECT id FROM service_orders WHERE ticket_id=$1`,
		ticketID).Scan(&osID) != nil {
		writeErrCode(w, 404, "os_nao_encontrada", "OS não encontrada")
		return
	}
	scope, err := s.osScope(r.Context(), ticketID)
	if err != nil {
		writeErrCode(w, 404, "chamado_nao_encontrado", "chamado não encontrado")
		return
	}
	quote, err := s.buildQuote(r.Context(), osID, scope)
	if err != nil {
		writeErrCode(w, 500, "falha_orcamento", "falha ao montar o orçamento")
		return
	}
	writeJSON(w, 200, quote)
}

type osItemRequest struct {
	PartID    *string  `json:"part_id"`
	ServiceID *string  `json:"service_id"`
	Label     string   `json:"label"`
	UnitCents *int64   `json:"unit_cents"`
	Quantity  *float64 `json:"quantity"`
	Note      string   `json:"note"`
	Position  *int     `json:"position"`
}

// AddOsItem acrescenta uma linha ao orçamento.
//
// Quando a linha aponta para o catálogo, rótulo e preço vêm de lá e o que o
// cliente mandou é ignorado: deixar o técnico informar o preço de uma peça
// catalogada anularia o sentido de ter catálogo. Linha avulsa — sem peça nem
// serviço — é o caso em que os dois vêm digitados.
func (s *Server) AddOsItem(w http.ResponseWriter, r *http.Request, ticketID string) {
	if !s.canManageTicket(r, ticketID) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var req osItemRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	if req.PartID != nil && req.ServiceID != nil {
		writeErrCode(w, 400, "peca_ou_servico",
			"a linha é peça ou serviço, não os dois")
		return
	}
	var osID string
	if s.Pool.QueryRow(r.Context(),
		`SELECT id FROM service_orders WHERE ticket_id=$1`,
		ticketID).Scan(&osID) != nil {
		writeErrCode(w, 404, "os_nao_encontrada", "OS não encontrada")
		return
	}

	label, note := strings.TrimSpace(req.Label), strings.TrimSpace(req.Note)
	var regionID *string
	_ = s.Pool.QueryRow(r.Context(),
		`SELECT region_id FROM support_tickets WHERE id=$1`, ticketID).Scan(&regionID)
	var unit, cost int64
	switch {
	case req.PartID != nil:
		if s.Pool.QueryRow(r.Context(),
			`SELECT label FROM part_catalog WHERE id=$1 AND active`,
			*req.PartID).Scan(&label) != nil {
			writeErrCode(w, 404, "peca_nao_encontrada", "peça não encontrada no catálogo")
			return
		}
		// Peças e consumíveis são itens de execução, não mercadoria TGDesk.
		unit, cost = 0, 0
	case req.ServiceID != nil:
		var serviceKey string
		if s.Pool.QueryRow(r.Context(),
			`SELECT label,key FROM service_catalog WHERE id=$1 AND active`,
			*req.ServiceID).Scan(&label, &serviceKey) != nil {
			writeErrCode(w, 404, "servico_nao_encontrado", "serviço não encontrado no catálogo")
			return
		}
		var found bool
		unit, found = s.resolveRegionalServiceBase(r.Context(), serviceKey, regionID)
		if !found {
			writeErrCode(w, 409, "servico_sem_faixa_regional",
				"este serviço não possui faixa de preço para a região do chamado")
			return
		}
	default:
		if label == "" || req.UnitCents == nil || *req.UnitCents < 0 {
			writeErrCode(w, 400, "linha_avulsa_precisa_rotulo_e_valor",
				"linha avulsa precisa de rótulo e valor")
			return
		}
		unit = *req.UnitCents
	}

	quantity, position := 1.0, 100
	if req.Quantity != nil && *req.Quantity > 0 {
		quantity = *req.Quantity
	}
	if req.Position != nil {
		position = *req.Position
	}

	var itemID string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO service_order_items(service_order_id,part_id,service_id,
		            label,unit_cents,cost_cents,quantity,note,position)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING id`,
		osID, req.PartID, req.ServiceID, label, unit, cost, quantity, note,
		position).Scan(&itemID)
	if err != nil {
		writeErrCode(w, 400, "falha_incluir_item", "falha ao incluir a linha")
		return
	}
	s.publishTicket(r, ticketID, "service_order",
		map[string]any{"id": osID, "item_id": itemID})
	writeJSON(w, 201, map[string]any{"id": itemID, "label": label,
		"unit_cents": unit, "quantity": quantity})
}

// resolveRegionalServiceBase entrega a base da faixa da região. O multiplicador
// de demanda e o travamento final continuam em buildQuote; o catálogo nunca é
// uma fonte de valor. A faixa específica da região sempre prevalece e, quando
// ela ainda não foi cadastrada, a referência nacional é convertida pelo índice
// regional para que um novo serviço não herde preço de outro lugar.
func (s *Server) resolveRegionalServiceBase(ctx context.Context, serviceKey string, regionID *string) (int64, bool) {
	var regionalScope any
	if regionID != nil {
		regionalScope = *regionID
	}
	if regionID != nil {
		var minC, maxC int64
		if s.Pool.QueryRow(ctx, `
			SELECT min_cents,max_cents FROM regional_service_price_bounds
			WHERE region_id=$1 AND service_key=$2 AND active`, *regionID, serviceKey).
			Scan(&minC, &maxC) == nil {
			return (minC + maxC) / 2, true
		}
	}

	var base int64
	var index float64 = 1
	err := s.Pool.QueryRow(ctx, `
		SELECT reference.national_base_cents, COALESCE(regional.cost_index, 1)
		FROM service_market_price_references reference
		LEFT JOIN region_cost_living_index regional ON regional.region_id=$2
		WHERE reference.service_key=$1`, serviceKey, regionalScope).Scan(&base, &index)
	if err != nil {
		return 0, false
	}
	return int64(math.Round(float64(base) * index)), true
}

func (s *Server) ListRegionalServiceBounds(w http.ResponseWriter, r *http.Request, regionID string) {
	rows, err := s.Pool.Query(r.Context(), `SELECT s.key,s.label,b.min_cents,b.max_cents FROM service_catalog s LEFT JOIN regional_service_price_bounds b ON b.service_key=s.key AND b.region_id=$1 WHERE s.active ORDER BY s.position,s.label`, regionID)
	if err != nil {
		writeErrCode(w, 500, "falha_listar_faixas", "falha ao listar faixas regionais")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var key, label string
		var min, max *int64
		if rows.Scan(&key, &label, &min, &max) == nil {
			out = append(out, map[string]any{"service_key": key, "label": label, "min_cents": min, "max_cents": max})
		}
	}
	writeJSON(w, 200, out)
}

func (s *Server) SaveRegionalServiceBounds(w http.ResponseWriter, r *http.Request, regionID string) {
	var req struct {
		ServiceKey string `json:"service_key"`
		MinCents   int64  `json:"min_cents"`
		MaxCents   int64  `json:"max_cents"`
	}
	if json.NewDecoder(r.Body).Decode(&req) != nil || strings.TrimSpace(req.ServiceKey) == "" || req.MinCents < 0 || req.MaxCents < req.MinCents {
		writeErrCode(w, 400, "faixa_invalida", "serviço, mínimo e máximo válidos são obrigatórios")
		return
	}
	_, err := s.Pool.Exec(r.Context(), `INSERT INTO regional_service_price_bounds(region_id,service_key,min_cents,max_cents,active) VALUES($1,$2,$3,$4,true) ON CONFLICT(region_id,service_key) DO UPDATE SET min_cents=excluded.min_cents,max_cents=excluded.max_cents,active=true,updated_at=now()`, regionID, req.ServiceKey, req.MinCents, req.MaxCents)
	if err != nil {
		writeErrCode(w, 400, "falha_salvar_faixa", "falha ao salvar faixa regional")
		return
	}
	writeJSON(w, 200, map[string]any{"saved": true})
}

// RemoveOsItem tira uma linha do orçamento. Fica restrito à OS do chamado
// informado de propósito: sem isso, conhecer o id de uma linha bastaria para
// apagá-la de uma OS que não é a sua.
func (s *Server) RemoveOsItem(w http.ResponseWriter, r *http.Request,
	ticketID, itemID string) {
	if !s.canManageTicket(r, ticketID) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	tag, err := s.Pool.Exec(r.Context(), `
		DELETE FROM service_order_items i
		USING service_orders o
		WHERE i.service_order_id = o.id AND o.ticket_id = $1 AND i.id = $2`,
		ticketID, itemID)
	if err != nil {
		writeErrCode(w, 500, "falha_remover_item", "falha ao remover a linha")
		return
	}
	if tag.RowsAffected() == 0 {
		writeErrCode(w, 404, "linha_nao_encontrada", "linha não encontrada nesta OS")
		return
	}
	s.publishTicket(r, ticketID, "service_order", map[string]any{"item_id": itemID})
	writeJSON(w, 200, map[string]any{"deleted": itemID})
}

// osItems lê as linhas de uma OS, para o snapshot e para a tela do chamado.
func (s *Server) osItems(ctx context.Context, osID string) []map[string]any {
	out := []map[string]any{}
	rows, err := s.Pool.Query(ctx, `
		SELECT id,part_id,service_id,label,unit_cents,cost_cents,quantity,
		       total_cents,note,position
		FROM service_order_items WHERE service_order_id=$1
		ORDER BY position,created_at`, osID)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, label, note string
		var part, service *string
		var unit, cost, total int64
		var quantity float64
		var position int
		if rows.Scan(&id, &part, &service, &label, &unit, &cost, &quantity,
			&total, &note, &position) != nil {
			continue
		}
		out = append(out, map[string]any{
			"id": id, "part_id": part, "service_id": service, "label": label,
			"unit_cents": unit, "cost_cents": cost, "quantity": quantity,
			"total_cents": total, "note": note, "position": position,
		})
	}
	return out
}

// serviceOrdersForSnapshot leva as OS dos chamados visíveis junto da abertura,
// com as linhas dentro.
//
// Vai separado dos chamados, e não como coluna deles, porque a consulta de
// chamados é montada pelo Authorizer: acrescentar colunas ali obrigaria a
// mexer na regra de visibilidade para carregar dado que não decide visibilidade
// nenhuma. Aqui os ids já vêm filtrados por ela.
func (s *Server) serviceOrdersForSnapshot(ctx context.Context,
	ticketIDs []string) []map[string]any {
	out := []map[string]any{}
	if len(ticketIDs) == 0 {
		return out
	}
	rows, err := s.Pool.Query(ctx, `
		SELECT id,ticket_id,status,os_type,scope_notes,instructions,manual_url,
		       quote,total_cents,scheduled_at,scheduled_location,
		       assigned_technician_id
		FROM service_orders WHERE ticket_id = ANY($1::uuid[])`, ticketIDs)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, ticketID, status, osType, scope, instructions, manual string
		var quote []byte
		var total int64
		var scheduledAt *time.Time
		var location []byte
		var assigned *string
		if rows.Scan(&id, &ticketID, &status, &osType, &scope, &instructions,
			&manual, &quote, &total, &scheduledAt, &location, &assigned) != nil {
			continue
		}
		var quoteJSON, locationJSON any
		_ = json.Unmarshal(quote, &quoteJSON)
		_ = json.Unmarshal(location, &locationJSON)
		out = append(out, map[string]any{
			"id": id, "ticket_id": ticketID, "status": status,
			"os_type": osType, "scope_notes": scope,
			"instructions": instructions, "manual_url": manual,
			"quote": quoteJSON, "total_cents": total,
			"scheduled_at": scheduledAt, "scheduled_location": locationJSON,
			"assigned_technician_id": assigned,
			"items":                  s.osItems(ctx, id),
		})
	}
	return out
}

// CloseOsQuote congela o orçamento na OS. Depois disto o número é registro: as
// linhas continuam legíveis, mas o valor que vale é o que ficou gravado aqui,
// e não o que uma nova conta daria hoje.
func (s *Server) CloseOsQuote(w http.ResponseWriter, r *http.Request, ticketID string) {
	if !s.canManageTicket(r, ticketID) {
		writeErrCode(w, 403, "permissao", "sem permissão")
		return
	}
	var osID string
	if s.Pool.QueryRow(r.Context(),
		`SELECT id FROM service_orders WHERE ticket_id=$1`,
		ticketID).Scan(&osID) != nil {
		writeErrCode(w, 404, "os_nao_encontrada", "OS não encontrada")
		return
	}
	scope, err := s.osScope(r.Context(), ticketID)
	if err != nil {
		writeErrCode(w, 404, "chamado_nao_encontrado", "chamado não encontrado")
		return
	}
	quote, err := s.buildQuote(r.Context(), osID, scope)
	if err != nil {
		writeErrCode(w, 500, "falha_orcamento", "falha ao montar o orçamento")
		return
	}
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE service_orders SET quote=$2,total_cents=$3 WHERE id=$1`,
		osID, quote, quote.TotalCents); err != nil {
		writeErrCode(w, 500, "falha_gravar_orcamento", "falha ao gravar o orçamento")
		return
	}
	s.publishTicket(r, ticketID, "service_order",
		map[string]any{"id": osID, "total_cents": quote.TotalCents})
	writeJSON(w, 200, quote)
}
