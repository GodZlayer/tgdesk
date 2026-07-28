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
	mux.Handle("GET /api/v1/organizations", private(auth(http.HandlerFunc(s.ListOrganizations))))
	mux.Handle("GET /api/v1/networks", private(auth(http.HandlerFunc(s.ListNetworks))))
	mux.Handle("GET /api/v1/client/update", private(http.HandlerFunc(s.ClientUpdate)))
	mux.Handle("GET /api/v1/client/update/download", private(http.HandlerFunc(s.DownloadClientUpdate)))
	mux.Handle("GET /api/v1/client/modules", private(http.HandlerFunc(s.ClientModuleManifest)))
	mux.Handle("GET /api/v1/client/modules/{version}/{path...}", private(http.HandlerFunc(s.DownloadClientModule)))
	mux.Handle("POST /api/v1/technicians/wg-key", auth(http.HandlerFunc(s.TechnicianWGKey)))
	mux.Handle("GET /api/v1/devices/{id}/health", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.DeviceHealth(w, r, r.PathValue("id"))
	}))))
	mux.Handle("POST /api/v1/devices/{id}/wake", private(auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.WakeDevice(w, r, r.PathValue("id"))
	}))))

	// Somente Super Admin.
	mux.Handle("POST /api/v1/organizations", admin(s.CreateOrganization))
	mux.Handle("POST /api/v1/networks", admin(s.CreateNetwork))
	mux.Handle("GET /api/v1/technicians", admin(s.ListTechnicians))
	mux.Handle("POST /api/v1/technicians", admin(s.CreateTechnician))
	mux.Handle("POST /api/v1/technicians/assignments", admin(s.CreateAssignment))
	mux.Handle("POST /api/v1/technicians/{id}/enrollment-key", admin(func(w http.ResponseWriter, r *http.Request) {
		s.CreateTechnicianEnrollmentKey(w, r, r.PathValue("id"))
	}))
	mux.Handle("GET /api/v1/admin/audit", admin(s.ListAuditLog))

	mux.Handle("POST /api/v1/admin/kill/technician/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.KillTechnician(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/kill/device/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.KillDevice(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/kill/network/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.KillNetwork(w, r, r.PathValue("id"))
	}))
	mux.Handle("POST /api/v1/admin/kill/organization/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.KillOrganization(w, r, r.PathValue("id"))
	}))

	mux.Handle("DELETE /api/v1/technicians/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteTechnician(w, r, r.PathValue("id"))
	}))
	mux.Handle("DELETE /api/v1/networks/{id}", admin(func(w http.ResponseWriter, r *http.Request) {
		s.DeleteNetwork(w, r, r.PathValue("id"))
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
