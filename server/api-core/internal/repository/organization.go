package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type OrganizationFilter struct {
	Status       *string
	OwnerID      *string
	TechnicianID *string
	Limit        int
	Offset       int
}

type OrganizationRepository interface {
	GetOrganization(ctx context.Context, id string) (*models.Organization, error)
	ListOrganizations(ctx context.Context, filter *OrganizationFilter) ([]*models.Organization, error)
	ListOrganizationsByTechnician(ctx context.Context, technicianID string) ([]*models.Organization, error)
	CreateOrganization(ctx context.Context, org *models.Organization) error
	UpdateOrganization(ctx context.Context, org *models.Organization) error
	RenameOrganization(ctx context.Context, id string, name string) error
	DeleteOrganization(ctx context.Context, id string) error
	GetOrganizationByName(ctx context.Context, name string) (*models.Organization, error)
}
