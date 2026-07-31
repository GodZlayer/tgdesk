package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type NetworkFilter struct {
	OrganizationID *string
	Status         *string
	Limit          int
	Offset         int
}

type NetworkRepository interface {
	GetNetwork(ctx context.Context, id string) (*models.Network, error)
	ListNetworks(ctx context.Context, filter *NetworkFilter) ([]*models.Network, error)
	ListNetworksByOrganization(ctx context.Context, orgID string) ([]*models.Network, error)
	ListNetworksByTechnician(ctx context.Context, technicianID string) ([]*models.Network, error)
	CreateNetwork(ctx context.Context, network *models.Network) error
	UpdateNetwork(ctx context.Context, network *models.Network) error
	RenameNetwork(ctx context.Context, id string, name string) error
	DeleteNetwork(ctx context.Context, id string) error
	GetNetworkByName(ctx context.Context, orgID string, name string) (*models.Network, error)
}
