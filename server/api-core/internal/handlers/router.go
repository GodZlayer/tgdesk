package handlers

import (
	"net/http"

	"tgdesk/api-core/internal/middleware"
)

func NewRouter(s *Server) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Público — usado pelo agente recém-instalado (estado guest).
	mux.HandleFunc("POST /api/v1/auth/technician/redeem", s.RedeemTechnicianEnrollment)
	mux.HandleFunc("POST /api/v1/auth/control-key/install", s.RedeemTechnicianEnrollment)
	mux.HandleFunc("POST /api/v1/auth/control-key/validate", s.ValidateTechnicianEnrollment)
	mux.HandleFunc("POST /api/v1/auth/technician/refresh", s.RefreshTechnicianMachine)
	mux.HandleFunc("POST /api/v1/devices/register", s.RegisterDevice)
	mux.HandleFunc("POST /api/v1/devices/heartbeat", s.Heartbeat)
	mux.HandleFunc("POST /api/v1/devices/wg-key", s.WGKey)
	mux.HandleFunc("GET /ws/control/device", s.DeviceControlWS)
	mux.HandleFunc("GET /ws/control/technician", s.TechnicianControlWS)
	// Recuperação do cliente: são artefatos públicos, somente leitura e
	// verificados por SHA-256. Precisam continuar acessíveis quando a própria
	// VPN está quebrada; caso contrário o atualizador não consegue repará-la.
	mux.HandleFunc("GET /api/v1/client/update", s.ClientUpdate)
	mux.HandleFunc("GET /api/v1/client/update/download", s.DownloadClientUpdate)
	mux.HandleFunc("GET /api/v1/client/modules", s.ClientModuleManifest)
	mux.HandleFunc("GET /api/v1/client/modules/{version}/{path...}", s.DownloadClientModule)
	mux.HandleFunc("GET /api/v1/client/updater", s.StandaloneUpdaterInfo)
	mux.HandleFunc("GET /api/v1/client/updater/download", s.DownloadStandaloneUpdater)
	mux.HandleFunc("GET /api/v1/client/bootstrap.ps1", s.DownloadPublicBootstrap)
	mux.HandleFunc("GET /api/v1/client/recover.ps1", s.DownloadPublicBootstrap)
	mux.HandleFunc("POST /api/v1/support/client/tickets", s.ClientOpenTicket)
	mux.HandleFunc("POST /api/v1/support/client/tickets/open", s.ClientOpenTicketStatus)
	// Chat do cliente e consentimento de acesso remoto. Autenticados por
	// device_id + device_token no corpo, como os demais endpoints de
	// dispositivo — o cliente não tem sessão de técnico.
	mux.HandleFunc("POST /api/v1/support/client/tickets/thread", s.ClientTicketThread)
	mux.HandleFunc("POST /api/v1/support/client/tickets/remote-access", s.ClientRespondRemoteAccess)
	mux.HandleFunc("POST /api/v1/support/client/tickets/confirm-closure", s.ClientConfirmClosure)
	// O cliente nomeia o próprio computador pelo menu do TGDesk. Vive sob
	// /support/client/ porque é o prefixo que trafega pelo canal do
	// dispositivo — a credencial dele só alcança o que é dele.
	mux.HandleFunc("POST /api/v1/support/client/device-name", s.ClientRenameDevice)
	// Entrada do cliente particular. Público como os demais endpoints de
	// dispositivo (autenticado por device_id + device_token no corpo): o device
	// ainda é guest, logo não tem túnel e não pode passar por private().
	mux.HandleFunc("POST /api/v1/pairing/standalone-bind", s.StandaloneBindDevice)
	// Entrada do cliente empresarial e a busca que o instalador faz antes dela.
	// Público pelo mesmo motivo: no momento da instalação ainda não existe
	// dispositivo, logo não existe túnel para passar por private().
	mux.HandleFunc("POST /api/v1/pairing/org-intake-bind", s.OrgIntakeBindDevice)
	mux.HandleFunc("GET /api/v1/public/technicians/search", s.SearchPublicTechnicians)
	mux.HandleFunc("GET /api/v1/public/technicians/{id}/branding",
		func(w http.ResponseWriter, r *http.Request) {
			s.GetPublicTechnicianBranding(w, r, r.PathValue("id"))
		})

	jwtAuth := middleware.RequireAuth(s.Cfg.JWTSecret)
	auth := func(h http.Handler) http.Handler {
		return jwtAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := middleware.ClaimsFrom(r.Context())
			var status string
			if claims == nil || s.Pool.QueryRow(r.Context(),
				`SELECT status FROM technicians WHERE id=$1`, claims.TechnicianID).
				Scan(&status) != nil || status != "ativo" {
				writeErrCode(w, http.StatusUnauthorized, "sessao_revogada_suspensa", "sessão revogada ou suspensa")
				return
			}
			h.ServeHTTP(w, r)
		}))
	}
	private := func(h http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !requestFromVPN(r) {
				writeErrCode(w, http.StatusForbidden, "operacao_disponivel_somente_vpn", "operação disponível somente pela VPN")
				return
			}
			h.ServeHTTP(w, r)
		})
	}
	admin := func(h http.HandlerFunc) http.Handler {
		return private(auth(middleware.RequireSuperAdmin(h)))
	}
	mux.Handle("POST /api/v1/devices/rustdesk-id", private(http.HandlerFunc(s.ReportRustdeskID)))
	mux.Handle("POST /api/v1/devices/telemetry", private(http.HandlerFunc(s.ReportTelemetry)))
	mux.Handle("GET /ws/presence", private(http.HandlerFunc(s.PresenceWS)))
	// Ingresso em servidor de serviço (tier 'crm'). private() porque o pedido
	// pressupõe túnel — é o caminho cliente→hub, o único que já está aberto
	// antes de existir subrede compartilhada. Autenticado por device_id +
	// device_token no corpo, como os demais endpoints de dispositivo.
	mux.Handle("POST /api/v1/crm/join", private(http.HandlerFunc(s.CRMJoin)))
	mux.Handle("GET /api/v1/admin/crm/devices", admin(s.ListCRMDevices))
	mux.Handle("PUT /api/v1/admin/devices/{id}/crm-tier", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SetCRMTier(w, r, r.PathValue("id"))
	}))

	// Autenticado — qualquer técnico (RBAC aplicado dentro do handler).
	mux.Handle("POST /api/v1/pairing/bind", private(auth(http.HandlerFunc(s.Bind))))
	mux.Handle("POST /api/v1/pairing/self-bind", private(auth(http.HandlerFunc(s.SelfBindDevice))))
	mux.Handle("GET /api/v1/bootstrap/pairing-context", private(auth(http.HandlerFunc(s.PairingContext))))
	mux.Handle("GET /api/v1/devices", private(auth(http.HandlerFunc(s.ListDevices))))
	mux.Handle("PATCH /api/v1/devices/{id}/display-name", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.UpdateDeviceDisplayName(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/control-machine", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ClaimControlMachine(w, r, r.PathValue("id"))
	}))))
	mux.Handle("PUT /api/v1/devices/{id}/networks", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.UpdateDeviceNetworks(w, r, r.PathValue("id"))
	}))))
	mux.Handle("PUT /api/v1/devices/{id}/subnetwork", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.UpdateDeviceSubnetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/organizations", private(auth(http.HandlerFunc(s.ListOrganizations))))
	// Uma organização pode ter vários supervisores: o dono gera um código e o
	// outro resgata, passando a enxergar a mesma fila de chamados.
	mux.Handle("POST /api/v1/organizations/{id}/supervisor-invite", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.CreateSupervisorInvite(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/organizations/{id}/supervisors", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ListOrganizationSupervisors(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/organizations/supervisor-invite/redeem", private(auth(http.HandlerFunc(s.RedeemSupervisorInvite))))
	mux.Handle("GET /api/v1/networks", private(auth(http.HandlerFunc(s.ListNetworks))))
	mux.Handle("POST /api/v1/networks", private(auth(http.HandlerFunc(s.CreateNetwork))))
	mux.Handle("GET /api/v1/subnetworks", private(auth(http.HandlerFunc(s.ListSubnetworks))))
	mux.Handle("POST /api/v1/subnetworks", private(auth(http.HandlerFunc(s.CreateSubnetwork))))
	mux.Handle("PUT /api/v1/subnetworks/{id}", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RenameSubnetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/subnetworks/{id}/suspend", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.SuspendSubnetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/subnetworks/{id}/resume", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeSubnetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("DELETE /api/v1/subnetworks/{id}", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteSubnetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("PUT /api/v1/networks/{id}", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RenameNetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/technicians/wg-key", auth(http.HandlerFunc(s.TechnicianWGKey)))
	// auth sem private, como o wg-key acima e pelo mesmo motivo: a máquina do
	// técnico chama isto ANTES de ter rede privada — é justamente esta chamada
	// que a coloca numa rede e lhe dá direito a um IP. Exigir a VPN aqui seria
	// exigir o resultado como pré-requisito de si mesmo.
	mux.Handle("POST /api/v1/pairing/technician-self-bind",
		auth(http.HandlerFunc(s.TechnicianSelfBindDevice)))
	mux.Handle("GET /api/v1/branding/me", private(auth(http.HandlerFunc(s.GetMyBranding))))
	mux.Handle("PUT /api/v1/branding/me", private(auth(http.HandlerFunc(s.UpdateMyBranding))))
	mux.Handle("GET /api/v1/devices/{id}/health", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeviceHealth(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/devices/{id}/remote-credential", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeviceRemoteCredential(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/wake", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.WakeDevice(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/diagnostics/catalog", private(auth(http.HandlerFunc(s.DiagnosticCatalog))))
	mux.Handle("GET /api/v1/support/tickets", private(auth(http.HandlerFunc(s.ListTickets))))
	mux.Handle("POST /api/v1/support/tickets/{id}/messages", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.AddTicketMessage(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/remote-access", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RequestRemoteAccess(w, r, r.PathValue("id"))
	}))))
	// Etapas de execução da OS e fechamento por confirmação de cada parte.
	mux.Handle("POST /api/v1/support/tickets/{id}/os/start", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.StartServiceOrder(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/os/step", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RecordServiceOrderStep(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/os/finish", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.FinishServiceOrder(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/confirm-closure", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ConfirmClosure(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/transition", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.TransitionTicket(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/service-order", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ConvertServiceOrder(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/support/tickets/{id}/audit", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.TicketAudit(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/dispatch", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DispatchTicket(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/support/freelancer/queue", private(auth(http.HandlerFunc(s.FreelancerQueue))))
	mux.Handle("POST /api/v1/support/tickets/{id}/accept", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.AcceptDispatch(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/support/tickets/{id}/permission", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.TicketPermission(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/evidence", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.AddOnsiteEvidence(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/support/tickets/{id}/export", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ExportServiceOrder(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/accept-supervisor", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.AcceptSupervisorOffer(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/support/supervisor/queue", private(auth(http.HandlerFunc(s.SupervisorQueue))))
	mux.Handle("GET /api/v1/support/freelancer/me", private(auth(http.HandlerFunc(s.MyFreelancerProfile))))
	mux.Handle("PUT /api/v1/support/freelancer/me/availability", private(auth(http.HandlerFunc(s.SetFreelancerAvailability))))
	mux.Handle("POST /api/v1/support/tickets", private(auth(http.HandlerFunc(s.SupervisorOpenTicket))))
	mux.Handle("POST /api/v1/support/tickets/{id}/rate", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RateTicket(w, r, r.PathValue("id"))
	}))))
	// Catálogo de tipos de chamado. A leitura é de qualquer autenticado —
	// quem abre chamado precisa do esquema para montar o formulário; a
	// edição é só do admin.
	mux.Handle("GET /api/v1/support/ticket-types", private(auth(http.HandlerFunc(s.TicketCatalog))))
	mux.Handle("POST /api/v1/admin/ticket-types", admin(s.SaveTicketType))
	mux.Handle("DELETE /api/v1/admin/ticket-types/{key}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteTicketType(w, r, r.PathValue("key"))
	}))
	mux.Handle("POST /api/v1/admin/ticket-type-fields", admin(s.SaveTicketTypeField))
	mux.Handle("DELETE /api/v1/admin/ticket-type-fields/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteTicketTypeField(w, r, r.PathValue("id"))
	}))

	// Precificação: percentual por classe, taxa do admin, promoção, vigência
	// e os limites entre os quais o valor dinâmico varia.
	mux.Handle("GET /api/v1/admin/pricing-rules", admin(s.ListPricingRules))
	mux.Handle("POST /api/v1/admin/pricing-rules", admin(s.SavePricingRule))
	mux.Handle("DELETE /api/v1/admin/pricing-rules/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeletePricingRule(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/admin/regions/{id}/service-price-bounds", admin(func(w http.ResponseWriter, r *http.Request) { s.ListRegionalServiceBounds(w, r, r.PathValue("id")) }))
	mux.Handle("POST /api/v1/admin/regions/{id}/service-price-bounds", admin(func(w http.ResponseWriter, r *http.Request) { s.SaveRegionalServiceBounds(w, r, r.PathValue("id")) }))

	// Localidade. A leitura é de qualquer autenticado — as telas mostram a
	// região de técnico, dispositivo e chamado — e o cadastro é do admin,
	// porque é ele quem decide onde o produto opera.
	mux.Handle("GET /api/v1/support/regions", private(auth(http.HandlerFunc(s.Regions))))
	mux.Handle("POST /api/v1/admin/regions", admin(s.SaveRegion))
	mux.Handle("DELETE /api/v1/admin/regions/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteRegion(w, r, r.PathValue("id"))
	}))
	// Pôr uma empresa, uma máquina ou um técnico numa região. O técnico que
	// informou coordenada já entra na certa sozinho; isto é para o resto.
	mux.Handle("POST /api/v1/admin/regions/assign", admin(s.AssignRegion))

	// Construtor de OS. O catálogo de peças e serviços é lido por qualquer
	// autenticado — é o que o técnico escolhe ao montar o orçamento — e
	// cadastrado só pelo admin, como o resto do que define dinheiro.
	mux.Handle("GET /api/v1/support/os-catalog", private(auth(http.HandlerFunc(s.OsCatalog))))
	mux.Handle("POST /api/v1/admin/parts", admin(s.SavePart))
	mux.Handle("DELETE /api/v1/admin/parts/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeletePart(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/services", admin(s.SaveService))
	mux.Handle("DELETE /api/v1/admin/services/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteService(w, r, r.PathValue("id"))
	}))

	// As linhas do orçamento e o valor que sai delas. A permissão é a mesma
	// que governa o chamado: quem pode conduzi-lo pode orçá-lo.
	mux.Handle("GET /api/v1/support/tickets/{id}/quote", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.OsQuote(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/quote/close", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.CloseOsQuote(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/support/tickets/{id}/os-items", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.AddOsItem(w, r, r.PathValue("id"))
	}))))
	mux.Handle("DELETE /api/v1/support/tickets/{id}/os-items/{itemId}", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.RemoveOsItem(w, r, r.PathValue("id"), r.PathValue("itemId"))
	}))))

	mux.Handle("GET /api/v1/devices/{id}/diagnostics", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ListDiagnostics(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.StartDiagnostic(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics/{run_id}/cancel", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.CancelDiagnostic(w, r, r.PathValue("id"), r.PathValue("run_id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics/{run_id}/pause", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.PauseDiagnostic(w, r, r.PathValue("id"), r.PathValue("run_id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics/{run_id}/resume", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeDiagnostic(w, r, r.PathValue("id"), r.PathValue("run_id"))
	}))))
	mux.Handle("POST /api/v1/networks/{id}/suspend", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.SuspendNetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/networks/{id}/resume", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeNetwork(w, r, r.PathValue("id"))
	}))))
	mux.Handle("DELETE /api/v1/networks/{id}", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteNetwork(w, r, r.PathValue("id"))
	}))))

	// Somente Super Admin.
	mux.Handle("POST /api/v1/organizations", admin(s.CreateOrganization))
	mux.Handle("PUT /api/v1/organizations/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.RenameOrganization(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/technicians", admin(s.ListTechnicians))
	mux.Handle("POST /api/v1/technicians", admin(s.CreateTechnician))
	mux.Handle("GET /api/v1/technicians/name-styles", admin(s.ListTechnicianNameStyles))
	mux.Handle("POST /api/v1/technicians/name-styles", admin(s.SaveTechnicianNameStyle))
	// Sob /admin/technicians/, e não /technicians/, porque
	// "DELETE /api/v1/technicians/{id}/name-style" colide com
	// "DELETE /api/v1/technicians/assignments/{id}", que já existia: para o
	// roteador, "assignments" casa com {id} e "name-style" casa com o {id} do
	// outro padrão, e nenhum dos dois é mais específico.
	//
	// Quem cedeu foi o name-style, por ser o novo: assignments é contrato que
	// os clientes instalados já chamam.
	mux.Handle("PUT /api/v1/admin/technicians/{id}/name-style", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SetTechnicianNameStyle(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/admin/technicians/{id}/name-style", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ClearTechnicianNameStyle(w, r, r.PathValue("id"))
	}))
	// Apagar um estilo do catálogo mora sob /admin/, e não sob /technicians/,
	// porque lá ela colidia: para o roteador do Go, "name-styles" também casa
	// com o {id} de DELETE /api/v1/technicians/{id}/name-style, e os dois
	// padrões têm a mesma forma — um segmento variável seguido de um fixo.
	// Padrões ambíguos não são erro de requisição, são pânico no registro: o
	// servidor inteiro não sobe.
	//
	// O endereço novo também é o dos outros catálogos — ticket-types, parts,
	// services, regions —, que é onde ele deveria estar desde o início.
	mux.Handle("DELETE /api/v1/admin/name-styles/{key}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteTechnicianNameStyle(w, r, r.PathValue("key"))
	}))
	mux.Handle("POST /api/v1/admin/freelancers", admin(s.CreateFreelancer))
	mux.Handle("PUT /api/v1/technicians/{id}/branding-enabled", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SetTechnicianBrandingEnabled(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/technicians/{id}/branding", admin(func(w http.ResponseWriter, r *http.Request) {
		s.GetTechnicianBranding(w, r, r.PathValue("id"))
	}))
	mux.Handle("PUT /api/v1/technicians/{id}/branding", admin(func(w http.ResponseWriter, r *http.Request) {
		s.UpdateTechnicianBranding(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/technicians/assignments", admin(s.ListTechnicianAssignments))
	mux.Handle("POST /api/v1/technicians/assignments", admin(s.CreateAssignment))
	mux.Handle("DELETE /api/v1/technicians/assignments/{id}", admin(s.DeleteTechnicianAssignment))
	mux.Handle("POST /api/v1/technicians/{id}/enrollment-key", admin(func(w http.ResponseWriter, r *http.Request) {
		s.CreateTechnicianEnrollmentKey(w, r, r.PathValue("id"))
	}))
	// Cotas: quanto cada organização pode usar do que será cobrado. Só o admin
	// lê e escreve — é decisão do dono do produto, como os percentuais.
	mux.Handle("GET /api/v1/admin/quotas", admin(s.ListQuotas))
	mux.Handle("POST /api/v1/admin/quotas", admin(s.SaveQuota))
	mux.Handle("POST /api/v1/admin/product-defaults", admin(s.SaveProductDefaults))
	mux.Handle("GET /api/v1/admin/config-descriptors", admin(s.AdminConfigDescriptors))
	mux.Handle("GET /api/v1/admin/linked-map", admin(s.LinkedMap))
	mux.Handle("GET /api/v1/admin/payment-rules", admin(s.PaymentRules))
	mux.Handle("POST /api/v1/admin/payment-rules", admin(s.SavePaymentRules))
	mux.Handle("GET /api/v1/admin/regional-cost-index", admin(s.RegionalCostIndex))
	mux.Handle("GET /api/v1/admin/territory/municipalities", admin(s.SearchBrazilMunicipalities))
	mux.Handle("GET /api/v1/admin/regions/{id}/municipalities", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ListRegionMunicipalities(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/regions/{id}/municipalities", admin(func(w http.ResponseWriter, r *http.Request) {
		s.AddRegionMunicipality(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/admin/regions/{id}/municipalities", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteRegionMunicipality(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/admin/regions/{id}/coverage-addresses", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ListRegionCoverageAddresses(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/regions/{id}/coverage-addresses", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SaveRegionCoverageAddress(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/admin/regions/{id}/coverage-addresses/{addressId}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteRegionCoverageAddress(w, r, r.PathValue("addressId"))
	}))

	mux.Handle("GET /api/v1/admin/audit", admin(s.ListAuditLog))
	mux.Handle("GET /api/v1/admin/audit/live-report", admin(s.AuditLiveReport))
	mux.Handle("GET /api/v1/admin/slideshow/templates", admin(s.AdminSlideTemplates))
	mux.Handle("GET /api/v1/admin/slideshow/export.pdf", admin(s.ExportAdminSlideshowPDF))
	mux.Handle("GET /api/v1/admin/audit/domains/{domain}/events", admin(func(w http.ResponseWriter, r *http.Request) {
		s.AuditDomainEvents(w, r, r.PathValue("domain"))
	}))
	mux.Handle("GET /api/v1/admin/audit/events/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.AuditEventDetail(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/admin/guest-devices/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteGuestDevice(w, r, r.PathValue("id"))
	}))

	mux.Handle("POST /api/v1/admin/suspend/technician/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SuspendTechnician(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/suspend/device/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SuspendDevice(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/suspend/organization/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.SuspendOrganization(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/resume/device/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeDevice(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/resume/technician/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeTechnician(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/resume/organization/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.ResumeOrganization(w, r, r.PathValue("id"))
	}))

	mux.Handle("DELETE /api/v1/technicians/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteTechnician(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/organizations/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteOrganization(w, r, r.PathValue("id"))
	}))

	return withCORS(mux)
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
