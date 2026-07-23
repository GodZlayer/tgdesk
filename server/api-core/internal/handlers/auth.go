package handlers

import (
	"encoding/json"
	"net/http"

	tgauth "tgdesk/api-core/internal/auth"
)

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token string `json:"token"`
	Role  string `json:"role"`
}

func (s *Server) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "corpo inválido")
		return
	}

	var id, passwordHash, role, status string
	err := s.Pool.QueryRow(r.Context(),
		`SELECT id, password_hash, role, status FROM technicians WHERE username=$1`, req.Username,
	).Scan(&id, &passwordHash, &role, &status)
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "credenciais inválidas")
		return
	}
	if status == "suspenso" {
		writeErr(w, http.StatusForbidden, "conta suspensa")
		return
	}
	if !tgauth.CheckPassword(passwordHash, req.Password) {
		writeErr(w, http.StatusUnauthorized, "credenciais inválidas")
		return
	}

	token, err := tgauth.IssueToken(s.Cfg.JWTSecret, id, req.Username, role)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao emitir token")
		return
	}
	writeJSON(w, http.StatusOK, loginResponse{Token: token, Role: role})
}
