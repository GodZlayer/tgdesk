package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"tgdesk/api-core/internal/middleware"
	"tgdesk/api-core/internal/presence"
)

const maxBrandLogoBytes = 1024 * 1024

type brandRecord struct {
	Enabled     bool
	Name        string
	LogoFile    string
	FaviconFile string
	UpdatedAt   time.Time
}

func brandingDir() string {
	if value := strings.TrimSpace(os.Getenv("BRANDING_DIR")); value != "" {
		return value
	}
	return "/branding"
}

func readBrandLogo(fileName string) []byte {
	if fileName == "" || filepath.Base(fileName) != fileName {
		return nil
	}
	data, err := os.ReadFile(filepath.Join(brandingDir(), fileName))
	if err != nil || len(data) > maxBrandLogoBytes {
		return nil
	}
	return data
}

func brandJSON(record brandRecord, includeLogo bool) map[string]any {
	result := map[string]any{
		"enabled":     record.Enabled,
		"name":        record.Name,
		"has_logo":    record.LogoFile != "",
		"has_favicon": record.FaviconFile != "",
		"updated_at":  record.UpdatedAt.UTC().Format(time.RFC3339Nano),
	}
	if includeLogo {
		if logo := readBrandLogo(record.LogoFile); len(logo) > 0 {
			result["logo_base64"] = base64.StdEncoding.EncodeToString(logo)
		}
		if favicon := readBrandLogo(record.FaviconFile); len(favicon) > 0 {
			result["favicon_base64"] = base64.StdEncoding.EncodeToString(favicon)
		}
	}
	return result
}

func (s *Server) technicianBrand(ctx context.Context, technicianID string) (brandRecord, error) {
	var record brandRecord
	err := s.Pool.QueryRow(ctx, `
		SELECT branding_enabled,brand_name,brand_logo_file,brand_favicon_file,
		       branding_updated_at
		FROM technicians WHERE id=$1`, technicianID).
		Scan(&record.Enabled, &record.Name, &record.LogoFile,
			&record.FaviconFile, &record.UpdatedAt)
	return record, err
}

func (s *Server) GetMyBranding(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	s.getBranding(w, r, claims.TechnicianID)
}

func (s *Server) GetTechnicianBranding(w http.ResponseWriter, r *http.Request, technicianID string) {
	s.getBranding(w, r, technicianID)
}

func (s *Server) getBranding(w http.ResponseWriter, r *http.Request, technicianID string) {
	record, err := s.technicianBrand(r.Context(), technicianID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	writeJSON(w, http.StatusOK, brandJSON(record, true))
}

type updateBrandingRequest struct {
	Name          string `json:"name"`
	LogoBase64    string `json:"logo_base64"`
	RemoveLogo    bool   `json:"remove_logo"`
	FaviconBase64 string `json:"favicon_base64"`
	RemoveFavicon bool   `json:"remove_favicon"`
}

func (s *Server) UpdateMyBranding(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFrom(r.Context())
	s.updateBranding(w, r, claims.TechnicianID, true)
}

func (s *Server) UpdateTechnicianBranding(w http.ResponseWriter, r *http.Request, technicianID string) {
	s.updateBranding(w, r, technicianID, false)
}

func (s *Server) updateBranding(w http.ResponseWriter, r *http.Request, technicianID string, requireEnabled bool) {
	record, err := s.technicianBrand(r.Context(), technicianID)
	if err != nil {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	if requireEnabled && !record.Enabled {
		writeErr(w, http.StatusForbidden, "personalização não habilitada pelo administrador")
		return
	}
	var req updateBrandingRequest
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 3*maxBrandLogoBytes))
	if decoder.Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "dados de personalização inválidos")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if len(req.Name) < 2 || len(req.Name) > 40 {
		writeErr(w, http.StatusBadRequest, "o nome deve possuir entre 2 e 40 caracteres")
		return
	}

	logoFile := record.LogoFile
	faviconFile := record.FaviconFile
	if req.RemoveLogo {
		logoFile = ""
	}
	if req.LogoBase64 != "" {
		logo, decodeErr := base64.StdEncoding.DecodeString(req.LogoBase64)
		if decodeErr != nil || len(logo) == 0 || len(logo) > maxBrandLogoBytes {
			writeErr(w, http.StatusBadRequest, "logo inválida ou maior que 1 MB")
			return
		}
		contentType := http.DetectContentType(logo)
		extension := map[string]string{
			"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp",
		}[contentType]
		if extension == "" {
			writeErr(w, http.StatusBadRequest, "use uma imagem PNG, JPG ou WebP")
			return
		}
		if err := os.MkdirAll(brandingDir(), 0750); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao preparar armazenamento da marca")
			return
		}
		logoFile = technicianID + extension
		target := filepath.Join(brandingDir(), logoFile)
		temp := target + ".tmp"
		if err := os.WriteFile(temp, logo, 0640); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao salvar logo")
			return
		}
		if err := os.Rename(temp, target); err != nil {
			_ = os.Remove(temp)
			writeErr(w, http.StatusInternalServerError, "falha ao concluir logo")
			return
		}
	}
	if req.RemoveFavicon {
		faviconFile = ""
	}
	if req.FaviconBase64 != "" {
		favicon, decodeErr := base64.StdEncoding.DecodeString(req.FaviconBase64)
		isICO := len(favicon) >= 6 && favicon[0] == 0 && favicon[1] == 0 &&
			favicon[2] == 1 && favicon[3] == 0
		if decodeErr != nil || !isICO || len(favicon) > maxBrandLogoBytes {
			writeErr(w, http.StatusBadRequest, "favicon inválido, use um arquivo ICO de até 1 MB")
			return
		}
		if err := os.MkdirAll(brandingDir(), 0750); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao preparar armazenamento da marca")
			return
		}
		faviconFile = technicianID + "-favicon.ico"
		target := filepath.Join(brandingDir(), faviconFile)
		temp := target + ".tmp"
		if err := os.WriteFile(temp, favicon, 0640); err != nil {
			writeErr(w, http.StatusInternalServerError, "falha ao salvar favicon")
			return
		}
		if err := os.Rename(temp, target); err != nil {
			_ = os.Remove(temp)
			writeErr(w, http.StatusInternalServerError, "falha ao concluir favicon")
			return
		}
	}
	if _, err := s.Pool.Exec(r.Context(), `
		UPDATE technicians SET brand_name=$1,brand_logo_file=$2,brand_favicon_file=$3,
			branding_updated_at=now() WHERE id=$4`,
		req.Name, logoFile, faviconFile, technicianID); err != nil {
		writeErr(w, http.StatusInternalServerError, "falha ao salvar personalização")
		return
	}
	if record.LogoFile != "" && record.LogoFile != logoFile &&
		filepath.Base(record.LogoFile) == record.LogoFile {
		_ = os.Remove(filepath.Join(brandingDir(), record.LogoFile))
	}
	if record.FaviconFile != "" && record.FaviconFile != faviconFile &&
		filepath.Base(record.FaviconFile) == record.FaviconFile {
		_ = os.Remove(filepath.Join(brandingDir(), record.FaviconFile))
	}
	record, _ = s.technicianBrand(r.Context(), technicianID)
	writeJSON(w, http.StatusOK, brandJSON(record, true))
}

type brandingEnabledRequest struct {
	Enabled bool `json:"enabled"`
}

func (s *Server) SetTechnicianBrandingEnabled(w http.ResponseWriter, r *http.Request, technicianID string) {
	var req brandingEnabledRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErr(w, http.StatusBadRequest, "estado inválido")
		return
	}
	tag, err := s.Pool.Exec(r.Context(), `
		UPDATE technicians SET branding_enabled=$1,branding_updated_at=now()
		WHERE id=$2 AND role='tecnico'`, req.Enabled, technicianID)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "técnico não encontrado")
		return
	}
	_ = presence.Publish(r.Context(), s.RDB, presence.Event{
		Type: "branding_permission", TargetID: technicianID,
		Payload: map[string]any{"enabled": req.Enabled},
	})
	writeJSON(w, http.StatusOK, map[string]any{"enabled": req.Enabled})
}

func (s *Server) deviceBranding(ctx context.Context, deviceID string) (map[string]any, string) {
	var technicianID string
	var record brandRecord
	err := s.Pool.QueryRow(ctx, `
		SELECT t.id,t.branding_enabled,t.brand_name,t.brand_logo_file,
		       t.brand_favicon_file,t.branding_updated_at
		FROM devices d
		JOIN networks n ON n.id=d.network_id
		JOIN organizations o ON o.id=n.organization_id
		JOIN technicians t ON t.id=o.owner_technician_id
		WHERE d.id=$1 AND d.role='host' AND d.state='ativo'`, deviceID).
		Scan(&technicianID, &record.Enabled, &record.Name, &record.LogoFile,
			&record.FaviconFile, &record.UpdatedAt)
	if err != nil || !record.Enabled || strings.TrimSpace(record.Name) == "" {
		return map[string]any{"enabled": false, "name": "TGDesk"}, "default"
	}
	signature := fmt.Sprintf("%s:%d", technicianID, record.UpdatedAt.UnixNano())
	return brandJSON(record, true), signature
}
