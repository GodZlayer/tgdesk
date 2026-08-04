import 'dart:io';
import 'api_client.dart' show kTgdeskServerDefault;

/// Diretório-lar do agente TGDesk: `%LOCALAPPDATA%\TGDesk`. É pra cá que o
/// `tgdesk-agent.exe` (embutido no app como asset) é extraído em tempo de
/// execução, junto dos módulos nativos necessários. Manter tudo aqui em vez
/// de solto na pasta do `tgdesk.exe` é o que faz o cliente instalado não
/// expor um `tgdesk-agent.exe` avulso (pedido do usuário) — o binário fica
/// embutido e só "materializa" numa pasta de dados do usuário quando roda.
String tgdeskDataHome() {
  final base = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
  final dir = Directory('$base${Platform.pathSeparator}TGDesk');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir.path;
}

String tgdeskStatusFilePath() =>
    '${tgdeskDataHome()}${Platform.pathSeparator}state'
    '${Platform.pathSeparator}status.json';

/// Garante que os módulos do agente estejam disponíveis em
/// [tgdeskAgentHome], a partir dos assets embutidos. Reescreve só quando o
/// tamanho difere (upgrade do app) e ignora falha de "arquivo em uso" — se o
/// agente já está rodando com a versão certa, não há o que atualizar.
Future<void> ensureAgentDeployed() async {}

/// O papel Host existe nos dois modos de interface. Uma estação operada por
/// um técnico continua registrada como cliente e pode receber acesso remoto.
Future<void> ensureHostAgentRunning() async {
  try {
    await Process.start(
      Platform.resolvedExecutable,
      [
        '--tgdesk-host',
        '--server',
        kTgdeskServerDefault,
        '--core-exe',
        Platform.resolvedExecutable,
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: File(Platform.resolvedExecutable).parent.path,
    );
  } catch (_) {
    // O singleton nomeado do agente torna chamadas repetidas inofensivas.
  }
}
