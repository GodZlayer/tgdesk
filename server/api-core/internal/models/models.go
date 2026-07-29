package models

import "time"

type Organization struct {
	ID                string    `json:"id"`
	Name              string    `json:"name"`
	Status            string    `json:"status"`
	OwnerTechnicianID *string   `json:"owner_technician_id,omitempty"`
	CanManage         bool      `json:"can_manage"`
	CreatedAt         time.Time `json:"created_at"`
}

type Network struct {
	ID             string    `json:"id"`
	OrganizationID string    `json:"organization_id"`
	Name           string    `json:"name"`
	CIDRVirtual    string    `json:"cidr_virtual,omitempty"`
	Status         string    `json:"status"`
	CreatedBy      *string   `json:"created_by_technician_id,omitempty"`
	CanManage      bool      `json:"can_manage"`
	CreatedAt      time.Time `json:"created_at"`
}

type Device struct {
	ID          string     `json:"id"`
	NetworkID   *string    `json:"network_id"`
	NetworkIDs  []string   `json:"network_ids"`
	Hostname    string     `json:"hostname"`
	DisplayName string     `json:"display_name,omitempty"`
	MAC         string     `json:"mac,omitempty"`
	WGPubkey    string     `json:"wg_pubkey,omitempty"`
	Role        string     `json:"role"`
	State       string     `json:"state"`
	PairingCode *string    `json:"pairing_code,omitempty"`
	DeviceToken string     `json:"device_token,omitempty"`
	RustdeskID  string     `json:"rustdesk_id,omitempty"`
	LastSeenAt  *time.Time `json:"last_seen_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	Presence    string     `json:"presence,omitempty"` // online | desligada | offline (calculado, não persistido)
	RemoteReady bool       `json:"remote_ready"`
	FilesReady  bool       `json:"files_ready"`
	HealthLevel string     `json:"health_level,omitempty"`
}

type Technician struct {
	ID            string    `json:"id"`
	Username      string    `json:"username"`
	PasswordHash  string    `json:"-"`
	Role          string    `json:"role"`
	CreatedViaEnv bool      `json:"created_via_env"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
}

type TechnicianAssignment struct {
	ID             string  `json:"id"`
	TechnicianID   string  `json:"technician_id"`
	OrganizationID *string `json:"organization_id"`
	NetworkID      *string `json:"network_id"`
}

type Session struct {
	ID           string     `json:"id"`
	DeviceID     string     `json:"device_id"`
	TechnicianID string     `json:"technician_id"`
	Tipo         string     `json:"tipo"`
	Inicio       time.Time  `json:"inicio"`
	Fim          *time.Time `json:"fim,omitempty"`
}

type AdminAction struct {
	ID        string    `json:"id"`
	ActorID   string    `json:"actor_id"`
	Tipo      string    `json:"tipo"`
	AlvoID    *string   `json:"alvo_id"`
	Detalhes  any       `json:"detalhes,omitempty"`
	Timestamp time.Time `json:"timestamp"`
}

const (
	RoleSuperAdmin = "super_admin"
	RoleTecnico    = "tecnico"

	DeviceStateGuest    = "guest"
	DeviceStateAtivo    = "ativo"
	DeviceStateSuspenso = "suspenso"

	StatusAtiva    = "ativa"
	StatusSuspensa = "suspensa"

	StatusAtivo    = "ativo"
	StatusSuspenso = "suspenso"
)
