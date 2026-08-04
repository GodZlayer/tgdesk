package wg

import (
	"fmt"
	"log"
	"os"
	"strings"

	"os/exec"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

// Hub is the server-side WireGuard interface — the "cloud controller" peer
// described in Seção 8.A. Every device connects to the hub as a spoke; full
// P2P mesh (rendezvous/relay) is Fase 2.
type Hub struct {
	dev        *device.Device
	tunName    string
	privateKey Key
	PublicKey  Key
	ListenPort int
}

// StartHub creates the wg0 interface, loads or generates the server's
// long-lived keypair at keyFile, and assigns hubCIDR (e.g. "10.70.0.1/16") to it.
func StartHub(keyFile string, listenPort int, hubCIDR string) (*Hub, error) {
	priv, err := loadOrCreateKey(keyFile)
	if err != nil {
		return nil, fmt.Errorf("chave do hub: %w", err)
	}

	tunDev, err := tun.CreateTUN("wg0", device.DefaultMTU)
	if err != nil {
		return nil, fmt.Errorf("criar tun wg0 (precisa de NET_ADMIN + /dev/net/tun): %w", err)
	}
	realName, _ := tunDev.Name()

	logger := device.NewLogger(device.LogLevelError, "wg-orchestrator: ")
	bind := conn.NewDefaultBind()
	dev := device.NewDevice(tunDev, bind, logger)

	uapi := fmt.Sprintf("private_key=%s\nlisten_port=%d\n", priv.Hex(), listenPort)
	if err := dev.IpcSet(uapi); err != nil {
		return nil, fmt.Errorf("configurar device wg: %w", err)
	}
	if err := dev.Up(); err != nil {
		return nil, fmt.Errorf("subir device wg: %w", err)
	}

	if err := assignInterfaceIP(realName, hubCIDR); err != nil {
		return nil, err
	}

	h := &Hub{
		dev: dev, tunName: realName,
		privateKey: priv, PublicKey: priv.Public(), ListenPort: listenPort,
	}
	if err := h.installPeerIsolation(); err != nil {
		// Não é fatal: o hub segue servindo. Mas o isolamento é requisito de
		// produto, então precisa aparecer no log em vez de falhar em silêncio.
		log.Printf("wg-orchestrator: isolamento entre peers NÃO aplicado (%v) — "+
			"dispositivos podem se alcançar diretamente pela VPN", err)
	}
	return h, nil
}

// peerChain concentra as regras de tráfego entre peers, para que o DROP padrão
// e as liberações temporárias de sessão vivam num lugar só e possam ser
// inspecionadas com `iptables -L TGDESK_PEERS`.
const peerChain = "TGDESK_PEERS"

// installPeerIsolation bloqueia, por padrão, todo tráfego de um peer para
// outro dentro da VPN.
//
// O modelo de produto define visibilidade por organização → rede → subrede, e
// a rede-base dos avulsos exige que os participantes não se enxerguem. Isso já
// era aplicado na camada de autorização (networks.peer_isolation), mas não na
// de rede: como todo cliente sobe o túnel com AllowedIPs 10.70.0.0/16, sem
// esta regra qualquer dispositivo alcança qualquer outro por IP.
//
// Tráfego peer → hub (API, controle, telemetria, rendezvous e relay, todos em
// 10.70.0.1) é entrega local e não passa por FORWARD, então não é afetado.
// Sessões de acesso remoto que precisem de rota direta são liberadas caso a
// caso por AllowSessionPair.
func (h *Hub) installPeerIsolation() error {
	// Idempotente: a chain é recriada a cada boot para não acumular regras
	// órfãs de sessões que ficaram abertas num processo anterior.
	_ = runCmd("iptables", "-D", "FORWARD", "-i", h.tunName, "-o", h.tunName, "-j", peerChain)
	_ = runCmd("iptables", "-F", peerChain)
	_ = runCmd("iptables", "-X", peerChain)
	if err := runCmd("iptables", "-N", peerChain); err != nil {
		return err
	}
	if err := runCmd("iptables", "-A", peerChain, "-j", "DROP"); err != nil {
		return err
	}
	return runCmd("iptables", "-I", "FORWARD", "1",
		"-i", h.tunName, "-o", h.tunName, "-j", peerChain)
}

// ApplySessionPairs reescreve a chain para liberar exatamente os pares
// informados — a "subrede temporária de sessão" do modelo de produto — e
// bloquear todo o resto.
//
// É deliberadamente uma reconciliação do conjunto inteiro, não um par de
// operações abrir/fechar. Regra de firewall que depende de receber o evento de
// fechamento vaza sempre que o evento se perde: permissão que expira sozinha,
// processo reiniciado no meio de uma sessão, erro no caminho de revogação. Aqui
// o estado do firewall é sempre derivado das permissões ativas no banco, então
// qualquer divergência se corrige na próxima passada.
func (h *Hub) ApplySessionPairs(pairs [][2]string) error {
	if err := runCmd("iptables", "-F", peerChain); err != nil {
		return err
	}
	for _, p := range pairs {
		if p[0] == "" || p[1] == "" {
			continue
		}
		for _, d := range [][2]string{{p[0], p[1]}, {p[1], p[0]}} {
			if err := runCmd("iptables", "-A", peerChain,
				"-s", d[0]+"/32", "-d", d[1]+"/32", "-j", "ACCEPT"); err != nil {
				return err
			}
		}
	}
	return runCmd("iptables", "-A", peerChain, "-j", "DROP")
}

func assignInterfaceIP(ifaceName, cidr string) error {
	if err := runCmd("ip", "addr", "add", cidr, "dev", ifaceName); err != nil {
		return err
	}
	return runCmd("ip", "link", "set", "up", "dev", ifaceName)
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %w (%s)", name, strings.Join(args, " "), err, string(out))
	}
	return nil
}

func loadOrCreateKey(path string) (Key, error) {
	if b, err := os.ReadFile(path); err == nil {
		return KeyFromBase64(strings.TrimSpace(string(b)))
	}
	k, err := GenerateKey()
	if err != nil {
		return Key{}, err
	}
	if err := os.WriteFile(path, []byte(k.Base64()), 0600); err != nil {
		return Key{}, err
	}
	return k, nil
}

// AddPeer authorizes a device to use exactly allowedIP/32 as its tunnel address.
func (h *Hub) AddPeer(pubKeyBase64, allowedIP string) error {
	pub, err := KeyFromBase64(pubKeyBase64)
	if err != nil {
		return err
	}
	uapi := fmt.Sprintf("public_key=%s\nallowed_ip=%s/32\n", pub.Hex(), allowedIP)
	return h.dev.IpcSet(uapi)
}

// RemovePeer drops a peer from the private network immediately.
func (h *Hub) RemovePeer(pubKeyBase64 string) error {
	pub, err := KeyFromBase64(pubKeyBase64)
	if err != nil {
		return err
	}
	uapi := fmt.Sprintf("public_key=%s\nremove=true\n", pub.Hex())
	return h.dev.IpcSet(uapi)
}

func (h *Hub) Close() {
	h.dev.Close()
}
