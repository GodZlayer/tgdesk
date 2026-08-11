#include "win32_window.h"

#include <flutter_windows.h>
#include <shobjidl_core.h>

#include "resource.h"

#include <cstdlib> // for getenv and _putenv
#include <cstring> // for strcmp
#include <string> // for std::wstring

namespace {

// Classe própria, e não a "FLUTTER_RUNNER_WIN32_WINDOW" do template.
// FindWindowW varre o sistema inteiro: com o nome padrão, qualquer outro app
// Flutter para Windows — o cliente Cloudflare WARP entre eles — casa na busca
// de instância única, e o TGDesk acabava trazendo a janela alheia para frente
// em vez da sua.
constexpr const wchar_t kWindowClassName[] = L"TGDESK_RUNNER_WIN32_WINDOW";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

// Static variable to hold the custom icon (needs cleanup on exit)
static HICON g_custom_icon_ = nullptr;

// Try to load icon from data\flutter_assets\assets\icon.ico if it exists.
// Returns nullptr if the file doesn't exist or can't be loaded.
HICON LoadCustomIcon() {
  if (g_custom_icon_ != nullptr) {
    return g_custom_icon_;
  }
  wchar_t program_data[MAX_PATH];
  DWORD program_data_length =
      GetEnvironmentVariableW(L"ProgramData", program_data, MAX_PATH);
  if (program_data_length > 0 && program_data_length < MAX_PATH) {
    std::wstring branded_icon(program_data);
    branded_icon += L"\\TGDesk\\branding\\favicon.ico";
    DWORD branded_attr = GetFileAttributesW(branded_icon.c_str());
    if (branded_attr != INVALID_FILE_ATTRIBUTES &&
        !(branded_attr & FILE_ATTRIBUTE_DIRECTORY) &&
        !(branded_attr & FILE_ATTRIBUTE_REPARSE_POINT)) {
      g_custom_icon_ = (HICON)LoadImageW(
          nullptr, branded_icon.c_str(), IMAGE_ICON, 0, 0,
          LR_LOADFROMFILE | LR_DEFAULTSIZE);
      if (g_custom_icon_ != nullptr) {
        return g_custom_icon_;
      }
    }
  }
  wchar_t exe_path[MAX_PATH];
  if (!GetModuleFileNameW(nullptr, exe_path, MAX_PATH)) {
    return nullptr;
  }

  std::wstring icon_path = exe_path;
  size_t last_slash = icon_path.find_last_of(L"\\/");
  if (last_slash == std::wstring::npos) {
    return nullptr;
  }

  icon_path = icon_path.substr(0, last_slash + 1);
  icon_path += L"data\\flutter_assets\\assets\\icon.ico";

  // Check file attributes - reject if missing, directory, or reparse point (symlink/junction)
  DWORD file_attr = GetFileAttributesW(icon_path.c_str());
  if (file_attr == INVALID_FILE_ATTRIBUTES ||
      (file_attr & FILE_ATTRIBUTE_DIRECTORY) ||
      (file_attr & FILE_ATTRIBUTE_REPARSE_POINT)) {
    return nullptr;
  }

  g_custom_icon_ = (HICON)LoadImageW(
      nullptr, icon_path.c_str(), IMAGE_ICON, 0, 0,
      LR_LOADFROMFILE | LR_DEFAULTSIZE);
  return g_custom_icon_;
}

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
    FreeLibrary(user32_module);
  }
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    
    // Try to load icon from data\flutter_assets\assets\icon.ico if it exists
    HICON custom_icon = LoadCustomIcon();
    if (custom_icon != nullptr) {
      window_class.hIcon = custom_icon;
    } else {
      window_class.hIcon =
          LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    }
    
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
  
  // Clean up the custom icon if it was loaded
  if (g_custom_icon_ != nullptr) {
    DestroyIcon(g_custom_icon_);
    g_custom_icon_ = nullptr;
  }
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::CreateAndShow(const std::wstring& title,
                                const Point& origin,
                                const Size& size, bool showOnTaskBar) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  ShowWindow(window, SW_SHOWNORMAL);
  UpdateWindow(window);

  if (!showOnTaskBar) {
    // hide from taskbar
    HRESULT hr;
    ITaskbarList* pTaskbarList;
    hr = CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER,IID_ITaskbarList,(void**)&pTaskbarList);
    if (FAILED(hr)) {
        return false;
    }
    hr = pTaskbarList->HrInit();
    hr = pTaskbarList->DeleteTab(window);
    hr = pTaskbarList->Release();
  }

  return OnCreate();
}

static void trySetWindowForeground(HWND window) {
    char* value = nullptr;
    size_t size = 0;
    // Use _dupenv_s to safely get the environment variable
    _dupenv_s(&value, &size, "SET_FOREGROUND_WINDOW");

    if (value != nullptr) {
        // Correctly compare the value with "1"
        if (strcmp(value, "1") == 0) {
            // Clear the environment variable
            _putenv("SET_FOREGROUND_WINDOW=");
            // Set the window to foreground
            SetForegroundWindow(window);
        }
        // Free the duplicated string
        free(value);
    }
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
    trySetWindowForeground(window);
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    // A faixa preta no topo em tela cheia.
    //
    // O window_manager entra em tela cheia MAXIMIZANDO a janela e só depois
    // tirando o WS_OVERLAPPEDWINDOW, e no mesmo SetWindowPos a leva para o
    // retângulo exato do monitor. Enquanto o Windows ainda a considera
    // maximizada, ele recua a área de cliente pela borda de redimensionamento
    // — uns 8px no topo. Como a barra de título é desenhada por nós
    // (TitleBarStyle.hidden), ninguém pinta essa faixa: ela fica preta.
    //
    // Contornar isso repetindo a transição, como se fazia, depende da ordem em
    // que as mensagens chegam, e por isso voltava a falhar. Aqui a resposta
    // vem da própria mensagem: se o retângulo PROPOSTO cobre exatamente um
    // monitor, isto é tela cheia por definição, e a área de cliente é a janela
    // inteira. Nenhum estado externo é consultado, então não há corrida.
    //
    // Janela apenas maximizada não entra aqui: o retângulo dela é MAIOR que o
    // do monitor, justamente pela borda.
    case WM_NCCALCSIZE: {
      if (wparam == TRUE) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        RECT proposed = params->rgrc[0];
        MONITORINFO monitor = {};
        monitor.cbSize = sizeof(monitor);
        if (GetMonitorInfo(MonitorFromRect(&proposed, MONITOR_DEFAULTTONEAREST),
                           &monitor) &&
            EqualRect(&proposed, &monitor.rcMonitor)) {
          // Sem tocar em rgrc[0]: área de cliente = retângulo da janela.
          return 0;
        }
      }
      break;
    }

    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    // The client area can change WITHOUT a WM_SIZE.
    //
    // WM_SIZE is only generated when the WINDOW rectangle changes size. A
    // SetWindowPos with SWP_FRAMECHANGED | SWP_NOSIZE -- which is what
    // window_manager issues when entering and leaving fullscreen -- only
    // changes the frame calculation: the window keeps its size while the
    // client area becomes a different rectangle. With no WM_SIZE the Flutter
    // view kept its previous size, larger than the window, so the app laid out
    // against a stale viewport: a black band on one side and clipped content
    // on the other.
    //
    // WM_WINDOWPOSCHANGED always arrives, and it arrives after WM_NCCALCSIZE,
    // so the client area is already final here. Refitting the child view at
    // this point keeps it matching the window no matter who resized it or how.
    //
    // No `return`: DefWindowProc still needs this message to generate the
    // WM_SIZE and WM_MOVE that other code depends on.
    case WM_WINDOWPOSCHANGED: {
      if (child_content_ != nullptr) {
        RECT rect = GetClientArea();
        // Only touch the child when it is actually out of date. This message
        // also arrives on every move, and repainting the view while the user
        // drags the window would be wasted work.
        RECT current = {};
        if (!GetWindowRect(child_content_, &current) ||
            (current.right - current.left) != (rect.right - rect.left) ||
            (current.bottom - current.top) != (rect.bottom - rect.top)) {
          MoveWindow(child_content_, rect.left, rect.top,
                     rect.right - rect.left, rect.bottom - rect.top, TRUE);
        }
      }
      break;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

const wchar_t* getWindowClassName() {
  return kWindowClassName;
}
