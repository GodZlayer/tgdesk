//go:build windows

package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/windows"
	"tgdesk/agent/internal/updatecore"
)

const (
	wmDestroy      = 0x0002
	wmClose        = 0x0010
	wsOverlapped   = 0x00CF0000
	wsCaption      = 0x00C00000
	wsSysMenu      = 0x00080000
	wsChild        = 0x40000000
	wsVisible      = 0x10000000
	wsExTopmost    = 0x00000008
	ssCenter       = 0x00000001
	cwUseDefault   = 0x80000000
	swShow         = 5
	pbmSetRange32  = 0x0406
	pbmSetPos      = 0x0402
	colorWindow    = 5
	idiApplication = 32512
	idcArrow       = 32512
)

type point struct{ x, y int32 }
type message struct {
	hwnd    windows.Handle
	message uint32
	wParam  uintptr
	lParam  uintptr
	time    uint32
	pt      point
}
type wndClassEx struct {
	size, style  uint32
	wndProc      uintptr
	clsExtra     int32
	wndExtra     int32
	instance     windows.Handle
	icon, cursor windows.Handle
	background   windows.Handle
	menuName     *uint16
	className    *uint16
	iconSmall    windows.Handle
}

var (
	user32              = windows.NewLazySystemDLL("user32.dll")
	kernel32            = windows.NewLazySystemDLL("kernel32.dll")
	comctl32            = windows.NewLazySystemDLL("comctl32.dll")
	procDefWindowProc   = user32.NewProc("DefWindowProcW")
	procRegisterClass   = user32.NewProc("RegisterClassExW")
	procCreateWindow    = user32.NewProc("CreateWindowExW")
	procShowWindow      = user32.NewProc("ShowWindow")
	procUpdateWindow    = user32.NewProc("UpdateWindow")
	procSetForeground   = user32.NewProc("SetForegroundWindow")
	procGetMessage      = user32.NewProc("GetMessageW")
	procTranslate       = user32.NewProc("TranslateMessage")
	procDispatch        = user32.NewProc("DispatchMessageW")
	procPostQuit        = user32.NewProc("PostQuitMessage")
	procDestroyWindow   = user32.NewProc("DestroyWindow")
	procSetWindowText   = user32.NewProc("SetWindowTextW")
	procSendMessage     = user32.NewProc("SendMessageW")
	procPostMessage     = user32.NewProc("PostMessageW")
	procMessageBox      = user32.NewProc("MessageBoxW")
	procLoadIcon        = user32.NewProc("LoadIconW")
	procLoadCursor      = user32.NewProc("LoadCursorW")
	procGetModuleHandle = kernel32.NewProc("GetModuleHandleW")
	procInitControls    = comctl32.NewProc("InitCommonControls")
	windowFinished      atomic.Bool
)

type updaterWindow struct {
	hwnd, label, detail, progress windows.Handle
	ready                         chan struct{}
	createError                   error
}

func utf16(value string) *uint16 { return windows.StringToUTF16Ptr(value) }

func updaterWndProc(hwnd windows.Handle, msg uint32, wParam, lParam uintptr) uintptr {
	switch msg {
	case wmClose:
		if windowFinished.Load() {
			procDestroyWindow.Call(uintptr(hwnd))
		}
		return 0
	case wmDestroy:
		procPostQuit.Call(0)
		return 0
	default:
		result, _, _ := procDefWindowProc.Call(uintptr(hwnd), uintptr(msg), wParam, lParam)
		return result
	}
}

func createChild(className, text string, style uint32, x, y, width, height int32,
	parent windows.Handle) windows.Handle {
	hwnd, _, _ := procCreateWindow.Call(0, uintptr(unsafe.Pointer(utf16(className))),
		uintptr(unsafe.Pointer(utf16(text))), uintptr(style), uintptr(x), uintptr(y),
		uintptr(width), uintptr(height), uintptr(parent), 0, 0, 0)
	return windows.Handle(hwnd)
}

func newUpdaterWindow() (*updaterWindow, error) {
	w := &updaterWindow{ready: make(chan struct{})}
	go w.run()
	<-w.ready
	if w.createError != nil {
		return nil, w.createError
	}
	return w, nil
}

func (w *updaterWindow) run() {
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	procInitControls.Call()
	instance, _, _ := procGetModuleHandle.Call(0)
	className := utf16("TGDeskUpdaterStatusWindow")
	icon, _, _ := procLoadIcon.Call(0, idiApplication)
	cursor, _, _ := procLoadCursor.Call(0, idcArrow)
	wc := wndClassEx{
		size: uint32(unsafe.Sizeof(wndClassEx{})), wndProc: syscall.NewCallback(updaterWndProc),
		instance: windows.Handle(instance), icon: windows.Handle(icon), cursor: windows.Handle(cursor),
		background: windows.Handle(colorWindow + 1), className: className, iconSmall: windows.Handle(icon),
	}
	procRegisterClass.Call(uintptr(unsafe.Pointer(&wc)))
	hwnd, _, createErr := procCreateWindow.Call(wsExTopmost, uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(utf16("Atualizacao do TGDesk"))), wsOverlapped&^(wsSysMenu^wsSysMenu)|wsCaption|wsSysMenu,
		cwUseDefault, cwUseDefault, 520, 220, 0, 0, instance, 0)
	w.hwnd = windows.Handle(hwnd)
	if w.hwnd == 0 {
		w.createError = fmt.Errorf("nao foi possivel abrir a janela do atualizador: %v", createErr)
		close(w.ready)
		return
	}
	w.label = createChild("STATIC", "Atualizando o TGDesk", wsChild|wsVisible|ssCenter, 25, 28, 455, 28, w.hwnd)
	w.detail = createChild("STATIC", "Preparando a atualizacao...", wsChild|wsVisible|ssCenter, 25, 70, 455, 42, w.hwnd)
	w.progress = createChild("msctls_progress32", "", wsChild|wsVisible, 45, 125, 415, 22, w.hwnd)
	procSendMessage.Call(uintptr(w.progress), pbmSetRange32, 0, 100)
	procShowWindow.Call(uintptr(w.hwnd), swShow)
	procUpdateWindow.Call(uintptr(w.hwnd))
	procSetForeground.Call(uintptr(w.hwnd))
	close(w.ready)
	var msg message
	for {
		ret, _, _ := procGetMessage.Call(uintptr(unsafe.Pointer(&msg)), 0, 0, 0)
		if int32(ret) <= 0 {
			return
		}
		procTranslate.Call(uintptr(unsafe.Pointer(&msg)))
		procDispatch.Call(uintptr(unsafe.Pointer(&msg)))
	}
}

func (w *updaterWindow) update(event updatecore.ProgressEvent) {
	procSetWindowText.Call(uintptr(w.detail), uintptr(unsafe.Pointer(utf16(event.Message))))
	procSendMessage.Call(uintptr(w.progress), pbmSetPos, uintptr(event.Percent), 0)
}

func (w *updaterWindow) complete() {
	log.Println("update: concluido com sucesso")
	w.update(updatecore.ProgressEvent{Percent: 100, Message: "Atualizacao concluida. O TGDesk foi iniciado."})
	time.Sleep(1800 * time.Millisecond)
	windowFinished.Store(true)
	procPostMessage.Call(uintptr(w.hwnd), wmClose, 0, 0)
}

func (w *updaterWindow) fail(err error) {
	log.Printf("update: FALHOU: %v", err)
	w.update(updatecore.ProgressEvent{Percent: 100, Message: "A atualizacao falhou. A versao anterior foi preservada."})
	procMessageBox.Call(uintptr(w.hwnd), uintptr(unsafe.Pointer(utf16(err.Error()))),
		uintptr(unsafe.Pointer(utf16("Falha na atualizacao do TGDesk"))), 0x10)
	windowFinished.Store(true)
	procPostMessage.Call(uintptr(w.hwnd), wmClose, 0, 0)
}

func openUpdaterLog() *os.File {
	base := os.Getenv("ProgramData")
	if base == "" {
		base = `C:\ProgramData`
	}
	logDir := filepath.Join(base, "TGDesk", "logs")
	_ = os.MkdirAll(logDir, 0755)
	logFile, err := os.OpenFile(filepath.Join(logDir, "update.log"),
		os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil
	}
	log.SetOutput(logFile)
	return logFile
}

func runApplyStagedWithStatus(staging, installDir string, parentPID uint32, readyFile string) error {
	if logFile := openUpdaterLog(); logFile != nil {
		defer logFile.Close()
	}
	log.Printf("update: tgdesk-updater.exe iniciado (staging=%s install-dir=%s parent=%d)",
		staging, installDir, parentPID)
	windowFinished.Store(false)
	w, windowErr := newUpdaterWindow()
	if windowErr != nil {
		return windowErr
	}
	if readyFile != "" {
		if err := os.WriteFile(readyFile, []byte("visible\n"), 0600); err != nil {
			w.fail(fmt.Errorf("Nao foi possivel confirmar a janela do atualizador: %w", err))
			return err
		}
	}
	err := updatecore.ApplyStagedOfflineWithProgress(staging, installDir, parentPID, w.update)
	if err != nil {
		w.fail(fmt.Errorf("Nao foi possivel atualizar o TGDesk: %w", err))
		return err
	}
	w.complete()
	return nil
}
