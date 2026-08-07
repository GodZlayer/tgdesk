import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/screen/desktop_remote_screen.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';

import 'diagnostics_dialog.dart';
import 'window_frame.dart';

const _annotationPrefix = '__TGDESK_ANNOTATION__:';

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
  bool _inputBlocked = false;
  bool _drawing = false;
  bool _eraser = false;
  bool _clipboardEnabled = false;
  bool _fileTransferEnabled = false;
  Color _color = const Color(0xffff3b30);
  double _strokeWidth = 5;
  Offset? _lastPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final sessionId = gFFI.sessionId;
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
    if (_inputBlocked) {
      bind.sessionToggleOption(
          sessionId: gFFI.sessionId, value: 'unblock-input');
    }
    if (_clipboardEnabled) {
      bind.sessionToggleOption(
        sessionId: gFFI.sessionId,
        value: 'disable-clipboard',
      );
    }
    if (_fileTransferEnabled) {
      bind.sessionToggleOption(
        sessionId: gFFI.sessionId,
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
    if (RemoteSessionsManager.instance.sessions.isEmpty) {
      stateGlobal.tgdeskEmbedTop = 0;
      stateGlobal.tgdeskEmbedLeft = 0;
      stateGlobal.tgdeskEmbedRight = 0;
      stateGlobal.tgdeskEmbedBottom = 0;
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleInputBlock() {
    bind.sessionToggleOption(
      sessionId: gFFI.sessionId,
      value: _inputBlocked ? 'unblock-input' : 'block-input',
    );
    setState(() => _inputBlocked = !_inputBlocked);
  }

  void _toggleDrawing() {
    setState(() {
      _drawing = !_drawing;
      _lastPoint = null;
    });
    _focusNode.requestFocus();
  }

  void _toggleClipboard() {
    bind.sessionToggleOption(
      sessionId: gFFI.sessionId,
      value: 'disable-clipboard',
    );
    setState(() => _clipboardEnabled = !_clipboardEnabled);
  }

  void _toggleFileTransfer() {
    bind.sessionToggleOption(
      sessionId: gFFI.sessionId,
      value: kOptionEnableFileCopyPaste,
    );
    setState(() => _fileTransferEnabled = !_fileTransferEnabled);
  }

  void _clearDrawing() {
    setState(_segments.clear);
    _sendAnnotation(const {'t': 'ClearDrawing'});
  }

  void _sendAnnotation(Map<String, dynamic> event) {
    bind.sessionSendChat(
      sessionId: gFFI.sessionId,
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

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
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
              icon: _inputBlocked
                  ? Icons.keyboard_alt_outlined
                  : Icons.keyboard_hide_outlined,
              text: _inputBlocked
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
  final GlobalKey _areaKey = GlobalKey();

  void _medirRecuo() {
    final render = _areaKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final origem = render.localToGlobal(Offset.zero);
    final janela = MediaQuery.sizeOf(context);
    final direita = (janela.width - origem.dx - render.size.width)
        .clamp(0, double.infinity);
    final inferior = (janela.height - origem.dy - render.size.height)
        .clamp(0, double.infinity);
    if (stateGlobal.tgdeskEmbedTop != origem.dy ||
        stateGlobal.tgdeskEmbedLeft != origem.dx ||
        stateGlobal.tgdeskEmbedRight != direita ||
        stateGlobal.tgdeskEmbedBottom != inferior) {
      stateGlobal.tgdeskEmbedTop = origem.dy;
      stateGlobal.tgdeskEmbedLeft = origem.dx;
      stateGlobal.tgdeskEmbedRight = direita.toDouble();
      stateGlobal.tgdeskEmbedBottom = inferior.toDouble();
    }
  }

  Widget _buildContent() {
    // Medido a cada quadro: a janela muda de tamanho, a barra lateral aparece
    // e some, e a tela cheia zera os dois. Comparar antes de escrever mantém
    // isso barato.
    WidgetsBinding.instance.addPostFrameCallback((_) => _medirRecuo());
    return Container(
      key: _areaKey,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DesktopRemoteScreen(params: {
            'id': widget.remoteId,
            'windowId': 0,
            'embedded': true,
            'forceRelay': true,
            'password': widget.credential,
            'tgdeskToolbarMenuBuilder': _tgdeskToolbarMenu,
          }),
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
          if (_inputBlocked)
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
