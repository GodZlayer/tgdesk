import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../main.dart' show kWindowId;
import 'startup_settings.dart';
import 'theme.dart';

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
  });

  /// Conteúdo abaixo da barra de título.
  final Widget child;

  /// Widget exibido à esquerda da barra (logo, título, etc). Se nulo, usa o
  /// logo horizontal padrão.
  final Widget? title;

  /// Ações extras (à esquerda dos botões de janela).
  final List<Widget>? actions;
  final String productName;

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

  Future<void> _showStartupSettings() async {
    var enabled = _startWithWindows;
    var updating = false;
    String? updateMessage;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Configurações do ${widget.productName}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Iniciar com o Windows'),
                  subtitle: Text(
                      'Abre a interface do ${widget.productName} automaticamente após entrar no Windows.'),
                  value: enabled,
                  onChanged: (value) async {
                    await setTgdeskStartsWithWindows(value);
                    enabled = value;
                    if (mounted) setState(() => _startWithWindows = value);
                    setDialogState(() {});
                  },
                ),
                const Divider(),
                const Text('Recuperação de atualização',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: TgdeskSpacing.xs),
                Text(
                    'Use quando uma versão não receber o aviso automático. O ${widget.productName} consultará diretamente o servidor e instalará a versão mais recente.'),
                const SizedBox(height: TgdeskSpacing.md),
                OutlinedButton.icon(
                  onPressed: updating
                      ? null
                      : () async {
                          setDialogState(() {
                            updating = true;
                            updateMessage = 'Consultando o servidor...';
                          });
                          try {
                            final result = await Process.run(
                              Platform.resolvedExecutable,
                              const ['--tgdesk-update'],
                              workingDirectory:
                                  File(Platform.resolvedExecutable).parent.path,
                            );
                            if (result.exitCode == 10) {
                              setDialogState(() => updateMessage =
                                  'Atualização iniciada. O ${widget.productName} será reiniciado.');
                              await Future<void>.delayed(
                                  const Duration(milliseconds: 500));
                              exit(0);
                            }
                            final output = [
                              result.stdout.toString().trim(),
                              result.stderr.toString().trim()
                            ].where((value) => value.isNotEmpty).join('\n');
                            setDialogState(() {
                              updateMessage = output.isEmpty
                                  ? 'O ${widget.productName} já está atualizado.'
                                  : output;
                              updating = false;
                            });
                          } catch (e) {
                            setDialogState(() {
                              updateMessage =
                                  'Não foi possível executar a atualização: $e';
                              updating = false;
                            });
                          }
                        },
                  icon: updating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_alt),
                  label: Text(updating
                      ? 'Verificando...'
                      : 'Buscar e forçar atualização'),
                ),
                if (updateMessage != null) ...[
                  const SizedBox(height: TgdeskSpacing.sm),
                  Text(updateMessage!,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  updating ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
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
            const Spacer(),
            if (widget.actions != null) ...widget.actions!,
            if (_isMainWindow)
              _WindowButton(
                icon: Icons.settings_outlined,
                onTap: _showStartupSettings,
                tooltip: 'Configurações',
              ),
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
