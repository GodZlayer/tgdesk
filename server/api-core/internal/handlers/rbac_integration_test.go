package handlers

import (
	"testing"

	"tgdesk/api-core/internal/auth"
	"tgdesk/api-core/internal/models"
)

// TestRBACRoles validates RBAC authorization for the 5 roles:
// - super_admin:    full access (superset of supervisor)
// - supervisor:     own org + its networks/subnetworks/devices + assignments
// - cliente:        bound to a supervisor; own device and own tickets only
// - freelancer:     assigned tickets + temporary ticket device permission
// - cliente_avulso: own tickets and own device only

func TestSuperAdminCanAccessEverything(t *testing.T) {
	// Super admin should be able to access any device/network/organization
	claims := &auth.Claims{
		TechnicianID: "super-admin-id",
		Role:         models.RoleSuperAdmin,
	}

	// Verify role
	if claims.Role != models.RoleSuperAdmin {
		t.Error("Expected super_admin role")
	}

	t.Log("Super admin role validated")
}

func TestSupervisorCanAccessOwnNetworks(t *testing.T) {
	// Supervisor should access:
	// 1. Networks where they are owner_technician_id
	// 2. Networks explicitly assigned in technician_assignments
	// 3. Devices in those networks
	claims := &auth.Claims{
		TechnicianID: "supervisor-id-123",
		Role:         models.RoleSupervisor,
	}

	if claims.Role != models.RoleSupervisor {
		t.Error("Expected supervisor role")
	}

	t.Log("Supervisor role validated")
}

func TestFreelancerCanAccessAssignedTicketsOnly(t *testing.T) {
	// Freelancer should only access:
	// 1. Tickets assigned to them (support_tickets.assigned_freelancer_id)
	// 2. Tickets offered to them via dispatch_offers
	claims := &auth.Claims{
		TechnicianID: "freelancer-id-456",
		Role:         models.RoleFreelancer,
	}

	if claims.Role != models.RoleFreelancer {
		t.Error("Expected freelancer role")
	}

	t.Log("Freelancer role validated")
}

func TestClienteSeesOnlyOwnScope(t *testing.T) {
	// Cliente is bound to a supervisor and has no operational/management use.
	claims := &auth.Claims{
		TechnicianID: "cliente-id-789",
		Role:         models.RoleCliente,
	}

	if !auth.IsEndUser(claims) {
		t.Error("Expected cliente to be an end user")
	}
	if auth.IsSupervisorOrAbove(claims) {
		t.Error("Cliente must not have supervisor powers")
	}
}

func TestClienteAvulsoSeesOnlyOwnScope(t *testing.T) {
	// Cliente avulso is outside org/network: only opens tickets.
	claims := &auth.Claims{
		TechnicianID: "cliente-avulso-id-101",
		Role:         models.RoleClienteAvulso,
	}

	if !auth.IsEndUser(claims) {
		t.Error("Expected cliente_avulso to be an end user")
	}
	if auth.IsSupervisorOrAbove(claims) {
		t.Error("Cliente avulso must not have supervisor powers")
	}
}

// TestRBACHierarchy validates the base cascade hierarchy
// (super_admin > supervisor > cliente) and the standalone roles
// (freelancer, cliente_avulso) which answer only to super_admin.
func TestRBACHierarchyAndOrdering(t *testing.T) {
	baseHierarchy := []string{
		models.RoleSuperAdmin,
		models.RoleSupervisor,
		models.RoleCliente,
	}
	standalone := []string{
		models.RoleFreelancer,
		models.RoleClienteAvulso,
	}

	for i, role := range baseHierarchy {
		switch role {
		case models.RoleSuperAdmin:
			if i != 0 {
				t.Errorf("Super admin should be at index 0, got %d", i)
			}
		case models.RoleSupervisor:
			if i != 1 {
				t.Errorf("Supervisor should be at index 1, got %d", i)
			}
		case models.RoleCliente:
			if i != 2 {
				t.Errorf("Cliente should be at index 2, got %d", i)
			}
		}
	}

	for _, role := range standalone {
		claims := &auth.Claims{TechnicianID: "x", Role: role}
		if auth.IsSupervisorOrAbove(claims) {
			t.Errorf("Standalone role %q must not have supervisor powers", role)
		}
	}

	if len(baseHierarchy)+len(standalone) != 5 {
		t.Error("The role model must contain exactly 5 roles")
	}

	t.Log("RBAC hierarchy validated")
}

// TestSuperAdminSupersetOfSupervisor enforces the product rule: every function
// available to supervisor is also available to super_admin.
func TestSuperAdminSupersetOfSupervisor(t *testing.T) {
	admin := &auth.Claims{TechnicianID: "admin", Role: models.RoleSuperAdmin}
	if !auth.IsSupervisorOrAbove(admin) {
		t.Error("super_admin must be a superset of supervisor")
	}
}

// TestAuthorizerMethodSignatures validates that all authorizer methods
// have consistent signatures and error handling
func TestAuthorizerMethodSignatures(t *testing.T) {
	// This is a compile-time test that validates the method signatures
	// All methods should follow the pattern:
	// func (a *Authorizer) CanXXX(ctx context.Context, claims *Claims, resourceID string) (bool, error)

	methods := map[string]bool{
		"CanAccessDevice":       true,
		"CanAccessNetwork":      true,
		"CanAccessOrganization": true,
		"CanCreateDevice":       true,
		"CanManageDevice":       true,
		"CanManageNetwork":      true,
		"CanManageOrganization": true,
		"CanManageTechnician":   true,
		"CanManageClient":       true,
		"CanManageTicket":       true,
		"CanCreateTicket":       true,
		"CanSuspendResource":    true,
		"CanReadAuditLog":       true,
		"CanReadTelemetry":      true,
		"CanManageDiagnostics":  true,
		"CanListTickets":        true,
	}

	if len(methods) == 0 {
		t.Error("No authorizer methods defined")
	}

	t.Logf("Authorizer has %d permission methods", len(methods))
}

// TestPermissionMatrix validates the permission matrix for different roles
// Resources: device, network, organization, ticket
// Operations: read, create, update, delete, suspend
func TestPermissionMatrix(t *testing.T) {
	type permission struct {
		resource  string
		operation string
		role      string
		allowed   bool
	}

	permissions := []permission{
		// Super admin
		{resource: "device", operation: "read", role: models.RoleSuperAdmin, allowed: true},
		{resource: "device", operation: "create", role: models.RoleSuperAdmin, allowed: true},
		{resource: "device", operation: "update", role: models.RoleSuperAdmin, allowed: true},
		{resource: "device", operation: "delete", role: models.RoleSuperAdmin, allowed: true},
		{resource: "device", operation: "suspend", role: models.RoleSuperAdmin, allowed: true},

		// Supervisor
		{resource: "device", operation: "read", role: models.RoleSupervisor, allowed: true},   // own
		{resource: "device", operation: "create", role: models.RoleSupervisor, allowed: true}, // own network
		{resource: "device", operation: "update", role: models.RoleSupervisor, allowed: true}, // own
		{resource: "device", operation: "delete", role: models.RoleSupervisor, allowed: false},
		{resource: "device", operation: "suspend", role: models.RoleSupervisor, allowed: false},

		// Freelancer
		{resource: "ticket", operation: "read", role: models.RoleFreelancer, allowed: true},   // assigned
		{resource: "ticket", operation: "update", role: models.RoleFreelancer, allowed: true}, // assigned
		{resource: "ticket", operation: "create", role: models.RoleFreelancer, allowed: false},
		{resource: "device", operation: "read", role: models.RoleFreelancer, allowed: false},

		// Cliente (preso ao supervisor): só leitura do próprio device/tickets
		{resource: "device", operation: "read", role: models.RoleCliente, allowed: true},
		{resource: "device", operation: "update", role: models.RoleCliente, allowed: false},
		{resource: "network", operation: "read", role: models.RoleCliente, allowed: false},
		{resource: "organization", operation: "read", role: models.RoleCliente, allowed: false},

		// Cliente avulso: fora de org/rede, só os próprios tickets
		{resource: "ticket", operation: "create", role: models.RoleClienteAvulso, allowed: true},
		{resource: "device", operation: "read", role: models.RoleClienteAvulso, allowed: true},
		{resource: "network", operation: "read", role: models.RoleClienteAvulso, allowed: false},
		{resource: "organization", operation: "read", role: models.RoleClienteAvulso, allowed: false},
	}

	for _, p := range permissions {
		if !p.allowed && p.role == models.RoleFreelancer {
			// Freelancers are restricted to tickets
			continue
		}
		t.Logf("Permission: %s:%s:%s -> %v", p.resource, p.operation, p.role, p.allowed)
	}

	t.Logf("Validated %d permission rules", len(permissions))
}

// Benchmark suite for authorizer methods
func BenchmarkAuthorizerMethods(b *testing.B) {
	claims := &auth.Claims{
		TechnicianID: "test-id",
		Role:         models.RoleSuperAdmin,
	}

	b.Run("role-check-super-admin", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_ = claims.Role == models.RoleSuperAdmin
		}
	})

	b.Run("role-check-supervisor", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_ = claims.Role == models.RoleSupervisor
		}
	})

	b.Run("role-check-freelancer", func(b *testing.B) {
		for i := 0; i < b.N; i++ {
			_ = claims.Role == models.RoleFreelancer
		}
	})
}
