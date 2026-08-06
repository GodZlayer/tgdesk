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
	// Esconder da WARP não pode significar deixar a interface inutilizável.
	//
	// Esta função nasceu com três passos, e dois deles quebravam a rede
	// privada: metric=9999, que faz a rota para 10.70.0.0/16 perder para
	// qualquer outra, e "gateway=none", que mexe na configuração de endereço da
	// interface recém-criada. O resultado era um adaptador de pé que nunca
	// fechava o aperto de mão com o hub.
	//
	// Foi por isso que toda máquina que atualizava para 1.1.50 ou mais perdia a
	// rede privada e via a atualização ser revertida: o adaptador antigo (de
	// antes desta função) fica com métrica automática 5 e funciona; o novo
	// nascia com 9999 e não alcançava o gateway.
	//
	// Sobra o passo que de fato serve ao propósito e não custa rota nenhuma: o
	// DNS estático, que impede a WARP de interceptar consultas por esta
	// interface. A métrica fica automática, como no adaptador que funciona.
	cmd := exec.Command("netsh", "interface", "ip", "set", "dns",
		"name="+ifaceName, "static", "0.0.0.0", "primary")
	if out, err := cmd.CombinedOutput(); err != nil {
		log.Printf("aviso: não foi possível configurar DNS na interface %s: %v (output: %s)", ifaceName, err, out)
	} else {
		log.Printf("interface %s com DNS próprio (não interceptável pela WARP)", ifaceName)
	}
}
