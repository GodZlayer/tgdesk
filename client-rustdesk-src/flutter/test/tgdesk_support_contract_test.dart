import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/tgdesk/support_contract.dart';

void main() {
  group('support roles', () {
    test('maps legacy technician to supervisor', () {
      expect(supportRoleFromServer('technician'), TgdeskSupportRole.supervisor);
      expect(supportRoleFromServer('supervisor'), TgdeskSupportRole.supervisor);
      expect(supportRoleFromServer('freelancer'), TgdeskSupportRole.freelancer);
      expect(supportRoleFromServer('super_admin'), TgdeskSupportRole.admin);
    });

    test('freelancer has client tab but no visible network management', () {
      expect(TgdeskSupportPolicy.hasClientTab(TgdeskSupportRole.freelancer),
          isTrue);
      expect(
          TgdeskSupportPolicy.canSeeNetworkManagement(
              TgdeskSupportRole.freelancer),
          isFalse);
      expect(TgdeskSupportPolicy.canManageQueue(TgdeskSupportRole.freelancer),
          isFalse);
    });

    test('admin is a superset of supervisor queue permissions', () {
      expect(
          TgdeskSupportPolicy.canManageQueue(TgdeskSupportRole.admin), isTrue);
      expect(
          TgdeskSupportPolicy.canSeeNetworkManagement(TgdeskSupportRole.admin),
          isTrue);
    });
  });

  group('ticket-bound permissions', () {
    test('temporary remote requires accepted virtual assignment', () {
      expect(
          TgdeskSupportPolicy.canUseTemporaryRemote(
              role: TgdeskSupportRole.freelancer,
              mode: TgdeskServiceMode.virtual,
              state: TgdeskTicketState.inProgress,
              assignedToCurrentUser: true),
          isTrue);
      expect(
          TgdeskSupportPolicy.canUseTemporaryRemote(
              role: TgdeskSupportRole.freelancer,
              mode: TgdeskServiceMode.onsite,
              state: TgdeskTicketState.inProgress,
              assignedToCurrentUser: true),
          isFalse);
      expect(
          TgdeskSupportPolicy.canUseTemporaryRemote(
              role: TgdeskSupportRole.freelancer,
              mode: TgdeskServiceMode.virtual,
              state: TgdeskTicketState.closed,
              assignedToCurrentUser: true),
          isFalse);
    });

    test('diagnostics require active assignment', () {
      expect(
          TgdeskSupportPolicy.canUseTicketDiagnostics(
              role: TgdeskSupportRole.freelancer,
              state: TgdeskTicketState.accepted,
              assignedToCurrentUser: true),
          isTrue);
      expect(
          TgdeskSupportPolicy.canUseTicketDiagnostics(
              role: TgdeskSupportRole.freelancer,
              state: TgdeskTicketState.accepted,
              assignedToCurrentUser: false),
          isFalse);
    });

    test('terminal states revoke temporary permissions', () {
      for (final state in const [
        TgdeskTicketState.closed,
        TgdeskTicketState.cancelled,
        TgdeskTicketState.expired,
      ]) {
        expect(TgdeskSupportPolicy.permissionsMustBeRevoked(state), isTrue);
      }
    });
  });

  group('workflow and evidence', () {
    test('only valid transitions are accepted', () {
      expect(
          TgdeskSupportPolicy.canTransition(TgdeskTicketState.open,
              TgdeskTicketState.offered, TgdeskSupportRole.supervisor),
          isTrue);
      expect(
          TgdeskSupportPolicy.canTransition(TgdeskTicketState.open,
              TgdeskTicketState.accepted, TgdeskSupportRole.supervisor),
          isFalse);
      expect(
          TgdeskSupportPolicy.canTransition(TgdeskTicketState.closed,
              TgdeskTicketState.open, TgdeskSupportRole.client),
          isTrue);
    });

    test('evidence serializes integrity and consent metadata', () {
      final evidence = TgdeskEvidenceDraft(
        kind: 'arrival_photo',
        capturedAt: DateTime.utc(2026, 7, 29, 12),
        sha256: 'abc123',
        latitude: -23.5,
        longitude: -46.6,
        accuracyMeters: 8,
        localId: 'offline-1',
      ).toJson();
      expect(evidence['sha256'], 'abc123');
      expect(evidence['accuracy_meters'], 8);
      expect(evidence['local_id'], 'offline-1');
    });
  });
}
