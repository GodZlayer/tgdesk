import 'package:flutter/material.dart';

import 'remote_session_page.dart';
import 'theme.dart';

/// As sessões de acesso remoto como abas na barra de título.
///
/// O dispositivo acessado vira uma aba ao lado do logo, como no navegador: a
/// máquina que se está operando é o assunto da janela inteira, não um item de
/// menu lateral que se escolhe entre outros. Enquanto era destino da barra
/// lateral, ela ficava no mesmo nível de "Chamados" e "Técnicos" — telas que a
/// pessoa consulta —, e não dava para saber quantas sessões estavam abertas
/// sem entrar na aba.
///
/// Sem sessão aberta o widget não ocupa espaço nenhum: a barra volta a ser só
/// o logo, e nada indica uma função que não está em uso.
class RemoteSessionTabs extends StatelessWidget {
  const RemoteSessionTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = RemoteSessionsManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        if (manager.sessions.isEmpty) return const SizedBox.shrink();
        // Sem Flexible aqui: quem decide a largura desta faixa é a barra de
        // título, que reserva a coluna do meio. Este widget só preenche o que
        // recebe — e rola por dentro quando as abas não cabem.
        return Row(
          children: [
            const SizedBox(width: TgdeskSpacing.md),
            Expanded(
              child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  onReorder: manager.reorder,
                  // A alça de arrasto é a aba inteira. Uma alça separada
                  // exigiria mirar num pedaço de 30 pixels de altura, e a aba
                  // já é o objeto que se quer mover.
                  itemCount: manager.sessions.length,
                  itemBuilder: (context, index) => ReorderableDragStartListener(
                    key: ValueKey(manager.sessions[index].deviceId),
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(right: TgdeskSpacing.xs),
                      child: _Tab(
                        entry: manager.sessions[index],
                        selected: index == manager.activeIndex,
                        onSelect: () => manager.focus(index),
                        onClose: () => manager.closeAt(index),
                      ),
                    ),
                  ),
                  // Sem a sombra e o realce padrão do Material: a aba
                  // arrastada some do lugar e reaparece maior no cursor, o que
                  // numa barra de 30px de altura parece defeito.
                  proxyDecorator: (child, _, __) =>
                    Material(color: Colors.transparent, child: child),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Uma aba. O trapézio do Chrome é dispensável; o que ele comunica — qual está
/// à frente — se resolve com fundo e contraste, que é o que o resto do produto
/// já usa.
class _Tab extends StatefulWidget {
  const _Tab({
    required this.entry,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final RemoteSessionEntry entry;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = widget.selected
        ? scheme.surfaceContainerHighest
        : _hovering
            ? scheme.surfaceContainerHigh
            : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: Container(
          height: 30,
          constraints: const BoxConstraints(maxWidth: 220, minWidth: 120),
          padding: const EdgeInsets.only(
              left: TgdeskSpacing.sm, right: TgdeskSpacing.xs),
          decoration: BoxDecoration(
            color: background,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TgdeskSpacing.sm)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.desktop_windows_outlined,
                  size: 14,
                  color: widget.selected
                      ? scheme.onSurface
                      : TgdeskTextColors.body),
              const SizedBox(width: TgdeskSpacing.xs),
              Expanded(
                child: Text(
                  widget.entry.hostname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        widget.selected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.selected
                        ? scheme.onSurface
                        : TgdeskTextColors.body,
                  ),
                ),
              ),
              // O X só aparece na aba à frente ou sob o cursor. Numa fileira
              // de abas, um X visível em todas convida ao fechamento errado —
              // e fechar aqui derruba uma sessão de acesso a uma máquina.
              SizedBox(
                width: 20,
                child: (widget.selected || _hovering)
                    ? _CloseButton(onTap: widget.onClose)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _hovering
                ? TgdeskColors.suspended.withOpacity(.85)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.close,
              size: 12,
              color:
                  _hovering ? Colors.white : Theme.of(context).hintColor),
        ),
      ),
    );
  }
}
