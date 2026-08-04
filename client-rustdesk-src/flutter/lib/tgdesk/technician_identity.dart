import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'api_client.dart';

const _cryptProtectLocalMachine = 0x4;

class TechnicianMachineCredential {
  const TechnicianMachineCredential({
    required this.credentialId,
    required this.secret,
    required this.machineId,
  });

  final String credentialId;
  final String secret;
  final String machineId;

  Map<String, dynamic> toJson() => {
        'credential_id': credentialId,
        'secret': secret,
        'machine_id': machineId,
      };

  static TechnicianMachineCredential fromJson(Map<String, dynamic> value) =>
      TechnicianMachineCredential(
        credentialId: value['credential_id'] as String,
        secret: value['secret'] as String,
        machineId: value['machine_id'] as String,
      );
}

String _identityPath() {
  final base = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
  return '$base${Platform.pathSeparator}TGDesk'
      '${Platform.pathSeparator}identity'
      '${Platform.pathSeparator}technician.dat';
}

String _pendingEnrollmentPath() {
  final base = Platform.environment['PROGRAMDATA'] ?? r'C:\ProgramData';
  return '$base${Platform.pathSeparator}TGDesk'
      '${Platform.pathSeparator}identity'
      '${Platform.pathSeparator}pending-enrollment.json';
}

Future<bool> importInstallerEnrollment() async {
  final pending = File(_pendingEnrollmentPath());
  if (!await pending.exists()) return false;
  try {
    final response =
        jsonDecode(await pending.readAsString()) as Map<String, dynamic>;
    final credential = TechnicianMachineCredential(
      credentialId: response['credential_id'] as String,
      secret: response['secret'] as String,
      machineId: response['machine_id'] as String,
    );
    await saveTechnicianCredential(credential);
    AppState.applyAuthentication(response);
    await pending.delete();
    return true;
  } catch (_) {
    return false;
  }
}

Future<String> tgdeskMachineId() async {
  if (Platform.isWindows) {
    try {
      final result = await Process.run('reg.exe', const [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (result.exitCode == 0) {
        final match =
            RegExp(r'MachineGuid\s+REG_\w+\s+([^\r\n]+)', caseSensitive: false)
                .firstMatch(result.stdout.toString());
        final value = match?.group(1)?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
    } catch (_) {}
  }
  return Platform.localHostname;
}

Uint8List _protect(Uint8List clear) {
  final input = calloc<CRYPT_INTEGER_BLOB>();
  final output = calloc<CRYPT_INTEGER_BLOB>();
  final bytes = calloc<Uint8>(clear.length);
  try {
    bytes.asTypedList(clear.length).setAll(0, clear);
    input.ref
      ..cbData = clear.length
      ..pbData = bytes;
    final ok = CryptProtectData(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      _cryptProtectLocalMachine,
      output,
    );
    if (ok == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }
    return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
  } finally {
    if (output.ref.pbData != nullptr) LocalFree(output.ref.pbData);
    calloc.free(bytes);
    calloc.free(input);
    calloc.free(output);
  }
}

Uint8List _unprotect(Uint8List encrypted) {
  final input = calloc<CRYPT_INTEGER_BLOB>();
  final output = calloc<CRYPT_INTEGER_BLOB>();
  final bytes = calloc<Uint8>(encrypted.length);
  try {
    bytes.asTypedList(encrypted.length).setAll(0, encrypted);
    input.ref
      ..cbData = encrypted.length
      ..pbData = bytes;
    final ok = CryptUnprotectData(
      input,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      0,
      output,
    );
    if (ok == 0) {
      throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
    }
    return Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
  } finally {
    if (output.ref.pbData != nullptr) LocalFree(output.ref.pbData);
    calloc.free(bytes);
    calloc.free(input);
    calloc.free(output);
  }
}

Future<void> saveTechnicianCredential(
    TechnicianMachineCredential credential) async {
  final file = File(_identityPath());
  await file.parent.create(recursive: true);
  final clear =
      Uint8List.fromList(utf8.encode(jsonEncode(credential.toJson())));
  await file.writeAsBytes(_protect(clear), flush: true);
}

Future<TechnicianMachineCredential?> loadTechnicianCredential() async {
  final file = File(_identityPath());
  if (!await file.exists()) return null;
  try {
    final clear = _unprotect(await file.readAsBytes());
    return TechnicianMachineCredential.fromJson(
        jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<bool> refreshAutomaticTechnicianLogin() async {
  final credential = await loadTechnicianCredential();
  if (credential == null) return false;
  try {
    final response = await TgdeskApi.refreshTechnicianMachine(
      credential.credentialId,
      credential.secret,
      credential.machineId,
    );
    AppState.applyAuthentication(response);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> redeemTechnicianKeyFile(String path) async {
  final key =
      jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
  final machineId = await tgdeskMachineId();
  final response = await TgdeskApi.redeemTechnicianKey(key, machineId);
  final credential = TechnicianMachineCredential(
    credentialId: response['credential_id'] as String,
    secret: response['secret'] as String,
    machineId: machineId,
  );
  await saveTechnicianCredential(credential);
  AppState.applyAuthentication(response);
}
