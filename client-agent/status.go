package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
)

type tgdeskStatus struct {
	State           string           `json:"state"`
	Error           string           `json:"error,omitempty"`
	PairingCode     string           `json:"pairing_code,omitempty"`
	Hostname        string           `json:"hostname"`
	DeviceID        string           `json:"device_id,omitempty"`
	VirtualIP       string           `json:"virtual_ip,omitempty"`
	RustdeskID      string           `json:"rustdesk_id,omitempty"`
	TunnelUp        bool             `json:"tunnel_up"`
	Hardware        HardwareSnapshot `json:"hardware"`
	Statistics      any              `json:"statistics,omitempty"`
	CollectedAt     string           `json:"collected_at,omitempty"`
	RemoteReady     bool             `json:"remote_ready"`
	FilesReady      bool             `json:"files_ready"`
	RemoteError     string           `json:"remote_error,omitempty"`
	FilesError      string           `json:"files_error,omitempty"`
	CurrentVersion  string           `json:"current_version"`
	UpdateAvailable bool             `json:"update_available"`
	UpdateVersion   string           `json:"update_version,omitempty"`
}

var updateState struct {
	sync.RWMutex
	available bool
	version   string
}

func setServerUpdateVersion(version string) {
	updateState.Lock()
	updateState.version = version
	updateState.available = version != "" && version != currentClientVersion()
	updateState.Unlock()
}

func statusPath() string {
	return filepath.Join(tgdeskDataDir(), "state", "status.json")
}

func writeStatus(s tgdeskStatus) {
	s.CurrentVersion = currentClientVersion()
	updateState.RLock()
	s.UpdateAvailable = updateState.version != "" &&
		updateState.version != currentClientVersion()
	s.UpdateVersion = updateState.version
	updateState.RUnlock()
	b, err := json.MarshalIndent(s, "", "  ")
	if err == nil {
		_ = os.WriteFile(statusPath(), b, 0644)
	}
}
