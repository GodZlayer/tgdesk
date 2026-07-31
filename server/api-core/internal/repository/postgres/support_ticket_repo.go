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

type PostgresSupportTicketRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresSupportTicketRepository(pool *pgxpool.Pool) repository.SupportTicketRepository {
	return &PostgresSupportTicketRepository{pool: pool}
}

func (r *PostgresSupportTicketRepository) GetTicket(ctx context.Context, id string) (*models.SupportTicket, error) {
	var t models.SupportTicket
	query := `
		SELECT id, organization_id, network_id, device_id, opened_by_device_id, assigned_freelancer_id,
		       title, description, modality, priority, status, standalone, location, created_at, updated_at
		FROM support_tickets WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&t.ID, &t.OrganizationID, &t.NetworkID, &t.DeviceID, &t.OpenedByDeviceID, &t.AssignedFreelancerID,
		&t.Title, &t.Description, &t.Modality, &t.Priority, &t.Status, &t.Standalone, &t.Location, &t.CreatedAt, &t.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("ticket not found")
		}
		return nil, err
	}

	return &t, nil
}

func (r *PostgresSupportTicketRepository) ListTickets(ctx context.Context, filter *repository.SupportTicketFilter) ([]*models.SupportTicket, error) {
	if filter == nil {
		filter = &repository.SupportTicketFilter{}
	}

	query := `
		SELECT id, organization_id, network_id, device_id, opened_by_device_id, assigned_freelancer_id,
		       title, description, modality, priority, status, standalone, location, created_at, updated_at
		FROM support_tickets WHERE 1=1`

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

	if filter.Priority != nil {
		query += fmt.Sprintf(` AND priority = $%d`, argIdx)
		args = append(args, *filter.Priority)
		argIdx++
	}

	query += ` ORDER BY priority DESC, created_at`

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

	var tickets []*models.SupportTicket
	for rows.Next() {
		var t models.SupportTicket
		if err := rows.Scan(
			&t.ID, &t.OrganizationID, &t.NetworkID, &t.DeviceID, &t.OpenedByDeviceID, &t.AssignedFreelancerID,
			&t.Title, &t.Description, &t.Modality, &t.Priority, &t.Status, &t.Standalone, &t.Location, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		tickets = append(tickets, &t)
	}

	return tickets, rows.Err()
}

func (r *PostgresSupportTicketRepository) ListTicketsByOrganization(ctx context.Context, orgID string) ([]*models.SupportTicket, error) {
	return r.ListTickets(ctx, &repository.SupportTicketFilter{
		OrganizationID: &orgID,
	})
}

func (r *PostgresSupportTicketRepository) ListTicketsByDevice(ctx context.Context, deviceID string) ([]*models.SupportTicket, error) {
	query := `
		SELECT id, organization_id, network_id, device_id, opened_by_device_id, assigned_freelancer_id,
		       title, description, modality, priority, status, standalone, location, created_at, updated_at
		FROM support_tickets WHERE device_id = $1 OR opened_by_device_id = $1
		ORDER BY created_at DESC`

	rows, err := r.pool.Query(ctx, query, deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tickets []*models.SupportTicket
	for rows.Next() {
		var t models.SupportTicket
		if err := rows.Scan(
			&t.ID, &t.OrganizationID, &t.NetworkID, &t.DeviceID, &t.OpenedByDeviceID, &t.AssignedFreelancerID,
			&t.Title, &t.Description, &t.Modality, &t.Priority, &t.Status, &t.Standalone, &t.Location, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		tickets = append(tickets, &t)
	}

	return tickets, rows.Err()
}

func (r *PostgresSupportTicketRepository) ListTicketsByFreelancer(ctx context.Context, freelancerID string) ([]*models.SupportTicket, error) {
	query := `
		SELECT id, organization_id, network_id, device_id, opened_by_device_id, assigned_freelancer_id,
		       title, description, modality, priority, status, standalone, location, created_at, updated_at
		FROM support_tickets WHERE assigned_freelancer_id = $1
		ORDER BY created_at DESC`

	rows, err := r.pool.Query(ctx, query, freelancerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tickets []*models.SupportTicket
	for rows.Next() {
		var t models.SupportTicket
		if err := rows.Scan(
			&t.ID, &t.OrganizationID, &t.NetworkID, &t.DeviceID, &t.OpenedByDeviceID, &t.AssignedFreelancerID,
			&t.Title, &t.Description, &t.Modality, &t.Priority, &t.Status, &t.Standalone, &t.Location, &t.CreatedAt, &t.UpdatedAt,
		); err != nil {
			return nil, err
		}
		tickets = append(tickets, &t)
	}

	return tickets, rows.Err()
}

func (r *PostgresSupportTicketRepository) CreateTicket(ctx context.Context, ticket *models.SupportTicket) error {
	query := `
		INSERT INTO support_tickets (organization_id, network_id, device_id, opened_by_device_id, title, description, modality, standalone, location)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, priority, status, created_at, updated_at`

	err := r.pool.QueryRow(ctx, query,
		ticket.OrganizationID, ticket.NetworkID, ticket.DeviceID, ticket.OpenedByDeviceID,
		ticket.Title, ticket.Description, ticket.Modality, ticket.Standalone, ticket.Location,
	).Scan(&ticket.ID, &ticket.Priority, &ticket.Status, &ticket.CreatedAt, &ticket.UpdatedAt)

	return err
}

func (r *PostgresSupportTicketRepository) UpdateTicket(ctx context.Context, ticket *models.SupportTicket) error {
	query := `
		UPDATE support_tickets
		SET title = $1, description = $2, modality = $3, priority = $4, status = $5, location = $6, updated_at = now()
		WHERE id = $7`

	_, err := r.pool.Exec(ctx, query,
		ticket.Title, ticket.Description, ticket.Modality, ticket.Priority, ticket.Status, ticket.Location, ticket.ID,
	)

	return err
}

func (r *PostgresSupportTicketRepository) UpdateTicketStatus(ctx context.Context, id string, status string) error {
	_, err := r.pool.Exec(ctx, `UPDATE support_tickets SET status = $1, updated_at = now() WHERE id = $2`, status, id)
	return err
}

func (r *PostgresSupportTicketRepository) UpdateTicketAssignment(ctx context.Context, id string, freelancerID *string) error {
	_, err := r.pool.Exec(ctx, `UPDATE support_tickets SET assigned_freelancer_id = $1, updated_at = now() WHERE id = $2`, freelancerID, id)
	return err
}

func (r *PostgresSupportTicketRepository) DeleteTicket(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM support_tickets WHERE id = $1`, id)
	return err
}

func (r *PostgresSupportTicketRepository) AssignTicket(ctx context.Context, ticketID string, freelancerID string) error {
	_, err := r.pool.Exec(ctx, `UPDATE support_tickets SET assigned_freelancer_id = $1, updated_at = now() WHERE id = $2`, freelancerID, ticketID)
	return err
}
