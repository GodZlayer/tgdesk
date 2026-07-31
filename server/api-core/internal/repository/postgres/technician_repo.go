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

type PostgresTechnicianRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresTechnicianRepository(pool *pgxpool.Pool) repository.TechnicianRepository {
	return &PostgresTechnicianRepository{pool: pool}
}

func (r *PostgresTechnicianRepository) GetTechnician(ctx context.Context, id string) (*models.Technician, error) {
	var t models.Technician
	query := `
		SELECT id, username, password_hash, role, created_via_env, status, created_at
		FROM technicians WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&t.ID, &t.Username, &t.PasswordHash, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("technician not found")
		}
		return nil, err
	}

	return &t, nil
}

func (r *PostgresTechnicianRepository) GetTechnicianByUsername(ctx context.Context, username string) (*models.Technician, error) {
	var t models.Technician
	query := `
		SELECT id, username, password_hash, role, created_via_env, status, created_at
		FROM technicians WHERE username = $1`

	err := r.pool.QueryRow(ctx, query, username).Scan(
		&t.ID, &t.Username, &t.PasswordHash, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("technician not found")
		}
		return nil, err
	}

	return &t, nil
}

func (r *PostgresTechnicianRepository) ListTechnicians(ctx context.Context, filter *repository.TechnicianFilter) ([]*models.Technician, error) {
	if filter == nil {
		filter = &repository.TechnicianFilter{}
	}

	query := `
		SELECT id, username, password_hash, role, created_via_env, status, created_at
		FROM technicians WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.Role != nil && *filter.Role != "" {
		query += fmt.Sprintf(` AND role = $%d`, argIdx)
		args = append(args, *filter.Role)
		argIdx++
	}

	if filter.Status != nil && *filter.Status != "" {
		query += fmt.Sprintf(` AND status = $%d`, argIdx)
		args = append(args, *filter.Status)
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

	var technicians []*models.Technician
	for rows.Next() {
		var t models.Technician
		if err := rows.Scan(&t.ID, &t.Username, &t.PasswordHash, &t.Role, &t.CreatedViaEnv, &t.Status, &t.CreatedAt); err != nil {
			return nil, err
		}
		technicians = append(technicians, &t)
	}

	return technicians, rows.Err()
}

func (r *PostgresTechnicianRepository) CreateTechnician(ctx context.Context, technician *models.Technician) error {
	query := `
		INSERT INTO technicians (username, password_hash, role, created_via_env, status)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at`

	err := r.pool.QueryRow(ctx, query,
		technician.Username, technician.PasswordHash, technician.Role, technician.CreatedViaEnv, technician.Status,
	).Scan(&technician.ID, &technician.CreatedAt)

	return err
}

func (r *PostgresTechnicianRepository) UpdateTechnician(ctx context.Context, technician *models.Technician) error {
	query := `
		UPDATE technicians
		SET username = $1, password_hash = $2, role = $3, status = $4
		WHERE id = $5`

	_, err := r.pool.Exec(ctx, query, technician.Username, technician.PasswordHash, technician.Role, technician.Status, technician.ID)

	return err
}

func (r *PostgresTechnicianRepository) DeleteTechnician(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM technicians WHERE id = $1`, id)
	return err
}

func (r *PostgresTechnicianRepository) GetTechnicianAssignments(ctx context.Context, technicianID string) ([]*models.TechnicianAssignment, error) {
	query := `
		SELECT id, technician_id, organization_id, network_id
		FROM technician_assignments WHERE technician_id = $1`

	rows, err := r.pool.Query(ctx, query, technicianID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var assignments []*models.TechnicianAssignment
	for rows.Next() {
		var ta models.TechnicianAssignment
		if err := rows.Scan(&ta.ID, &ta.TechnicianID, &ta.OrganizationID, &ta.NetworkID); err != nil {
			return nil, err
		}
		assignments = append(assignments, &ta)
	}

	return assignments, rows.Err()
}

func (r *PostgresTechnicianRepository) CreateTechnicianAssignment(ctx context.Context, assignment *models.TechnicianAssignment) error {
	query := `
		INSERT INTO technician_assignments (technician_id, organization_id, network_id)
		VALUES ($1, $2, $3)
		RETURNING id`

	err := r.pool.QueryRow(ctx, query, assignment.TechnicianID, assignment.OrganizationID, assignment.NetworkID).Scan(&assignment.ID)

	return err
}

func (r *PostgresTechnicianRepository) DeleteTechnicianAssignment(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM technician_assignments WHERE id = $1`, id)
	return err
}

func (r *PostgresTechnicianRepository) GetTechnicianAssignmentsByOrganization(ctx context.Context, orgID string) ([]*models.TechnicianAssignment, error) {
	query := `
		SELECT id, technician_id, organization_id, network_id
		FROM technician_assignments WHERE organization_id = $1`

	rows, err := r.pool.Query(ctx, query, orgID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var assignments []*models.TechnicianAssignment
	for rows.Next() {
		var ta models.TechnicianAssignment
		if err := rows.Scan(&ta.ID, &ta.TechnicianID, &ta.OrganizationID, &ta.NetworkID); err != nil {
			return nil, err
		}
		assignments = append(assignments, &ta)
	}

	return assignments, rows.Err()
}

func (r *PostgresTechnicianRepository) GetTechnicianAssignmentsByNetwork(ctx context.Context, networkID string) ([]*models.TechnicianAssignment, error) {
	query := `
		SELECT id, technician_id, organization_id, network_id
		FROM technician_assignments WHERE network_id = $1`

	rows, err := r.pool.Query(ctx, query, networkID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var assignments []*models.TechnicianAssignment
	for rows.Next() {
		var ta models.TechnicianAssignment
		if err := rows.Scan(&ta.ID, &ta.TechnicianID, &ta.OrganizationID, &ta.NetworkID); err != nil {
			return nil, err
		}
		assignments = append(assignments, &ta)
	}

	return assignments, rows.Err()
}
