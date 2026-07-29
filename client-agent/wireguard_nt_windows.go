//go:build windows

package main

import (
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

func wireGuardNTDLLPath() string {
	executable, err := os.Executable()
	if err != nil {
		return "wireguard.dll"
	}
	return filepath.Join(filepath.Dir(executable), "wireguard.dll")
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
		return raw, fmt.Errorf("endpoint inválido %q: %w", endpoint, err)
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
	return raw, fmt.Errorf("endpoint %q não possui endereço IPv4", endpoint)
}

func startWireGuardNT(name string, guid windows.GUID, privateKey, peerPublicKey wgKey, endpoint string) error {
	if err := wgNTDLL.Load(); err != nil {
		return fmt.Errorf("carregar wireguard.dll: %w", err)
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
