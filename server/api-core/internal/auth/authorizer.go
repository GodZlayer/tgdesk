package auth

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/models"
)

// AuthContext holds the authorization context extracted from JWT claims
// and enriched with permission data from the database.
type AuthContext struct {
	TechnicianID   string
	Role           string
	OrganizationID *string
	NetworkID      *string
	IsOrgOwner     bool
	IsNetworkOwner bool
}

// Authorizer centralizes all RBAC permission checks.
//
// Modelo de papéis (5, exaustivo):
//
//	super_admin    - gerente geral de tudo. Superconjunto de supervisor:
//	                 toda função disponível ao supervisor está disponível a ele.
//	supervisor     - admin da própria org (organizations.owner_technician_id)
//	                 + redes/subredes/devices dentro dela + seus assignments.
//	cliente        - vinculado a um supervisor. Sem gestão: apenas leitura do
//	                 próprio device e dos próprios tickets.
//	freelancer     - avulso. Somente tickets atribuídos a ele + acesso a device
//	                 via temporary_ticket_permissions (respeitando expires_at).
//	cliente_avulso - avulso. Somente os próprios tickets e o próprio device.
type Authorizer struct {
	pool *pgxpool.Pool
}

// NewAuthorizer creates a new authorizer instance.
func NewAuthorizer(pool *pgxpool.Pool) *Authorizer {
	return &Authorizer{pool: pool}
}

// IsSuperAdmin reports whether the claims belong to the global administrator.
func IsSuperAdmin(claims *Claims) bool {
	return claims != nil && claims.Role == models.RoleSuperAdmin
}

// IsSupervisorOrAbove reports whether the role has org-level management powers.
// super_admin is always a superset of supervisor.
func IsSupervisorOrAbove(claims *Claims) bool {
	if claims == nil {
		return false
	}
	return claims.Role == models.RoleSuperAdmin || claims.Role == models.RoleSupervisor
}

// IsEndUser reports whether the role is a pure consumer (no management at all).
func IsEndUser(claims *Claims) bool {
	if claims == nil {
		return false
	}
	return claims.Role == models.RoleCliente || claims.Role == models.RoleClienteAvulso
}

// ownsDevice reports whether the device is the user's own device.
func (a *Authorizer) ownsDevice(ctx context.Context, technicianID, deviceID string) (bool, error) {
	var ok bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM devices d
			WHERE d.id=$2 AND d.control_technician_id=$1
		)`, technicianID, deviceID).Scan(&ok)
	return ok, err
}

// hasTemporaryTicketAccess reports whether a freelancer holds a live temporary
// permission over the device (granted by an accepted ticket, not yet expired).
func (a *Authorizer) hasTemporaryTicketAccess(ctx context.Context, freelancerID, deviceID string) (bool, error) {
	var ok bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM temporary_ticket_permissions p
			WHERE p.device_id=$2 AND p.freelancer_id=$1
			  AND p.status='active' AND p.expires_at>now()
		)`, freelancerID, deviceID).Scan(&ok)
	return ok, err
}

// ownsTicket reports whether the ticket belongs to the user, either because the
// user is the supervisor of record or because it was opened from their device.
func (a *Authorizer) ownsTicket(ctx context.Context, technicianID, ticketID string) (bool, error) {
	var ok bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM support_tickets t
			LEFT JOIN devices d1 ON d1.id=t.device_id
			LEFT JOIN devices d2 ON d2.id=t.opened_by_device_id
			WHERE t.id=$2
			  AND (t.supervisor_id=$1
			       OR d1.control_technician_id=$1
			       OR d2.control_technician_id=$1)
		)`, technicianID, ticketID).Scan(&ok)
	return ok, err
}

// CanAccessDevice checks if a user can access a device.
// super_admin: always. supervisor: devices of own org or assigned networks.
// cliente / cliente_avulso: only their own device.
// freelancer: only through a live temporary ticket permission.
func (a *Authorizer) CanAccessDevice(ctx context.Context, claims *Claims, deviceID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}

	switch claims.Role {
	case models.RoleCliente, models.RoleClienteAvulso:
		return a.ownsDevice(ctx, claims.TechnicianID, deviceID)

	case models.RoleFreelancer:
		return a.hasTemporaryTicketAccess(ctx, claims.TechnicianID, deviceID)

	case models.RoleSupervisor:
		var exclusiveHeld bool
		err := a.pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM temporary_ticket_permissions p
				WHERE p.device_id=$1 AND p.status='active' AND p.expires_at>now() AND p.exclusive=true
			)`, deviceID).Scan(&exclusiveHeld)
		if err != nil {
			return false, err
		}
		if exclusiveHeld {
			return false, nil
		}
		var allowed bool
		err = a.pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1
				FROM device_networks dn
				JOIN networks n ON n.id=dn.network_id
				WHERE dn.device_id=$2
				  AND (
					n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1 OR lower(name)='tgdevs')
					OR n.id IN (SELECT network_id FROM technician_assignments
						WHERE technician_id=$1 AND network_id IS NOT NULL)
				  )
			)`, claims.TechnicianID, deviceID).Scan(&allowed)
		return allowed, err

	default:
		return false, nil
	}
}

// CanAccessNetwork checks if a user can access a network.
// Only super_admin and supervisor deal with networks/subnetworks.
func (a *Authorizer) CanAccessNetwork(ctx context.Context, claims *Claims, networkID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	var allowed bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM networks n
			WHERE n.id=$2
			  AND (
				n.organization_id IN (SELECT id FROM organizations WHERE owner_technician_id=$1 OR lower(name)='tgdevs')
				OR n.id IN (SELECT network_id FROM technician_assignments
					WHERE technician_id=$1 AND network_id IS NOT NULL)
			  )
		)`, claims.TechnicianID, networkID).Scan(&allowed)
	return allowed, err
}

// CanAccessOrganization checks if a user can access an organization.
// Only super_admin and supervisor belong to organizations.
func (a *Authorizer) CanAccessOrganization(ctx context.Context, claims *Claims, organizationID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	var allowed bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM organizations o
			WHERE o.id=$2
			  AND (
				o.owner_technician_id=$1 OR lower(o.name)='tgdevs'
				OR EXISTS (SELECT 1 FROM networks n
					JOIN technician_assignments ta ON ta.network_id=n.id
					WHERE n.organization_id=o.id AND ta.technician_id=$1)
			  )
		)`, claims.TechnicianID, organizationID).Scan(&allowed)
	return allowed, err
}

// CanCreateDevice checks if a user can create a device in a network.
// super_admin always; supervisor within reachable networks; nobody else.
func (a *Authorizer) CanCreateDevice(ctx context.Context, claims *Claims, networkID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	return a.CanAccessNetwork(ctx, claims, networkID)
}

// CanManageDevice checks if a user can manage (modify/delete) a device.
// super_admin and supervisor only — end users and freelancers may reach a
// device through CanAccessDevice but never manage it.
func (a *Authorizer) CanManageDevice(ctx context.Context, claims *Claims, deviceID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}
	return a.CanAccessDevice(ctx, claims, deviceID)
}

// CanManageNetwork checks if a user can manage (modify/delete) a network.
// super_admin always; supervisor only for networks of the org he owns.
func (a *Authorizer) CanManageNetwork(ctx context.Context, claims *Claims, networkID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	var allowed bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM networks n
			JOIN organizations o ON o.id=n.organization_id
			WHERE n.id=$2 AND o.owner_technician_id=$1
		)`, claims.TechnicianID, networkID).Scan(&allowed)
	return allowed, err
}

// CanManageOrganization checks if a user can manage an organization.
// super_admin always; supervisor only for the org he owns.
func (a *Authorizer) CanManageOrganization(ctx context.Context, claims *Claims, organizationID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	var allowed bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM organizations o
			WHERE o.id=$2 AND o.owner_technician_id=$1
		)`, claims.TechnicianID, organizationID).Scan(&allowed)
	return allowed, err
}

// CanManageTechnician checks if a user can create/modify accounts globally.
// Only super_admin manages accounts globally.
func (a *Authorizer) CanManageTechnician(ctx context.Context, claims *Claims) (bool, error) {
	return claims.Role == models.RoleSuperAdmin, nil
}

// CanManageClient checks if a user can manage a 'cliente' account.
// super_admin always; supervisor only for clients bound to his own org.
func (a *Authorizer) CanManageClient(ctx context.Context, claims *Claims, clientID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	var allowed bool
	err := a.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM technician_assignments ta
			LEFT JOIN networks n ON n.id=ta.network_id
			WHERE ta.technician_id=$2
			  AND coalesce(ta.organization_id, n.organization_id)
			      IN (SELECT id FROM organizations WHERE owner_technician_id=$1)
		)`, claims.TechnicianID, clientID).Scan(&allowed)
	return allowed, err
}

// CanManageTicket checks if a user can manage a support ticket.
// super_admin: all. freelancer: only tickets assigned to him.
// cliente / cliente_avulso: only their own tickets.
// supervisor: tickets inside organizations he can reach.
func (a *Authorizer) CanManageTicket(ctx context.Context, claims *Claims, ticketID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}

	switch claims.Role {
	case models.RoleFreelancer:
		var ok bool
		err := a.pool.QueryRow(ctx, `
			SELECT assigned_freelancer_id=$2 FROM support_tickets WHERE id=$1`,
			ticketID, claims.TechnicianID).Scan(&ok)
		return ok, err

	case models.RoleCliente, models.RoleClienteAvulso:
		return a.ownsTicket(ctx, claims.TechnicianID, ticketID)

	case models.RoleSupervisor:
		var orgID string
		err := a.pool.QueryRow(ctx, `
			SELECT organization_id FROM support_tickets WHERE id=$1`, ticketID).
			Scan(&orgID)
		if err != nil {
			return false, err
		}
		return a.CanAccessOrganization(ctx, claims, orgID)

	default:
		return false, nil
	}
}

// CanCreateTicket checks if a user can open a support ticket.
// super_admin and supervisor open tickets inside their organizations.
// cliente opens tickets in the org he is bound to; cliente_avulso opens only
// standalone tickets (no organization). freelancer never opens, only accepts.
func (a *Authorizer) CanCreateTicket(ctx context.Context, claims *Claims, organizationID string) (bool, error) {
	switch claims.Role {
	case models.RoleSuperAdmin:
		return true, nil

	case models.RoleFreelancer:
		return false, nil

	case models.RoleClienteAvulso:
		// Fora de qualquer organização/rede: só abre chamado avulso.
		return organizationID == "", nil

	case models.RoleCliente:
		if organizationID == "" {
			return true, nil
		}
		var ok bool
		err := a.pool.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM technician_assignments ta
				LEFT JOIN networks n ON n.id=ta.network_id
				WHERE ta.technician_id=$1
				  AND coalesce(ta.organization_id, n.organization_id)=$2
			)`, claims.TechnicianID, organizationID).Scan(&ok)
		return ok, err

	case models.RoleSupervisor:
		return a.CanAccessOrganization(ctx, claims, organizationID)

	default:
		return false, nil
	}
}

// CanAcceptFreelanceTicket checks if a user can accept a dispatch offer.
// Only freelancers accept offers.
func (a *Authorizer) CanAcceptFreelanceTicket(ctx context.Context, claims *Claims) (bool, error) {
	return claims.Role == models.RoleFreelancer, nil
}

// CanSuspendResource checks if a user can suspend/unsuspend a resource.
// Only super_admin and the owning supervisor can suspend resources.
func (a *Authorizer) CanSuspendResource(ctx context.Context, claims *Claims, resourceType, resourceID string) (bool, error) {
	if claims.Role == models.RoleSuperAdmin {
		return true, nil
	}
	if claims.Role != models.RoleSupervisor {
		return false, nil
	}

	switch resourceType {
	case "device":
		// Device owner: org owner of the network the device belongs to
		var orgID string
		err := a.pool.QueryRow(ctx, `
			SELECT n.organization_id
			FROM devices d
			JOIN networks n ON n.id=d.network_id
			WHERE d.id=$1`, resourceID).Scan(&orgID)
		if err != nil {
			return false, err
		}
		return a.CanManageOrganization(ctx, claims, orgID)

	case "network":
		// Network owner: org owner
		return a.CanManageNetwork(ctx, claims, resourceID)

	case "organization":
		// Org owner: only owner of that org
		return a.CanManageOrganization(ctx, claims, resourceID)

	default:
		return false, nil
	}
}

// CanReadAuditLog checks if a user can read audit logs.
// Only super_admin can read audit logs.
func (a *Authorizer) CanReadAuditLog(ctx context.Context, claims *Claims) (bool, error) {
	return claims.Role == models.RoleSuperAdmin, nil
}

// CanReadTelemetry checks if a user can read telemetry data.
// Same reach as device access.
func (a *Authorizer) CanReadTelemetry(ctx context.Context, claims *Claims, deviceID string) (bool, error) {
	return a.CanAccessDevice(ctx, claims, deviceID)
}

// CanManageDiagnostics checks if a user can trigger/view diagnostics.
// super_admin and supervisor over their devices; freelancer only while a
// temporary ticket permission is live. End users cannot trigger diagnostics.
func (a *Authorizer) CanManageDiagnostics(ctx context.Context, claims *Claims, deviceID string) (bool, error) {
	if IsEndUser(claims) {
		return false, nil
	}
	if claims.Role == models.RoleSupervisor {
		var status *string
		err := a.pool.QueryRow(ctx, `
			SELECT status FROM support_tickets
			WHERE device_id=$1 OR opened_by_device_id=$1
			ORDER BY created_at DESC LIMIT 1`, deviceID).Scan(&status)
		if err != nil && err != pgx.ErrNoRows {
			return false, err
		}
		if status != nil && (*status == "open" || *status == "offered_supervisor") {
			return false, nil
		}
	}
	return a.CanAccessDevice(ctx, claims, deviceID)
}

// CanListTickets returns the query filter for listing tickets visible to the user.
// super_admin sees all. freelancer sees assigned and offered tickets.
// supervisor sees tickets in their organizations.
// cliente / cliente_avulso see only their own tickets.
func (a *Authorizer) CanListTickets(ctx context.Context, claims *Claims) (string, []interface{}, error) {
	query := `SELECT t.id,t.title,t.description,t.modality,t.priority,t.status,t.standalone,t.organization_id,t.network_id,t.device_id,t.assigned_freelancer_id,t.supervisor_id,t.created_at,t.updated_at FROM support_tickets t`
	args := []interface{}{}

	switch claims.Role {
	case models.RoleSuperAdmin:
		// sem filtro: vê tudo

	case models.RoleFreelancer:
		query += ` WHERE t.assigned_freelancer_id=$1 OR EXISTS(SELECT 1 FROM dispatch_offers o WHERE o.ticket_id=t.id AND o.freelancer_id=$1 AND o.available_at<=now() AND o.expires_at>now())`
		args = []interface{}{claims.TechnicianID}

	case models.RoleCliente, models.RoleClienteAvulso:
		query += ` WHERE t.supervisor_id=$1 OR EXISTS(SELECT 1 FROM devices d WHERE d.control_technician_id=$1 AND (d.id=t.device_id OR d.id=t.opened_by_device_id))`
		args = []interface{}{claims.TechnicianID}

	case models.RoleSupervisor:
		query += ` WHERE t.organization_id IN (SELECT organization_id FROM technician_assignments WHERE technician_id=$1 UNION SELECT id FROM organizations WHERE owner_technician_id=$1)`
		args = []interface{}{claims.TechnicianID}

	default:
		query += ` WHERE false`
	}
	query += ` ORDER BY priority DESC,created_at`

	return query, args, nil
}
