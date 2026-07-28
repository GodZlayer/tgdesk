package wg

import (
	"fmt"
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

	return &Hub{
		dev: dev, tunName: realName,
		privateKey: priv, PublicKey: priv.Public(), ListenPort: listenPort,
	}, nil
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
