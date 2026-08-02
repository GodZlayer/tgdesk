package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const moduleReleaseRoot = "/app/releases/modules"
const standaloneUpdaterPath = "/app/releases/tgdesk-updater.exe"
const publicBootstrapPath = "/app/releases/tgdesk-bootstrap.ps1"

func (s *Server) StandaloneUpdaterInfo(w http.ResponseWriter, r *http.Request) {
	f, err := os.Open(standaloneUpdaterPath)
	if err != nil {
		writeErr(w, http.StatusServiceUnavailable, "updater standalone indisponível")
		return
	}
	defer f.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, f); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao verificar updater")
		return
	}
	info, err := f.Stat()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao verificar updater")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"sha256": hex.EncodeToString(hash.Sum(nil)), "size": info.Size(),
		"url": "/api/v1/client/updater/download",
	})
}

func (s *Server) DownloadStandaloneUpdater(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/vnd.microsoft.portable-executable")
	w.Header().Set("Content-Disposition", `attachment; filename="tgdesk-updater.exe"`)
	http.ServeFile(w, r, standaloneUpdaterPath)
}

func (s *Server) DownloadPublicBootstrap(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="tgdesk-bootstrap.ps1"`)
	http.ServeFile(w, r, publicBootstrapPath)
}

func (s *Server) ClientModuleManifest(w http.ResponseWriter, r *http.Request) {
	version := os.Getenv("CLIENT_VERSION")
	if version == "" {
		writeErr(w, http.StatusServiceUnavailable, "atualização modular indisponível")
		return
	}
	if !updateAvailable(r.URL.Query().Get("version"), version) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	path := filepath.Join(moduleReleaseRoot, version, "manifest.json")
	f, err := os.Open(path)
	if err != nil {
		writeErr(w, http.StatusServiceUnavailable, "manifesto modular indisponível")
		return
	}
	defer f.Close()
	var manifest any
	if err := json.NewDecoder(f).Decode(&manifest); err != nil {
		writeErr(w, http.StatusInternalServerError, "manifesto modular inválido")
		return
	}
	writeJSON(w, http.StatusOK, manifest)
}

func (s *Server) DownloadClientModule(w http.ResponseWriter, r *http.Request) {
	version := r.PathValue("version")
	requested := strings.ReplaceAll(r.PathValue("path"), "\\", "/")
	if version == "" || requested == "" || !filepath.IsLocal(requested) ||
		strings.Contains(requested, "..") {
		writeErr(w, http.StatusBadRequest, "caminho de módulo inválido")
		return
	}
	root := filepath.Join(moduleReleaseRoot, version, "files")
	target := filepath.Join(root, filepath.FromSlash(requested))
	relative, err := filepath.Rel(root, target)
	if err != nil || strings.HasPrefix(relative, "..") {
		writeErr(w, http.StatusBadRequest, "caminho de módulo inválido")
		return
	}
	w.Header().Set("Content-Disposition", `attachment; filename="`+filepath.Base(target)+`"`)
	http.ServeFile(w, r, target)
}
