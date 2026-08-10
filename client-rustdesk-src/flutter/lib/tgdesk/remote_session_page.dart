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

/// Evento único que o núcleo empurra quando reconhece um Ctrl+Shift+<tecla>.
/// O nome do comando vem no campo `action`; a tabela de teclas vive no Rust
/// (keyboard.rs::TGDESK_SHORTCUTS) para as três camadas nativas lerem a mesma.
const tgdeskShortcutEvent = 'tgdesk_shortcut';

/// Nomes dos comandos, iguais dos dois lados da ponte.
const tgdeskActionSystemKeys = 'system_keys';
const tgdeskActionBlockInput = 'block_input';
const tgdeskActionDrawing = 'drawing';
const tgdeskActionClipboard = 'clipboard';
const tgdeskActionFileTransfer = 'file_transfer';

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
  final Map<String, void Function(String)> _shortcutHandlers = {};
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

  void registerShortcutHandler(String deviceId, void Function(String) handler) {
    _shortcutHandlers[deviceId] = handler;
  }

  void unregisterShortcutHandler(String deviceId) {
    _shortcutHandlers.remove(deviceId);
  }

  /// O acorde nativo é global — vale para o computador inteiro, não para um
  /// widget. Quem responde é sempre a sessão que está à frente: é a máquina que
  /// o técnico está operando quando aperta a tecla.
  Future<void> handleNativeShortcut(String action) async {
    final deviceId = active?.deviceId;
    if (deviceId == null) return;
    _shortcutHandlers[deviceId]?.call(action);
  }

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
    final wasActive = index == _activeIndex;
    _entries.removeAt(index);
    if (_entries.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex > index) {
      _activeIndex--;
    } else if (_activeIndex >= _entries.length) {
      _activeIndex = _entries.length - 1;
    }
    if (wasActive) {
      stateGlobal.setFullscreen(false, procWnd: false);
      if (isWindows) bind.hostStopSystemKeyPropagate(stopped: false);
    }
    notifyListeners();
  }

  /// Fecha todas as abas e deixa o Hub sem uma sessão ativa. A remoção dos
  /// filhos do IndexedStack dispara o dispose de cada RemotePage, que encerra
  /// a sessão RustDesk correspondente.
  void closeAll() {
    if (_entries.isEmpty && _activeIndex == -1) return;
    _entries.clear();
    _activeIndex = -1;
    if (isWindows) bind.hostStopSystemKeyPropagate(stopped: false);
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
  // Observáveis, e não campos comuns, porque agora os botões do toolbar
  // flutuante mostram o estado de cada comando. O toolbar é construído dentro
  // da RemotePage, longe deste setState: só um Rx faz o ícone acompanhar quem
  // apertou o atalho.
  final RxBool _drawingOn = false.obs;
  final RxBool _clipboardOn = false.obs;
  final RxBool _fileTransferOn = false.obs;
  bool _eraser = false;
  // Começa com o grabber remoto ativo. Ctrl+Shift+I libera o teclado para o
  // computador local; um novo clique no canvas retoma o controle remoto.
  final RxBool _captureSystemKeys = true.obs;
  final Map<String, int> _lastShortcutMicros = {};
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
    // O canvas remoto pode manter o foco e consumir o acorde antes de o
    // Focus.onKeyEvent do shell receber a tecla. O handler global garante que
    // os atalhos continuem funcionando como no Parsec, mas só para a aba ativa.
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    // Este estado Ã© lido pelo shell antes de o filho RemotePage entrar na
    // Ã¡rvore. Sem registrar os estados compartilhados neste ponto, o GetX
    // lanÃ§a "Instance not found" no primeiro frame e o Hub fica cinza.
    initSharedStates(widget.remoteId);
    _inputBlocked = BlockInputState.find(widget.remoteId);
    RemoteSessionsManager.instance
        .registerShortcutHandler(widget.deviceId, _runShortcut);
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
    if (_isActiveKeyboardSession()) {
      stateGlobal.setFullscreen(false, procWnd: false);
    }
    if (isWindows) {
      bind.hostStopSystemKeyPropagate(stopped: false);
    }
    _ffi?.inputModel.enterOrLeave(false);
    RemoteSessionsManager.instance.unregisterShortcutHandler(widget.deviceId);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    if (_inputBlocked.isTrue) {
      bind.sessionToggleOption(sessionId: _sessionId, value: 'unblock-input');
    }
    if (_clipboardOn.isTrue) {
      bind.sessionToggleOption(
        sessionId: _sessionId,
        value: 'disable-clipboard',
      );
    }
    if (_fileTransferOn.isTrue) {
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
    _lastPoint = null;
    _drawingOn.toggle();
    _focusNode.requestFocus();
    _notify(_drawingOn.isTrue ? 'Anotação ativada' : 'Anotação encerrada');
  }

  void _toggleClipboard() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: 'disable-clipboard',
    );
    _clipboardOn.toggle();
    _notify(_clipboardOn.isTrue
        ? 'Copiar e colar ativado'
        : 'Copiar e colar desativado');
  }

  void _toggleFileTransfer() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: kOptionEnableFileCopyPaste,
    );
    _fileTransferOn.toggle();
    _notify(_fileTransferOn.isTrue
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

  /// Tudo que é comando de sessão passa por aqui — atalho nativo, tecla vista
  /// pelo Flutter ou clique no botão do toolbar. Um caminho só significa um
  /// comportamento só, e o estado que os botões mostram nunca discorda do que
  /// o teclado acabou de fazer.
  bool _runShortcut(String action) {
    final now = DateTime.now().microsecondsSinceEpoch;
    // O mesmo toque pode chegar pelo hook nativo E pelo teclado do Flutter.
    // Sem esta janela, um comando alternaria duas vezes e pareceria inerte.
    if (now - (_lastShortcutMicros[action] ?? 0) < 200000) return true;
    _lastShortcutMicros[action] = now;
    switch (action) {
      case tgdeskActionSystemKeys:
        _toggleSystemKeys();
        break;
      case tgdeskActionBlockInput:
        _toggleInputBlock();
        break;
      case tgdeskActionDrawing:
        _toggleDrawing();
        break;
      case tgdeskActionClipboard:
        _toggleClipboard();
        break;
      case tgdeskActionFileTransfer:
        _toggleFileTransfer();
        break;
      default:
        return false;
    }
    return true;
  }

  /// A tecla de cada comando, do lado do Flutter. É a mesma tabela do Rust;
  /// aqui ela existe para o caso em que o acorde chega pelo teclado normal —
  /// janela em foco e nenhum hook no meio.
  static final _shortcutKeys = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.keyI: tgdeskActionSystemKeys,
    LogicalKeyboardKey.keyB: tgdeskActionBlockInput,
    LogicalKeyboardKey.keyD: tgdeskActionDrawing,
    LogicalKeyboardKey.keyC: tgdeskActionClipboard,
    LogicalKeyboardKey.keyF: tgdeskActionFileTransfer,
  };

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent || !_isActiveKeyboardSession()) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed || !keys.isShiftPressed) return false;
    final action = _shortcutKeys[event.logicalKey];
    if (action == null) return false;
    return _runShortcut(action);
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
        _drawingOn.isFalse) {
      stateGlobal.setFullscreen(false);
      return KeyEventResult.handled;
    }
    if (keys.isControlPressed && keys.isShiftPressed) {
      final action = _shortcutKeys[event.logicalKey];
      if (action != null) {
        return _runShortcut(action)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
    }
    if (_drawingOn.isTrue && event.logicalKey == LogicalKeyboardKey.escape) {
      _toggleDrawing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Os comandos de sessão, um botão cada, no toolbar flutuante. A ordem é a
  /// mesma da tabela de atalhos, e cada dica de tela repete o acorde: o botão
  /// ensina o atalho, e quem já sabe o atalho não precisa do botão.
  List<TgdeskToolbarAction> _toolbarActions() => [
        TgdeskToolbarAction(
          active: _inputBlocked,
          activeIcon: Icons.keyboard_alt_outlined,
          inactiveIcon: Icons.keyboard_hide_outlined,
          activeTooltip: 'Liberar mouse e teclado do cliente (Ctrl+Shift+B)',
          inactiveTooltip: 'Bloquear mouse e teclado do cliente (Ctrl+Shift+B)',
          onPressed: () => _runShortcut(tgdeskActionBlockInput),
        ),
        TgdeskToolbarAction(
          active: _drawingOn,
          activeIcon: Icons.edit_off_outlined,
          inactiveIcon: Icons.draw_outlined,
          activeTooltip: 'Encerrar anotação (Ctrl+Shift+D)',
          inactiveTooltip: 'Anotar na tela do cliente (Ctrl+Shift+D)',
          onPressed: () => _runShortcut(tgdeskActionDrawing),
        ),
        TgdeskToolbarAction(
          active: _clipboardOn,
          activeIcon: Icons.content_paste_go_outlined,
          inactiveIcon: Icons.content_paste_off_outlined,
          activeTooltip: 'Desativar copiar e colar (Ctrl+Shift+C)',
          inactiveTooltip: 'Ativar copiar e colar (Ctrl+Shift+C)',
          onPressed: () => _runShortcut(tgdeskActionClipboard),
        ),
        TgdeskToolbarAction(
          active: _fileTransferOn,
          activeIcon: Icons.file_copy_outlined,
          inactiveIcon: Icons.folder_off_outlined,
          activeTooltip: 'Desativar transferência de arquivos (Ctrl+Shift+F)',
          inactiveTooltip: 'Ativar transferência de arquivos (Ctrl+Shift+F)',
          onPressed: () => _runShortcut(tgdeskActionFileTransfer),
        ),
      ];

  /// O que sobrou do menu: diagnóstico não é um comando que se liga e desliga,
  /// é uma janela que se abre. Botão de estado seria mentira para ele.
  Widget _tgdeskToolbarMenu(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Ferramentas TGDesk',
        icon: const Icon(Icons.build_circle_outlined, size: 20),
        onSelected: (value) {
          if (value == 'diagnostics') {
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => DiagnosticDialog(
                deviceId: widget.deviceId,
                deviceName: widget.hostname,
                online: true,
              ),
            );
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
                tgdeskActions: _toolbarActions(),
                tgdeskCloseSession: () {
                  _notify('Sessão remota encerrada');
                  RemoteSessionsManager.instance.close(widget.deviceId);
                },
              ),
            ),
          ),
          // Camada de sobreposição num Obx só: os comandos agora vivem em
          // observáveis, porque o mesmo estado é lido daqui e dos botões do
          // toolbar, que são construídos lá dentro da RemotePage. Um setState
          // desta classe não alcançaria os dois.
          Positioned.fill(
            child: Obx(() {
              final drawing = _drawingOn.value;
              final clipboard = _clipboardOn.value;
              final files = _fileTransferOn.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (drawing)
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
                  if (_inputBlocked.value)
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
                  if (drawing) _drawingToolbar(),
                  if (clipboard || files)
                    Positioned(
                      left: 14,
                      bottom: 14,
                      child: _StatusChip(
                        icon: files
                            ? Icons.file_copy_outlined
                            : Icons.content_paste_go_outlined,
                        text: clipboard && files
                            ? 'Copiar, colar e arquivos ativos'
                            : files
                                ? 'Transferência de arquivos ativa'
                                : 'Copiar e colar ativo',
                        color: const Color(0xff35a7ff),
                        onTap: files ? _toggleFileTransfer : _toggleClipboard,
                      ),
                    ),
                ],
              );
            }),
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

/// Os comandos com atalho saíram do menu e viraram botão; o que sobra aqui não
/// tem acorde para mostrar.
class _MenuEntry extends StatelessWidget {
  const _MenuEntry({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
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
