import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/remote_page.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:get/get.dart';

import 'diagnostics_dialog.dart';
import 'window_frame.dart';

const _annotationPrefix = '__TGDESK_ANNOTATION__:';
const _nativeSystemKeysShortcutEvent = 'tgdesk_system_keys_toggle';

class RemoteSessionEntry {
  const RemoteSessionEntry({
    required this.deviceId,
    required this.remoteId,
    required this.hostname,
    required this.credential,
  });

  final String deviceId;
  final String remoteId;
  final String hostname;
  final String credential;
}

class RemoteSessionsManager extends ChangeNotifier {
  RemoteSessionsManager._();
  static final RemoteSessionsManager instance = RemoteSessionsManager._();

  final List<RemoteSessionEntry> _entries = [];
  List<RemoteSessionEntry> get entries => List.unmodifiable(_entries);

  /// Mesmo conteúdo de [entries], com o nome que as abas usam.
  List<RemoteSessionEntry> get sessions => entries;
  bool get hasEntries => _entries.isNotEmpty;

  /// Qual sessão está à frente. -1 quando não há nenhuma.
  int _activeIndex = -1;
  int get activeIndex => _activeIndex;

  RemoteSessionEntry? get active =>
      _activeIndex >= 0 && _activeIndex < _entries.length
          ? _entries[_activeIndex]
          : null;

  bool isOpen(String deviceId) => _entries.any((e) => e.deviceId == deviceId);

  /// Abre uma sessão e a traz para a frente.
  ///
  /// Pedir acesso a uma máquina já aberta não abre uma segunda: foca a que
  /// existe. Duas sessões para o mesmo computador seriam duas telas mostrando
  /// a mesma coisa, e fechar uma delas deixaria a dúvida de qual caiu.
  void open(RemoteSessionEntry entry) {
    final existing = _entries.indexWhere((e) => e.deviceId == entry.deviceId);
    if (existing >= 0) {
      focus(existing);
      return;
    }
    _entries.add(entry);
    _activeIndex = _entries.length - 1;
    notifyListeners();
  }

  void focus(int index) {
    if (index < 0 || index >= _entries.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Move uma aba de lugar, arrastando.
  ///
  /// A que estava à frente continua à frente depois da mudança: reordenar é
  /// arrumar a fileira, não trocar de máquina. Sem isso, arrastar uma aba
  /// qualquer trocaria a tela por baixo da mão de quem arrasta.
  void reorder(int from, int to) {
    if (from < 0 || from >= _entries.length) return;
    if (to < 0 || to > _entries.length) return;
    final aFrente = active;
    final movida = _entries.removeAt(from);
    if (to > from) to--;
    _entries.insert(to, movida);
    if (aFrente != null) {
      _activeIndex = _entries.indexOf(aFrente);
    }
    notifyListeners();
  }

  /// Tira todas as abas da frente sem fechar nenhuma. É o que acontece ao
  /// escolher um destino da barra lateral: a sessão continua viva, apenas
  /// deixa de ser o que está na tela — como trocar de aba no navegador.
  void blur() {
    if (_activeIndex == -1) return;
    _activeIndex = -1;
    notifyListeners();
  }

  void close(String deviceId) {
    final index = _entries.indexWhere((e) => e.deviceId == deviceId);
    if (index >= 0) closeAt(index);
  }

  /// Fecha a aba na posição informada.
  ///
  /// A seguinte assume o lugar, como no navegador — e quando a fechada era a
  /// última, quem assume é a anterior. Deixar o índice apontando para fora da
  /// lista mostraria tela vazia com abas abertas.
  void closeAt(int index) {
    if (index < 0 || index >= _entries.length) return;
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex > index) {
      _activeIndex--;
    } else if (_activeIndex >= _entries.length) {
      _activeIndex = _entries.length - 1;
    }
    notifyListeners();
  }
}

class TgdeskRemoteSessionPage extends StatefulWidget {
  const TgdeskRemoteSessionPage({
    super.key,
    required this.deviceId,
    required this.remoteId,
    required this.hostname,
    required this.credential,
    this.embedded = false,
  });

  final String deviceId;
  final String remoteId;
  final String hostname;
  final String credential;

  /// Dentro do Hub, onde a barra de título já é do shell e a aba desta sessão
  /// já está nela. Fora dele a sessão é uma janela por si e monta a própria.
  final bool embedded;

  @override
  State<TgdeskRemoteSessionPage> createState() =>
      _TgdeskRemoteSessionPageState();
}

class _TgdeskRemoteSessionPageState extends State<TgdeskRemoteSessionPage> {
  final _focusNode = FocusNode();
  final List<_DrawingSegment> _segments = [];
  late final RxBool _inputBlocked;
  bool _drawing = false;
  bool _eraser = false;
  bool _clipboardEnabled = false;
  bool _fileTransferEnabled = false;
  // Começa com o grabber remoto ativo. Ctrl+Shift+I libera o teclado para o
  // computador local; um novo clique no canvas retoma o controle remoto.
  final RxBool _captureSystemKeys = true.obs;
  int _lastSystemKeysShortcutMicros = 0;
  Worker? _tgdeskFullscreenWatcher;
  Color _color = const Color(0xffff3b30);
  double _strokeWidth = 5;
  Offset? _lastPoint;
  FFI? _ffi;

  get _sessionId => _ffi?.sessionId ?? gFFI.sessionId;

  @override
  void initState() {
    super.initState();
    // DesktopRemoteScreen fazia esta inicializaÃ§Ã£o antes de criar a aba
    // nativa. O caminho embutido monta RemotePage diretamente, entÃ£o o estado
    // global de entrada precisa ser preparado aqui uma vez por sessÃ£o.
    bind.mainInitInputSource();
    stateGlobal.getInputSource(force: true);
    if (isWindows) {
      bind.hostStopSystemKeyPropagate(stopped: true);
    }
    // O canvas remoto pode manter o foco e consumir Ctrl+Shift+I antes de o
    // Focus.onKeyEvent do shell receber a tecla. O handler global garante que
    // o atalho continue funcionando como no Parsec, mas só para a aba ativa.
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    // Este estado Ã© lido pelo shell antes de o filho RemotePage entrar na
    // Ã¡rvore. Sem registrar os estados compartilhados neste ponto, o GetX
    // lanÃ§a "Instance not found" no primeiro frame e o Hub fica cinza.
    initSharedStates(widget.remoteId);
    _inputBlocked = BlockInputState.find(widget.remoteId);
    platformFFI.registerEventHandler(
      _nativeSystemKeysShortcutEvent,
      'tgdesk-remote-${widget.deviceId}',
      _handleNativeSystemKeysShortcut,
      replace: true,
    );
    _tgdeskFullscreenWatcher = ever<bool>(stateGlobal.fullscreen, (_) {
      if (!_isActiveKeyboardSession()) return;
      final ffi = _ffi;
      if (ffi == null) return;
      // The native window has just changed size. Ask the peer for a fresh
      // frame after the Flutter texture has received its final bounds; this
      // recovers the first image when Win32 resized the surface mid-connect.
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted || !_isActiveKeyboardSession()) return;
        unawaited(sessionRefreshVideo(ffi.sessionId, ffi.ffiModel.pi));
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final sessionId = _sessionId;
      final clipboardDisabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId,
        arg: 'disable-clipboard',
      );
      if (!clipboardDisabled) {
        await bind.sessionToggleOption(
          sessionId: sessionId,
          value: 'disable-clipboard',
        );
      }
      final fileTransferEnabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId,
        arg: kOptionEnableFileCopyPaste,
      );
      if (fileTransferEnabled) {
        await bind.sessionToggleOption(
          sessionId: sessionId,
          value: kOptionEnableFileCopyPaste,
        );
      }
    });
  }

  @override
  void dispose() {
    _tgdeskFullscreenWatcher?.dispose();
    platformFFI.unregisterEventHandler(
      _nativeSystemKeysShortcutEvent,
      'tgdesk-remote-${widget.deviceId}',
    );
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    if (_inputBlocked.isTrue) {
      bind.sessionToggleOption(sessionId: _sessionId, value: 'unblock-input');
    }
    if (_clipboardEnabled) {
      bind.sessionToggleOption(
        sessionId: _sessionId,
        value: 'disable-clipboard',
      );
    }
    if (_fileTransferEnabled) {
      bind.sessionToggleOption(
        sessionId: _sessionId,
        value: kOptionEnableFileCopyPaste,
      );
    }
    _sendAnnotation(const {'t': 'ClearDrawing'});
    // Zera o recuo só quando esta era a última sessão. Com outras abertas,
    // quem continua na tela remede no próximo quadro e o valor volta — mas
    // entre zerar e remedir passa um quadro com o cursor deslocado, e fechar
    // uma aba não deve mexer no ponteiro da que ficou.
    //
    // Zerar quando a última sai continua necessário: uma janela solta não tem
    // barra lateral nenhuma, e herdar o recuo do Hub a faria nascer torta.
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleInputBlock() {
    final willBlock = !_inputBlocked.value;
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: willBlock ? 'block-input' : 'unblock-input',
    );
    _inputBlocked.value = willBlock;
    _notify(willBlock
        ? 'Entrada local do cliente bloqueada'
        : 'Entrada local do cliente liberada');
  }

  void _notify(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    BotToast.showText(
      text: text,
      duration: const Duration(seconds: 3),
      clickClose: true,
      onlyOne: true,
    );
  }

  void _toggleDrawing() {
    setState(() {
      _drawing = !_drawing;
      _lastPoint = null;
    });
    _focusNode.requestFocus();
    _notify(_drawing ? 'Anotação ativada' : 'Anotação encerrada');
  }

  void _toggleClipboard() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: 'disable-clipboard',
    );
    setState(() => _clipboardEnabled = !_clipboardEnabled);
    _notify(_clipboardEnabled
        ? 'Copiar e colar ativado'
        : 'Copiar e colar desativado');
  }

  void _toggleFileTransfer() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: kOptionEnableFileCopyPaste,
    );
    setState(() => _fileTransferEnabled = !_fileTransferEnabled);
    _notify(_fileTransferEnabled
        ? 'Transferência de arquivos ativada'
        : 'Transferência de arquivos desativada');
  }

  void _toggleSystemKeys() {
    _captureSystemKeys.toggle();
    final capture = _captureSystemKeys.value;
    if (isWindows) {
      bind.hostStopSystemKeyPropagate(stopped: capture);
    }
    final ffi = _ffi;
    if (ffi != null) {
      if (capture) {
        ffi.inputModel.enterOrLeave(true);
        _focusNode.requestFocus();
      } else {
        // A flag nativa de propagação não basta: o rdev grabber do RustDesk
        // também precisa ser liberado para Alt+Tab voltar ao computador local.
        ffi.inputModel.enterOrLeave(false);
        _focusNode.unfocus();
      }
    }
    _notify(capture
        ? 'Atalhos do Windows enviados ao computador remoto'
        : 'Atalhos do Windows liberados neste computador');
  }

  bool _isActiveKeyboardSession() {
    if (!widget.embedded) return true;
    return RemoteSessionsManager.instance.active?.deviceId == widget.deviceId;
  }

  bool _toggleSystemKeysFromShortcut() {
    final now = DateTime.now().microsecondsSinceEpoch;
    // Windows/Flutter podem entregar o mesmo KeyDown ao handler global e ao
    // FocusNode. Evita duas alternâncias e mantém uma única notificação.
    if (now - _lastSystemKeysShortcutMicros < 100000) return true;
    _lastSystemKeysShortcutMicros = now;
    _toggleSystemKeys();
    return true;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent || !_isActiveKeyboardSession()) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyI &&
        keys.isControlPressed &&
        keys.isShiftPressed) {
      return _toggleSystemKeysFromShortcut();
    }
    return false;
  }

  Future<void> _handleNativeSystemKeysShortcut(
      Map<String, dynamic> event) async {
    if (!mounted || !_isActiveKeyboardSession()) return;
    _toggleSystemKeysFromShortcut();
  }

  void _clearDrawing() {
    setState(_segments.clear);
    _sendAnnotation(const {'t': 'ClearDrawing'});
  }

  void _sendAnnotation(Map<String, dynamic> event) {
    bind.sessionSendChat(
      sessionId: _sessionId,
      text: '$_annotationPrefix${jsonEncode(event)}',
    );
  }

  void _startStroke(DragStartDetails details, Size size) {
    _lastPoint = details.localPosition;
  }

  void _continueStroke(DragUpdateDetails details, Size size) {
    final previous = _lastPoint;
    final current = details.localPosition;
    if (previous == null || (current - previous).distance < 1.2) return;
    final segment = _DrawingSegment(
      start: Offset(previous.dx / size.width, previous.dy / size.height),
      end: Offset(current.dx / size.width, current.dy / size.height),
      color: _color,
      width: _eraser ? _strokeWidth * 3 : _strokeWidth,
      erase: _eraser,
    );
    setState(() => _segments.add(segment));
    _lastPoint = current;
    _sendAnnotation({
      't': 'Stroke',
      'c': {
        'x0': segment.start.dx,
        'y0': segment.start.dy,
        'x1': segment.end.dx,
        'y1': segment.end.dy,
        'argb': segment.color.value,
        'width': segment.width,
        'erase': segment.erase,
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) =>
      _handleTgdeskShortcut(event);

  KeyEventResult _handleTgdeskShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      stateGlobal.setFullscreen(!stateGlobal.fullscreen.value);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        stateGlobal.fullscreen.value &&
        !_drawing) {
      stateGlobal.setFullscreen(false);
      return KeyEventResult.handled;
    }
    if (keys.isControlPressed && keys.isShiftPressed) {
      if (event.logicalKey == LogicalKeyboardKey.keyI) {
        return _toggleSystemKeysFromShortcut()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyB) {
        _toggleInputBlock();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _toggleDrawing();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        _toggleClipboard();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFileTransfer();
        return KeyEventResult.handled;
      }
    }
    if (_drawing && event.logicalKey == LogicalKeyboardKey.escape) {
      _toggleDrawing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _tgdeskToolbarMenu(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Ferramentas TGDesk',
        icon: const Icon(Icons.build_circle_outlined, size: 20),
        onSelected: (value) {
          switch (value) {
            case 'diagnostics':
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => DiagnosticDialog(
                  deviceId: widget.deviceId,
                  deviceName: widget.hostname,
                  online: true,
                ),
              );
              break;
            case 'block_input':
              _toggleInputBlock();
              break;
            case 'drawing':
              _toggleDrawing();
              break;
            case 'clipboard':
              _toggleClipboard();
              break;
            case 'file_transfer':
              _toggleFileTransfer();
              break;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem<String>(
            value: 'diagnostics',
            child: _MenuEntry(
              icon: Icons.science_outlined,
              text: 'Diagnósticos do dispositivo',
            ),
          ),
          PopupMenuItem<String>(
            value: 'block_input',
            child: _MenuEntry(
              icon: _inputBlocked.isTrue
                  ? Icons.keyboard_alt_outlined
                  : Icons.keyboard_hide_outlined,
              text: _inputBlocked.isTrue
                  ? 'Liberar mouse e teclado do cliente'
                  : 'Bloquear mouse e teclado do cliente',
              shortcut: 'Ctrl+Shift+B',
            ),
          ),
          PopupMenuItem<String>(
            value: 'drawing',
            child: _MenuEntry(
              icon: _drawing ? Icons.edit_off_outlined : Icons.draw_outlined,
              text:
                  _drawing ? 'Encerrar anotação' : 'Anotar na tela do cliente',
              shortcut: 'Ctrl+Shift+D',
            ),
          ),
          PopupMenuItem<String>(
            value: 'clipboard',
            child: _MenuEntry(
              icon: _clipboardEnabled
                  ? Icons.content_paste_go_outlined
                  : Icons.content_paste_off_outlined,
              text: _clipboardEnabled
                  ? 'Desativar copiar e colar'
                  : 'Ativar copiar e colar',
              shortcut: 'Ctrl+Shift+C',
            ),
          ),
          PopupMenuItem<String>(
            value: 'file_transfer',
            child: _MenuEntry(
              icon: _fileTransferEnabled
                  ? Icons.file_copy_outlined
                  : Icons.folder_off_outlined,
              text: _fileTransferEnabled
                  ? 'Desativar transferência de arquivos'
                  : 'Ativar transferência de arquivos',
              shortcut: 'Ctrl+Shift+F',
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      // Embutida no Hub, a sessão não monta barra de título própria: a aba dela
      // já está na barra compartilhada, e duas barras empilhadas seriam duas
      // vezes o mesmo. Fora do Hub — janela solta — ela ainda precisa da
      // própria, senão a janela não teria como ser arrastada nem fechada.
      child: widget.embedded
          ? content
          : TgdeskWindowScaffold(
              title: Text(widget.hostname,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              child: content,
            ),
    );
  }

  /// Onde esta sessão começa dentro da janela, medido depois do layout.
  ///
  /// É o que corrige o ponteiro: o mapeamento do mouse trabalha com a posição
  /// global e desconta este recuo. Medir é a única forma honesta — a barra de
  /// título tem altura fixa, mas a barra lateral muda de largura conforme os
  /// destinos visíveis, e cravar números aqui daria um cursor certo hoje e
  /// errado no primeiro destino novo.
  // RemotePage receives the exact embedded viewport constraints through its
  // LayoutBuilder; no global window-coordinate recuo is needed here.

  Widget _buildContent() {
    // Medido a cada quadro: a janela muda de tamanho, a barra lateral aparece
    // e some, e a tela cheia zera os dois. Comparar antes de escrever mantém
    // isso barato.
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ClipRect(
              child: RemotePage(
                key: ValueKey(widget.remoteId),
                id: widget.remoteId,
                password: widget.credential,
                forceRelay: false,
                toolbarState: ToolbarState(),
                tgdeskEmbedded: true,
                // Deixe o RustDesk negociar direto e usar relay como fallback.
                // Forçar relay aqui deixava a tela cinza quando o par estava na
                // mesma rede ou quando o relay ainda estava em reconexão.
                tgdeskToolbarMenuBuilder: _tgdeskToolbarMenu,
                tgdeskSessionReady: (ffi) => _ffi = ffi,
                tgdeskShortcutHandler: _handleTgdeskShortcut,
                tgdeskCaptureSystemKeys: _captureSystemKeys,
                tgdeskToggleSystemKeys: _toggleSystemKeys,
                tgdeskCloseSession: () {
                  _notify('Sessão remota encerrada');
                  RemoteSessionsManager.instance.close(widget.deviceId);
                },
              ),
            ),
          ),
          if (_drawing)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (event) =>
                      _startStroke(event, constraints.biggest),
                  onPanUpdate: (event) =>
                      _continueStroke(event, constraints.biggest),
                  onPanEnd: (_) => _lastPoint = null,
                  child: CustomPaint(
                    painter: _AnnotationPainter(_segments),
                  ),
                ),
              ),
            ),
          if (_inputBlocked.isTrue)
            Positioned(
              right: 14,
              bottom: 14,
              child: _StatusChip(
                icon: Icons.keyboard_hide_outlined,
                text: 'Entrada do cliente bloqueada',
                color: const Color(0xffffb020),
                onTap: _toggleInputBlock,
              ),
            ),
          if (_drawing) _drawingToolbar(),
          if (_clipboardEnabled || _fileTransferEnabled)
            Positioned(
              left: 14,
              bottom: 14,
              child: _StatusChip(
                icon: _fileTransferEnabled
                    ? Icons.file_copy_outlined
                    : Icons.content_paste_go_outlined,
                text: _clipboardEnabled && _fileTransferEnabled
                    ? 'Copiar, colar e arquivos ativos'
                    : _fileTransferEnabled
                        ? 'Transferência de arquivos ativa'
                        : 'Copiar e colar ativo',
                color: const Color(0xff35a7ff),
                onTap: _fileTransferEnabled
                    ? _toggleFileTransfer
                    : _toggleClipboard,
              ),
            ),
        ],
      ),
    );
  }

  Widget _drawingToolbar() => Positioned(
        top: 8,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: const Color(0xff111820).withOpacity(.97),
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Anotação'),
                ),
                IconButton(
                  tooltip: 'Caneta',
                  onPressed: () => setState(() => _eraser = false),
                  color: !_eraser ? const Color(0xff35a7ff) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Borracha',
                  onPressed: () => setState(() => _eraser = true),
                  color: _eraser ? const Color(0xff35a7ff) : null,
                  icon: const Icon(Icons.auto_fix_normal_outlined),
                ),
                if (!_eraser)
                  ...[
                    const Color(0xffff3b30),
                    const Color(0xffffcc00),
                    const Color(0xff34c759),
                    const Color(0xff32ade6),
                    const Color(0xffffffff),
                  ].map((color) => _ColorButton(
                        color: color,
                        selected: color.value == _color.value,
                        onTap: () => setState(() => _color = color),
                      )),
                SizedBox(
                  width: 115,
                  child: Slider(
                    value: _strokeWidth,
                    min: 2,
                    max: 18,
                    onChanged: (value) => setState(() => _strokeWidth = value),
                  ),
                ),
                IconButton(
                  tooltip: 'Apagar todas as anotações',
                  onPressed: _clearDrawing,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
                IconButton(
                  tooltip: 'Encerrar anotação (Esc)',
                  onPressed: _toggleDrawing,
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _DrawingSegment {
  const _DrawingSegment({
    required this.start,
    required this.end,
    required this.color,
    required this.width,
    required this.erase,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double width;
  final bool erase;
}

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter(this.segments);
  final List<_DrawingSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final segment in segments) {
      canvas.drawLine(
        Offset(segment.start.dx * size.width, segment.start.dy * size.height),
        Offset(segment.end.dx * size.width, segment.end.dy * size.height),
        Paint()
          ..color = segment.color
          ..strokeWidth = segment.width
          ..strokeCap = StrokeCap.round
          ..blendMode = segment.erase ? BlendMode.clear : BlendMode.srcOver,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) => true;
}

class _MenuEntry extends StatelessWidget {
  const _MenuEntry(
      {required this.icon, required this.text, this.shortcut = ''});
  final IconData icon;
  final String text;
  final String shortcut;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
        if (shortcut.isNotEmpty) ...[
          const SizedBox(width: 20),
          Text(shortcut, style: Theme.of(context).textTheme.labelSmall),
        ],
      ]);
}

class _ColorButton extends StatelessWidget {
  const _ColorButton(
      {required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          margin: const EdgeInsets.all(4),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? const Color(0xff35a7ff) : Colors.black,
                width: selected ? 3 : 1),
          ),
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xff111820).withOpacity(.96),
        elevation: 6,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(text),
            ]),
          ),
        ),
      );
}
