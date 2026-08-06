
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../main.dart' show kWindowId;
import 'remote_session_tabs.dart';
import 'startup_settings.dart';
import 'theme.dart';

/// Andamento da atualização que o servidor mandou aplicar. Só leitura: a
/// decisão de atualizar deixou de ser do cliente, então a barra de título
/// informa em vez de oferecer.
class TgdeskUpdateStatus {
  const TgdeskUpdateStatus({
    required this.updating,
    this.version = '',
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.bytesPerSecond = 0,
    this.throttleKbps = 0,
  });

  final bool updating;
  final String version;
  final int totalBytes;
  final int downloadedBytes;
  final int bytesPerSecond;

  /// Teto imposto pelo servidor quando a fila está grande. Aparece na tela
  /// porque "está lento" precisa ser explicável.
  final int throttleKbps;

  double? get fraction =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : null;

  String get speedLabel {
    if (bytesPerSecond <= 0) return '';
    final mb = bytesPerSecond / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB/s';
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }

  String get label {
    final parts = <String>[
      version.isEmpty ? 'Atualizando' : 'Atualizando para $version',
      if (speedLabel.isNotEmpty) speedLabel,
      if (throttleKbps > 0) 'velocidade limitada pelo servidor',
    ];
    return parts.join(' — ');
  }
}

/// A janela nativa do TGDesk roda com a barra de título do Windows escondida
/// (`TitleBarStyle.hidden`, ver main.dart). Sem uma região de arrasto no lado
/// Flutter, a janela não pode ser movida — só redimensionada pela borda. Este
/// widget devolve essa capacidade: uma barra de título própria, arrastável,
/// com os botões minimizar/maximizar/fechar, funcionando tanto na janela
/// principal (`windowManager`) quanto nas sub-janelas multi-window do Hub
/// (`WindowController`, identificadas por [kWindowId] != null).
class TgdeskWindowScaffold extends StatefulWidget {
  const TgdeskWindowScaffold({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.productName = 'TGDesk',
    this.deviceName,
    this.onRenameDevice,
    this.updateStatus,
  });

  /// Conteúdo abaixo da barra de título.
  final Widget child;

  /// Widget exibido à esquerda da barra (logo, título, etc). Se nulo, usa o
  /// logo horizontal padrão.
  final Widget? title;

  /// Ações extras (à esquerda dos botões de janela).
  final List<Widget>? actions;
  final String productName;

  /// Nome atual do computador e como salvá-lo. Quando ausente, o menu não
  /// oferece a edição — é o caso das sub-janelas do Hub, que não representam
  /// um dispositivo.
  final String? deviceName;
  final Future<void> Function(String)? onRenameDevice;

  /// Atualização em curso, empurrada pelo servidor. Só indicador: não há mais
  /// nada para clicar.
  final TgdeskUpdateStatus? updateStatus;

  @override
  State<TgdeskWindowScaffold> createState() => _TgdeskWindowScaffoldState();
}

class _TgdeskWindowScaffoldState extends State<TgdeskWindowScaffold>
    with WindowListener {
  bool get _isMainWindow => kWindowId == null;
  bool _startWithWindows = true;

  @override
  void initState() {
    super.initState();
    if (_isMainWindow) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      tgdeskStartsWithWindows().then((value) {
        if (mounted) setState(() => _startWithWindows = value);
      });
    }
  }

  @override
  void dispose() {
    if (_isMainWindow) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_isMainWindow) windowManager.hide();
  }

  void _startDragging() {
    if (_isMainWindow) {
      windowManager.startDragging();
    } else {
      WindowController.fromWindowId(kWindowId!).startDragging();
    }
  }

  Future<void> _minimize() async {
    if (_isMainWindow) {
      await windowManager.minimize();
    } else {
      await WindowController.fromWindowId(kWindowId!).minimize();
    }
  }

  Future<void> _toggleMaximize() async {
    if (_isMainWindow) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } else {
      final c = WindowController.fromWindowId(kWindowId!);
      // desktop_multi_window não expõe isMaximized; alterna pelo próprio SO.
      await c.maximize();
    }
  }

  Future<void> _close() async {
    if (_isMainWindow) {
      await windowManager.hide();
    } else {
      await WindowController.fromWindowId(kWindowId!).close();
    }
  }


  Future<void> _promptRename() async {
    final controller = TextEditingController(text: widget.deviceName ?? '');
    final novo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nome deste computador'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nome',
              helperText: 'É como o técnico identifica este computador.',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (novo == null || widget.onRenameDevice == null) return;
    try {
      await widget.onRenameDevice!(novo.trim());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  /// O menu substitui a janela de configuração: o que sobrou depois de a
  /// atualização virar decisão do servidor cabe em duas linhas, e uma janela
  /// inteira para isso era peso sem função.
  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: Icon(Icons.menu,
          size: 18, color: Theme.of(context).colorScheme.onSurface),
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == 'startup') {
          final novo = !_startWithWindows;
          await setTgdeskStartsWithWindows(novo);
          if (mounted) setState(() => _startWithWindows = novo);
        } else if (value == 'rename') {
          await _promptRename();
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem<String>(
          value: 'startup',
          checked: _startWithWindows,
          child: const Text('Iniciar com o Windows'),
        ),
        if (widget.onRenameDevice != null)
          const PopupMenuItem<String>(
            value: 'rename',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.badge_outlined),
              title: Text('Editar nome'),
            ),
          ),
      ],
    );
  }

  /// Indicador, não botão. A atualização é empurrada pelo servidor e não há o
  /// que clicar — o que a tela deve é explicar o que está acontecendo,
  /// inclusive por que está devagar quando a fila está grande.
  Widget _buildUpdateIndicator(BuildContext context, TgdeskUpdateStatus status) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TgdeskSpacing.sm),
      child: Tooltip(
        message: status.label,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, value: status.fraction),
          ),
          if (status.speedLabel.isNotEmpty) ...[
            const SizedBox(width: TgdeskSpacing.xs),
            Text(status.speedLabel,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (status.throttleKbps > 0) ...[
            const SizedBox(width: 4),
            Icon(Icons.speed,
                size: 14, color: Theme.of(context).colorScheme.outline),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTitleBar(context),
          const Divider(height: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(left: TgdeskSpacing.md),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
          children: [
            widget.title ??
                Image.asset('assets/tgdesk_logo_horizontal.png', height: 22),
            // As sessões de acesso remoto vivem aqui, como abas de navegador:
            // a máquina que se está operando é o assunto da janela, não um
            // item entre os destinos da barra lateral. Sem sessão aberta não
            // ocupa espaço nenhum.
            if (_isMainWindow) const RemoteSessionTabs(),
            const Spacer(),
            if (widget.actions != null) ...widget.actions!,
            if (widget.updateStatus?.updating == true)
              _buildUpdateIndicator(context, widget.updateStatus!),
            if (_isMainWindow) _buildMenu(context),
            _WindowButton(
                icon: Icons.remove, onTap: _minimize, tooltip: 'Minimizar'),
            _WindowButton(
                icon: Icons.crop_square,
                onTap: _toggleMaximize,
                tooltip: 'Maximizar'),
            _WindowButton(
              icon: Icons.close,
              onTap: _close,
              tooltip: 'Fechar',
              hoverColor: Colors.red.shade700,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.hoverColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color? hoverColor;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovering
        ? (widget.hoverColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest)
        : Colors.transparent;
    final fg = _hovering && widget.hoverColor != null
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 40,
            color: bg,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
