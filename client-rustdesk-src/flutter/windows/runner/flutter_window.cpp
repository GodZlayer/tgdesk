#include "flutter_window.h"

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <texture_rgba_renderer/texture_rgba_renderer_plugin_c_api.h>
#include <flutter_gpu_texture_renderer/flutter_gpu_texture_renderer_plugin_c_api.h>

#include "flutter/generated_plugin_registrant.h"

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <optional>
#include <memory>

#include "win32_desktop.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  flutter::MethodChannel<> channel(
    flutter_controller_->engine()->messenger(),
    "org.rustdesk.rustdesk/host",
    &flutter::StandardMethodCodec::GetInstance());

  channel.SetMethodCallHandler(
    [](const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
      if (call.method_name() == "bumpMouse") {
        auto arguments = call.arguments();

        int dx = 0, dy = 0;

        if (std::holds_alternative<flutter::EncodableMap>(*arguments)) {
          auto argsMap = std::get<flutter::EncodableMap>(*arguments);

          auto dxIt = argsMap.find(flutter::EncodableValue("dx"));
          auto dyIt = argsMap.find(flutter::EncodableValue("dy"));

          if ((dxIt != argsMap.end()) && std::holds_alternative<int>(dxIt->second)) {
            dx = std::get<int>(dxIt->second);
          }
          if ((dyIt != argsMap.end()) && std::holds_alternative<int>(dyIt->second)) {
            dy = std::get<int>(dyIt->second);
          }
        } else if (std::holds_alternative<flutter::EncodableList>(*arguments)) {
          auto argsList = std::get<flutter::EncodableList>(*arguments);

          if ((argsList.size() >= 1) && std::holds_alternative<int>(argsList[0])) {
            dx = std::get<int>(argsList[0]);
          }
          if ((argsList.size() >= 2) && std::holds_alternative<int>(argsList[1])) {
            dy = std::get<int>(argsList[1]);
          }
        }

        bool succeeded = Win32Desktop::BumpMouse(dx, dy);

        result->Success(succeeded);
      }
    });

  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    TextureRgbaRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("TextureRgbaRendererPlugin"));
    FlutterGpuTextureRendererPluginCApiRegisterWithRegistrar(
        registry->GetRegistrarForPlugin("FlutterGpuTextureRendererPluginCApi"));
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // A faixa preta de 8px no topo em tela cheia.
  //
  // Isto roda ANTES do Flutter de propósito. O window_manager responde a todo
  // WM_NCCALCSIZE quando a barra de título não é a nativa — que é o nosso caso
  // — e o `if (result) return *result;` logo abaixo encerra a mensagem ali.
  // Qualquer tratamento nosso depois deste ponto seria código morto.
  //
  // O que ele faz, em window_manager_plugin.cpp:
  //
  //   if (IsFullScreen()) return 0;              // área de cliente inteira
  //   if (title_bar_style_ == "hidden") {
  //     if (IsMaximized()) sz->rgrc[0].top += 8; // <- a faixa
  //
  // E `IsFullScreen()` lê uma variável que ele só grava na ÚLTIMA linha de
  // SetFullScreen. Todo recálculo de moldura que chegue antes disso — ou
  // depois, provocado por outra coisa, como uma tela virtual entrando e
  // mudando a resolução — cai no ramo do `+= 8`, e o conteúdo desce.
  //
  // Aqui a decisão não depende de estado guardado por ninguém:
  //
  //  - o retângulo PROPOSTO cobre exatamente um monitor: é a transição para
  //    tela cheia, e vale mesmo antes de o estilo ter sido trocado;
  //  - a janela está sem WS_CAPTION: só o window_manager tira isso, e só em
  //    tela cheia (a barra escondida do TGDesk usa DWM, não mexe no estilo).
  //    Este cobre todo recálculo posterior, que é o caso da tela virtual.
  //
  // Janela apenas maximizada não entra em nenhum dos dois: ela mantém o
  // WS_CAPTION, e o retângulo dela é maior que o do monitor pela borda.
  if (message == WM_NCCALCSIZE && wparam == TRUE) {
    auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
    RECT proposed = params->rgrc[0];
    MONITORINFO monitor = {};
    monitor.cbSize = sizeof(monitor);
    const bool covers_monitor =
        GetMonitorInfo(MonitorFromRect(&proposed, MONITOR_DEFAULTTONEAREST),
                       &monitor) &&
        EqualRect(&proposed, &monitor.rcMonitor);
    const bool no_frame = (GetWindowLong(hwnd, GWL_STYLE) & WS_CAPTION) == 0;
    if (covers_monitor || no_frame) {
      // Sem tocar em rgrc[0]: área de cliente = retângulo da janela.
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
