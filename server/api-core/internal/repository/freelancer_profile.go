package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type FreelancerFilter struct {
	Status         *string
	Specialization *string
	MinRating      *float64
	Limit          int
	Offset         int
}

type FreelancerProfileRepository interface {
	GetProfile(ctx context.Context, technicianID string) (*models.FreelancerProfile, error)
	ListProfiles(ctx context.Context, filter *FreelancerFilter) ([]*models.FreelancerProfile, error)
	CreateProfile(ctx context.Context, profile *models.FreelancerProfile) error
	UpdateProfile(ctx context.Context, profile *models.FreelancerProfile) error
	UpdateRating(ctx context.Context, technicianID string, rating float64) error
	UpdateCompletedTickets(ctx context.Context, technicianID string, count int) error
	DeleteProfile(ctx context.Context, technicianID string) error
}
