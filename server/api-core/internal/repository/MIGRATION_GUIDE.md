# Repository Layer Migration Guide

This document provides step-by-step instructions for refactoring handlers to use the new repository layer pattern.

## Quick Start

### 1. Update Server Struct

**Before:**
```go
type Server struct {
    Pool *pgxpool.Pool
    // ... other fields
}
```

**After:**
```go
import "tgdesk/api-core/internal/repository/postgres"

type Server struct {
    Pool  *pgxpool.Pool
    Repos *postgres.Factory
    // ... other fields
}

func NewServer(pool *pgxpool.Pool) *Server {
    return &Server{
        Pool:  pool,
        Repos: postgres.NewFactory(pool),
        // ... other fields
    }
}
```

### 2. Refactor Handler Methods

#### Example 1: GetDevice (Simple Query)

**Before:**
```go
func (s *Server) GetDevice(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    
    var d models.Device
    err := s.Pool.QueryRow(r.Context(), `
        SELECT id, hostname, mac, role, state, created_at
        FROM devices WHERE id = $1`, id).
        Scan(&d.ID, &d.Hostname, &d.MAC, &d.Role, &d.State, &d.CreatedAt)
    
    if err != nil {
        writeErr(w, http.StatusNotFound, "device not found")
        return
    }
    writeJSON(w, http.StatusOK, d)
}
```

**After:**
```go
func (s *Server) GetDevice(w http.ResponseWriter, r *http.Request) {
    id := r.PathValue("id")
    
    d, err := s.Repos.Device.GetDevice(r.Context(), id)
    if err != nil {
        writeErr(w, http.StatusNotFound, "device not found")
        return
    }
    writeJSON(w, http.StatusOK, d)
}
```

#### Example 2: ListDevices (Filtered Query)

**Before:**
```go
func (s *Server) ListDevices(w http.ResponseWriter, r *http.Request) {
    networkID := r.URL.Query().Get("network_id")
    
    query := `
        SELECT id, hostname, mac, role, state, created_at
        FROM devices WHERE 1=1`
    var args []any
    
    if networkID != "" {
        query += ` AND network_id = $1`
        args = append(args, networkID)
    }
    
    rows, err := s.Pool.Query(r.Context(), query, args...)
    if err != nil {
        writeErr(w, http.StatusInternalServerError, "query failed")
        return
    }
    defer rows.Close()
    
    var devices []*models.Device
    for rows.Next() {
        var d models.Device
        rows.Scan(&d.ID, &d.Hostname, &d.MAC, &d.Role, &d.State, &d.CreatedAt)
        devices = append(devices, &d)
    }
    
    writeJSON(w, http.StatusOK, devices)
}
```

**After:**
```go
func (s *Server) ListDevices(w http.ResponseWriter, r *http.Request) {
    networkID := r.URL.Query().Get("network_id")
    
    filter := &repository.DeviceFilter{}
    if networkID != "" {
        filter.NetworkID = &networkID
    }
    
    devices, err := s.Repos.Device.ListDevices(r.Context(), filter)
    if err != nil {
        writeErr(w, http.StatusInternalServerError, "query failed")
        return
    }
    
    writeJSON(w, http.StatusOK, devices)
}
```

#### Example 3: CreateDevice

**Before:**
```go
func (s *Server) CreateDevice(w http.ResponseWriter, r *http.Request) {
    var req struct {
        Hostname string `json:"hostname"`
        MAC      string `json:"mac"`
    }
    json.NewDecoder(r.Body).Decode(&req)
    
    var id, token string
    err := s.Pool.QueryRow(r.Context(), `
        INSERT INTO devices (hostname, mac, role, state)
        VALUES ($1, $2, 'host', 'guest')
        RETURNING id, device_token`, req.Hostname, req.MAC).
        Scan(&id, &token)
    
    if err != nil {
        writeErr(w, http.StatusBadRequest, "failed to create device")
        return
    }
    
    writeJSON(w, http.StatusCreated, map[string]string{
        "id": id, "device_token": token,
    })
}
```

**After:**
```go
func (s *Server) CreateDevice(w http.ResponseWriter, r *http.Request) {
    var req struct {
        Hostname string `json:"hostname"`
        MAC      string `json:"mac"`
    }
    json.NewDecoder(r.Body).Decode(&req)
    
    device := &models.Device{
        Hostname: req.Hostname,
        MAC:      req.MAC,
        Role:     "host",
        State:    "guest",
    }
    
    err := s.Repos.Device.CreateDevice(r.Context(), device)
    if err != nil {
        writeErr(w, http.StatusBadRequest, "failed to create device")
        return
    }
    
    writeJSON(w, http.StatusCreated, map[string]string{
        "id": device.ID, "device_token": device.DeviceToken,
    })
}
```

### 3. Migration Order

Recommend refactoring in this order:

1. **Handlers using Organization** → `s.Repos.Organization.*`
2. **Handlers using Device** → `s.Repos.Device.*`
3. **Handlers using Network** → `s.Repos.Network.*`
4. **Handlers using Subnetwork** → `s.Repos.Subnetwork.*`
5. **Handlers using Technician** → `s.Repos.Technician.*`
6. **Handlers using SupportTicket** → `s.Repos.SupportTicket.*`
7. **Handlers using FreelancerProfile** → `s.Repos.FreelancerProfile.*`

### 4. Testing with Mocks

Create mock repositories for unit testing:

```go
type MockDeviceRepository struct {
    GetDeviceFn func(ctx context.Context, id string) (*models.Device, error)
}

func (m *MockDeviceRepository) GetDevice(ctx context.Context, id string) (*models.Device, error) {
    return m.GetDeviceFn(ctx, id)
}

// ... implement other methods ...

// Use in tests:
mockRepo := &MockDeviceRepository{
    GetDeviceFn: func(ctx context.Context, id string) (*models.Device, error) {
        return &models.Device{ID: id, Hostname: "test"}, nil
    },
}

// Inject into handler for testing
```

### 5. Common Patterns

#### Get single record with not-found handling:
```go
item, err := s.Repos.Device.GetDevice(ctx, id)
if err != nil {
    writeErr(w, http.StatusNotFound, "not found")
    return
}
```

#### List with optional filters:
```go
filter := &repository.DeviceFilter{}
if query := r.URL.Query().Get("network_id"); query != "" {
    filter.NetworkID = &query
}
devices, _ := s.Repos.Device.ListDevices(ctx, filter)
```

#### Create with return values:
```go
device := &models.Device{...}
err := s.Repos.Device.CreateDevice(ctx, device)
// device.ID and other fields populated by repository
```

#### Update multiple fields:
```go
device.Hostname = "newname"
device.State = "ativo"
err := s.Repos.Device.UpdateDevice(ctx, device)
```

## Query Count Reduction

**Before:** 89 inline SQL queries across handlers
**After:** Consolidated into 65+ repository methods

This means:
- Easier to audit and fix SQL issues
- Single place to implement RBAC checks
- Consistent error handling
- Better separation of concerns

## Next Steps

1. Update `handlers/server.go` to initialize `Repos` in `NewServer()`
2. Start refactoring handlers one by one
3. Add unit tests for refactored handlers using mock repositories
4. Once all handlers are refactored, remove direct `s.Pool.Query()` calls
5. Add RBAC checks in repository methods where needed
