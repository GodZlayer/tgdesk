package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/repository"
)

type PostgresOrganizationRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresOrganizationRepository(pool *pgxpool.Pool) repository.OrganizationRepository {
	return &PostgresOrganizationRepository{pool: pool}
}

func (r *PostgresOrganizationRepository) GetOrganization(ctx context.Context, id string) (*models.Organization, error) {
	var org models.Organization
	query := `SELECT id, name, status, owner_technician_id, created_at FROM organizations WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&org.ID, &org.Name, &org.Status, &org.OwnerTechnicianID, &org.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("organization not found")
		}
		return nil, err
	}

	return &org, nil
}

func (r *PostgresOrganizationRepository) ListOrganizations(ctx context.Context, filter *repository.OrganizationFilter) ([]*models.Organization, error) {
	if filter == nil {
		filter = &repository.OrganizationFilter{}
	}

	query := `SELECT id, name, status, owner_technician_id, created_at FROM organizations WHERE 1=1`
	var args []any
	argIdx := 1

	if filter.Status != nil && *filter.Status != "" {
		query += fmt.Sprintf(` AND status = $%d`, argIdx)
		args = append(args, *filter.Status)
		argIdx++
	}

	if filter.OwnerID != nil && *filter.OwnerID != "" {
		query += fmt.Sprintf(` AND owner_technician_id = $%d`, argIdx)
		args = append(args, *filter.OwnerID)
		argIdx++
	}

	query += ` ORDER BY created_at`

	if filter.Limit > 0 {
		query += fmt.Sprintf(` LIMIT $%d`, argIdx)
		args = append(args, filter.Limit)
		argIdx++
	}

	if filter.Offset > 0 {
		query += fmt.Sprintf(` OFFSET $%d`, argIdx)
		args = append(args, filter.Offset)
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orgs []*models.Organization
	for rows.Next() {
		var org models.Organization
		if err := rows.Scan(&org.ID, &org.Name, &org.Status, &org.OwnerTechnicianID, &org.CreatedAt); err != nil {
			return nil, err
		}
		orgs = append(orgs, &org)
	}

	return orgs, rows.Err()
}

func (r *PostgresOrganizationRepository) ListOrganizationsByTechnician(ctx context.Context, technicianID string) ([]*models.Organization, error) {
	query := `
		SELECT DISTINCT o.id, o.name, o.status, o.owner_technician_id, o.created_at
		FROM organizations o
		LEFT JOIN networks n ON n.organization_id = o.id
		WHERE o.owner_technician_id = $1
		   OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id = $1 AND network_id IS NOT NULL)
		ORDER BY o.created_at`

	rows, err := r.pool.Query(ctx, query, technicianID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var orgs []*models.Organization
	for rows.Next() {
		var org models.Organization
		if err := rows.Scan(&org.ID, &org.Name, &org.Status, &org.OwnerTechnicianID, &org.CreatedAt); err != nil {
			return nil, err
		}
		orgs = append(orgs, &org)
	}

	return orgs, rows.Err()
}

func (r *PostgresOrganizationRepository) CreateOrganization(ctx context.Context, org *models.Organization) error {
	query := `
		INSERT INTO organizations (name)
		VALUES ($1)
		RETURNING id, name, status, created_at`

	err := r.pool.QueryRow(ctx, query, org.Name).Scan(
		&org.ID, &org.Name, &org.Status, &org.CreatedAt,
	)

	return err
}

func (r *PostgresOrganizationRepository) UpdateOrganization(ctx context.Context, org *models.Organization) error {
	query := `
		UPDATE organizations
		SET name = $1, status = $2, owner_technician_id = $3
		WHERE id = $4`

	_, err := r.pool.Exec(ctx, query, org.Name, org.Status, org.OwnerTechnicianID, org.ID)

	return err
}

func (r *PostgresOrganizationRepository) RenameOrganization(ctx context.Context, id string, name string) error {
	_, err := r.pool.Exec(ctx, `UPDATE organizations SET name = $1 WHERE id = $2`, name, id)
	return err
}

func (r *PostgresOrganizationRepository) DeleteOrganization(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM organizations WHERE id = $1`, id)
	return err
}

func (r *PostgresOrganizationRepository) GetOrganizationByName(ctx context.Context, name string) (*models.Organization, error) {
	var org models.Organization
	query := `SELECT id, name, status, owner_technician_id, created_at FROM organizations WHERE name = $1`

	err := r.pool.QueryRow(ctx, query, name).Scan(
		&org.ID, &org.Name, &org.Status, &org.OwnerTechnicianID, &org.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("organization not found")
		}
		return nil, err
	}

	return &org, nil
}
