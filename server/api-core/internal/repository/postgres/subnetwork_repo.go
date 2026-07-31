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

type PostgresSubnetworkRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresSubnetworkRepository(pool *pgxpool.Pool) repository.SubnetworkRepository {
	return &PostgresSubnetworkRepository{pool: pool}
}

func (r *PostgresSubnetworkRepository) GetSubnetwork(ctx context.Context, id string) (*models.Subnetwork, error) {
	var sn models.Subnetwork
	query := `
		SELECT id, network_id, name, status, created_by_technician_id, created_at
		FROM subnetworks WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("subnetwork not found")
		}
		return nil, err
	}

	return &sn, nil
}

func (r *PostgresSubnetworkRepository) ListSubnetworks(ctx context.Context, filter *repository.SubnetworkFilter) ([]*models.Subnetwork, error) {
	if filter == nil {
		filter = &repository.SubnetworkFilter{}
	}

	query := `
		SELECT id, network_id, name, status, created_by_technician_id, created_at
		FROM subnetworks WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.NetworkID != nil && *filter.NetworkID != "" {
		query += fmt.Sprintf(` AND network_id = $%d`, argIdx)
		args = append(args, *filter.NetworkID)
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

	var subnetworks []*models.Subnetwork
	for rows.Next() {
		var sn models.Subnetwork
		if err := rows.Scan(&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt); err != nil {
			return nil, err
		}
		subnetworks = append(subnetworks, &sn)
	}

	return subnetworks, rows.Err()
}

func (r *PostgresSubnetworkRepository) ListSubnetworksByNetwork(ctx context.Context, networkID string) ([]*models.Subnetwork, error) {
	return r.ListSubnetworks(ctx, &repository.SubnetworkFilter{
		NetworkID: &networkID,
	})
}

func (r *PostgresSubnetworkRepository) CreateSubnetwork(ctx context.Context, subnetwork *models.Subnetwork) error {
	query := `
		INSERT INTO subnetworks (network_id, name, status, created_by_technician_id)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`

	err := r.pool.QueryRow(ctx, query,
		subnetwork.NetworkID, subnetwork.Name, subnetwork.Status, subnetwork.CreatedBy,
	).Scan(&subnetwork.ID, &subnetwork.CreatedAt)

	return err
}

func (r *PostgresSubnetworkRepository) UpdateSubnetwork(ctx context.Context, subnetwork *models.Subnetwork) error {
	query := `
		UPDATE subnetworks
		SET name = $1, status = $2
		WHERE id = $3`

	_, err := r.pool.Exec(ctx, query, subnetwork.Name, subnetwork.Status, subnetwork.ID)

	return err
}

func (r *PostgresSubnetworkRepository) RenameSubnetwork(ctx context.Context, id string, name string) error {
	_, err := r.pool.Exec(ctx, `UPDATE subnetworks SET name = $1 WHERE id = $2`, name, id)
	return err
}

func (r *PostgresSubnetworkRepository) DeleteSubnetwork(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM subnetworks WHERE id = $1`, id)
	return err
}

func (r *PostgresSubnetworkRepository) GetSubnetworkByName(ctx context.Context, networkID string, name string) (*models.Subnetwork, error) {
	var sn models.Subnetwork
	query := `
		SELECT id, network_id, name, status, created_by_technician_id, created_at
		FROM subnetworks WHERE network_id = $1 AND name = $2`

	err := r.pool.QueryRow(ctx, query, networkID, name).Scan(
		&sn.ID, &sn.NetworkID, &sn.Name, &sn.Status, &sn.CreatedBy, &sn.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("subnetwork not found")
		}
		return nil, err
	}

	return &sn, nil
}
