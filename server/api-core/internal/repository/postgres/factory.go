package postgres

import (
	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/repository"
)

// Factory holds all repository implementations
type Factory struct {
	Device             repository.DeviceRepository
	Organization       repository.OrganizationRepository
	Network            repository.NetworkRepository
	Subnetwork         repository.SubnetworkRepository
	Technician         repository.TechnicianRepository
	SupportTicket      repository.SupportTicketRepository
	FreelancerProfile  repository.FreelancerProfileRepository
}

// NewFactory creates a new repository factory with PostgreSQL implementations
func NewFactory(pool *pgxpool.Pool) *Factory {
	return &Factory{
		Device:            NewPostgresDeviceRepository(pool),
		Organization:      NewPostgresOrganizationRepository(pool),
		Network:           NewPostgresNetworkRepository(pool),
		Subnetwork:        NewPostgresSubnetworkRepository(pool),
		Technician:        NewPostgresTechnicianRepository(pool),
		SupportTicket:     NewPostgresSupportTicketRepository(pool),
		FreelancerProfile: NewPostgresFreelancerProfileRepository(pool),
	}
}
