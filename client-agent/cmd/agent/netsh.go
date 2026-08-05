package main

import (
	"log"
	"os/exec"
)

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

// hideAdapterFromWARP configures the tunnel adapter with a very high metric
// and disables automatic metric so that Cloudflare WARP and similar VPN/DNS
// interceptors treat it as irrelevant traffic. This prevents them from
// reacting (e.g., showing their GUI) when the adapter comes up.
//
// Without this, Windows broadcasts a network-change event that WARP listens
// for, causing it to pop up or reconfigure itself.
func hideAdapterFromWARP(ifaceName string) {
	// 1. Disable automatic metric and set a very high one (9999)
	//    This tells Windows "this adapter is low priority, don't care about it"
	cmd := exec.Command("netsh", "interface", "ip", "set", "interface",
		"name="+ifaceName, "metric=9999")
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("aviso: não foi possível definir métrica na interface %s: %v (output: %s)", ifaceName, err, out)
	} else {
		log.Printf("interface %s configurada com métrica 9999 (invisível para WARP)", ifaceName)
	}

	// 2. Disable automatic DNS configuration on the adapter
	//    Prevents WARP from intercepting DNS queries through this interface
	cmd = exec.Command("netsh", "interface", "ip", "set", "dns",
		"name="+ifaceName, "static", "0.0.0.0", "primary")
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("aviso: não foi possível configurar DNS na interface %s: %v (output: %s)", ifaceName, err, out)
	}

	// 3. Remove any default gateway that might have been added
	//    Ensures TGDesk traffic doesn't route through WARP
	cmd = exec.Command("netsh", "interface", "ip", "set", "address",
		"name="+ifaceName, "gateway=none")
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("aviso: não foi possível remover gateway da interface %s: %v (output: %s)", ifaceName, err, out)
	}
}
