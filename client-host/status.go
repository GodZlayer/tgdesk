package main

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// tgdeskStatus is the small, well-known file the Flutter core (tgdesk.exe)
// polls to render its minimal window — this is the only channel between the
// Go agent (which owns the registration/pairing/WireGuard state machine) and
// the UI process, deliberately kept as a flat file instead of IPC/sockets.
type tgdeskStatus struct {
	State       string `json:"state"` // guest | ativo | suspenso
	PairingCode string `json:"pairing_code,omitempty"`
	Hostname    string `json:"hostname"`
	DeviceID    string `json:"device_id,omitempty"`
	VirtualIP   string `json:"virtual_ip,omitempty"`
	RustdeskID  string `json:"rustdesk_id,omitempty"`
	TunnelUp    bool   `json:"tunnel_up"`
}

func statusPath() string {
	exe, err := os.Executable()
	if err != nil {
		return "tgdesk-status.json"
	}
	return filepath.Join(filepath.Dir(exe), "tgdesk-status.json")
}

func writeStatus(s tgdeskStatus) {
	b, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(statusPath(), b, 0644)
}
