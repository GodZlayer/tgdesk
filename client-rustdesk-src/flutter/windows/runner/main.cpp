#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <tchar.h>
#include <uni_links_desktop/uni_links_desktop_plugin.h>
#include <windows.h>

#include <algorithm>
#include <fstream>
#include <iostream>
#include <memory>

#include "win32_desktop.h"
#include "flutter_window.h"
#include "utils.h"

typedef char** (*FUNC_RUSTDESK_CORE_MAIN)(int*);
typedef void (*FUNC_RUSTDESK_FREE_ARGS)( char**, int);
typedef int (*FUNC_RUSTDESK_GET_APP_NAME)(wchar_t*, int);
typedef int (*FUNC_RUSTDESK_IS_DISABLE_INSTALLATION)();
typedef int (*FUNC_TGDESK_AGENT_HOST)(const char*, const char*);
typedef int (*FUNC_TGDESK_AGENT_TECHNICIAN)(const char*, const char*);
typedef int (*FUNC_TGDESK_AGENT_TECHNICIAN_SERVICE)(const char*);
typedef int (*FUNC_TGDESK_AGENT_UPDATE)(int);
typedef int (*FUNC_TGDESK_AGENT_APPLY_STAGED)(const char*, const char*, int);
/// Note: `--server`, `--service` are already handled in [core_main.rs].
// Background remote-session roles must never own the interactive UI mutex.
// The Windows service keeps `--server` alive in the user session; allowing it
// through the UI singleton gate leaves the no-argument TGDesk window free to
// start and acquire Global\TGDesk.UI.<session>.
// --option e --password entram aqui porque NAO abrem interface nenhuma: sao
// consultas de linha de comando ao nucleo, feitas pelo agente para configurar
// o acesso remoto (ver client-agent/cmd/agent/remote_access.go).
//
// Sem isso elas batiam no mutex da UI e saiam ANTES de imprimir qualquer coisa
// sempre que a janela do TGDesk estivesse aberta. O agente lia a resposta
// vazia, concluia "o nucleo remoto nao confirmou custom-rendezvous-server", e
// marcava o dispositivo como sem acesso remoto — o botao de acesso remoto
// simplesmente sumia da lista, e so voltava se ninguem estivesse com o TGDesk
// aberto na hora certa.
const std::vector<std::string> parameters_white_list = {
    "--install", "--cm",     "--server",   "--tray",
    "--option",  "--password", "--get-id"};

const wchar_t* getWindowClassName();

struct TgdeskServiceHostContext {
  FUNC_TGDESK_AGENT_HOST start_host;
  std::string core_exe;
};

DWORD WINAPI StartTgdeskServiceHost(LPVOID parameter) {
  std::unique_ptr<TgdeskServiceHostContext> context(
      static_cast<TgdeskServiceHostContext*>(parameter));
  return static_cast<DWORD>(
      context->start_host("", context->core_exe.c_str()));
}

static void DebugLaunchLog(const std::string& message) {
  std::ofstream f("C:\\ProgramData\\TGDesk\\logs\\debug-launch.log",
                   std::ios::app);
  if (f.is_open()) {
    f << message << std::endl;
  }
}

// Caminho completo do executável de um processo, vazio se não der para ler.
static std::wstring ProcessImagePath(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    return std::wstring();
  }
  wchar_t path[MAX_PATH] = {0};
  DWORD size = MAX_PATH;
  const BOOL ok = ::QueryFullProcessImageNameW(process, 0, path, &size);
  ::CloseHandle(process);
  return ok ? std::wstring(path, size) : std::wstring();
}

// Janela de outra instância do MESMO executável.
//
// FindWindowW sozinho não serve: ele busca em todo o sistema, e a classe de
// janela não é garantia de identidade — apps de terceiros podem registrar a
// mesma. Aqui a janela só é aceita depois que o processo dono dela prova ser
// o mesmo binário que está rodando agora.
static HWND FindOwnInstanceWindow(const wchar_t* title) {
  wchar_t self[MAX_PATH] = {0};
  const DWORD self_len = ::GetModuleFileNameW(nullptr, self, MAX_PATH);
  if (self_len == 0 || self_len >= MAX_PATH) {
    return nullptr;
  }
  const std::wstring self_path(self, self_len);
  const DWORD self_pid = ::GetCurrentProcessId();

  HWND candidate = nullptr;
  while ((candidate = ::FindWindowExW(nullptr, candidate, getWindowClassName(),
                                      title)) != nullptr) {
    DWORD pid = 0;
    ::GetWindowThreadProcessId(candidate, &pid);
    if (pid == 0 || pid == self_pid) {
      continue;
    }
    if (ProcessImagePath(pid) == self_path) {
      return candidate;
    }
  }
  return nullptr;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  DebugLaunchLog("=== wWinMain entered ===");
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  DebugLaunchLog("GetCommandLineArguments returned " +
                  std::to_string(command_line_arguments.size()) + " args");
  const auto find_value = [&command_line_arguments](const std::string& name) {
    for (size_t i = 0; i + 1 < command_line_arguments.size(); ++i) {
      if (command_line_arguments[i] == name) return command_line_arguments[i + 1];
    }
    return std::string();
  };
  const bool tgdesk_host =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-host") != command_line_arguments.end();
  const bool tgdesk_technician =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-technician") != command_line_arguments.end();
  const bool tgdesk_technician_service =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-technician-service") != command_line_arguments.end();
  const bool tgdesk_update =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-update") != command_line_arguments.end();
  const bool tgdesk_update_check =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-update-check") != command_line_arguments.end();
  const bool tgdesk_apply_update =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tgdesk-apply-update") != command_line_arguments.end();
  const bool tgdesk_tray =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--tray") != command_line_arguments.end();
  const bool rustdesk_service =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--service") != command_line_arguments.end();
  if (tgdesk_host || tgdesk_technician || tgdesk_technician_service || tgdesk_update ||
      tgdesk_update_check || tgdesk_apply_update) {
    HINSTANCE agent = LoadLibraryA("tgdesk_agent.dll");
    if (!agent) return EXIT_FAILURE;
    const std::string server = find_value("--server");
    if (tgdesk_host) {
      auto start_host = reinterpret_cast<FUNC_TGDESK_AGENT_HOST>(
          GetProcAddress(agent, "TGDeskAgentHost"));
      if (!start_host) return EXIT_FAILURE;
      const std::string core_exe = find_value("--core-exe");
      return start_host(server.c_str(), core_exe.c_str());
    }
    if (tgdesk_technician) {
      auto start_technician = reinterpret_cast<FUNC_TGDESK_AGENT_TECHNICIAN>(
          GetProcAddress(agent, "TGDeskAgentTechnician"));
      if (!start_technician) return EXIT_FAILURE;
      const std::string token = find_value("--token");
      return start_technician(server.c_str(), token.c_str());
    }
    if (tgdesk_technician_service) {
      auto start_technician_service =
          reinterpret_cast<FUNC_TGDESK_AGENT_TECHNICIAN_SERVICE>(
              GetProcAddress(agent, "TGDeskAgentTechnicianService"));
      if (!start_technician_service) return EXIT_FAILURE;
      return start_technician_service(server.c_str());
    }
    if (tgdesk_apply_update) {
      auto apply = reinterpret_cast<FUNC_TGDESK_AGENT_APPLY_STAGED>(
          GetProcAddress(agent, "TGDeskAgentApplyStaged"));
      if (!apply) return EXIT_FAILURE;
      const std::string staging = find_value("--staging");
      const std::string install_dir = find_value("--install-dir");
      const std::string parent = find_value("--parent");
      return apply(staging.c_str(), install_dir.c_str(),
                   parent.empty() ? 0 : std::stoi(parent));
    }
    auto update = reinterpret_cast<FUNC_TGDESK_AGENT_UPDATE>(
        GetProcAddress(agent, "TGDeskAgentUpdate"));
    if (!update) return EXIT_FAILURE;
    return update(tgdesk_update_check ? 1 : 0);
  }

  // The same Windows service owns both the remote core and the TGDesk host
  // agent. Running the host here gives it LocalSystem privileges, which are
  // required to configure unattended access and capture elevated UAC windows.
  if (rustdesk_service) {
    HINSTANCE agent = LoadLibraryA("tgdesk_agent.dll");
    if (agent) {
      auto start_host = reinterpret_cast<FUNC_TGDESK_AGENT_HOST>(
          GetProcAddress(agent, "TGDeskAgentHost"));
      if (start_host) {
        char exe_path[MAX_PATH] = {};
        if (GetModuleFileNameA(nullptr, exe_path, MAX_PATH) > 0) {
          auto context = new TgdeskServiceHostContext{
              start_host, std::string(exe_path)};
          HANDLE host_thread =
              CreateThread(nullptr, 0, StartTgdeskServiceHost, context, 0, nullptr);
          if (host_thread) {
            CloseHandle(host_thread);
          } else {
            delete context;
          }
        }
      }
    }
  }

  // --tray is whitelisted out of the main UI mutex below on purpose (the
  // full window and the tray helper must coexist), but that left tray
  // launches with NO singleton protection of their own: every relaunch
  // (reinstall, reboot, manual double-click) spawned one more --tray
  // process that never got cleaned up, and multiple copies independently
  // fighting over the same WireGuard/Wintun adapter produced exactly the
  // intermittent "network unreachable" failures seen in the field — not a
  // real internet problem. Give tray its own dedicated singleton.
  if (tgdesk_tray) {
    DWORD tray_session_id = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &tray_session_id);
    const std::wstring tray_mutex_name =
        L"Global\\TGDesk.Tray." + std::to_wstring(tray_session_id);
    HANDLE tray_mutex = CreateMutexW(nullptr, FALSE, tray_mutex_name.c_str());
    if (!tray_mutex || WaitForSingleObject(tray_mutex, 500) != WAIT_OBJECT_0) {
      DebugLaunchLog("Tray singleton already held by another process. Exiting.");
      if (tray_mutex) CloseHandle(tray_mutex);
      return EXIT_SUCCESS;
    }
    DebugLaunchLog("Tray singleton acquired.");
    // Intentionally leak tray_mutex: it must stay held for the whole
    // process lifetime, released automatically by Windows on exit.
  }

  // Enforce one interactive TGDesk UI per Windows session independently of
  // the current window title/branding. Named mutex with explicit ownership
  // pattern prevents race conditions during rapid startup attempts.
  const bool allow_multiple_ui =
      std::any_of(parameters_white_list.begin(), parameters_white_list.end(),
                  [&command_line_arguments](const std::string& parameter) {
                    return std::find(command_line_arguments.begin(),
                                     command_line_arguments.end(),
                                     parameter) != command_line_arguments.end();
                  });
  HANDLE tgdesk_ui_mutex = nullptr;
  if (!rustdesk_service && !allow_multiple_ui) {
    DWORD session_id = 0;
    ProcessIdToSessionId(GetCurrentProcessId(), &session_id);
    const std::wstring mutex_name =
        L"Global\\TGDesk.UI." + std::to_wstring(session_id);
    // Attempt to acquire singleton mutex for UI process.
    tgdesk_ui_mutex = CreateMutexW(nullptr, FALSE, mutex_name.c_str());
    if (!tgdesk_ui_mutex) {
      return EXIT_FAILURE;
    }
    DWORD wait_result = WaitForSingleObject(tgdesk_ui_mutex, 1000);
    if (wait_result != WAIT_OBJECT_0) {
      // Another instance owns the mutex or timeout occurred.
      DebugLaunchLog("Mutex wait FAILED/timeout (wait_result=" +
                      std::to_string(wait_result) +
                      ") - another instance may hold it. Exiting silently.");
      HWND existing = FindOwnInstanceWindow(nullptr);
      if (existing) {
        DebugLaunchLog("Found existing TGDesk window, bringing to foreground.");
        ::ShowWindow(existing, SW_MAXIMIZE);
        ::SetForegroundWindow(existing);
      } else {
        DebugLaunchLog("No existing TGDesk window found.");
      }
      CloseHandle(tgdesk_ui_mutex);
      return EXIT_SUCCESS;
    } else {
      DebugLaunchLog("Mutex acquired successfully.");
    }
  } else {
    DebugLaunchLog("Skipped mutex check (rustdesk_service=" +
                    std::to_string(rustdesk_service) + ", allow_multiple_ui=" +
                    std::to_string(allow_multiple_ui) + ")");
  }

  DebugLaunchLog("About to LoadLibraryA(libtgdeskcore.dll)");
  HINSTANCE hInstance = LoadLibraryA("libtgdeskcore.dll");
  if (!hInstance)
  {
    DebugLaunchLog("LoadLibraryA FAILED, GetLastError=" +
                    std::to_string(GetLastError()));
    std::cout << "Failed to load libtgdeskcore.dll." << std::endl;
    return EXIT_FAILURE;
  }
  DebugLaunchLog("LoadLibraryA succeeded");
  FUNC_RUSTDESK_CORE_MAIN rustdesk_core_main =
      (FUNC_RUSTDESK_CORE_MAIN)GetProcAddress(hInstance, "rustdesk_core_main_args");
  if (!rustdesk_core_main)
  {
    std::cout << "Failed to get rustdesk_core_main." << std::endl;
    return EXIT_FAILURE;
  }
  FUNC_RUSTDESK_FREE_ARGS free_c_args =
      (FUNC_RUSTDESK_FREE_ARGS)GetProcAddress(hInstance, "free_c_args");
  if (!free_c_args)
  {
    std::cout << "Failed to get free_c_args." << std::endl;
    return EXIT_FAILURE;
  }
  // Remove possible trailing whitespace from command line arguments
  //
  // O `+ 1` não é detalhe: find_last_not_of devolve o ÍNDICE do último
  // caractere que se quer MANTER, e erase(pos) apaga a partir de pos. Sem ele,
  // todo argumento perdia a própria última letra — `--option` virava `--optio`,
  // `--cm` virava `--c`, `10.70.0.1` virava `10.70.0.`.
  //
  // O estrago não era no log. Este vetor ainda é usado depois em três lugares:
  // a segunda checagem da lista branca (que decide se uma segunda instância
  // pode existir), a detecção da página `--cm`, e os argumentos entregues ao
  // Dart. Com `--option` truncado, toda escrita de opção pelo agente caía no
  // ramo de "já existe janela, trazer para frente": a opção era descartada e a
  // janela pulava para a frente do usuário. O debug-launch.log ficava com
  // centenas de "Found existing window, bringing to foreground." seguidas.
  //
  // npos + 1 == 0, então argumento só de espaços continua virando string
  // vazia, que é o comportamento desejado.
  for (auto& argument : command_line_arguments) {
    argument.erase(argument.find_last_not_of(" \n\r\t") + 1);
  }

  DebugLaunchLog("About to call rustdesk_core_main");
  int args_len = 0;
  char** c_args = rustdesk_core_main(&args_len);
  if (!c_args)
  {
    std::string args_str = "";
    for (const auto& argument : command_line_arguments) {
      args_str += (argument + " ");
    }
    DebugLaunchLog("rustdesk_core_main returned NULL (core decided not to "
                    "launch Flutter) for args: [" + args_str + "]");
    // std::cout << "RustDesk [" << args_str << "], core returns false, exiting without launching Flutter app." << std::endl;
    return EXIT_SUCCESS;
  }
  DebugLaunchLog("rustdesk_core_main returned " + std::to_string(args_len) +
                  " args, proceeding to launch Flutter");
  std::vector<std::string> rust_args(c_args, c_args + args_len);
  free_c_args(c_args, args_len);
  FUNC_RUSTDESK_IS_DISABLE_INSTALLATION rustdesk_is_disable_installation =
      (FUNC_RUSTDESK_IS_DISABLE_INSTALLATION)GetProcAddress(hInstance, "rustdesk_is_disable_installation");
  bool is_disable_installation =
      rustdesk_is_disable_installation && rustdesk_is_disable_installation() != 0;
  const auto installParam = std::string("--install");
  // Flutter reads the original process command line, not only rust_args, so
  // remove the `--install` injected by the portable wrapper here as well. This
  // also lets `no-install.exe` continue as a portable app when installation is
  // disabled. See: https://github.com/rustdesk/rustdesk-server-pro/issues/991#issuecomment-4978376890
  if (is_disable_installation) {
    command_line_arguments.erase(
        std::remove(command_line_arguments.begin(),
                    command_line_arguments.end(),
                    installParam),
        command_line_arguments.end());
  }

  std::wstring app_name = L"RustDesk";
  FUNC_RUSTDESK_GET_APP_NAME get_rustdesk_app_name = (FUNC_RUSTDESK_GET_APP_NAME)GetProcAddress(hInstance, "get_rustdesk_app_name");
  if (get_rustdesk_app_name) {
    wchar_t app_name_buffer[512] = {0};
    if (get_rustdesk_app_name(app_name_buffer, 512) == 0) {
      app_name = std::wstring(app_name_buffer);
    }
  }
  // Uri links dispatch
  DebugLaunchLog("About to look for an existing instance");
  HWND hwnd = FindOwnInstanceWindow(app_name.c_str());
  DebugLaunchLog(hwnd != NULL
                     ? "Found an EXISTING TGDesk window - may exit here"
                     : "No existing TGDesk window, continuing");
  if (hwnd != NULL) {
    // Allow multiple flutter instances when being executed by parameters
    // contained in whitelists.
    bool allow_multiple_instances = false;
    for (auto& whitelist_param : parameters_white_list) {
      allow_multiple_instances =
          allow_multiple_instances ||
          std::find(command_line_arguments.begin(),
                    command_line_arguments.end(),
                    whitelist_param) != command_line_arguments.end();
    }
    if (!allow_multiple_instances) {
      if (!command_line_arguments.empty()) {
        // Dispatch command line arguments
        DispatchToUniLinksDesktop(hwnd);
      } else {
        // Not called with arguments, or just open the app shortcut on desktop.
        // So we just show the main window instead.
        ::ShowWindow(hwnd, SW_NORMAL);
        ::SetForegroundWindow(hwnd);
      }
      return EXIT_FAILURE;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // connection manager hide icon from taskbar
  bool is_cm_page = false;
  auto cmParam = std::string("--cm");
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, cmParam.size(), cmParam.c_str()) == 0) {
    is_cm_page = true;
  }
  bool is_install_page = false;
  if (!command_line_arguments.empty() && command_line_arguments.front().compare(0, installParam.size(), installParam.c_str()) == 0) {
    is_install_page = true;
  }

  command_line_arguments.insert(command_line_arguments.end(), rust_args.begin(), rust_args.end());
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Get primary monitor's work area.
  Win32Window::Point workarea_origin(0, 0);
  Win32Window::Size workarea_size(0, 0);

  Win32Desktop::GetWorkArea(workarea_origin, workarea_size);

  // Compute window bounds for default main window position: (10, 10) x(800, 600)
  Win32Window::Point relative_origin(10, 10);

  Win32Window::Point origin(workarea_origin.x + relative_origin.x, workarea_origin.y + relative_origin.y);
  Win32Window::Size size(800u, 600u);

  // Fit the window to the monitor's work area.
  Win32Desktop::FitToWorkArea(origin, size);

  std::wstring window_title;
  if (is_cm_page) {
    window_title = app_name + L" - Connection Manager";
  } else if (is_install_page) {
    window_title = app_name + L" - Install";
  } else {
    window_title = app_name;
  }
  DebugLaunchLog("About to call window.CreateAndShow");
  if (!window.CreateAndShow(window_title, origin, size, !is_cm_page)) {
      DebugLaunchLog("window.CreateAndShow returned FALSE - engine/window init failed");
      return EXIT_FAILURE;
  }
  DebugLaunchLog("window.CreateAndShow SUCCEEDED - entering message loop");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
