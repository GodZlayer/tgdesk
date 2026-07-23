package main

import "os/exec"

// assignWindowsIP sets the tunnel adapter's address using netsh (no external
// deps, ships with every Windows install).
func assignWindowsIP(ifaceName, ip string) error {
	cmd := exec.Command("netsh", "interface", "ip", "set", "address",
		"name="+ifaceName, "static", ip, "255.255.0.0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return err
	}
	_ = out
	return nil
}
