enum TgdeskSupportRole { client, freelancer, supervisor, admin }

enum TgdeskTicketState {
  open,
  offeredSupervisor,
  offered,
  accepted,
  inProgress,
  awaitingConfirmation,
  closed,
  cancelled,
  expired,
  reopened,
}

enum TgdeskServiceMode { virtual, onsite }

TgdeskSupportRole supportRoleFromServer(String? value) {
  switch (value) {
    case 'super_admin':
      return TgdeskSupportRole.admin;
    case 'supervisor':
    case 'technician':
      return TgdeskSupportRole.supervisor;
    case 'freelancer':
      return TgdeskSupportRole.freelancer;
    default:
      return TgdeskSupportRole.client;
  }
}

const Map<String, TgdeskTicketState> _kServerTicketStates = {
  'open': TgdeskTicketState.open,
  'offered_supervisor': TgdeskTicketState.offeredSupervisor,
  'offered': TgdeskTicketState.offered,
  'accepted': TgdeskTicketState.accepted,
  'in_progress': TgdeskTicketState.inProgress,
  // A OS terminada espera confirmação das partes. Faltava aqui, e como
  // ticketStateFromServer lança em estado desconhecido, um chamado nesse
  // ponto derrubava a tela inteira de Chamados.
  'awaiting_confirmation': TgdeskTicketState.awaitingConfirmation,
  'closed': TgdeskTicketState.closed,
  'cancelled': TgdeskTicketState.cancelled,
  'expired': TgdeskTicketState.expired,
  'reopened': TgdeskTicketState.reopened,
};

TgdeskTicketState ticketStateFromServer(String? value) {
  final state = _kServerTicketStates[value];
  if (state == null) {
    throw ArgumentError.value(
        value, 'value', 'estado de chamado desconhecido no servidor');
  }
  return state;
}

class TgdeskSupportPolicy {
  const TgdeskSupportPolicy._();

  static bool canManageQueue(TgdeskSupportRole role) =>
      role == TgdeskSupportRole.supervisor || role == TgdeskSupportRole.admin;

  static bool canSeeNetworkManagement(TgdeskSupportRole role) =>
      role == TgdeskSupportRole.supervisor || role == TgdeskSupportRole.admin;

  static bool hasClientTab(TgdeskSupportRole role) => true;

  static bool canUseTemporaryRemote({
    required TgdeskSupportRole role,
    required TgdeskServiceMode mode,
    required TgdeskTicketState state,
    required bool assignedToCurrentUser,
  }) =>
      (role == TgdeskSupportRole.freelancer ||
          role == TgdeskSupportRole.supervisor ||
          role == TgdeskSupportRole.admin) &&
      mode == TgdeskServiceMode.virtual &&
      assignedToCurrentUser &&
      (state == TgdeskTicketState.accepted ||
          state == TgdeskTicketState.inProgress);

  static bool canUseTicketDiagnostics({
    required TgdeskSupportRole role,
    required TgdeskTicketState state,
    required bool assignedToCurrentUser,
  }) =>
      role != TgdeskSupportRole.client &&
      assignedToCurrentUser &&
      (state == TgdeskTicketState.accepted ||
          state == TgdeskTicketState.inProgress);

  static bool permissionsMustBeRevoked(TgdeskTicketState state) =>
      state == TgdeskTicketState.closed ||
      state == TgdeskTicketState.cancelled ||
      state == TgdeskTicketState.expired;

  /// Espelha exatamente o mapa de transições válidas do servidor
  /// (server/api-core/internal/handlers/support.go, TransitionTicket).
  static bool canTransition(
      TgdeskTicketState from, TgdeskTicketState to, TgdeskSupportRole role) {
    if (role == TgdeskSupportRole.client) {
      return (from == TgdeskTicketState.closed &&
              to == TgdeskTicketState.open) ||
          (from == TgdeskTicketState.open && to == TgdeskTicketState.cancelled);
    }
    const transitions = <TgdeskTicketState, Set<TgdeskTicketState>>{
      TgdeskTicketState.open: {
        TgdeskTicketState.closed,
        TgdeskTicketState.cancelled,
        TgdeskTicketState.offered,
        TgdeskTicketState.offeredSupervisor,
      },
      TgdeskTicketState.offeredSupervisor: {
        TgdeskTicketState.open,
        TgdeskTicketState.expired,
        TgdeskTicketState.cancelled,
      },
      TgdeskTicketState.offered: {
        TgdeskTicketState.accepted,
        TgdeskTicketState.cancelled,
        TgdeskTicketState.expired,
      },
      TgdeskTicketState.accepted: {
        TgdeskTicketState.inProgress,
        TgdeskTicketState.closed,
        TgdeskTicketState.cancelled,
      },
      TgdeskTicketState.inProgress: {
        TgdeskTicketState.closed,
        TgdeskTicketState.cancelled,
      },
      TgdeskTicketState.closed: {
        TgdeskTicketState.reopened,
      },
      TgdeskTicketState.reopened: {
        TgdeskTicketState.inProgress,
        TgdeskTicketState.closed,
      },
    };
    return transitions[from]?.contains(to) == true;
  }
}

class TgdeskEvidenceDraft {
  const TgdeskEvidenceDraft({
    required this.kind,
    required this.capturedAt,
    required this.sha256,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.localId,
  });

  final String kind;
  final DateTime capturedAt;
  final String sha256;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? localId;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'sha256': sha256,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (localId != null) 'local_id': localId,
      };
}
