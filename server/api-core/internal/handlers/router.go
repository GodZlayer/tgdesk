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

	auth := middleware.RequireAuth(s.Cfg.JWTSecret)
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
	mux.Handle("GET /api/v1/organizations", private(auth(http.HandlerFunc(s.ListOrganizations))))
	mux.Handle("GET /api/v1/networks", private(auth(http.HandlerFunc(s.ListNetworks))))
	mux.Handle("POST /api/v1/networks", private(auth(http.HandlerFunc(s.CreateNetwork))))
	mux.Handle("POST /api/v1/technicians/wg-key", auth(http.HandlerFunc(s.TechnicianWGKey)))
	mux.Handle("GET /api/v1/devices/{id}/health", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeviceHealth(w, r, r.PathValue("id"))
	}))))
	mux.Handle("GET /api/v1/devices/{id}/remote-credential", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeviceRemoteCredential(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/wake", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.WakeDevice(w, r, r.PathValue("id"))
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
	mux.Handle("GET /api/v1/technicians", admin(s.ListTechnicians))
	mux.Handle("POST /api/v1/technicians", admin(s.CreateTechnician))
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
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
