package handlers

import (
	"encoding/json"
	"net/http"
	"strings"
)

// Catálogo de estilos de nome do técnico.
//
// O nome de exibição do técnico não é o username cru: é o resultado de aplicar
// uma template do catálogo em cima dele. A template é literal, com o
// placeholder {nome} substituído pelo username. Assim "nomeDesk",
// "nome - assistência" e "nomeassist" são templates, não ramos de código — o
// supervisor escolhe por técnico qual delas usar, e tudo é dado de cadastro.

func (s *Server) ListTechnicianNameStyles(w http.ResponseWriter, r *http.Request) {
	rows, err := s.Pool.Query(r.Context(),
		`SELECT key,label,template FROM technician_name_styles ORDER BY position,key`)
	if err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_listar_estilos", "falha ao listar estilos")
		return
	}
	defer rows.Close()
	styles := []map[string]any{}
	for rows.Next() {
		var key, label, template string
		if rows.Scan(&key, &label, &template) != nil {
			continue
		}
		styles = append(styles, map[string]any{
			"key": key, "label": label, "template": template,
		})
	}
	writeJSON(w, http.StatusOK, styles)
}

type nameStyleRequest struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	Template string `json:"template"`
	Position *int   `json:"position"`
	Active   *bool  `json:"active"`
}

func (s *Server) SaveTechnicianNameStyle(w http.ResponseWriter, r *http.Request) {
	var req nameStyleRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, http.StatusBadRequest, "dados_invalidos", "dados inválidos")
		return
	}
	req.Key = strings.ToLower(strings.TrimSpace(req.Key))
	req.Label = strings.TrimSpace(req.Label)
	req.Template = strings.TrimSpace(req.Template)
	if req.Key == "" || req.Label == "" {
		writeErrCode(w, http.StatusBadRequest, "chave_rotulo_obrigatorios", "chave e rótulo são obrigatórios")
		return
	}
	if !strings.Contains(req.Template, "{nome}") {
		writeErrCode(w, http.StatusBadRequest, "template_sem_placeholder",
			"a template precisa conter o placeholder {nome}")
		return
	}
	position := 100
	if req.Position != nil {
		position = *req.Position
	}
	active := true
	if req.Active != nil {
		active = *req.Active
	}
	if _, err := s.Pool.Exec(r.Context(), `
		INSERT INTO technician_name_styles(key,label,template,position,active)
		VALUES($1,$2,$3,$4,$5)
		ON CONFLICT (key) DO UPDATE SET
			label=EXCLUDED.label, template=EXCLUDED.template,
			position=EXCLUDED.position, active=EXCLUDED.active`,
		req.Key, req.Label, req.Template, position, active); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_salvar_estilo", "falha ao salvar o estilo")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"key": req.Key})
}

// DeleteTechnicianNameStyle só apaga estilo que nenhum técnico usa. Se algum
// usa, o nome dele ainda aponta para aqui — apagar reescreveria o nome exibido
// em silêncio; o certo é desativar o estilo na tela do admin.
func (s *Server) DeleteTechnicianNameStyle(w http.ResponseWriter, r *http.Request, key string) {
	var usados int
	if s.Pool.QueryRow(r.Context(),
		`SELECT count(*) FROM technicians WHERE name_style=$1`, key).Scan(&usados) != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_verificar_estilo", "falha ao verificar o estilo")
		return
	}
	if usados > 0 {
		writeErrCode(w, http.StatusConflict, "estilo_em_uso",
			"estilo em uso por técnico(s); desative em vez de excluir")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`DELETE FROM technician_name_styles WHERE key=$1`, key); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_excluir_estilo", "falha ao excluir o estilo")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": key})
}

type setTechnicianNameStyleRequest struct {
	Style string `json:"style"`
}

// SetTechnicianNameStyle grava o estilo escolhido pelo supervisor. Ao contrário
// do username (login), o estilo é cosmético e pode mudar a qualquer hora; NULL
// preserva o comportamento atual de "só o nome".
func (s *Server) SetTechnicianNameStyle(w http.ResponseWriter, r *http.Request, id string) {
	var req setTechnicianNameStyleRequest
	if json.NewDecoder(r.Body).Decode(&req) != nil {
		writeErrCode(w, http.StatusBadRequest, "dados_invalidos", "dados inválidos")
		return
	}
	req.Style = strings.TrimSpace(req.Style)
	if req.Style == "" {
		writeErrCode(w, http.StatusBadRequest, "estilo_obrigatorio", "style é obrigatório")
		return
	}
	var existe bool
	if s.Pool.QueryRow(r.Context(),
		`SELECT EXISTS(SELECT 1 FROM technician_name_styles WHERE key=$1)`, req.Style).
		Scan(&existe) != nil || !existe {
		writeErrCode(w, http.StatusBadRequest, "estilo_nao_encontrado", "estilo não encontrado")
		return
	}
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE technicians SET name_style=$1 WHERE id=$2`, req.Style, id); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_aplicar_estilo", "falha ao aplicar o estilo")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "style": req.Style})
}

// ClearTechnicianNameStyle volta o técnico ao comportamento padrão de só nome.
func (s *Server) ClearTechnicianNameStyle(w http.ResponseWriter, r *http.Request, id string) {
	if _, err := s.Pool.Exec(r.Context(),
		`UPDATE technicians SET name_style=NULL WHERE id=$1`, id); err != nil {
		writeErrCode(w, http.StatusInternalServerError, "falha_limpar_estilo", "falha ao limpar o estilo")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "style": nil})
}