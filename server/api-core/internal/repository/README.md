# Repository Layer (DAO Pattern)

This layer abstracts data access logic from handlers, implementing the Data Access Object (DAO) pattern.

## Structure

```
repository/
├── device.go                      # DeviceRepository interface
├── organization.go                # OrganizationRepository interface
├── network.go                     # NetworkRepository interface
├── subnetwork.go                  # SubnetworkRepository interface
├── technician.go                  # TechnicianRepository interface
├── support_ticket.go              # SupportTicketRepository interface
├── freelancer_profile.go          # FreelancerProfileRepository interface
├── example_handler_refactor.go    # Example of handler refactoring
│
└── postgres/
    ├── factory.go                 # Factory that creates all repositories
    ├── device_repo.go             # PostgreSQL implementation
    ├── organization_repo.go       # PostgreSQL implementation
    ├── network_repo.go            # PostgreSQL implementation
    ├── subnetwork_repo.go         # PostgreSQL implementation
    ├── technician_repo.go         # PostgreSQL implementation
    ├── support_ticket_repo.go     # PostgreSQL implementation
    └── freelancer_profile_repo.go # PostgreSQL implementation
```

## Interfaces (7 total)

### 1. DeviceRepository
- GetDevice, GetDeviceByMAC, GetDevicesByNetwork, GetDevicesBySubnetwork
- ListDevices, CreateDevice, UpdateDevice, DeleteDevice
- GetDeviceToken, UpdateDeviceLastSeen, GetDevicesWithPresence

### 2. OrganizationRepository
- GetOrganization, ListOrganizations, ListOrganizationsByTechnician
- CreateOrganization, UpdateOrganization, RenameOrganization, DeleteOrganization
- GetOrganizationByName

### 3. NetworkRepository
- GetNetwork, ListNetworks, ListNetworksByOrganization, ListNetworksByTechnician
- CreateNetwork, UpdateNetwork, RenameNetwork, DeleteNetwork, GetNetworkByName

### 4. SubnetworkRepository
- GetSubnetwork, ListSubnetworks, ListSubnetworksByNetwork
- CreateSubnetwork, UpdateSubnetwork, RenameSubnetwork, DeleteSubnetwork
- GetSubnetworkByName

### 5. TechnicianRepository
- GetTechnician, GetTechnicianByUsername, ListTechnicians
- CreateTechnician, UpdateTechnician, DeleteTechnician
- GetTechnicianAssignments, CreateTechnicianAssignment, DeleteTechnicianAssignment
- GetTechnicianAssignmentsByOrganization, GetTechnicianAssignmentsByNetwork

### 6. SupportTicketRepository
- GetTicket, ListTickets, ListTicketsByOrganization, ListTicketsByDevice
- ListTicketsByFreelancer, CreateTicket, UpdateTicket
- UpdateTicketStatus, UpdateTicketAssignment, DeleteTicket, AssignTicket

### 7. FreelancerProfileRepository
- GetProfile, ListProfiles, CreateProfile, UpdateProfile
- UpdateRating, UpdateCompletedTickets, DeleteProfile

## PostgreSQL Implementations

All interfaces have PostgreSQL implementations in `postgres/` subdirectory:
- Safe parameterized queries (prevent SQL injection)
- Error handling with pgx.ErrNoRows
- Support for dynamic filtering and pagination
- Transaction-aware context propagation

## Usage

### Initialize repositories in server setup:

```go
import "tgdesk/api-core/internal/repository/postgres"

type Server struct {
    Pool  *pgxpool.Pool
    Repos *postgres.Factory
}

func NewServer(pool *pgxpool.Pool) *Server {
    return &Server{
        Pool:  pool,
        Repos: postgres.NewFactory(pool),
    }
}
```

### Use in handlers:

```go
// OLD: s.Pool.Query("SELECT ... FROM devices WHERE ...")
// NEW: device, _ := s.Repos.Device.GetDevice(ctx, id)

func (s *Server) GetDevice(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    device, err := s.Repos.Device.GetDevice(r.Context(), id)
    if err != nil {
        writeErr(w, http.StatusNotFound, "device not found")
        return
    }
    writeJSON(w, http.StatusOK, device)
}
```

## Benefits

1. **Separation of Concerns**: Data access logic separate from business logic
2. **Testability**: Easy to mock repositories for unit tests
3. **Maintainability**: Changes to queries only affect repository layer
4. **RBAC Preparation**: All permission checks can be centralized here
5. **Database Abstraction**: Can swap PostgreSQL for another DB without touching handlers
6. **Query Consolidation**: 89 inline queries → organized repository methods

## Migration Path

1. Start using repositories for new handlers
2. Gradually refactor existing handlers to use repositories
3. Remove direct pool usage from handlers
4. Add RBAC checks in repository methods where needed
