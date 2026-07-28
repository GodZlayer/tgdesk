package handlers

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

const moduleReleaseRoot = "/app/releases/modules"

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
