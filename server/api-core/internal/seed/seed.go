package seed

import (
	"context"
	"log"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/config"
)

// Run seeds technician accounts (TECH_USERS), their assignments (TECH_ASSIGN)
// and optional demo organizations/networks (SEED_ORGANIZATIONS) from env vars.
// It is idempotent: existing usernames are left untouched unless ForceReseed is set.
func Run(ctx context.Context, pool *pgxpool.Pool, cfg config.Config) error {
	if cfg.EnableDemoSeed && cfg.SeedOrgs != "" {
		if err := seedOrganizations(ctx, pool, cfg.SeedOrgs); err != nil {
			return err
		}
	}
	if cfg.TechUsers != "" {
		if err := seedTechUsers(ctx, pool, cfg.TechUsers, cfg.ForceReseed); err != nil {
			return err
		}
	}
	if cfg.TechAssign != "" {
		if err := seedAssignments(ctx, pool, cfg.TechAssign); err != nil {
			return err
		}
	}
	return nil
}

// SEED_ORGANIZATIONS=OrgXYZ:LojaCentro|LojaNorte;OutraOrg:Loja1
func seedOrganizations(ctx context.Context, pool *pgxpool.Pool, spec string) error {
	for _, orgSpec := range splitNonEmpty(spec, ";") {
		parts := strings.SplitN(orgSpec, ":", 2)
		orgName := strings.TrimSpace(parts[0])
		if orgName == "" {
			continue
		}
		var orgID string
		err := pool.QueryRow(ctx, `
			INSERT INTO organizations (name) VALUES ($1)
			ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
			RETURNING id`, orgName).Scan(&orgID)
		if err != nil {
			return err
		}
		log.Printf("seed: organização %q pronta (id=%s)", orgName, orgID)

		if len(parts) == 2 {
			for _, netName := range splitNonEmpty(parts[1], "|") {
				netName = strings.TrimSpace(netName)
				if netName == "" {
					continue
				}
				_, err := pool.Exec(ctx, `
					INSERT INTO networks (organization_id, name) VALUES ($1, $2)
					ON CONFLICT (organization_id, name) DO NOTHING`, orgID, netName)
				if err != nil {
					return err
				}
				log.Printf("seed: rede %q criada em %q", netName, orgName)
			}
		}
	}
	return nil
}

// TECH_USERS=joao:senhaForte123:admin,maria:outraSenha456:tecnico
func seedTechUsers(ctx context.Context, pool *pgxpool.Pool, spec string, force bool) error {
	for _, userSpec := range splitNonEmpty(spec, ",") {
		parts := strings.SplitN(userSpec, ":", 3)
		if len(parts) != 3 {
			log.Printf("seed: entrada TECH_USERS inválida, ignorando: %q", userSpec)
			continue
		}
		username := strings.TrimSpace(parts[0])
		password := parts[1]
		role := normalizeRole(strings.TrimSpace(parts[2]))

		var existingID string
		err := pool.QueryRow(ctx, `SELECT id FROM technicians WHERE username=$1`, username).Scan(&existingID)
		exists := err == nil

		if exists && !force {
			log.Printf("seed: técnico %q já existe, mantendo senha atual", username)
			continue
		}

		hash, err := auth.HashPassword(password)
		if err != nil {
			return err
		}

		if exists && force {
			_, err = pool.Exec(ctx, `UPDATE technicians SET password_hash=$1, role=$2 WHERE id=$3`, hash, role, existingID)
			log.Printf("seed: técnico %q resetado via FORCE_RESEED", username)
		} else {
			_, err = pool.Exec(ctx, `
				INSERT INTO technicians (username, password_hash, role, created_via_env)
				VALUES ($1, $2, $3, true)`, username, hash, role)
			log.Printf("seed: técnico %q criado (papel=%s)", username, role)
		}
		if err != nil {
			return err
		}
	}
	return nil
}

// TECH_ASSIGN=tecnico01:OrgXYZ,tecnico01:OrgXYZ:LojaCentro
func seedAssignments(ctx context.Context, pool *pgxpool.Pool, spec string) error {
	for _, item := range splitNonEmpty(spec, ",") {
		parts := strings.Split(strings.TrimSpace(item), ":")
		if len(parts) < 2 {
			log.Printf("seed: entrada TECH_ASSIGN inválida, ignorando: %q", item)
			continue
		}
		username := strings.TrimSpace(parts[0])
		orgName := strings.TrimSpace(parts[1])

		var techID string
		if err := pool.QueryRow(ctx, `SELECT id FROM technicians WHERE username=$1`, username).Scan(&techID); err != nil {
			log.Printf("seed: técnico %q não encontrado para atribuição, ignorando", username)
			continue
		}
		var orgID string
		if err := pool.QueryRow(ctx, `SELECT id FROM organizations WHERE name=$1`, orgName).Scan(&orgID); err != nil {
			log.Printf("seed: organização %q não encontrada para atribuição, ignorando", orgName)
			continue
		}

		if len(parts) == 3 {
			netName := strings.TrimSpace(parts[2])
			var netID string
			if err := pool.QueryRow(ctx, `SELECT id FROM networks WHERE organization_id=$1 AND name=$2`, orgID, netName).Scan(&netID); err != nil {
				log.Printf("seed: rede %q não encontrada em %q, ignorando", netName, orgName)
				continue
			}
			_, err := pool.Exec(ctx, `
				INSERT INTO technician_assignments (technician_id, network_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING`, techID, netID)
			if err != nil {
				return err
			}
			log.Printf("seed: %q atribuído à rede %q/%q", username, orgName, netName)
		} else {
			_, err := pool.Exec(ctx, `
				INSERT INTO technician_assignments (technician_id, organization_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING`, techID, orgID)
			if err != nil {
				return err
			}
			log.Printf("seed: %q atribuído à organização %q", username, orgName)
		}
	}
	return nil
}

func normalizeRole(role string) string {
	switch role {
	case "admin", "super_admin", "superadmin":
		return "super_admin"
	default:
		return "tecnico"
	}
}

func splitNonEmpty(s, sep string) []string {
	var out []string
	for _, p := range strings.Split(s, sep) {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
