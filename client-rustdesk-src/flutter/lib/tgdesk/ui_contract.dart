import 'dart:async';

enum TgdeskSeverity {
  normal,
  warning,
  critical,
  maximum;

  static TgdeskSeverity parse(Object? value) => switch ('$value') {
        'warning' => warning,
        'critical' => critical,
        'maximum' => maximum,
        _ => normal,
      };

  int get rank => index;
}

class TgdeskClientUiPolicy {
  const TgdeskClientUiPolicy._();

  static TgdeskSeverity metricSeverity(
      Map<String, dynamic> health, String metric) {
    final metrics = health['metrics'];
    if (metrics is! Map) return TgdeskSeverity.normal;
    final value = metrics[metric];
    if (value is! Map) return TgdeskSeverity.normal;
    return TgdeskSeverity.parse(value['level']);
  }

  /// A cor global vem exclusivamente da análise histórica do servidor. Um
  /// indicador leve continua amarelo no próprio cartão, sem transformar toda
  /// a experiência do cliente em um alarme crítico.
  static TgdeskSeverity overallSeverity(Map<String, dynamic> health) =>
      TgdeskSeverity.parse(health['client_level']);

  static bool isSuspended(Object? state) => state == 'suspenso';
}

class TgdeskDeviceUiPolicy {
  const TgdeskDeviceUiPolicy._();

  static bool canOfferRemote({
    required String? localDeviceId,
    required Map<String, dynamic> device,
  }) {
    final id = device['id']?.toString() ?? '';
    final remoteId = device['rustdesk_id']?.toString().trim() ?? '';
    return id.isNotEmpty &&
        id != localDeviceId &&
        device['state'] == 'ativo' &&
        device['presence'] == 'online' &&
        device['remote_ready'] == true &&
        remoteId.isNotEmpty;
  }

  static TgdeskSeverity aggregateSeverity(Iterable<Object?> levels) =>
      levels.map(TgdeskSeverity.parse).fold(
            TgdeskSeverity.normal,
            (highest, value) => value.rank > highest.rank ? value : highest,
          );
}

class TgdeskRemotePolicy {
  const TgdeskRemotePolicy._();

  static const clipboardEnabledByDefault = false;
  static const fileTransferEnabledByDefault = false;

  static bool mustRestoreLocalInput({
    required bool inputWasBlocked,
    required bool sessionClosing,
  }) =>
      inputWasBlocked && sessionClosing;
}

class TgdeskBrandingPolicy {
  const TgdeskBrandingPolicy._();

  static bool showCustomerBrand({
    required bool embeddedClientPreview,
    required String role,
    required String state,
    required bool enabled,
  }) =>
      !embeddedClientPreview && role == 'client' && state == 'ativo' && enabled;

  static bool canEdit({
    required String role,
    required bool adminEnabledForSupervisor,
  }) =>
      role == 'super_admin' ||
      (role == 'supervisor' && adminEnabledForSupervisor);
}

class TgdeskDiagnosticPolicy {
  const TgdeskDiagnosticPolicy._();

  static const loadTimeout = Duration(seconds: 20);

  static String loadErrorMessage(Object error) => error is TimeoutException
      ? 'O diagnÃ³stico demorou demais para responder. Verifique a conexÃ£o e tente novamente.'
      : 'NÃ£o foi possÃ­vel carregar os diagnÃ³sticos. Tente novamente.';

  static const forbiddenStorageTests = {
    'badblocks-write',
    'destructive-write',
    'secure-erase',
    'format',
  };

  static bool isSafeManualTest(Map<String, dynamic> test) {
    final id = test['id']?.toString().toLowerCase() ?? '';
    final destructive = test['destructive'] == true;
    return id.isNotEmpty && !destructive && !forbiddenStorageTests.contains(id);
  }

  static bool catalogEntryIsComplete(Map<String, dynamic> test) =>
      isSafeManualTest(test) &&
      (test['name']?.toString().trim().isNotEmpty ?? false) &&
      (test['description']?.toString().trim().isNotEmpty ?? false) &&
      (test['impact']?.toString().trim().isNotEmpty ?? false) &&
      (test['requirements'] is List || test['requirement'] != null);
}
