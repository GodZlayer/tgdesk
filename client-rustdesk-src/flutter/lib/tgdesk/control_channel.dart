import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Canal de controle único do processo. Sobrevive à navegação e à bandeja.
class TgdeskControlChannel extends ChangeNotifier {
  TgdeskControlChannel._();
  static final TgdeskControlChannel instance = TgdeskControlChannel._();

  WebSocket? _socket;
  Timer? _reconnect;
  Timer? _refreshDebounce;
  bool _stopped = true;
  bool _loading = false;
  List<dynamic> organizations = const [];
  List<dynamic> networks = const [];
  List<dynamic> subnetworks = const [];
  List<dynamic> devices = const [];
  final Map<String, Map<String, dynamic>> deviceHealth = {};
  final Map<String, Map<String, Map<String, dynamic>>> diagnosticRuns = {};
  List<Map<String, dynamic>> tickets = const [];
  List<Map<String, dynamic>> offers = const [];

  /// Conversa e histórico de cada chamado, por id. São a mesma lista de
  /// eventos vista de dois jeitos: mensagem é um tipo de evento entre outros.
  /// Chega empurrada, evento a evento — a tela nunca vai buscar.
  final Map<String, List<Map<String, dynamic>>> ticketEvents = {};

  List<Map<String, dynamic>> messagesOf(String ticketId) =>
      (ticketEvents[ticketId] ?? const [])
          .where((event) =>
              event['type'] == 'message' || event['type'] == 'client_message')
          .toList(growable: false);
  bool? brandingEnabled;
  Object? error;
  bool connected = false;
  bool get loading => _loading;

  Future<void> start() async {
    await stop();
    _stopped = false;
    await _connect();
  }

  Future<bool> authenticateAndStart(Map<String, dynamic> credential) async {
    await stop();
    _stopped = false;
    return _connect(credential: credential);
  }

  Future<void> stop() async {
    _stopped = true;
    _reconnect?.cancel();
    _refreshDebounce?.cancel();
    final socket = _socket;
    _socket = null;
    connected = false;
    notifyListeners();
    await socket?.close();
  }

  Future<void> refresh() async {
    if (!AppState.isLoggedIn || _loading) return;
    _loading = true;
    notifyListeners();
    try {
      final result = await Future.wait([
        TgdeskApi.organizations(),
        TgdeskApi.networks(),
        TgdeskApi.subnetworks(),
        TgdeskApi.devices(),
      ]);
      organizations = result[0];
      networks = result[1];
      subnetworks = result[2];
      devices = result[3];
      error = null;
    } catch (e) {
      error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSupport() async {
    if (!AppState.isLoggedIn) return;
    try {
      final results = await Future.wait([
        TgdeskApi.supportTickets(),
        if (AppState.isFreelancer) TgdeskApi.supportOffers(),
      ]);
      tickets = results.first
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      offers = AppState.isFreelancer
          ? results.last
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const [];
      notifyListeners();
    } catch (e) {
      error = e;
      notifyListeners();
    }
  }

  Future<bool> _connect({Map<String, dynamic>? credential}) async {
    if (_stopped ||
        (credential == null && !AppState.isLoggedIn) ||
        _socket != null) {
      return connected;
    }
    try {
      final socket = await TgdeskApi.connectPrivateControlWS(_onEvent,
          credential: credential);
      if (_stopped) {
        await socket.close();
        return false;
      }
      _socket = socket;
      connected = true;
      error = null;
      notifyListeners();
      socket.done.whenComplete(() {
        if (identical(_socket, socket)) {
          _socket = null;
          connected = false;
          notifyListeners();
          _scheduleReconnect();
        }
      });
      return true;
    } catch (e) {
      error = e;
      connected = false;
      notifyListeners();
      _scheduleReconnect();
      return false;
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    if (event['type'] == 'snapshot') {
      organizations =
          List<dynamic>.from(event['organizations'] as List? ?? const []);
      networks = List<dynamic>.from(event['networks'] as List? ?? const []);
      subnetworks =
          List<dynamic>.from(event['subnetworks'] as List? ?? const []);
      devices = List<dynamic>.from(event['devices'] as List? ?? const []);
      error = null;
      notifyListeners();
      return;
    }
    if (event['type'] == 'event' && event['event'] is Map) {
      event = Map<String, dynamic>.from(event['event'] as Map);
    }
    if (event['type'] == 'presence' && event['target_id'] != null) {
      final id = event['target_id'].toString();
      final payload = event['payload'];
      final presence = payload is Map
          ? payload['presence']?.toString() ?? 'online'
          : 'online';
      devices = devices.map((item) {
        if (item is! Map || item['id']?.toString() != id) return item;
        return <String, dynamic>{
          ...Map<String, dynamic>.from(item),
          'presence': presence
        };
      }).toList(growable: false);
      notifyListeners();
      return;
    }
    if (event['type'] == 'branding_permission' && event['payload'] is Map) {
      brandingEnabled = (event['payload'] as Map)['enabled'] == true;
      notifyListeners();
      return;
    }
    if (event['type'] == 'support_snapshot' && event['payload'] is Map) {
      final payload = event['payload'] as Map;
      tickets = (payload['tickets'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      offers = (payload['offers'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      notifyListeners();
      return;
    }
    if (event['type'] == 'support_ticket' && event['payload'] is Map) {
      final ticket =
          Map<String, dynamic>.from(event['payload'] as Map<dynamic, dynamic>);
      final id = ticket['id']?.toString();
      if (id != null) {
        tickets = [
          ...tickets.where((item) => item['id']?.toString() != id),
          ticket,
        ];
        notifyListeners();
      }
      return;
    }
    // Delta de dispositivo: uma linha trocada na lista, em vez do estado
    // inteiro reenviado. O desenho da tela é dela e não trafega.
    if (event['type'] == 'device' && event['payload'] is Map) {
      final device =
          Map<String, dynamic>.from(event['payload'] as Map<dynamic, dynamic>);
      final id = device['id']?.toString();
      if (id != null) {
        devices = [
          ...devices.where(
              (item) => item is! Map || item['id']?.toString() != id),
          device,
        ];
        notifyListeners();
      }
      return;
    }
    // Um evento do chamado: mensagem, etapa de OS, confirmação. Chega pronto,
    // não como aviso de "vá buscar".
    if (event['type'] == 'ticket_event' && event['payload'] is Map) {
      final entry =
          Map<String, dynamic>.from(event['payload'] as Map<dynamic, dynamic>);
      final ticketId = entry['ticket_id']?.toString();
      final id = entry['id']?.toString();
      if (ticketId != null && id != null) {
        final current = <Map<String, dynamic>>[
          ...(ticketEvents[ticketId] ?? const <Map<String, dynamic>>[])
        ]
          ..removeWhere((item) => item['id']?.toString() == id)
          ..add(entry);
        current.sort((a, b) => (a['created_at']?.toString() ?? '')
            .compareTo(b['created_at']?.toString() ?? ''));
        ticketEvents[ticketId] = current;
        notifyListeners();
      }
      return;
    }
    if (event['type'] == 'support_offer' && event['payload'] is Map) {
      final offer =
          Map<String, dynamic>.from(event['payload'] as Map<dynamic, dynamic>);
      final id = offer['id']?.toString();
      if (id != null) {
        offers = [
          ...offers.where((item) => item['id']?.toString() != id),
          offer,
        ];
        notifyListeners();
      }
      return;
    }
    if (event['type'] == 'telemetry') {
      final id = event['target_id']?.toString();
      final payload = event['payload'];
      if (id != null && payload is Map) {
        deviceHealth[id] = Map<String, dynamic>.from(payload);
        final statistics = payload['statistics'];
        final health = statistics is Map ? statistics['health'] : null;
        final level = health is Map ? health['level']?.toString() : null;
        if (level != null) {
          devices = devices.map((item) {
            if (item is! Map || item['id']?.toString() != id) return item;
            return <String, dynamic>{
              ...Map<String, dynamic>.from(item),
              'health_level': level,
            };
          }).toList(growable: false);
        }
      }
      notifyListeners();
      return;
    }
    if ((event['type'] == 'diagnostic_progress' ||
            event['type'] == 'diagnostic_result') &&
        event['target_id'] != null &&
        event['payload'] is Map) {
      final deviceId = event['target_id'].toString();
      final payload = Map<String, dynamic>.from(event['payload'] as Map);
      final runId = payload['id']?.toString();
      if (runId != null) {
        final runs = diagnosticRuns.putIfAbsent(deviceId, () => {});
        runs[runId] = <String, dynamic>{
          ...?runs[runId],
          ...payload,
          'device_id': deviceId,
        };
        notifyListeners();
      }
    }
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), () => _connect());
  }
}
