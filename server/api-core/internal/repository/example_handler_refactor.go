// Example: How to refactor handlers to use repositories
//
// OLD PATTERN (inline queries):
// func (s *Server) GetDevice(w http.ResponseWriter, r *http.Request) {
//     var d models.Device
//     err := s.Pool.QueryRow(r.Context(),
//         `SELECT id, name FROM devices WHERE id = $1`, id).
//         Scan(&d.ID, &d.Name)
//     if err != nil {
//         writeErr(w, 500, "device not found")
//         return
//     }
//     writeJSON(w, 200, d)
// }
//
// NEW PATTERN (using repository):
// type DeviceHandler struct {
//     repos *repository.postgres.Factory
// }
//
// func (h *DeviceHandler) GetDevice(w http.ResponseWriter, r *http.Request) {
//     id := r.PathValue("id")
//     d, err := h.repos.Device.GetDevice(r.Context(), id)
//     if err != nil {
//         writeErr(w, http.StatusNotFound, "device not found")
//         return
//     }
//     writeJSON(w, http.StatusOK, d)
// }
//
// INJECTION IN SERVER SETUP:
// type Server struct {
//     Pool  *pgxpool.Pool
//     Repos *repository.postgres.Factory
// }
//
// func NewServer(pool *pgxpool.Pool) *Server {
//     return &Server{
//         Pool:  pool,
//         Repos: repository.postgres.NewFactory(pool),
//     }
// }
//
// BENEFITS:
// - Centralized data access logic
// - Easy to mock for testing
// - Simplified RBAC implementation (all checks in repository layer)
// - Decouples business logic from database details
// - Easier to refactor queries without touching handlers
package repository
