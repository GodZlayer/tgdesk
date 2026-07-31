package repository

import (
	"context"

	"tgdesk/api-core/internal/models"
)

type TechnicianFilter struct {
	Role   *string
	Status *string
	Limit  int
	Offset int
}

type TechnicianRepository interface {
	GetTechnician(ctx context.Context, id string) (*models.Technician, error)
	GetTechnicianByUsername(ctx context.Context, username string) (*models.Technician, error)
	ListTechnicians(ctx context.Context, filter *TechnicianFilter) ([]*models.Technician, error)
	CreateTechnician(ctx context.Context, technician *models.Technician) error
	UpdateTechnician(ctx context.Context, technician *models.Technician) error
	DeleteTechnician(ctx context.Context, id string) error
	GetTechnicianAssignments(ctx context.Context, technicianID string) ([]*models.TechnicianAssignment, error)
	CreateTechnicianAssignment(ctx context.Context, assignment *models.TechnicianAssignment) error
	DeleteTechnicianAssignment(ctx context.Context, id string) error
	GetTechnicianAssignmentsByOrganization(ctx context.Context, orgID string) ([]*models.TechnicianAssignment, error)
	GetTechnicianAssignmentsByNetwork(ctx context.Context, networkID string) ([]*models.TechnicianAssignment, error)
}
