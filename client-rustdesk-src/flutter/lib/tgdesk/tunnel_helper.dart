import 'dart:io';
import 'api_client.dart';

/// Lança `tgdesk-agent.exe technician` para dar ao Hub seu próprio túnel
/// WireGuard — independente de qualquer papel Host que o mesmo agente também
/// saiba desempenhar nesta máquina (adaptador de rede próprio, chave própria,
/// ver client-tgdesk/ARCHITECTURE_FLOW.md). O agente vem embutido no app
/// (asset) e é extraído para `%LOCALAPPDATA%\TGDesk` — não é um `.exe` solto
/// ao lado do tgdesk.exe. Falha silenciosamente se precisar de administrador
/// para o driver Wintun — o Hub continua utilizável para as telas que só
/// dependem da API de controle.
Future<void> launchTunnelHelper() async {
  if (AppState.token == null) return;
  try {
    await Process.start(
      Platform.resolvedExecutable,
      [
        '--tgdesk-technician',
        '--server',
        AppState.serverUrl,
        '--token',
        AppState.token!
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: File(Platform.resolvedExecutable).parent.path,
    );
  } catch (_) {
    // sem túnel próprio por enquanto; telas de controle continuam funcionando.
  }
}
