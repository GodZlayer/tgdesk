//go:build windows

package main

import (
	_ "embed"
	"encoding/binary"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"

	"golang.org/x/sys/windows"
)

// tgdeskvpnDLL contém os bytes vendorizados da DLL WireGuardNT (renomeada de
// wireguard.dll para tgdeskvpn.dll), embutidos no binário em tempo de
// compilação em vez de serem distribuídos como arquivo solto na pasta de
// instalação. É extraída em runtime para um diretório oculto sob ProgramData.
//
//go:embed tgdeskvpn.dll
var tgdeskvpnDLL []byte

// Public WireGuardNT wireguard.h ABI layouts.
type wireGuardNTInterface struct {
	Flags      uint32
	ListenPort uint16
	PrivateKey [32]byte
	PublicKey  [32]byte
	PeersCount uint32
	_          [4]byte
}

type wireGuardNTPeer struct {
	Flags               uint32
	_                   uint32
	PublicKey           [32]byte
	PresharedKey        [32]byte
	PersistentKeepalive uint16
	_                   uint16
	Endpoint            [28]byte
	TxBytes             uint64
	RxBytes             uint64
	LastHandshake       uint64
	AllowedIPsCount     uint32
	_                   [4]byte
}

type wireGuardNTAllowedIP struct {
	Address       [16]byte
	AddressFamily uint16
	CIDR          uint8
	_             uint8
	Flags         uint32
}

const (
	wgNTInterfaceHasPrivateKey = 1 << 1
	wgNTInterfaceReplacePeers  = 1 << 3
	wgNTPeerHasPublicKey       = 1 << 0
	wgNTPeerHasKeepalive       = 1 << 2
	wgNTPeerHasEndpoint        = 1 << 3
	wgNTPeerReplaceAllowedIPs  = 1 << 5
	wgNTAdapterUp              = 1
	wgNTAdapterDown            = 0
)

func stopWireGuardNT(name string) error {
	if err := wgNTDLL.Load(); err != nil {
		return err
	}
	name16, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return err
	}
	handle, _, callErr := wgNTOpenAdapter.Call(uintptr(unsafe.Pointer(name16)))
	if handle == 0 {
		return nil
	}
	result, _, callErr := wgNTSetAdapterState.Call(handle, wgNTAdapterDown)
	if result == 0 {
		return fmt.Errorf("desativar adaptador TGDesk: %w", callErr)
	}
	return nil
}

var (
	wgNTDLL              = windows.NewLazyDLL(wireGuardNTDLLPath())
	wgNTCreateAdapter    = wgNTDLL.NewProc("WireGuardCreateAdapter")
	wgNTOpenAdapter      = wgNTDLL.NewProc("WireGuardOpenAdapter")
	wgNTSetConfiguration = wgNTDLL.NewProc("WireGuardSetConfiguration")
	wgNTSetAdapterState  = wgNTDLL.NewProc("WireGuardSetAdapterState")
	wgNTHandlesMu        sync.Mutex
	wgNTHandles          []uintptr
)

// wireGuardNTHiddenDir retorna o diretório oculto usado para extrair
// binários internos do agente (mesmo padrão ProgramData\TGDesk\... usado em
// host.go/tgdeskDataDir e internal/updatecore.DataDir), num subdiretório
// "bin" dedicado a artefatos nativos que não devem ficar soltos e visíveis
// na pasta de instalação.
func wireGuardNTHiddenDir() string {
	if configured := os.Getenv("TGDESK_DATA_DIR"); configured != "" {
		return filepath.Join(configured, "bin")
	}
	base := os.Getenv("ProgramData")
	if base == "" {
		base = `C:\ProgramData`
	}
	return filepath.Join(base, "TGDesk", "bin")
}

// extractTGDeskVPNDLL grava os bytes embutidos de tgdeskvpn.dll no diretório
// oculto de dados do agente e retorna o caminho resultante. A escrita é
// atômica (arquivo temporário + rename) para evitar corrupção caso dois
// processos tentem extrair ao mesmo tempo. Se o arquivo já existir no
// destino com o mesmo tamanho, a extração é pulada.
func extractTGDeskVPNDLL() (string, error) {
	dir := wireGuardNTHiddenDir()
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", fmt.Errorf("criar diretório de dados do TGDesk: %w", err)
	}
	dest := filepath.Join(dir, "tgdeskvpn.dll")

	if info, err := os.Stat(dest); err == nil && info.Size() == int64(len(tgdeskvpnDLL)) {
		return dest, nil
	}

	tmp, err := os.CreateTemp(dir, "tgdeskvpn-*.dll.tmp")
	if err != nil {
		return "", fmt.Errorf("criar arquivo temporário para tgdeskvpn.dll: %w", err)
	}
	tmpPath := tmp.Name()
	_, writeErr := tmp.Write(tgdeskvpnDLL)
	closeErr := tmp.Close()
	if writeErr != nil {
		_ = os.Remove(tmpPath)
		return "", fmt.Errorf("gravar tgdeskvpn.dll: %w", writeErr)
	}
	if closeErr != nil {
		_ = os.Remove(tmpPath)
		return "", fmt.Errorf("fechar arquivo temporário de tgdeskvpn.dll: %w", closeErr)
	}
	if err := os.Rename(tmpPath, dest); err != nil {
		_ = os.Remove(tmpPath)
		return "", fmt.Errorf("mover tgdeskvpn.dll para destino final: %w", err)
	}
	return dest, nil
}

// wireGuardNTDLLPath extrai a DLL WireGuardNT embutida para o diretório
// oculto de dados do agente e retorna esse caminho, em vez de procurar um
// arquivo solto ao lado do executável. A extração roda de forma síncrona
// aqui, garantindo que o arquivo já exista em disco antes de wgNTDLL.Load()
// ser chamado.
func wireGuardNTDLLPath() string {
	dest, err := extractTGDeskVPNDLL()
	if err != nil {
		// Fallback: mantém compatibilidade com uma DLL solta ao lado do
		// executável, caso a extração para o diretório oculto falhe (ex.:
		// permissão negada), para não deixar o WireGuard totalmente
		// inoperante.
		if executable, execErr := os.Executable(); execErr == nil {
			return filepath.Join(filepath.Dir(executable), "tgdeskvpn.dll")
		}
		return "tgdeskvpn.dll"
	}
	return dest
}

func appendNativeStruct[T any](dst []byte, value *T) []byte {
	return append(dst, unsafe.Slice((*byte)(unsafe.Pointer(value)), unsafe.Sizeof(*value))...)
}

func wireGuardNTOpenOrCreate(name string, requestedGUID *windows.GUID) (uintptr, error) {
	name16, err := windows.UTF16PtrFromString(name)
	if err != nil {
		return 0, err
	}
	handle, _, _ := wgNTOpenAdapter.Call(uintptr(unsafe.Pointer(name16)))
	if handle != 0 {
		return handle, nil
	}
	tunnelType16, err := windows.UTF16PtrFromString("TGDesk")
	if err != nil {
		return 0, err
	}
	handle, _, callErr := wgNTCreateAdapter.Call(
		uintptr(unsafe.Pointer(name16)),
		uintptr(unsafe.Pointer(tunnelType16)),
		uintptr(unsafe.Pointer(requestedGUID)),
	)
	if handle == 0 {
		return 0, fmt.Errorf("WireGuardCreateAdapter(%s): %w", name, callErr)
	}
	return handle, nil
}

func resolveWireGuardEndpoint(endpoint string) ([28]byte, error) {
	var raw [28]byte
	host, portText, err := net.SplitHostPort(endpoint)
	if err != nil {
		return raw, fmt.Errorf("endpoint invÃ¡lido %q: %w", endpoint, err)
	}
	port, err := net.LookupPort("udp", portText)
	if err != nil {
		return raw, err
	}
	addresses, err := net.LookupIP(host)
	if err != nil {
		return raw, err
	}
	for _, address := range addresses {
		if ip4 := address.To4(); ip4 != nil {
			binary.LittleEndian.PutUint16(raw[0:2], windows.AF_INET)
			binary.BigEndian.PutUint16(raw[2:4], uint16(port))
			copy(raw[4:8], ip4)
			return raw, nil
		}
	}
	return raw, fmt.Errorf("endpoint %q nÃ£o possui endereÃ§o IPv4", endpoint)
}

func startWireGuardNT(name string, guid windows.GUID, privateKey, peerPublicKey wgKey, endpoint string) error {
	if err := wgNTDLL.Load(); err != nil {
		return fmt.Errorf("carregar tgdeskvpn.dll: %w", err)
	}
	handle, err := wireGuardNTOpenOrCreate(name, &guid)
	if err != nil {
		return err
	}
	rawEndpoint, err := resolveWireGuardEndpoint(endpoint)
	if err != nil {
		return err
	}

	interfaze := wireGuardNTInterface{
		Flags:      wgNTInterfaceHasPrivateKey | wgNTInterfaceReplacePeers,
		PrivateKey: [32]byte(privateKey),
		PeersCount: 1,
	}
	peer := wireGuardNTPeer{
		Flags: wgNTPeerHasPublicKey | wgNTPeerHasKeepalive |
			wgNTPeerHasEndpoint | wgNTPeerReplaceAllowedIPs,
		PublicKey:           [32]byte(peerPublicKey),
		PersistentKeepalive: 25,
		Endpoint:            rawEndpoint,
		AllowedIPsCount:     1,
	}
	allowed := wireGuardNTAllowedIP{AddressFamily: windows.AF_INET, CIDR: 16}
	copy(allowed.Address[:4], net.IPv4(10, 70, 0, 0).To4())

	config := make([]byte, 0, int(unsafe.Sizeof(interfaze)+unsafe.Sizeof(peer)+unsafe.Sizeof(allowed)))
	config = appendNativeStruct(config, &interfaze)
	config = appendNativeStruct(config, &peer)
	config = appendNativeStruct(config, &allowed)
	result, _, callErr := wgNTSetConfiguration.Call(handle, uintptr(unsafe.Pointer(&config[0])), uintptr(len(config)))
	runtime.KeepAlive(config)
	if result == 0 {
		return fmt.Errorf("WireGuardSetConfiguration(%s): %w", name, callErr)
	}
	result, _, callErr = wgNTSetAdapterState.Call(handle, wgNTAdapterUp)
	if result == 0 {
		return fmt.Errorf("WireGuardSetAdapterState(%s): %w", name, callErr)
	}
	wgNTHandlesMu.Lock()
	wgNTHandles = append(wgNTHandles, handle)
	wgNTHandlesMu.Unlock()
	return nil
}

var (
	tgdeskHostAdapterGUID = windows.GUID{Data1: 0x68176e21, Data2: 0xd43a, Data3: 0x4f50, Data4: [8]byte{0x8b, 0x18, 0x2e, 0xa8, 0xd4, 0xe0, 0x71, 0x01}}
	tgdeskTechAdapterGUID = windows.GUID{Data1: 0x68176e22, Data2: 0xd43a, Data3: 0x4f50, Data4: [8]byte{0x8b, 0x18, 0x2e, 0xa8, 0xd4, 0xe0, 0x71, 0x02}}
)
