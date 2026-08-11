import 'dart:convert';
import 'dart:async';

import 'package:window_manager/window_manager.dart';

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

/// As duas fontes de entrada do núcleo (keyboard.rs::input_source).
///
/// A "1" é o gancho global do rdev: ele fica na frente do Windows e engole
/// Alt+Tab, tecla Windows e afins para mandá-los ao computador remoto. A "2"
/// são os eventos de teclado da própria janela: as teclas normais continuam
/// chegando ao remoto, mas os atalhos do sistema seguem sendo do computador
/// do técnico. É essa troca que o Ctrl+Shift+I faz.
const kInputSourceGrab = 'Input source 1';
const kInputSourceFlutter = 'Input source 2';

/// Nomes dos comandos, iguais dos dois lados da ponte.
const tgdeskActionSystemKeys = 'system_keys';
const tgdeskActionBlockInput = 'block_input';
const tgdeskActionDrawing = 'drawing';
const tgdeskActionClipboard = 'clipboard';
const tgdeskActionFileTransfer = 'file_transfer';
const tgdeskActionMicrophone = 'microphone';
const tgdeskActionRemoteAudio = 'remote_audio';
/// Prefixo dos acordes de tela: 'display_1' a 'display_10'. O sufixo é a
/// posição na lista de telas do cliente, contando de 1, e o Ctrl+Shift+0 é a
/// décima. Espelha keyboard.rs::TGDESK_SHORTCUTS.
const tgdeskActionDisplayPrefix = 'display_';

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

class _TgdeskRemoteSessionPageState extends State<TgdeskRemoteSessionPage>
    with WindowListener {
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
  // Meu microfone começa DESLIGADO: o cliente não deve me ouvir sem que eu
  // tenha pedido isso uma vez, de propósito.
  final RxBool _microphoneOn = false.obs;
  // O som do PC do cliente começa LIGADO — é o motivo de estar na sessão.
  final RxBool _remoteAudioOn = true.obs;
  bool _eraser = false;
  // Começa DESLIGADO, e só o botão do toolbar ou o Ctrl+Shift+I ligam.
  //
  // Antes a captura subia sozinha quando a janela ganhava o foco: bastava
  // clicar na tela remota para o técnico perder Alt+Tab e a tecla Windows no
  // próprio computador, sem ter pedido nada. Quem decide entregar os atalhos
  // do sistema à máquina remota é o técnico, uma vez, de propósito.
  final RxBool _captureSystemKeys = false.obs;
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
    // A sessão nasce sem grabber. É esta linha que devolve o Alt+Tab: com a
    // fonte de entrada do Flutter, as teclas continuam chegando à máquina
    // remota pelos eventos da janela, mas nenhum gancho global do RustDesk
    // engole atalho de sistema no computador do técnico.
    _applySystemKeysCapture(false);
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
    if (widget.embedded) windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final sessionId = _sessionId;
      // Copiar e colar e transferência de arquivos nascem LIGADOS.
      //
      // Levar um arquivo até a máquina do cliente e colar um texto no chamado
      // é o feijão com arroz do atendimento; começar com os dois desligados
      // fazia o técnico ter de ligá-los toda vez, sem que houvesse decisão
      // nenhuma a tomar ali. Quem quiser desligar tem o botão e o atalho.
      //
      // O estado é imposto aqui, e não restaurado ao sair: o que vale é o que
      // a sessão decide ao abrir, não o que ficou guardado da anterior.
      final clipboardDisabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId,
        arg: 'disable-clipboard',
      );
      if (clipboardDisabled) {
        await bind.sessionToggleOption(
          sessionId: sessionId,
          value: 'disable-clipboard',
        );
      }
      final fileTransferEnabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId,
        arg: kOptionEnableFileCopyPaste,
      );
      if (!fileTransferEnabled) {
        await bind.sessionToggleOption(
          sessionId: sessionId,
          value: kOptionEnableFileCopyPaste,
        );
      }
      // 'disable-audio' é lembrado por dispositivo, então o estado do botão vem
      // do que ficou guardado, não de um palpite.
      final audioDisabled = bind.sessionGetToggleOptionSync(
        sessionId: sessionId,
        arg: 'disable-audio',
      );
      if (!mounted) return;
      _clipboardOn.value = true;
      _fileTransferOn.value = true;
      _remoteAudioOn.value = !audioDisabled;
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
    if (widget.embedded) windowManager.removeListener(this);
    RemoteSessionsManager.instance.unregisterShortcutHandler(widget.deviceId);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    if (_inputBlocked.isTrue) {
      bind.sessionToggleOption(sessionId: _sessionId, value: 'unblock-input');
    }
    // O microfone é o único destes que não pode ficar ligado: sair da sessão
    // com ele aberto deixaria o cliente me ouvindo sem eu estar olhando.
    if (_microphoneOn.isTrue) {
      bind.sessionCloseVoiceCall(sessionId: _sessionId);
    }
    // Copiar e colar e arquivos não são mais desfeitos aqui. Ficam ligados,
    // que é como a próxima sessão vai querê-los de qualquer forma — e a
    // próxima impõe o estado ao abrir, então desligar na saída era só trabalho
    // para ser refeito.
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
    _notify(
      willBlock
          ? 'Entrada local do cliente bloqueada'
          : 'Entrada local do cliente liberada',
      icon: willBlock
          ? Icons.keyboard_hide_outlined
          : Icons.keyboard_alt_outlined,
      color: willBlock ? const Color(0xffffb020) : const Color(0xff35a7ff),
    );
  }

  /// Aviso passageiro, com o desenho da tarja escura que antes ficava fixa na
  /// tela.
  ///
  /// Eram duas coisas erradas ao mesmo tempo: a tarja bonita nunca saía —
  /// virava sujeira permanente sobre o desktop do cliente — e o que sumia
  /// sozinho era a barra branca do Material, que destoava de tudo. Agora o
  /// estado de cada comando é o botão aceso no toolbar, e a tarja voltou ao
  /// que serve: dizer o que acabou de acontecer e sair.
  void _notify(
    String text, {
    IconData icon = Icons.info_outline,
    Color color = const Color(0xff35a7ff),
  }) {
    BotToast.showCustomText(
      duration: const Duration(seconds: 3),
      align: const Alignment(0, 0.82),
      onlyOne: true,
      clickClose: true,
      toastBuilder: (_) => _StatusChip(icon: icon, text: text, color: color),
    );
  }

  void _toggleDrawing() {
    _lastPoint = null;
    _drawingOn.toggle();
    _focusNode.requestFocus();
    _notify(
      _drawingOn.isTrue ? 'Anotação ativada' : 'Anotação encerrada',
      icon: _drawingOn.isTrue ? Icons.draw_outlined : Icons.edit_off_outlined,
    );
  }

  void _toggleClipboard() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: 'disable-clipboard',
    );
    _clipboardOn.toggle();
    _notify(
      _clipboardOn.isTrue
          ? 'Copiar e colar ativado'
          : 'Copiar e colar desativado',
      icon: _clipboardOn.isTrue
          ? Icons.content_paste_go_outlined
          : Icons.content_paste_off_outlined,
    );
  }

  void _toggleFileTransfer() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: kOptionEnableFileCopyPaste,
    );
    _fileTransferOn.toggle();
    _notify(
      _fileTransferOn.isTrue
          ? 'Transferência de arquivos ativada'
          : 'Transferência de arquivos desativada',
      icon: _fileTransferOn.isTrue
          ? Icons.file_copy_outlined
          : Icons.folder_off_outlined,
    );
  }

  /// Manda o meu microfone para as caixas do cliente, ou para de mandar.
  ///
  /// Nada do cliente é capturado aqui, e por isso o outro lado aceita sem
  /// perguntar — ele só mostra que está ativo, e pode encerrar quando quiser.
  void _toggleMicrophone() {
    if (_microphoneOn.isTrue) {
      bind.sessionCloseVoiceCall(sessionId: _sessionId);
    } else {
      bind.sessionRequestVoiceCall(sessionId: _sessionId);
    }
    _microphoneOn.toggle();
    _notify(
      _microphoneOn.isTrue
          ? 'Microfone ligado — o cliente está te ouvindo'
          : 'Microfone desligado',
      icon: _microphoneOn.isTrue ? Icons.mic_none : Icons.mic_off_outlined,
    );
  }

  /// Liga e desliga a minha escuta do som do PC do cliente.
  ///
  /// Isso não silencia o cliente: as caixas dele continuam como estavam, e a
  /// minha voz continua saindo lá mesmo com a escuta desligada.
  void _toggleRemoteAudio() {
    bind.sessionToggleOption(
      sessionId: _sessionId,
      value: 'disable-audio',
    );
    _remoteAudioOn.toggle();
    _notify(
      _remoteAudioOn.isTrue
          ? 'Escutando o som do cliente'
          : 'Som do cliente silenciado aqui',
      icon: _remoteAudioOn.isTrue
          ? Icons.volume_up_outlined
          : Icons.volume_off_outlined,
    );
  }

  /// Liga e desliga o grabber, que é o que realmente decide quem fica com o
  /// Alt+Tab.
  ///
  /// A flag de propagação sozinha nunca resolveu: quem engole as teclas é o
  /// laço do rdev, e ele roda enquanto a fonte de entrada for a "1". Trocar
  /// para a fonte do Flutter desliga o gancho global inteiro — as teclas
  /// continuam indo à máquina remota pelos eventos da janela, e os atalhos do
  /// Windows voltam a ser do computador do técnico.
  Future<void> _applySystemKeysCapture(bool capture) async {
    await stateGlobal.setInputSource(
      _sessionId,
      capture ? kInputSourceGrab : kInputSourceFlutter,
    );
    if (isWindows) {
      bind.hostStopSystemKeyPropagate(stopped: capture);
    }
    _ffi?.inputModel.enterOrLeave(capture);
  }

  void _toggleSystemKeys() {
    _captureSystemKeys.toggle();
    final capture = _captureSystemKeys.value;
    // O foco fica onde está nos dois casos. Tirá-lo ao soltar os atalhos
    // interrompia a digitação — e soltar Alt+Tab nunca quis dizer parar de
    // escrever na máquina remota.
    _focusNode.requestFocus();
    unawaited(_applySystemKeysCapture(capture));
    _notify(
      capture
          ? 'Atalhos do Windows enviados ao computador remoto'
          : 'Atalhos do Windows liberados neste computador',
      icon: capture ? Icons.keyboard_tab : Icons.keyboard,
    );
  }

  /// Voltar para a janela devolve o teclado e o mouse à sessão.
  ///
  /// A RemotePage escuta as janelas do multi-window, que não é por onde os
  /// eventos da janela principal passam — então, embutida no Hub, ela nunca
  /// sabia que a janela voltou. O foco ficava solto, e com ele a marca de
  /// "sessão atual" que o núcleo usa para rotear mouse e teclado: a tela
  /// remota continuava desenhando e não respondia a nada.
  ///
  /// Era por isso que ligar a captura ressuscitava a entrada — ela chama este
  /// mesmo enterOrLeave por outro caminho. Consertar o sintoma pelo atalho
  /// seria consertar pelo lugar errado.
  @override
  void onWindowFocus() {
    super.onWindowFocus();
    if (!mounted || !_isActiveKeyboardSession()) return;
    _focusNode.requestFocus();
    _ffi?.inputModel.enterOrLeave(true);
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
      case tgdeskActionMicrophone:
        _toggleMicrophone();
        break;
      case tgdeskActionRemoteAudio:
        _toggleRemoteAudio();
        break;
      default:
        if (action.startsWith(tgdeskActionDisplayPrefix)) {
          return _switchDisplay(action);
        }
        return false;
    }
    return true;
  }

  /// Mostra a tela de número `action` do cliente, contando de 1.
  ///
  /// A lista do `PeerInfo` traz telas físicas e virtuais na mesma ordem em que
  /// o cliente as reporta, então o atalho alcança as duas sem precisar
  /// distingui-las. Pedir uma tela que não existe não faz nada — quem tem dois
  /// monitores aperta o 5 e continua vendo o que via, em vez de ficar com a
  /// sessão em branco.
  bool _switchDisplay(String action) {
    final ffi = _ffi;
    if (ffi == null) return false;
    final number = int.tryParse(
      action.substring(tgdeskActionDisplayPrefix.length),
    );
    if (number == null || number < 1) return false;
    final pi = ffi.ffiModel.pi;
    final index = number - 1;
    if (index >= pi.displays.length) return true;
    if (index == pi.currentDisplay) return true;
    openMonitorInTheSameTab(index, ffi, pi);
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
    LogicalKeyboardKey.keyM: tgdeskActionMicrophone,
    LogicalKeyboardKey.keyA: tgdeskActionRemoteAudio,
    LogicalKeyboardKey.digit1: '${tgdeskActionDisplayPrefix}1',
    LogicalKeyboardKey.digit2: '${tgdeskActionDisplayPrefix}2',
    LogicalKeyboardKey.digit3: '${tgdeskActionDisplayPrefix}3',
    LogicalKeyboardKey.digit4: '${tgdeskActionDisplayPrefix}4',
    LogicalKeyboardKey.digit5: '${tgdeskActionDisplayPrefix}5',
    LogicalKeyboardKey.digit6: '${tgdeskActionDisplayPrefix}6',
    LogicalKeyboardKey.digit7: '${tgdeskActionDisplayPrefix}7',
    LogicalKeyboardKey.digit8: '${tgdeskActionDisplayPrefix}8',
    LogicalKeyboardKey.digit9: '${tgdeskActionDisplayPrefix}9',
    LogicalKeyboardKey.digit0: '${tgdeskActionDisplayPrefix}10',
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
        TgdeskToolbarAction(
          active: _microphoneOn,
          activeIcon: Icons.mic_none,
          inactiveIcon: Icons.mic_off_outlined,
          activeTooltip: 'Desligar meu microfone (Ctrl+Shift+M)',
          inactiveTooltip: 'Falar no computador do cliente (Ctrl+Shift+M)',
          onPressed: () => _runShortcut(tgdeskActionMicrophone),
        ),
        TgdeskToolbarAction(
          active: _remoteAudioOn,
          activeIcon: Icons.volume_up_outlined,
          inactiveIcon: Icons.volume_off_outlined,
          activeTooltip: 'Parar de escutar o som do cliente (Ctrl+Shift+A)',
          inactiveTooltip: 'Escutar o som do cliente (Ctrl+Shift+A)',
          onPressed: () => _runShortcut(tgdeskActionRemoteAudio),
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
          // Sobra a anotação. As tarjas de estado saíram daqui: o que está
          // ligado agora se lê no botão aceso do toolbar, que é onde também se
          // desliga. Tarja fixa sobre o desktop do cliente só tapava a tela do
          // que o técnico foi ver.
          Positioned.fill(
            child: Obx(() {
              if (_drawingOn.isFalse) return const SizedBox.shrink();
              return Stack(
                fit: StackFit.expand,
                children: [
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
                  _drawingToolbar(),
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

/// A tarja escura dos avisos. Nasceu fixa na tela e virou passageira, mas o
/// desenho é o mesmo — era a parte que estava certa.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xff111820).withOpacity(.96),
        elevation: 6,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(color: Colors.white)),
          ]),
        ),
      );
}
