package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type DeviceFilter struct {
	NetworkID    *string
	SubnetworkID *string
	Status       *string
	TechnicianID *string
	Limit        int
	Offset       int
}

type DeviceRepository interface {
	GetDevice(ctx context.Context, id string) (*models.Device, error)
	GetDeviceByMAC(ctx context.Context, mac string) (*models.Device, error)
	GetDevicesByNetwork(ctx context.Context, networkID string) ([]*models.Device, error)
	GetDevicesBySubnetwork(ctx context.Context, subnetworkID string) ([]*models.Device, error)
	ListDevices(ctx context.Context, filter *DeviceFilter) ([]*models.Device, error)
	CreateDevice(ctx context.Context, device *models.Device) error
	UpdateDevice(ctx context.Context, device *models.Device) error
	DeleteDevice(ctx context.Context, id string) error
	GetDeviceToken(ctx context.Context, id string) (string, error)
	UpdateDeviceLastSeen(ctx context.Context, id string) error
	GetDevicesWithPresence(ctx context.Context, filter *DeviceFilter, presenceMap map[string]string) ([]*models.Device, error)
}
