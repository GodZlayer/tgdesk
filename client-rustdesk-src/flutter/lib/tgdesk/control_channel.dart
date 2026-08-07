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

  /// Catálogo de tipos de chamado, com os campos que cada um exige. É o
  /// esquema a partir do qual o formulário se monta e o chamado se lê — o app
  /// não conhece tipo nenhum por dentro, só o que chega aqui.
  List<Map<String, dynamic>> ticketTypes = const [];

  /// Regras de preço. Só o admin as recebe — preço é configuração do dono do
  /// produto, e as demais telas não têm o que fazer com elas.
  List<Map<String, dynamic>> pricingRules = const [];

  /// Regiões cadastradas. É o recorte de localidade do produto: o preço
  /// dinâmico mede demanda, técnicos e clientes por região, e não por rede —
  /// rede é fronteira administrativa, região é o lugar.
  List<Map<String, dynamic>> regions = const [];

  Map<String, dynamic>? regionOf(String? id) {
    if (id == null) return null;
    for (final region in regions) {
      if (region['id']?.toString() == id) return region;
    }
    return null;
  }

  /// Catálogo de peças e de serviços com preço. É o que o construtor de OS
  /// oferece ao técnico: ele escolhe da lista em vez de arbitrar o valor.
  List<Map<String, dynamic>> parts = const [];
  List<Map<String, dynamic>> services = const [];

  /// As OS dos chamados visíveis, com as linhas do orçamento dentro. Vêm na
  /// abertura pelo mesmo motivo do resto: a tela do chamado se monta do canal.
  final Map<String, Map<String, dynamic>> serviceOrders = {};

  Map<String, dynamic>? serviceOrderOf(String ticketId) =>
      serviceOrders[ticketId];

  /// Peças e serviços que valem para um tipo de chamado. Item sem tipo vale
  /// para todos — um cabo de rede entra em qualquer OS.
  List<Map<String, dynamic>> partsFor(String? typeKey) => parts.where((item) {
        final key = item['ticket_type_key']?.toString();
        return key == null || key.isEmpty || key == typeKey;
      }).toList(growable: false);

  List<Map<String, dynamic>> servicesFor(String? typeKey, String? osType) =>
      services.where((item) {
        final key = item['ticket_type_key']?.toString();
        final keys = (item['service_type_keys'] as List? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toSet();
        final kind = item['os_type']?.toString();
        final tipoServe = key == null ||
            key.isEmpty ||
            key == typeKey ||
            (typeKey != null && keys.contains(typeKey));
        final modoServe = kind == null || kind.isEmpty || kind == osType;
        return tipoServe && modoServe;
      }).toList(growable: false);

  void _readOsCatalog(Map<dynamic, dynamic> payload) {
    parts = (payload['parts'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    services = (payload['services'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Map<String, dynamic>? ticketTypeOf(String? key) {
    if (key == null) return null;
    for (final type in ticketTypes) {
      if (type['key']?.toString() == key) return type;
    }
    return null;
  }

  /// Campos visíveis de um tipo, já com as condições resolvidas: um campo com
  /// `depends_on` só aparece quando o campo (ou atributo do chamado) de que
  /// depende está com o valor declarado.
  List<Map<String, dynamic>> visibleFieldsOf(
      String? typeKey, Map<String, dynamic> values) {
    final type = ticketTypeOf(typeKey);
    final fields = (type?['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item));
    return fields.where((field) {
      final dependsOn = field['depends_on']?.toString();
      if (dependsOn == null || dependsOn.isEmpty) return true;
      return values[dependsOn]?.toString() ==
          field['depends_value']?.toString();
    }).toList(growable: false);
  }

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
      // Os chamados vêm na abertura da sessão, como as redes. Antes a tela
      // buscava sozinha ao montar, e quem abrisse a aba com a lista já em
      // memória não via chamado nenhum até remontar.
      tickets = (event['tickets'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      // O catálogo de tipos vem na abertura pelo mesmo motivo: a tela que abre
      // um chamado monta o formulário a partir do esquema, e ela se monta do
      // canal.
      ticketTypes = (event['ticket_types'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      // A fila do técnico também: era a última tela que ainda perguntava ao
      // servidor de dez em dez segundos.
      offers = (event['dispatch_offers'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      pricingRules = (event['pricing_rules'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      // O catálogo de peças e serviços e as OS abertas: o construtor de
      // orçamento se monta daqui, sem pedir nada ao abrir.
      if (event['os_catalog'] is Map) {
        _readOsCatalog(event['os_catalog'] as Map);
      }
      regions = (event['regions'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      serviceOrders.clear();
      for (final item in (event['service_orders'] as List? ?? const [])) {
        if (item is! Map) continue;
        final order = Map<String, dynamic>.from(item);
        final ticketId = order['ticket_id']?.toString();
        if (ticketId != null) serviceOrders[ticketId] = order;
      }
      // O histórico vem junto: sem ele a tela do chamado abria vazia,
      // porque os eventos só chegavam por delta e tudo que aconteceu
      // antes da sessão era invisível.
      ticketEvents.clear();
      for (final item in (event['ticket_events'] as List? ?? const [])) {
        if (item is! Map) continue;
        final entry = Map<String, dynamic>.from(item);
        final ticketId = entry['ticket_id']?.toString();
        if (ticketId == null) continue;
        (ticketEvents[ticketId] ??= <Map<String, dynamic>>[]).add(entry);
      }
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
    // O catálogo chega inteiro quando o admin mexe nele: mudar um tipo costuma
    // mexer em vários campos de uma vez, e ele é pequeno.
    if (event['type'] == 'ticket_catalog' && event['payload'] is List) {
      ticketTypes = (event['payload'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      notifyListeners();
      return;
    }
    if (event['type'] == 'regions' && event['payload'] is List) {
      regions = (event['payload'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      notifyListeners();
      return;
    }
    // Peças e serviços chegam inteiros pela mesma razão do catálogo de tipos.
    if (event['type'] == 'os_catalog' && event['payload'] is Map) {
      _readOsCatalog(event['payload'] as Map);
      notifyListeners();
      return;
    }
    if (event['type'] == 'pricing_rules' && event['payload'] is List) {
      pricingRules = (event['payload'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      notifyListeners();
      return;
    }
    // A fila de ofertas chega inteira porque ela é a lista, não uma linha: uma
    // oferta aceita por outro técnico sai da fila sem gerar evento próprio.
    if (event['type'] == 'dispatch_offers' && event['payload'] is List) {
      offers = (event['payload'] as List)
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
          ...devices
              .where((item) => item is! Map || item['id']?.toString() != id),
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
