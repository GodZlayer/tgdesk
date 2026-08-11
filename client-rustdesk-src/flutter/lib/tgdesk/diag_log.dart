import 'dart:io';

/// Log de diagnóstico do lado Dart, desligado por padrão.
///
/// Escreve no MESMO arquivo e com o mesmo interruptor do log do runner C++
/// (`windows/runner/tgdesk_log.cpp`), de propósito: uma faixa preta pode nascer
/// da moldura da janela ou de quem desenha dentro dela, e só dá para separar as
/// duas coisas lendo os dois lados na mesma linha do tempo, em ordem.
///
/// Liga por variável de ambiente `TGDESK_DEBUG_LOG=1` ou pela existência de
/// `C:\ProgramData\TGDesk\logs\debug.on`. A decisão é lida uma vez.
class DiagLog {
  static const _dir = r'C:\ProgramData\TGDesk\logs';
  static const _path = r'C:\ProgramData\TGDesk\logs\tgdesk-diag.log';
  static const _switchPath = r'C:\ProgramData\TGDesk\logs\debug.on';

  static bool? _enabled;
  static IOSink? _sink;

  static bool get enabled {
    if (_enabled != null) return _enabled!;
    var on = false;
    try {
      if (Platform.isWindows) {
        on = Platform.environment['TGDESK_DEBUG_LOG'] == '1' ||
            File(_switchPath).existsSync();
      }
    } catch (_) {
      on = false;
    }
    _enabled = on;
    return on;
  }

  /// Uma linha por evento. `area` acompanha a convenção do lado C++ ("canvas",
  /// "fullscreen", ...) para o arquivo continuar filtrável.
  static void write(String area, String message) {
    if (!enabled) return;
    try {
      final sink = _sink ??= () {
        Directory(_dir).createSync(recursive: true);
        return File(_path).openWrite(mode: FileMode.append);
      }();
      final now = DateTime.now();
      final stamp = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}.'
          '${now.millisecond.toString().padLeft(3, '0')}';
      sink.writeln('$stamp [$pid:dart] $area: $message');
    } catch (_) {
      // Diagnóstico nunca derruba a sessão: se não der para escrever, cala.
    }
  }

  /// Atalho para não repetir `toStringAsFixed` em cada ponto de medida —
  /// geometria com quinze casas decimais é ilegível no arquivo.
  static String n(num? value) =>
      value == null ? 'null' : value.toStringAsFixed(1);
}
