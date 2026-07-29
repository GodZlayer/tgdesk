package main

import (
	"encoding/base64"
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
	Branding        BrandingState    `json:"branding"`
}

type BrandingState struct {
	Enabled       bool   `json:"enabled"`
	Name          string `json:"name"`
	LogoBase64    string `json:"logo_base64,omitempty"`
	FaviconBase64 string `json:"favicon_base64,omitempty"`
	UpdatedAt     string `json:"updated_at,omitempty"`
}

func syncBrandFavicon(branding BrandingState) {
	dir := filepath.Join(tgdeskDataDir(), "branding")
	target := filepath.Join(dir, "favicon.ico")
	if !branding.Enabled || branding.FaviconBase64 == "" {
		_ = os.Remove(target)
		return
	}
	data, err := base64.StdEncoding.DecodeString(branding.FaviconBase64)
	if err != nil || len(data) < 6 || data[0] != 0 || data[1] != 0 ||
		data[2] != 1 || data[3] != 0 {
		return
	}
	if os.MkdirAll(dir, 0700) != nil {
		return
	}
	temp := target + ".tmp"
	if os.WriteFile(temp, data, 0600) != nil {
		return
	}
	if os.Rename(temp, target) != nil {
		_ = os.Remove(temp)
	}
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
