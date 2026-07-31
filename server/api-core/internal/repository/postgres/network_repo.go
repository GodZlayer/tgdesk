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

type PostgresNetworkRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresNetworkRepository(pool *pgxpool.Pool) repository.NetworkRepository {
	return &PostgresNetworkRepository{pool: pool}
}

func (r *PostgresNetworkRepository) GetNetwork(ctx context.Context, id string) (*models.Network, error) {
	var net models.Network
	query := `
		SELECT id, organization_id, name, cidr_virtual, status, created_by_technician_id, created_at
		FROM networks WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&net.ID, &net.OrganizationID, &net.Name, &net.CIDRVirtual, &net.Status, &net.CreatedBy, &net.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("network not found")
		}
		return nil, err
	}

	return &net, nil
}

func (r *PostgresNetworkRepository) ListNetworks(ctx context.Context, filter *repository.NetworkFilter) ([]*models.Network, error) {
	if filter == nil {
		filter = &repository.NetworkFilter{}
	}

	query := `
		SELECT id, organization_id, name, cidr_virtual, status, created_by_technician_id, created_at
		FROM networks WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.OrganizationID != nil && *filter.OrganizationID != "" {
		query += fmt.Sprintf(` AND organization_id = $%d`, argIdx)
		args = append(args, *filter.OrganizationID)
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

	var networks []*models.Network
	for rows.Next() {
		var net models.Network
		if err := rows.Scan(&net.ID, &net.OrganizationID, &net.Name, &net.CIDRVirtual, &net.Status, &net.CreatedBy, &net.CreatedAt); err != nil {
			return nil, err
		}
		networks = append(networks, &net)
	}

	return networks, rows.Err()
}

func (r *PostgresNetworkRepository) ListNetworksByOrganization(ctx context.Context, orgID string) ([]*models.Network, error) {
	return r.ListNetworks(ctx, &repository.NetworkFilter{
		OrganizationID: &orgID,
	})
}

func (r *PostgresNetworkRepository) ListNetworksByTechnician(ctx context.Context, technicianID string) ([]*models.Network, error) {
	query := `
		SELECT n.id, n.organization_id, n.name, n.cidr_virtual, n.status, n.created_by_technician_id, n.created_at
		FROM networks n
		WHERE n.created_by_technician_id = $1
		   OR n.organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id = $1)
		   OR n.id IN (SELECT network_id FROM technician_assignments WHERE technician_id = $1 AND network_id IS NOT NULL)
		ORDER BY n.created_at`

	rows, err := r.pool.Query(ctx, query, technicianID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var networks []*models.Network
	for rows.Next() {
		var net models.Network
		if err := rows.Scan(&net.ID, &net.OrganizationID, &net.Name, &net.CIDRVirtual, &net.Status, &net.CreatedBy, &net.CreatedAt); err != nil {
			return nil, err
		}
		networks = append(networks, &net)
	}

	return networks, rows.Err()
}

func (r *PostgresNetworkRepository) CreateNetwork(ctx context.Context, network *models.Network) error {
	query := `
		INSERT INTO networks (organization_id, name, cidr_virtual, status, created_by_technician_id)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at`

	err := r.pool.QueryRow(ctx, query,
		network.OrganizationID, network.Name, network.CIDRVirtual, network.Status, network.CreatedBy,
	).Scan(&network.ID, &network.CreatedAt)

	return err
}

func (r *PostgresNetworkRepository) UpdateNetwork(ctx context.Context, network *models.Network) error {
	query := `
		UPDATE networks
		SET name = $1, cidr_virtual = $2, status = $3
		WHERE id = $4`

	_, err := r.pool.Exec(ctx, query, network.Name, network.CIDRVirtual, network.Status, network.ID)

	return err
}

func (r *PostgresNetworkRepository) RenameNetwork(ctx context.Context, id string, name string) error {
	_, err := r.pool.Exec(ctx, `UPDATE networks SET name = $1 WHERE id = $2`, name, id)
	return err
}

func (r *PostgresNetworkRepository) DeleteNetwork(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM networks WHERE id = $1`, id)
	return err
}

func (r *PostgresNetworkRepository) GetNetworkByName(ctx context.Context, orgID string, name string) (*models.Network, error) {
	var net models.Network
	query := `
		SELECT id, organization_id, name, cidr_virtual, status, created_by_technician_id, created_at
		FROM networks WHERE organization_id = $1 AND name = $2`

	err := r.pool.QueryRow(ctx, query, orgID, name).Scan(
		&net.ID, &net.OrganizationID, &net.Name, &net.CIDRVirtual, &net.Status, &net.CreatedBy, &net.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("network not found")
		}
		return nil, err
	}

	return &net, nil
}
