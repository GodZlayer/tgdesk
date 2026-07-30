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
	mux.HandleFunc("POST /api/v1/support/client/tickets", s.ClientOpenTicket)

	jwtAuth := middleware.RequireAuth(s.Cfg.JWTSecret)
	auth := func(h http.Handler) http.Handler {
		return jwtAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			claims := middleware.ClaimsFrom(r.Context())
			var status string
			if claims == nil || s.Pool.QueryRow(r.Context(),
				`SELECT status FROM technicians WHERE id=$1`, claims.TechnicianID).
				Scan(&status) != nil || status != "ativo" {
				writeErr(w, http.StatusUnauthorized, "sessão revogada ou suspensa")
				return
			}
			h.ServeHTTP(w, r)
		}))
	}
	private := func(h http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !requestFromVPN(r) {
				writeErr(w, http.StatusForbidden, "operação disponível somente pela VPN")
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

	// Autenticado — qualquer técnico (RBAC aplicado dentro do handler).
	mux.Handle("POST /api/v1/pairing/bind", private(auth(http.HandlerFunc(s.Bind))))
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
	mux.Handle("GET /api/v1/devices/{id}/diagnostics", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.ListDiagnostics(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.StartDiagnostic(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/diagnostics/{run_id}/cancel", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.CancelDiagnostic(w, r, r.PathValue("id"), r.PathValue("run_id"))
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
	mux.Handle("GET /api/v1/admin/audit", admin(s.ListAuditLog))
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
