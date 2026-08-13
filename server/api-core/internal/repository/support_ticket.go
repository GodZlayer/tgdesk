package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type SupportTicketFilter struct {
	OrganizationID     *string
	NetworkID          *string
	Status             *string
	Priority           *int
	AssignedFreelancer *string
	Limit              int
	Offset             int
}

type SupportTicketRepository interface {
	GetTicket(ctx context.Context, id string) (*models.SupportTicket, error)
	ListTickets(ctx context.Context, filter *SupportTicketFilter) ([]*models.SupportTicket, error)
	ListTicketsByOrganization(ctx context.Context, orgID string) ([]*models.SupportTicket, error)
	ListTicketsByDevice(ctx context.Context, deviceID string) ([]*models.SupportTicket, error)
	ListTicketsByFreelancer(ctx context.Context, freelancerID string) ([]*models.SupportTicket, error)
	CreateTicket(ctx context.Context, ticket *models.SupportTicket) error
	UpdateTicket(ctx context.Context, ticket *models.SupportTicket) error
	UpdateTicketStatus(ctx context.Context, id string, status string) error
	UpdateTicketAssignment(ctx context.Context, id string, freelancerID *string) error
	DeleteTicket(ctx context.Context, id string) error
	AssignTicket(ctx context.Context, ticketID string, freelancerID string) error
}
