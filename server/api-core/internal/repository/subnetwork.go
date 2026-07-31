package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type SubnetworkFilter struct {
	NetworkID *string
	Status    *string
	Limit     int
	Offset    int
}

type SubnetworkRepository interface {
	GetSubnetwork(ctx context.Context, id string) (*models.Subnetwork, error)
	ListSubnetworks(ctx context.Context, filter *SubnetworkFilter) ([]*models.Subnetwork, error)
	ListSubnetworksByNetwork(ctx context.Context, networkID string) ([]*models.Subnetwork, error)
	CreateSubnetwork(ctx context.Context, subnetwork *models.Subnetwork) error
	UpdateSubnetwork(ctx context.Context, subnetwork *models.Subnetwork) error
	RenameSubnetwork(ctx context.Context, id string, name string) error
	DeleteSubnetwork(ctx context.Context, id string) error
	GetSubnetworkByName(ctx context.Context, networkID string, name string) (*models.Subnetwork, error)
}
