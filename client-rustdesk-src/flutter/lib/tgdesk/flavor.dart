import 'dart:io';

/// O executável é único. O instalador grava este marker somente quando o
/// operador escolhe Técnico; sem ele, a experiência inicial é Cliente.
class TgdeskInstallMode {
  TgdeskInstallMode._();

  static const technicianMarkerName = 'tgdesk_mode_tech.marker';

  static bool get isTechnician {
    if (!Platform.isWindows) return false;
    final exe = File(Platform.resolvedExecutable);
    return File(
      '${exe.parent.path}${Platform.pathSeparator}$technicianMarkerName',
    ).existsSync();
  }
}
