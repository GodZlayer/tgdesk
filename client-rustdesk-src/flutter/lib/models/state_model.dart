import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../consts.dart';
import './platform_model.dart';

enum SvcStatus { notReady, connecting, ready }

class StateGlobal {
  int _windowId = -1;
  final RxBool _fullscreen = false.obs;
  bool _isMinimized = false;
  final RxBool isMaximized = false.obs;
  final RxBool _showTabBar = true.obs;
  final RxDouble _resizeEdgeSize = RxDouble(windowResizeEdgeSize);
  final RxDouble _windowBorderWidth = RxDouble(kWindowBorderWidth);
  final RxBool showRemoteToolBar = false.obs;
  final svcStatus = SvcStatus.notReady.obs;
  final RxInt videoConnCount = 0.obs;
  final RxBool isFocused = false.obs;
  // The TGDesk Hub embeds the remote canvas in the main Flutter window. Native
  // Win32 fullscreen tears down/recreates the Flutter texture surface on some
  // machines, which looks like a frozen remote connection. For the Hub we use
  // a borderless maximized client area instead and keep the FFI/texture alive.
  bool _tgdeskHubWasMaximized = false;
  int _tgdeskFullscreenTransition = 0;
  // for mobile and web
  bool isInMainPage = true;
  bool isWebVisible = true;

  final isPortrait = false.obs;

  final updateUrl = ''.obs;

  String _inputSource = '';

  // Track relative mouse mode state for each peer connection.
  // Key: peerId, Value: true if relative mouse mode is active.
  // Note: This is session-only runtime state, NOT persisted to config.
  final RxMap<String, bool> relativeMouseModeState = <String, bool>{}.obs;

  // Use for desktop -> remote toolbar -> resolution
  final Map<String, Map<int, String?>> _lastResolutionGroupValues = {};

  int get windowId => _windowId;
  RxBool get fullscreen => _fullscreen;
  bool get isMinimized => _isMinimized;
  double get tabBarHeight => fullscreen.isTrue ? 0 : kDesktopRemoteTabBarHeight;

  // TGDesk: onde a tela remota realmente começa dentro da janela.
  //
  // No RustDesk original a sessão ocupa a janela inteira abaixo da barra de
  // abas, e por isso o mapeamento do mouse trabalha com a posição GLOBAL do
  // ponteiro descontando só tabBarHeight e as bordas. No TGDesk ela é embutida
  // no Hub: tem a barra de título por cima e a barra lateral à esquerda.
  //
  // Sem informar esse recuo, o ponteiro chega à máquina remota deslocado
  // exatamente pelo tamanho do que está em volta — o cursor de lá anda longe
  // de onde o mouse está aqui.
  //
  // Zero quando não há embutimento (janela solta, tela cheia), que é quando o
  // cálculo original já está certo.
  double tgdeskEmbedTop = 0;
  double tgdeskEmbedLeft = 0;
  double tgdeskEmbedRight = 0;
  double tgdeskEmbedBottom = 0;
  RxBool get showTabBar => _showTabBar;
  RxDouble get resizeEdgeSize => _resizeEdgeSize;
  RxDouble get windowBorderWidth => _windowBorderWidth;

  resetLastResolutionGroupValues(String peerId) {
    _lastResolutionGroupValues[peerId] = {};
  }

  setLastResolutionGroupValue(
      String peerId, int currentDisplay, String? value) {
    if (!_lastResolutionGroupValues.containsKey(peerId)) {
      _lastResolutionGroupValues[peerId] = {};
    }
    _lastResolutionGroupValues[peerId]![currentDisplay] = value;
  }

  String? getLastResolutionGroupValue(String peerId, int currentDisplay) {
    return _lastResolutionGroupValues[peerId]?[currentDisplay];
  }

  setWindowId(int id) => _windowId = id;
  setMaximized(bool v) {
    if (!_fullscreen.isTrue) {
      if (isMaximized.value != v) {
        isMaximized.value = v;
        refreshResizeEdgeSize();
      }
      if (!isMacOS) {
        _windowBorderWidth.value = v ? 0 : kWindowBorderWidth;
      }
    }
  }

  setMinimized(bool v) => _isMinimized = v;

  setFullscreen(bool v, {bool procWnd = true}) {
    if (_fullscreen.value == v) return;

    // The Hub embeds the RustDesk canvas in the main Flutter window.  Apply
    // the native maximize/unmaximize first and only then change the Flutter
    // fullscreen state.  Changing the layout before Win32 finishes resizing
    // can invalidate the texture surface while the peer is already connected,
    // leaving the local side stuck on "connecting" with no first frame.
    final hubWindow = windowId < 0 && desktopType == DesktopType.main;
    if (hubWindow && procWnd && !isWebDesktop) {
      final transition = ++_tgdeskFullscreenTransition;
      _applyHubFullscreen(v, transition);
      return;
    }

    _fullscreen.value = v;
    _showTabBar.value = !_fullscreen.value;
    if (isWebDesktop) {
      procFullscreenWeb();
    } else {
      procFullscreenNative(procWnd);
    }
  }

  procFullscreenWeb() {
    final isFullscreen = ffiGetByName('fullscreen') == 'Y';
    String fullscreenValue = '';
    if (isFullscreen && _fullscreen.isFalse) {
      fullscreenValue = 'N';
    } else if (!isFullscreen && fullscreen.isTrue) {
      fullscreenValue = 'Y';
    }
    if (fullscreenValue.isNotEmpty) {
      ffiSetByName('fullscreen', fullscreenValue);
    }
  }

  procFullscreenNative(bool procWnd) {
    refreshResizeEdgeSize();
    print("fullscreen: $fullscreen, resizeEdgeSize: ${_resizeEdgeSize.value}");
    _windowBorderWidth.value = fullscreen.isTrue ? 0 : kWindowBorderWidth;
    if (procWnd) {
      // TGDesk embedded sessions run inside the main window and never go
      // through the 'multi_window' launch branch in main.dart, so
      // stateGlobal._windowId stays at its default (-1) and
      // WindowController.fromWindowId(-1) is invalid and applies no native
      // fullscreen at all. In that case, drive the main window directly via
      // window_manager. RustDesk's native multi_window flow (a valid
      // windowId set via stateGlobal.setWindowId) keeps using
      // WindowController.fromWindowId as before.
      if (windowId < 0) {
        windowManager.setFullScreen(_fullscreen.isTrue);
      } else {
        final wc = WindowController.fromWindowId(windowId);
        wc.setFullscreen(_fullscreen.isTrue).then((_) {
          // We remove the redraw (width + 1, height + 1), because this issue cannot be reproduced.
          // https://github.com/rustdesk/rustdesk/issues/9675
        });
      }
    }
  }

  Future<void> _applyHubFullscreen(
      bool fullscreenRequested, int transition) async {
    try {
      if (transition != _tgdeskFullscreenTransition) return;
      if (fullscreenRequested) {
        _tgdeskHubWasMaximized = await windowManager.isMaximized();
        if (transition != _tgdeskFullscreenTransition) return;
        if (!_tgdeskHubWasMaximized) {
          await windowManager.maximize();
        }
      } else if (!_tgdeskHubWasMaximized) {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
      }

      if (transition != _tgdeskFullscreenTransition) return;
      _fullscreen.value = fullscreenRequested;
      _showTabBar.value = !fullscreenRequested;
      _windowBorderWidth.value = fullscreenRequested ? 0 : kWindowBorderWidth;
      refreshResizeEdgeSize();
    } catch (e) {
      // Keep the Flutter state coherent even if a window-manager backend is
      // unavailable.  A failed native transition must not leave the session
      // permanently waiting for a frame.
      debugPrint('TGDesk fullscreen transition failed: $e');
      if (transition == _tgdeskFullscreenTransition) {
        _fullscreen.value = fullscreenRequested;
        _showTabBar.value = !fullscreenRequested;
        refreshResizeEdgeSize();
      }
    }
  }

  refreshResizeEdgeSize() => _resizeEdgeSize.value = fullscreen.isTrue
      ? kFullScreenEdgeSize
      : isMaximized.isTrue
          ? kMaximizeEdgeSize
          : windowResizeEdgeSize;

  String getInputSource({bool force = false}) {
    if (force || _inputSource.isEmpty) {
      _inputSource = bind.mainGetInputSource();
    }
    return _inputSource;
  }

  setInputSource(SessionID sessionId, String v) async {
    await bind.mainSetInputSource(sessionId: sessionId, value: v);
    _inputSource = bind.mainGetInputSource();
  }

  StateGlobal._() {
    if (isWebDesktop) {
      platformFFI.setFullscreenCallback((v) {
        _fullscreen.value = v;
      });
    }
  }

  static final StateGlobal instance = StateGlobal._();
}

// This final variable is initialized when the first time it is accessed.
final stateGlobal = StateGlobal.instance;
