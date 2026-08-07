import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String _appliedFaviconHash = '';
String _appliedShortcutSignature = '';

/// Applies the customer ICO to the real Win32 window. WM_SETICON updates both
/// the title-bar icon and the taskbar representation for this process.
Future<void> applyClientBrandingWindowIcon(
    Map<String, dynamic> branding) async {
  if (!Platform.isWindows || branding['enabled'] != true) return;
  final encoded = branding['favicon_base64']?.toString() ?? '';
  final hash =
      branding['favicon_sha256']?.toString() ?? encoded.hashCode.toString();
  if (encoded.isEmpty || hash == _appliedFaviconHash) return;
  final bytes = base64Decode(encoded);
  if (bytes.length < 6 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 1) {
    return;
  }
  final brandingRoot =
      Platform.environment['ProgramData'] ?? Directory.systemTemp.path;
  final directory = Directory(
      '$brandingRoot${Platform.pathSeparator}TGDesk${Platform.pathSeparator}branding');
  await directory.create(recursive: true);
  final path = '${directory.path}${Platform.pathSeparator}favicon.ico';
  await File(path).writeAsBytes(bytes, flush: true);
  await _syncClientShortcuts(branding, path);
  final windowClass = 'TGDESK_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final iconPath = path.toNativeUtf16();
  try {
    final hwnd = FindWindow(windowClass, nullptr);
    if (hwnd == 0) return;
    final icon = LoadImage(0, iconPath, GDI_IMAGE_TYPE.IMAGE_ICON, 0, 0,
        IMAGE_FLAGS.LR_LOADFROMFILE | IMAGE_FLAGS.LR_DEFAULTSIZE);
    if (icon == 0) return;
    SendMessage(hwnd, WM_SETICON, ICON_BIG, icon);
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, icon);
    _appliedFaviconHash = hash;
  } finally {
    calloc.free(windowClass);
    calloc.free(iconPath);
  }
}

String _brandShortcutName(Map<String, dynamic> branding) {
  final resolved = branding['shortcut_name']?.toString().trim() ??
      branding['application_name']?.toString().trim() ??
      '';
  final raw = resolved.isNotEmpty
      ? resolved
      : branding['name']?.toString().trim() ?? '';
  final clean = raw.replaceAll(RegExp(r'[\\/:*?"<>| \-_.]'), '');
  if (clean.isEmpty) return 'TGDesk';
  return clean.length > 72 ? clean.substring(0, 72) : clean;
}

Future<void> _syncClientShortcuts(
    Map<String, dynamic> branding, String iconPath) async {
  final name = _brandShortcutName(branding);
  final signature = '$name|$iconPath';
  if (signature == _appliedShortcutSignature) return;
  final exePath = Platform.resolvedExecutable;
  final temp = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}tgdesk-brand-shortcuts.ps1');
  final script = '''
\$ErrorActionPreference = 'Stop'
\$exe = ${jsonEncode(exePath)}
\$icon = ${jsonEncode(iconPath)}
\$name = ${jsonEncode(name)}
\$targets = @(
  [IO.Path]::Combine(\$env:PUBLIC, 'Desktop'),
  [IO.Path]::Combine(\$env:ProgramData, 'Microsoft', 'Windows', 'Start Menu', 'Programs')
)
\$shell = New-Object -ComObject WScript.Shell
foreach (\$dir in \$targets) {
  if (-not [IO.Directory]::Exists(\$dir)) { continue }
  foreach (\$old in @('TGDesk.lnk', 'TGDesk Client.lnk')) {
    \$oldPath = [IO.Path]::Combine(\$dir, \$old)
    if ([IO.File]::Exists(\$oldPath)) { Remove-Item -LiteralPath \$oldPath -Force }
  }
  \$path = [IO.Path]::Combine(\$dir, "\$name.lnk")
  \$shortcut = \$shell.CreateShortcut(\$path)
  \$shortcut.TargetPath = \$exe
  \$shortcut.WorkingDirectory = [IO.Path]::GetDirectoryName(\$exe)
  \$shortcut.IconLocation = "\$icon,0"
  \$shortcut.Save()
}
''';
  await temp.writeAsString(script, flush: true);
  try {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      temp.path,
    ]);
    if (result.exitCode == 0) {
      _appliedShortcutSignature = signature;
    }
  } finally {
    unawaited(temp.delete().catchError((_) => temp));
  }
}
