import 'dart:io';

const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _settingsKey = r'HKCU\Software\TGDesk';

Future<bool> tgdeskStartsWithWindows() async {
  if (!Platform.isWindows) return false;
  final result =
      await Process.run('reg.exe', ['query', _runKey, '/v', 'TGDesk']);
  return result.exitCode == 0;
}

Future<void> setTgdeskStartsWithWindows(bool enabled) async {
  if (!Platform.isWindows) return;
  if (enabled) {
    final add = await Process.run('reg.exe', [
      'add',
      _runKey,
      '/v',
      'TGDesk',
      '/t',
      'REG_SZ',
      '/d',
      Platform.resolvedExecutable,
      '/f',
    ]);
    if (add.exitCode != 0) {
      throw StateError(add.stderr.toString().trim());
    }
  } else {
    await Process.run('reg.exe', ['delete', _runKey, '/v', 'TGDesk', '/f']);
  }
  await Process.run('reg.exe', [
    'add',
    _settingsKey,
    '/v',
    'StartWithWindowsConfigured',
    '/t',
    'REG_DWORD',
    '/d',
    '1',
    '/f',
  ]);
  await Process.run('reg.exe', [
    'add',
    _settingsKey,
    '/v',
    'StartWithWindows',
    '/t',
    'REG_DWORD',
    '/d',
    enabled ? '1' : '0',
    '/f',
  ]);
}
