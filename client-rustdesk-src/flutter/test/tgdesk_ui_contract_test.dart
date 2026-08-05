import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/tgdesk/ui_contract.dart';

void main() {
  group('client information policy', () {
    test('uses server severity and preserves each metric severity', () {
      final health = <String, dynamic>{
        'client_level': 'warning',
        'metrics': {
          'processing': {'level': 'normal'},
          'storage': {'level': 'critical'},
        }
      };
      expect(
          TgdeskClientUiPolicy.overallSeverity(health), TgdeskSeverity.warning);
      expect(TgdeskClientUiPolicy.metricSeverity(health, 'processing'),
          TgdeskSeverity.normal);
      expect(TgdeskClientUiPolicy.metricSeverity(health, 'storage'),
          TgdeskSeverity.critical);
    });

    test('recognizes the suspended client state exactly', () {
      expect(TgdeskClientUiPolicy.isSuspended('suspenso'), isTrue);
      expect(TgdeskClientUiPolicy.isSuspended('ativo'), isFalse);
    });
  });

  group('device inventory policy', () {
    final remoteDevice = <String, dynamic>{
      'id': 'remote',
      'state': 'ativo',
      'presence': 'online',
      'remote_ready': true,
      'rustdesk_id': '123456',
    };

    test('never offers remote access to the current device', () {
      expect(
          TgdeskDeviceUiPolicy.canOfferRemote(
              localDeviceId: 'remote', device: remoteDevice),
          isFalse);
    });

    test('offers remote only for a currently capable online peer', () {
      expect(
          TgdeskDeviceUiPolicy.canOfferRemote(
              localDeviceId: 'local', device: remoteDevice),
          isTrue);
      for (final key in ['presence', 'remote_ready', 'rustdesk_id']) {
        final changed = {...remoteDevice};
        changed[key] = switch (key) {
          'presence' => 'offline',
          'remote_ready' => false,
          _ => '',
        };
        expect(
            TgdeskDeviceUiPolicy.canOfferRemote(
                localDeviceId: 'local', device: changed),
            isFalse);
      }
    });

    test('network badge aggregates the most severe device', () {
      expect(
          TgdeskDeviceUiPolicy.aggregateSeverity(
              ['normal', 'critical', 'warning']),
          TgdeskSeverity.critical);
    });

    test('create subnet is grouped with the network title actions', () {
      final source = File('lib/tgdesk/devices_page.dart').readAsStringSync();
      final networkTile = source.substring(
          source.indexOf('Widget _buildNetTile'),
          source.indexOf('Widget _buildSubnetTile'));
      expect(networkTile, contains("tooltip: 'Criar sub-rede'"));
      expect(networkTile.indexOf("tooltip: 'Criar sub-rede'"),
          lessThan(networkTile.indexOf("tooltip: 'Renomear esta rede'")));
      expect(networkTile, isNot(contains('TextButton.icon')));
    });
  });

  group('remote safety policy', () {
    test('clipboard and file transfer default to off', () {
      expect(TgdeskRemotePolicy.clipboardEnabledByDefault, isFalse);
      expect(TgdeskRemotePolicy.fileTransferEnabledByDefault, isFalse);
    });

    test('closing a blocked session requires local input restoration', () {
      expect(
          TgdeskRemotePolicy.mustRestoreLocalInput(
              inputWasBlocked: true, sessionClosing: true),
          isTrue);
    });
  });

  group('branding policy', () {
    test('customer brand is client-only and not shown in control preview', () {
      expect(
          TgdeskBrandingPolicy.showCustomerBrand(
              embeddedClientPreview: false,
              role: 'client',
              state: 'ativo',
              enabled: true),
          isTrue);
      for (final role in ['supervisor', 'super_admin', 'freelancer']) {
        expect(
            TgdeskBrandingPolicy.showCustomerBrand(
                embeddedClientPreview: false,
                role: role,
                state: 'ativo',
                enabled: true),
            isFalse);
      }
      expect(
          TgdeskBrandingPolicy.showCustomerBrand(
              embeddedClientPreview: true,
              role: 'client',
              state: 'ativo',
              enabled: true),
          isFalse);
    });

    test('admin is superset and supervisor requires admin enablement', () {
      expect(
          TgdeskBrandingPolicy.canEdit(
              role: 'super_admin', adminEnabledForSupervisor: false),
          isTrue);
      expect(
          TgdeskBrandingPolicy.canEdit(
              role: 'supervisor', adminEnabledForSupervisor: false),
          isFalse);
      expect(
          TgdeskBrandingPolicy.canEdit(
              role: 'supervisor', adminEnabledForSupervisor: true),
          isTrue);
    });
  });

  group('diagnostic safety policy', () {
    test('diagnostic loading is bounded and errors are actionable', () {
      expect(TgdeskDiagnosticPolicy.loadTimeout, const Duration(seconds: 20));
      expect(TgdeskDiagnosticPolicy.loadErrorMessage(TimeoutException('late')),
          contains('tente novamente'));
      expect(TgdeskDiagnosticPolicy.loadErrorMessage(Exception('offline')),
          contains('Tente novamente'));

      final dialog =
          File('lib/tgdesk/diagnostics_dialog.dart').readAsStringSync();
      expect(dialog, contains('finally {'));
      expect(dialog, contains('setState(() => _loading = false)'));
      expect(dialog, contains("label: const Text('Tentar novamente')"));
      expect(dialog, contains('Nenhum teste'));
    });

    test('rejects destructive storage tests', () {
      expect(
          TgdeskDiagnosticPolicy.isSafeManualTest(
              {'id': 'badblocks-write', 'destructive': false}),
          isFalse);
      expect(
          TgdeskDiagnosticPolicy.isSafeManualTest(
              {'id': 'disk-read', 'destructive': true}),
          isFalse);
    });

    test('requires complete risk metadata without duration estimates', () {
      expect(
          TgdeskDiagnosticPolicy.catalogEntryIsComplete({
            'id': 'cpu',
            'name': 'CPU',
            'description': 'Carga controlada',
            'impact': 'high',
            'requirements': ['energia'],
          }),
          isTrue);
      expect(
          TgdeskDiagnosticPolicy.catalogEntryIsComplete({
            'id': 'cpu',
            'name': 'CPU',
            'description': 'Carga controlada',
          }),
          isFalse);
    });
  });
}
