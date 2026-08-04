import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String _appliedFaviconHash = '';

/// Applies the customer ICO to the real Win32 window. WM_SETICON updates both
/// the title-bar icon and the taskbar representation for this process.
Future<void> applyClientBrandingWindowIcon(
    Map<String, dynamic> branding) async {
  if (!Platform.isWindows || branding['enabled'] != true) return;
  final encoded = branding['favicon_base64']?.toString() ?? '';
  final hash = branding['favicon_sha256']?.toString() ?? encoded.hashCode.toString();
  if (encoded.isEmpty || hash == _appliedFaviconHash) return;
  final bytes = base64Decode(encoded);
  if (bytes.length < 6 || bytes[0] != 0 || bytes[1] != 0 || bytes[2] != 1) {
    return;
  }
  final brandingRoot = Platform.environment['LOCALAPPDATA'] ??
      Directory.systemTemp.path;
  final directory = Directory(
      '$brandingRoot${Platform.pathSeparator}TGDesk${Platform.pathSeparator}branding');
  await directory.create(recursive: true);
  final path = '${directory.path}${Platform.pathSeparator}favicon.ico';
  await File(path).writeAsBytes(bytes, flush: true);
  final title = 'TGDesk'.toNativeUtf16();
  final iconPath = path.toNativeUtf16();
  try {
    final hwnd = FindWindow(nullptr, title);
    if (hwnd == 0) return;
    final icon = LoadImage(0, iconPath, GDI_IMAGE_TYPE.IMAGE_ICON, 0, 0,
        IMAGE_FLAGS.LR_LOADFROMFILE | IMAGE_FLAGS.LR_DEFAULTSIZE);
    if (icon == 0) return;
    SendMessage(hwnd, WM_SETICON, ICON_BIG, icon);
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, icon);
    _appliedFaviconHash = hash;
  } finally {
    calloc.free(title);
    calloc.free(iconPath);
  }
}
