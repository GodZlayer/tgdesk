import 'package:flutter/material.dart';

/// Tokens de cor do TGDesk Hub. Nunca use `Colors.red` etc. direto numa tela
/// nova — adicione (ou reaproveite) um token aqui, para que trocar uma cor
/// não vire uma busca-e-substitui em 4 arquivos.
class TgdeskColors {
  TgdeskColors._();

  static const seed = Colors.indigo;

  /// Dispositivo ativo e com heartbeat recente.
  static const online = Colors.green;

  /// Dispositivo ativo mas sem heartbeat (ou estado "offline" explícito).
  static const offline = Colors.grey;

  /// Dispositivo ainda não vinculado (estado guest).
  static const guest = Colors.blueGrey;

  /// Entidade suspensa administrativamente.
  static const suspended = Colors.red;

  /// Alerta ou ação administrativa de atenção.
  static const warning = Colors.orange;
}

/// Escala de espaçamento de 4px. Prefira estes valores a números arbitrários.
class TgdeskSpacing {
  TgdeskSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Cor da bolinha de presença — único lugar que decide o mapeamento
/// estado→cor; use em qualquer tela que precise mostrar presença.
Color presenceColor(String presence) {
  switch (presence) {
    case 'online':
      return TgdeskColors.online;
    case 'offline':
      return TgdeskColors.offline;
    case 'guest':
      return TgdeskColors.guest;
    case 'suspenso':
      return TgdeskColors.suspended;
    default:
      return TgdeskColors.warning;
  }
}

/// Texto de erro padrão do Hub — substitui a repetição de
/// `Text(msg, style: TextStyle(color: Colors.red))` em cada tela.
class TgdeskErrorText extends StatelessWidget {
  final String message;
  const TgdeskErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(message, style: const TextStyle(color: TgdeskColors.suspended));
  }
}

Future<bool> showTgdeskConfirmSuspendDialog(
    BuildContext context, String targetLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar suspensão'),
      content: Text(
          'Suspender $targetLabel? O vínculo será preservado, mas a conexão privada e as verificações serão interrompidas.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: TgdeskColors.suspended),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Suspender'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> showTgdeskConfirmDeleteDialog(
    BuildContext context, String targetLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apagar definitivamente?'),
      content: Text('Apagar $targetLabel? Essa ação não pode ser desfeita.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );
  return ok == true;
}
