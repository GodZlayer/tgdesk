package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net/http"
	"os"
)

const clientUpdatePackagePath = "/app/releases/tgdesk-update.exe"

func (s *Server) ClientUpdate(w http.ResponseWriter, r *http.Request) {
	version := os.Getenv("CLIENT_VERSION")
	if version == "" {
		http.Error(w, "atualizacao indisponivel", http.StatusServiceUnavailable)
		return
	}
	if !updateAvailable(r.URL.Query().Get("version"), version) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	f, err := os.Open(clientUpdatePackagePath)
	if err != nil {
		http.Error(w, "atualizacao indisponivel", http.StatusServiceUnavailable)
		return
	}
	defer f.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, f); err != nil {
		http.Error(w, "falha ao verificar atualizacao", http.StatusInternalServerError)
		return
	}
	info, err := f.Stat()
	if err != nil {
		http.Error(w, "falha ao verificar atualizacao", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"version": version,
		"sha256":  hex.EncodeToString(hash.Sum(nil)),
		"size":    info.Size(),
		"url":     "/api/v1/client/update/download",
	})
}

func (s *Server) DownloadClientUpdate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/vnd.microsoft.portable-executable")
	w.Header().Set("Content-Disposition", `attachment; filename="tgdesk-update.exe"`)
	http.ServeFile(w, r, clientUpdatePackagePath)
}
