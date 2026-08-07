package handlers

import "net/http"

func (s *Server) LinkedMap(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	orgs := []map[string]any{}
	nets := []map[string]any{}
	subs := []map[string]any{}
	devices := []map[string]any{}
	techs := []map[string]any{}
	links := []map[string]any{}

	if rows, err := s.Pool.Query(ctx, `
		SELECT o.id,o.name,o.status,o.owner_technician_id,o.region_id,o.municipality_id,
		       count(DISTINCT n.id), count(DISTINCT d.id), count(DISTINCT ta.technician_id)
		FROM organizations o
		LEFT JOIN networks n ON n.organization_id=o.id
		LEFT JOIN devices d ON d.network_id=n.id
		LEFT JOIN technician_assignments ta ON ta.organization_id=o.id OR ta.network_id=n.id
		GROUP BY o.id,o.name,o.status,o.owner_technician_id,o.region_id,o.municipality_id
		ORDER BY o.name`); err == nil {
		defer rows.Close()
		for rows.Next() {
			row := map[string]any{}
			if rows.Scan(field(&row, "id"), field(&row, "name"), field(&row, "status"),
				field(&row, "owner_technician_id"), field(&row, "region_id"), field(&row, "municipality_id"),
				field(&row, "networks_count"), field(&row, "devices_count"), field(&row, "technicians_count")) == nil {
				row["kind"] = "organization"
				orgs = append(orgs, row)
			}
		}
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT id,organization_id,name,status,system_key,peer_isolation,created_at
		FROM networks ORDER BY name`); err == nil {
		defer rows.Close()
		for rows.Next() {
			row := map[string]any{}
			if rows.Scan(field(&row, "id"), field(&row, "organization_id"), field(&row, "name"),
				field(&row, "status"), field(&row, "system_key"), field(&row, "peer_isolation"),
				field(&row, "created_at")) == nil {
				row["kind"] = "network"
				nets = append(nets, row)
				links = append(links, map[string]any{"from_kind": "organization", "from_id": row["organization_id"], "to_kind": "network", "to_id": row["id"], "relation": "owns"})
			}
		}
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT id,network_id,name,status,created_at FROM subnetworks ORDER BY name`); err == nil {
		defer rows.Close()
		for rows.Next() {
			row := map[string]any{}
			if rows.Scan(field(&row, "id"), field(&row, "network_id"), field(&row, "name"),
				field(&row, "status"), field(&row, "created_at")) == nil {
				row["kind"] = "subnetwork"
				subs = append(subs, row)
				links = append(links, map[string]any{"from_kind": "network", "from_id": row["network_id"], "to_kind": "subnetwork", "to_id": row["id"], "relation": "contains"})
			}
		}
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT d.id,d.network_id,d.subnetwork_id,d.hostname,coalesce(d.display_name,''),d.role,d.state,
		       d.control_technician_id,d.region_id,d.municipality_id,d.last_seen_at,d.created_at,coalesce(d.rustdesk_id,'')
		FROM devices d ORDER BY d.created_at DESC`); err == nil {
		defer rows.Close()
		for rows.Next() {
			row := map[string]any{}
			if rows.Scan(field(&row, "id"), field(&row, "network_id"), field(&row, "subnetwork_id"),
				field(&row, "hostname"), field(&row, "display_name"), field(&row, "role"), field(&row, "state"),
				field(&row, "control_technician_id"), field(&row, "region_id"), field(&row, "municipality_id"),
				field(&row, "last_seen_at"), field(&row, "created_at"), field(&row, "rustdesk_id")) == nil {
				row["kind"] = "device"
				devices = append(devices, row)
				links = append(links, map[string]any{"from_kind": "network", "from_id": row["network_id"], "to_kind": "device", "to_id": row["id"], "relation": "has_device"})
				if row["subnetwork_id"] != nil {
					links = append(links, map[string]any{"from_kind": "subnetwork", "from_id": row["subnetwork_id"], "to_kind": "device", "to_id": row["id"], "relation": "subnetwork_device"})
				}
				if row["control_technician_id"] != nil {
					links = append(links, map[string]any{"from_kind": "technician", "from_id": row["control_technician_id"], "to_kind": "device", "to_id": row["id"], "relation": "control_machine"})
				}
			}
		}
	}

	if rows, err := s.Pool.Query(ctx, `
		SELECT t.id,t.username,t.role,t.status,t.created_at,
		       fp.supervisor_id,fp.organization_id,fp.availability,fp.quality_score,fp.region_id,
		       sp.rating_avg,sp.rating_count
		FROM technicians t
		LEFT JOIN freelancer_profiles fp ON fp.technician_id=t.id
		LEFT JOIN supervisor_profiles sp ON sp.technician_id=t.id
		ORDER BY t.username`); err == nil {
		defer rows.Close()
		for rows.Next() {
			row := map[string]any{}
			if rows.Scan(field(&row, "id"), field(&row, "username"), field(&row, "role"), field(&row, "status"),
				field(&row, "created_at"), field(&row, "supervisor_id"), field(&row, "organization_id"),
				field(&row, "availability"), field(&row, "quality_score"), field(&row, "region_id"),
				field(&row, "rating_avg"), field(&row, "rating_count")) == nil {
				row["kind"] = "technician"
				techs = append(techs, row)
				if row["organization_id"] != nil {
					links = append(links, map[string]any{"from_kind": "organization", "from_id": row["organization_id"], "to_kind": "technician", "to_id": row["id"], "relation": "employs"})
				}
				if row["supervisor_id"] != nil {
					links = append(links, map[string]any{"from_kind": "technician", "from_id": row["supervisor_id"], "to_kind": "technician", "to_id": row["id"], "relation": "supervises"})
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"summary": map[string]any{
			"organizations": len(orgs), "networks": len(nets), "subnetworks": len(subs),
			"devices": len(devices), "technicians": len(techs), "links": len(links),
		},
		"organizations": orgs,
		"networks":      nets,
		"subnetworks":   subs,
		"devices":       devices,
		"technicians":   techs,
		"links":         links,
	})
}
