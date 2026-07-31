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

type PostgresFreelancerProfileRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresFreelancerProfileRepository(pool *pgxpool.Pool) repository.FreelancerProfileRepository {
	return &PostgresFreelancerProfileRepository{pool: pool}
}

func (r *PostgresFreelancerProfileRepository) GetProfile(ctx context.Context, technicianID string) (*models.FreelancerProfile, error) {
	var fp models.FreelancerProfile
	query := `
		SELECT id, technician_id, specialization, rating, completed_tickets, status, created_at, updated_at
		FROM freelancer_profiles WHERE technician_id = $1`

	err := r.pool.QueryRow(ctx, query, technicianID).Scan(
		&fp.ID, &fp.TechnicianID, &fp.Specialization, &fp.Rating, &fp.CompletedTickets, &fp.Status, &fp.CreatedAt, &fp.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("freelancer profile not found")
		}
		return nil, err
	}

	return &fp, nil
}

func (r *PostgresFreelancerProfileRepository) ListProfiles(ctx context.Context, filter *repository.FreelancerFilter) ([]*models.FreelancerProfile, error) {
	if filter == nil {
		filter = &repository.FreelancerFilter{}
	}

	query := `
		SELECT id, technician_id, specialization, rating, completed_tickets, status, created_at, updated_at
		FROM freelancer_profiles WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.Status != nil && *filter.Status != "" {
		query += fmt.Sprintf(` AND status = $%d`, argIdx)
		args = append(args, *filter.Status)
		argIdx++
	}

	if filter.Specialization != nil && *filter.Specialization != "" {
		query += fmt.Sprintf(` AND specialization = $%d`, argIdx)
		args = append(args, *filter.Specialization)
		argIdx++
	}

	if filter.MinRating != nil && *filter.MinRating > 0 {
		query += fmt.Sprintf(` AND rating >= $%d`, argIdx)
		args = append(args, *filter.MinRating)
		argIdx++
	}

	query += ` ORDER BY rating DESC, completed_tickets DESC`

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

	var profiles []*models.FreelancerProfile
	for rows.Next() {
		var fp models.FreelancerProfile
		if err := rows.Scan(&fp.ID, &fp.TechnicianID, &fp.Specialization, &fp.Rating, &fp.CompletedTickets, &fp.Status, &fp.CreatedAt, &fp.UpdatedAt); err != nil {
			return nil, err
		}
		profiles = append(profiles, &fp)
	}

	return profiles, rows.Err()
}

func (r *PostgresFreelancerProfileRepository) CreateProfile(ctx context.Context, profile *models.FreelancerProfile) error {
	query := `
		INSERT INTO freelancer_profiles (technician_id, specialization, rating, completed_tickets, status)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at, updated_at`

	err := r.pool.QueryRow(ctx, query,
		profile.TechnicianID, profile.Specialization, profile.Rating, profile.CompletedTickets, profile.Status,
	).Scan(&profile.ID, &profile.CreatedAt, &profile.UpdatedAt)

	return err
}

func (r *PostgresFreelancerProfileRepository) UpdateProfile(ctx context.Context, profile *models.FreelancerProfile) error {
	query := `
		UPDATE freelancer_profiles
		SET specialization = $1, rating = $2, completed_tickets = $3, status = $4, updated_at = now()
		WHERE technician_id = $5`

	_, err := r.pool.Exec(ctx, query,
		profile.Specialization, profile.Rating, profile.CompletedTickets, profile.Status, profile.TechnicianID,
	)

	return err
}

func (r *PostgresFreelancerProfileRepository) UpdateRating(ctx context.Context, technicianID string, rating float64) error {
	_, err := r.pool.Exec(ctx, `UPDATE freelancer_profiles SET rating = $1, updated_at = now() WHERE technician_id = $2`, rating, technicianID)
	return err
}

func (r *PostgresFreelancerProfileRepository) UpdateCompletedTickets(ctx context.Context, technicianID string, count int) error {
	_, err := r.pool.Exec(ctx, `UPDATE freelancer_profiles SET completed_tickets = $1, updated_at = now() WHERE technician_id = $2`, count, technicianID)
	return err
}

func (r *PostgresFreelancerProfileRepository) DeleteProfile(ctx context.Context, technicianID string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM freelancer_profiles WHERE technician_id = $1`, technicianID)
	return err
}
