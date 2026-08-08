package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
)

func (s *Server) SearchBrazilMunicipalities(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	uf := strings.ToUpper(strings.TrimSpace(r.URL.Query().Get("uf")))
	limit := 80
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 && parsed <= 300 {
			limit = parsed
		}
	}
	where := "WHERE true"
	args := []any{}
	if query != "" {
		args = append(args, "%"+query+"%")
		where += " AND (name ILIKE $" + strconv.Itoa(len(args)) +
			" OR immediate_region_name ILIKE $" + strconv.Itoa(len(args)) +
			" OR intermediate_region_name ILIKE $" + strconv.Itoa(len(args)) + ")"
	}
	if uf != "" {
		args = append(args, uf)
		where += " AND uf_sigla=$" + strconv.Itoa(len(args))
	}
	args = append(args, limit)
	rows, err := s.Pool.Query(r.Context(), `
		SELECT ibge_id,name,uf_sigla,uf_name,macroregion_name,
		       immediate_region_id,immediate_region_name,
		       intermediate_region_id,intermediate_region_name,
		       microregion_name,mesoregion_name
		FROM brazil_municipalities `+where+`
		ORDER BY uf_sigla,name LIMIT $`+strconv.Itoa(len(args)), args...)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_buscar_municipios", "falha ao buscar municípios")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var item struct {
			ID                      int
			Name, UF, UFName, Macro string
			ImmediateID             int
			ImmediateName           string
			IntermediateID          int
			IntermediateName        string
			MicroName, MesoName     string
		}
		if rows.Scan(&item.ID, &item.Name, &item.UF, &item.UFName, &item.Macro,
			&item.ImmediateID, &item.ImmediateName, &item.IntermediateID,
			&item.IntermediateName, &item.MicroName, &item.MesoName) == nil {
			out = append(out, map[string]any{
				"ibge_id":                  item.ID,
				"name":                     item.Name,
				"uf_sigla":                 item.UF,
				"uf_name":                  item.UFName,
				"country":                  "Brasil",
				"macroregion_name":         item.Macro,
				"immediate_region_id":      item.ImmediateID,
				"immediate_region_name":    item.ImmediateName,
				"intermediate_region_id":   item.IntermediateID,
				"intermediate_region_name": item.IntermediateName,
				"microregion_name":         item.MicroName,
				"mesoregion_name":          item.MesoName,
			})
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) ListRegionMunicipalities(w http.ResponseWriter, r *http.Request, regionID string) {
	rows, err := s.Pool.Query(r.Context(), `
		SELECT m.ibge_id,m.name,m.uf_sigla,m.immediate_region_name,
		       m.intermediate_region_name,rm.relation_kind
		FROM region_municipalities rm
		JOIN brazil_municipalities m ON m.ibge_id=rm.municipality_id
		WHERE rm.region_id=$1
		ORDER BY m.uf_sigla,m.name,rm.relation_kind`, regionID)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_municipios_regiao", "falha ao listar municípios da região")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id int
		var name, uf, immediate, intermediate, kind string
		if rows.Scan(&id, &name, &uf, &immediate, &intermediate, &kind) == nil {
			out = append(out, map[string]any{
				"ibge_id": id, "name": name, "uf_sigla": uf,
				"immediate_region_name":    immediate,
				"intermediate_region_name": intermediate,
				"relation_kind":            kind,
			})
		}
	}
	writeJSON(w, http.StatusOK, out)
}

type regionMunicipalityRequest struct {
	MunicipalityID int    `json:"municipality_id"`
	RelationKind   string `json:"relation_kind"`
}

func (s *Server) AddRegionMunicipality(w http.ResponseWriter, r *http.Request, regionID string) {
	var req regionMunicipalityRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil || req.MunicipalityID == 0 {
		writeErrCode(w, http.StatusBadRequest, "municipio_obrigatorio", "município obrigatório")
		return
	}
	if strings.TrimSpace(req.RelationKind) == "" {
		req.RelationKind = "commercial"
	}
	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO region_municipalities(region_id,municipality_id,relation_kind)
		VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,
		regionID, req.MunicipalityID, req.RelationKind); err != nil {
		writeErrCode(w, http.StatusBadRequest, "falha_vincular_municipio", "falha ao vincular município")
		return
	}
	s.publishRegions(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{"saved": true})
}

func (s *Server) DeleteRegionMunicipality(w http.ResponseWriter, r *http.Request, regionID string) {
	municipalityID, _ := strconv.Atoi(r.URL.Query().Get("municipality_id"))
	kind := strings.TrimSpace(r.URL.Query().Get("relation_kind"))
	if municipalityID == 0 {
		writeErrCode(w, http.StatusBadRequest, "municipio_obrigatorio", "município obrigatório")
		return
	}
	if kind == "" {
		kind = "commercial"
	}
	_, _ = s.Pool.Exec(r.Context(), `
		DELETE FROM region_municipalities
		WHERE region_id=$1 AND municipality_id=$2 AND relation_kind=$3`,
		regionID, municipalityID, kind)
	s.publishRegions(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true})
}

func (s *Server) ListRegionCoverageAddresses(w http.ResponseWriter, r *http.Request, regionID string) {
	rows, err := s.Pool.Query(r.Context(), `
		SELECT a.id,a.country_code,a.state_code,a.municipality_id,m.name,
		       a.neighborhood,a.street,a.cep,a.active
		FROM region_coverage_addresses a
		JOIN brazil_municipalities m ON m.ibge_id=a.municipality_id
		WHERE a.region_id=$1
		ORDER BY a.state_code,m.name,a.neighborhood,a.street`, regionID)
	if err != nil {
		writeErrCode(w, 500, "falha_listar_enderecos", "falha ao listar endereços de cobertura")
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, country, state, name, neighborhood, street, cep string
		var municipalityID int
		var active bool
		if rows.Scan(&id, &country, &state, &municipalityID, &name, &neighborhood, &street, &cep, &active) == nil {
			out = append(out, map[string]any{"id": id, "country_code": country, "state_code": state,
				"municipality_id": municipalityID, "municipality_name": name, "neighborhood": neighborhood,
				"street": street, "cep": cep, "active": active})
		}
	}
	writeJSON(w, 200, out)
}

type regionCoverageAddressRequest struct {
	CountryCode    string `json:"country_code"`
	StateCode      string `json:"state_code"`
	MunicipalityID int    `json:"municipality_id"`
	Neighborhood   string `json:"neighborhood"`
	Street         string `json:"street"`
	CEP            string `json:"cep"`
	Active         *bool  `json:"active"`
}

func (s *Server) SaveRegionCoverageAddress(w http.ResponseWriter, r *http.Request, regionID string) {
	var req regionCoverageAddressRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, 400, "dados_invalidos", "dados inválidos")
		return
	}
	req.CountryCode = strings.ToUpper(strings.TrimSpace(req.CountryCode))
	if req.CountryCode == "" {
		req.CountryCode = "BR"
	}
	req.StateCode = strings.ToUpper(strings.TrimSpace(req.StateCode))
	req.Neighborhood, req.Street = strings.TrimSpace(req.Neighborhood), strings.TrimSpace(req.Street)
	req.CEP = strings.ReplaceAll(strings.TrimSpace(req.CEP), " ", "")
	if req.StateCode == "" || req.MunicipalityID == 0 || req.Neighborhood == "" || req.Street == "" || len(strings.ReplaceAll(req.CEP, "-", "")) != 8 {
		writeErrCode(w, 400, "endereco_incompleto", "estado, cidade, bairro, rua e CEP são obrigatórios")
		return
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	var id string
	err := s.Pool.QueryRow(r.Context(), `
		INSERT INTO region_coverage_addresses(region_id,country_code,state_code,municipality_id,neighborhood,street,cep,active)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8)
		ON CONFLICT(region_id,municipality_id,neighborhood,street,cep)
		DO UPDATE SET state_code=excluded.state_code,country_code=excluded.country_code,active=excluded.active,updated_at=now()
		RETURNING id`, regionID, req.CountryCode, req.StateCode, req.MunicipalityID,
		req.Neighborhood, req.Street, req.CEP, active).Scan(&id)
	if err != nil {
		writeErrCode(w, 400, "falha_salvar_endereco", "falha ao salvar endereço de cobertura")
		return
	}
	writeJSON(w, 200, map[string]any{"id": id})
}

func (s *Server) DeleteRegionCoverageAddress(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(), `DELETE FROM region_coverage_addresses WHERE id=$1`, id); err != nil {
		writeErrCode(w, 400, "falha_apagar_endereco", "falha ao apagar endereço de cobertura")
		return
	}
	writeJSON(w, 200, map[string]any{"deleted": id})
}
