package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/config"
	"tgdesk/api-core/internal/wg"
)

type Server struct {
	Pool       *pgxpool.Pool
	RDB        *redis.Client
	Cfg        config.Config
	Hub        *wg.Hub
	Authorizer *auth.Authorizer
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// writeErrCode acompanha a mensagem de um código estável. A frase serve ao
// desktop em português; o código é o que um cliente em outro idioma — ou
// outro tratamento de erro — tem como reconhecer sem ler texto.
func writeErrCode(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]string{"error": msg, "code": code})
}

