package handlers

import "net/http"

func (s *Server) RegionalCostIndex(w http.ResponseWriter, r *http.Request) {
	rows, err := s.Pool.Query(r.Context(), `
		SELECT r.id,r.key,r.label,idx.uf_sigla,idx.relation_kind,
		       idx.per_capita_income_cents,idx.national_income_cents,
		       idx.income_ratio,idx.locality_factor,idx.cost_index,
		       idx.formula,idx.source_key,idx.reference_year,idx.updated_at
		FROM region_cost_living_index idx
		JOIN regions r ON r.id=idx.region_id
		ORDER BY r.position,r.label`)
	if err != nil {
		writeJSON(w, 200, []map[string]any{})
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var regionID, key, label, uf, relation, formula, source string
		var income, national int64
		var incomeRatio, locality, index float64
		var year int
		var updated any
		if rows.Scan(&regionID, &key, &label, &uf, &relation, &income, &national,
			&incomeRatio, &locality, &index, &formula, &source, &year, &updated) != nil {
			continue
		}
		out = append(out, map[string]any{
			"region_id": regionID, "region_key": key, "region_label": label,
			"uf_sigla": uf, "relation_kind": relation,
			"per_capita_income_cents": income,
			"national_income_cents":   national,
			"income_ratio":            incomeRatio, "locality_factor": locality,
			"cost_index": index, "formula": formula,
			"source_key": source, "reference_year": year,
			"updated_at": updated,
		})
	}
	writeJSON(w, 200, out)
}
