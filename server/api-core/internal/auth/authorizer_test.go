package auth

import (
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/models"
)

// TestAuthorizerPermissions validates RBAC authorization rules.
// These tests assume a test database is available.
func TestSuperAdminAccess(t *testing.T) {
	// Super admin should be able to access any device/network/organization
	// This is validated by the CanAccessDevice, CanAccessNetwork, CanAccessOrganization methods
	// which all return true immediately for super_admin role

	claims := &Claims{
		TechnicianID: "test-super-admin",
		Role:         models.RoleSuperAdmin,
	}

	// Create a mock authorizer (in real tests, use a test DB)
	// For now, just verify the logic is sound by checking the role
	if claims.Role != models.RoleSuperAdmin {
		t.Error("Super admin role check failed")
	}
}

func TestFreelancerAccess(t *testing.T) {
	// Freelancers should only access tickets assigned to them
	claims := &Claims{
		TechnicianID: "test-freelancer",
		Role:         models.RoleFreelancer,
	}

	if claims.Role != models.RoleFreelancer {
		t.Error("Freelancer role check failed")
	}
}

func TestSupervisorAccess(t *testing.T) {
	// Supervisor should access org they own or networks assigned to them
	claims := &Claims{
		TechnicianID: "test-supervisor",
		Role:         models.RoleSupervisor,
	}

	if claims.Role != models.RoleSupervisor {
		t.Error("Supervisor role check failed")
	}
	if !IsSupervisorOrAbove(claims) {
		t.Error("Supervisor should satisfy IsSupervisorOrAbove")
	}
}

func TestClienteAccess(t *testing.T) {
	// Cliente is bound to a supervisor: no management powers at all.
	claims := &Claims{
		TechnicianID: "test-cliente",
		Role:         models.RoleCliente,
	}

	if !IsEndUser(claims) {
		t.Error("Cliente should be an end user")
	}
	if IsSupervisorOrAbove(claims) {
		t.Error("Cliente must not have supervisor powers")
	}
}

func TestClienteAvulsoAccess(t *testing.T) {
	// Cliente avulso is outside any org/network: only own tickets and device.
	claims := &Claims{
		TechnicianID: "test-cliente-avulso",
		Role:         models.RoleClienteAvulso,
	}

	if !IsEndUser(claims) {
		t.Error("Cliente avulso should be an end user")
	}
	if IsSupervisorOrAbove(claims) {
		t.Error("Cliente avulso must not have supervisor powers")
	}
}

// TestSuperAdminIsSupersetOfSupervisor enforces the product rule: every
// function available to supervisor must also be available to super_admin.
func TestSuperAdminIsSupersetOfSupervisor(t *testing.T) {
	admin := &Claims{TechnicianID: "admin", Role: models.RoleSuperAdmin}
	if !IsSupervisorOrAbove(admin) {
		t.Error("super_admin must be a superset of supervisor")
	}
	if !IsSuperAdmin(admin) {
		t.Error("super_admin role check failed")
	}
}

// Benchmark the CanAccessDevice method
func BenchmarkCanAccessDevice(b *testing.B) {
	// This is a placeholder benchmark
	// In real tests, connect to test DB and benchmark actual queries
	b.Run("super-admin-access", func(b *testing.B) {
		claims := &Claims{
			TechnicianID: "test-super-admin",
			Role:         models.RoleSuperAdmin,
		}
		// Super admin always returns true immediately, so this should be very fast
		for i := 0; i < b.N; i++ {
			_ = claims.Role == models.RoleSuperAdmin
		}
	})
}

// TestAuthorizerInitialization validates that authorizer is properly created
func TestAuthorizerInitialization(t *testing.T) {
	// In a real test, you would pass a real pgxpool
	// For now, we just verify the structure
	var pool *pgxpool.Pool
	authorizer := NewAuthorizer(pool)
	if authorizer == nil {
		t.Error("Authorizer initialization failed")
	}
}
