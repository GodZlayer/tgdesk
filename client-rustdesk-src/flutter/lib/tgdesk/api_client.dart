import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Endereço do api-core. Override em build time com
/// --dart-define=TGDESK_SERVER=http://host:porta
const String kTgdeskServerDefault = String.fromEnvironment('TGDESK_SERVER',
    defaultValue: 'http://168.232.199.161:8090');

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

/// Estado global simples do Hub: token JWT, papel do técnico logado, base URL.
/// Sem persistência em disco por enquanto — login é pedido a cada abertura do Hub.
class AppState {
  static String serverUrl = kTgdeskServerDefault;
  static String? token;
  static String? role;
  static String? username;

  static bool get isSuperAdmin => role == 'super_admin';
  static bool get isFreelancer => role == 'freelancer';
  static bool get isSupervisor => role == 'supervisor' || role == 'technician';
  static bool get canManageNetworks => isSuperAdmin || isSupervisor;
  static bool get isLoggedIn => token != null;

  /// ID do técnico logado, extraído do claim "tid" do JWT (sem verificar
  /// assinatura — só leitura local do payload já validado pelo servidor).
  /// Usado para decidir "este ticket é meu?" e como ratee_id/rater_id em
  /// avaliações. Retorna null se não houver token ou o claim não existir.
  static String? get technicianId {
    final t = token;
    if (t == null) return null;
    final parts = t.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1];
      payload += '=' * ((4 - payload.length % 4) % 4);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload))) as Map;
      return decoded['tid']?.toString();
    } catch (_) {
      return null;
    }
  }

  static void applyAuthentication(Map<String, dynamic> response) {
    token = response['token'] as String;
    role = response['role'] as String;
    username = response['username']?.toString() ?? 'técnico';
  }

  static void logout() {
    token = null;
    role = null;
    username = null;
  }
}

/// Cliente HTTP minimalista (dart:io puro, sem dependências extras) para a API do TGDesk.
class TgdeskApi {
  static WebSocket? _controlSocket;
  static final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  static int _requestSequence = 0;

  static Uri _uri(String path,
      [Map<String, String>? query, bool privateControl = false]) {
    final base = privateControl
        ? Uri.parse('http://10.70.0.1:8080')
        : Uri.parse(AppState.serverUrl);
    return base.replace(path: path, queryParameters: query);
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = {'Content-Type': 'application/json'};
    if (auth && AppState.token != null) {
      h['Authorization'] = 'Bearer ${AppState.token}';
    }
    return h;
  }

  static Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body,
      bool auth = true,
      bool? privateControl}) async {
    // Credencial define O QUE se pode fazer, nunca POR ONDE se fala. Com
    // sessão de técnico o canal é o dele; sem sessão, é o canal do próprio
    // dispositivo, alcançado pela ponte local do agente. HTTP fica só para o
    // resgate da instalação, quando ainda não existe canal nenhum.
    if (auth) {
      return _rpc(method, path, body);
    }
    if (_deviceChannelPath(path)) {
      return _deviceRpc(method, path, body);
    }
    final client = HttpClient();
    try {
      final usePrivateControl = privateControl ??
          (auth &&
              path != '/api/v1/pairing/bind' &&
              path != '/api/v1/bootstrap/pairing-context');
      final req =
          await client.openUrl(method, _uri(path, null, usePrivateControl));
      final headers = await _headers(auth: auth);
      headers.forEach((k, v) => req.headers.set(k, v));
      if (body != null) {
        req.write(jsonEncode(body));
      }
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (text.isEmpty) return null;
        return jsonDecode(text);
      }
      String msg = text;
      try {
        msg = (jsonDecode(text) as Map)['error']?.toString() ?? text;
      } catch (_) {}
      throw ApiException(resp.statusCode, msg);
    } finally {
      client.close(force: true);
    }
  }

  /// Operações que a credencial do dispositivo cobre. Vão pelo canal do
  /// dispositivo; o resgate da instalação fica de fora porque nessa hora ainda
  /// não existe canal.
  static bool _deviceChannelPath(String path) =>
      path.startsWith('/api/v1/support/client/');

  static WebSocket? _deviceSocket;
  static final Map<String, Completer<Map<String, dynamic>>> _devicePending = {};

  /// Porta local onde o agente publica o canal do dispositivo. A tela e o
  /// agente são o mesmo TGDesk: existe UMA conexão com o servidor, e é a do
  /// agente — a tela a alcança por aqui em vez de abrir a sua.
  static const int _bridgePort = 47615;

  static Future<WebSocket> _deviceChannel() async {
    final existing = _deviceSocket;
    if (existing != null && existing.readyState == WebSocket.open) {
      return existing;
    }
    final ws = await WebSocket.connect('ws://127.0.0.1:$_bridgePort/ui');
    ws.listen((data) {
      try {
        final event = jsonDecode(data as String) as Map<String, dynamic>;
        if (event['type'] == 'rpc_response') {
          final id = event['id']?.toString() ?? '';
          _devicePending.remove(id)?.complete(event);
        } else if (event['type'] == 'ticket_thread') {
          _onTicketThread?.call(_asMap(event['payload']));
        }
      } catch (_) {}
    }, onDone: () {
      if (identical(_deviceSocket, ws)) _deviceSocket = null;
    }, onError: (_) {
      if (identical(_deviceSocket, ws)) _deviceSocket = null;
    });
    _deviceSocket = ws;
    return ws;
  }

  /// Chamado quando o servidor empurra a conversa do chamado. É push: a tela
  /// nunca pergunta.
  static void Function(Map<String, dynamic>)? _onTicketThread;
  static set onTicketThread(void Function(Map<String, dynamic>)? handler) {
    _onTicketThread = handler;
    if (handler != null) unawaited(_deviceChannel());
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static Future<dynamic> _deviceRpc(
      String method, String path, Map<String, dynamic>? body) async {
    final socket = await _deviceChannel();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
    final completer = Completer<Map<String, dynamic>>();
    _devicePending[id] = completer;
    // device_id e device_token não vão aqui: o servidor os injeta a partir da
    // credencial do canal, para que ninguém possa agir em nome de outro
    // dispositivo escrevendo outro id no corpo.
    socket.add(jsonEncode({
      'type': 'rpc',
      'id': id,
      'method': method,
      'path': path,
      if (body != null) 'payload': body,
    }));
    final response =
        await completer.future.timeout(const Duration(seconds: 15));
    final status = response['status'] as int? ?? 500;
    if (status < 200 || status >= 300) {
      final payload = response['payload'];
      throw ApiException(
          status,
          payload is Map
              ? payload['error']?.toString() ?? payload.toString()
              : payload?.toString() ?? 'falha no canal do dispositivo');
    }
    return response['payload'];
  }

  static Future<dynamic> _rpc(
      String method, String path, Map<String, dynamic>? body) async {
    final socket = _controlSocket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw ApiException(503, 'canal WebSocket privado indisponível');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    socket.add(jsonEncode({
      'type': 'rpc',
      'id': id,
      'method': method,
      'path': path,
      if (body != null) 'payload': body,
    }));
    final response =
        await completer.future.timeout(const Duration(seconds: 15));
    final status = response['status'] as int? ?? 500;
    if (status < 200 || status >= 300) {
      final payload = response['payload'];
      final message = payload is Map
          ? payload['error']?.toString() ?? payload.toString()
          : payload?.toString() ?? 'falha no canal privado';
      throw ApiException(status, message);
    }
    return response['payload'];
  }

  static Future<Map<String, dynamic>> redeemTechnicianKey(
      Map<String, dynamic> key, String machineId) async {
    final res = await _send('POST', '/api/v1/auth/technician/redeem',
        body: {'key': key, 'machine_id': machineId}, auth: false);
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> refreshTechnicianMachine(
      String credentialId, String secret, String machineId) async {
    final body = {
      'credential_id': credentialId,
      'secret': secret,
      'machine_id': machineId,
    };
    final res = await _send('POST', '/api/v1/auth/technician/refresh',
        body: body, auth: false, privateControl: true);
    return res as Map<String, dynamic>;
  }

  static Future<List<dynamic>> organizations() async =>
      await _send('GET', '/api/v1/organizations') as List<dynamic>;

  static Future<List<dynamic>> networks() async =>
      await _send('GET', '/api/v1/networks') as List<dynamic>;

  static Future<List<dynamic>> subnetworks() async =>
      await _send('GET', '/api/v1/subnetworks') as List<dynamic>;

  static Future<List<dynamic>> devices() async =>
      await _send('GET', '/api/v1/devices') as List<dynamic>;

  static Future<String> remoteCredential(String deviceId) async {
    final response =
        await _send('GET', '/api/v1/devices/$deviceId/remote-credential')
            as Map<String, dynamic>;
    return response['credential']?.toString() ?? '';
  }

  static Future<void> updateDeviceDisplayName(
      String deviceId, String displayName) async {
    await _send('PATCH', '/api/v1/devices/$deviceId/display-name',
        body: {'display_name': displayName});
  }

  static Future<void> claimControlMachine(String deviceId) async =>
      await _send('POST', '/api/v1/devices/$deviceId/control-machine');

  static Future<void> updateDeviceNetworks(
      String deviceId, List<String> networkIds) async {
    await _send('PUT', '/api/v1/devices/$deviceId/networks',
        body: {'network_ids': networkIds});
  }

  static Future<void> updateDeviceSubnetwork(
          String deviceId, String subnetworkId) async =>
      await _send('PUT', '/api/v1/devices/$deviceId/subnetwork',
          body: {'subnetwork_id': subnetworkId});

  static Future<void> updateDeviceSubnetworks(
          String deviceId, List<String> subnetworkIds) async =>
      await _send('PUT', '/api/v1/devices/$deviceId/subnetwork',
          body: {'subnetwork_ids': subnetworkIds});

  static Future<Map<String, dynamic>> bindDevice(
      String pairingCode, String networkId) async {
    final res = await _send('POST', '/api/v1/pairing/bind',
        body: {'pairing_code': pairingCode, 'network_id': networkId});
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> selfBindDevice(
      String pairingCode) async {
    final res = await _send('POST', '/api/v1/pairing/self-bind',
        body: {'pairing_code': pairingCode});
    return res as Map<String, dynamic>;
  }

  /// A entrada do cliente — avulso ou empresarial — deixou de ser uma ação da
  /// interface: o instalador grava a escolha e o agente a executa na primeira
  /// conexão, inclusive quando ninguém abre o TGDesk. Ver
  /// client-agent/cmd/agent/install_intent.go.

  /// Código que vincula outro supervisor a esta organização. A fila de
  /// chamados sempre foi da org, então todos os supervisores vinculados veem
  /// os mesmos chamados ao mesmo tempo.
  static Future<Map<String, dynamic>> createSupervisorInvite(
          String organizationId) async =>
      Map<String, dynamic>.from(await _send(
              'POST', '/api/v1/organizations/$organizationId/supervisor-invite')
          as Map);

  static Future<Map<String, dynamic>> redeemSupervisorInvite(
          String code) async =>
      Map<String, dynamic>.from(await _send(
              'POST', '/api/v1/organizations/supervisor-invite/redeem',
              body: {'code': code}) as Map);

  static Future<List<dynamic>> organizationSupervisors(
          String organizationId) async =>
      await _send('GET', '/api/v1/organizations/$organizationId/supervisors')
          as List<dynamic>;

  static Future<Map<String, dynamic>> pairingContext() async =>
      await _send('GET', '/api/v1/bootstrap/pairing-context')
          as Map<String, dynamic>;

  static Future<Map<String, dynamic>> createOrganization(String name) async {
    final res =
        await _send('POST', '/api/v1/organizations', body: {'name': name});
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createNetwork(
      String organizationId, String name, String cidr) async {
    final res = await _send('POST', '/api/v1/networks', body: {
      'organization_id': organizationId,
      'name': name,
      'cidr_virtual': cidr
    });
    return res as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> createSubnetwork(
      String networkId, String name) async {
    return Map<String, dynamic>.from(await _send('POST', '/api/v1/subnetworks',
        body: {'network_id': networkId, 'name': name}) as Map);
  }

  static Future<void> renameSubnetwork(String id, String name) async =>
      await _send('PUT', '/api/v1/subnetworks/$id', body: {'name': name});

  static Future<void> renameOrganization(String id, String name) async =>
      await _send('PUT', '/api/v1/organizations/$id', body: {'name': name});

  static Future<void> renameNetwork(String id, String name) async =>
      await _send('PUT', '/api/v1/networks/$id', body: {'name': name});

  static Future<List<dynamic>> technicians() async =>
      await _send('GET', '/api/v1/technicians') as List<dynamic>;

  static Future<Map<String, dynamic>> createTechnician(String name) async {
    final res =
        await _send('POST', '/api/v1/technicians', body: {'name': name});
    return res as Map<String, dynamic>;
  }

  static Future<void> setTechnicianBrandingEnabled(
          String technicianId, bool enabled) async =>
      await _send('PUT', '/api/v1/technicians/$technicianId/branding-enabled',
          body: {'enabled': enabled});

  static Future<Map<String, dynamic>> myBranding() async =>
      await _send('GET', '/api/v1/branding/me') as Map<String, dynamic>;

  static Future<Map<String, dynamic>> updateMyBranding(
          String name,
          String? logoBase64,
          bool removeLogo,
          String? faviconBase64,
          bool removeFavicon) async =>
      await _send('PUT', '/api/v1/branding/me', body: {
        'name': name,
        if (logoBase64 != null) 'logo_base64': logoBase64,
        'remove_logo': removeLogo,
        if (faviconBase64 != null) 'favicon_base64': faviconBase64,
        'remove_favicon': removeFavicon,
      }) as Map<String, dynamic>;

  static Future<Map<String, dynamic>> technicianBranding(
          String technicianId) async =>
      await _send('GET', '/api/v1/technicians/$technicianId/branding')
          as Map<String, dynamic>;

  static Future<Map<String, dynamic>> updateTechnicianBranding(
          String technicianId,
          String name,
          String? logoBase64,
          bool removeLogo,
          String? faviconBase64,
          bool removeFavicon) async =>
      await _send('PUT', '/api/v1/technicians/$technicianId/branding', body: {
        'name': name,
        if (logoBase64 != null) 'logo_base64': logoBase64,
        'remove_logo': removeLogo,
        if (faviconBase64 != null) 'favicon_base64': faviconBase64,
        'remove_favicon': removeFavicon,
      }) as Map<String, dynamic>;

  static Future<Map<String, dynamic>> createTechnicianEnrollmentKey(
      String technicianId,
      {int expiresInHours = 72}) async {
    final res = await _send(
        'POST', '/api/v1/technicians/$technicianId/enrollment-key',
        body: {'expires_in_hours': expiresInHours});
    return res as Map<String, dynamic>;
  }

  static Future<void> createAssignment(
      String technicianId, String? organizationId, String? networkId) async {
    await _send('POST', '/api/v1/technicians/assignments', body: {
      'technician_id': technicianId,
      if (organizationId != null && organizationId.isNotEmpty)
        'organization_id': organizationId,
      if (networkId != null && networkId.isNotEmpty) 'network_id': networkId,
    });
  }

  static Future<List<dynamic>> technicianAssignments() async =>
      await _send('GET', '/api/v1/technicians/assignments') as List<dynamic>;

  static Future<void> deleteTechnicianAssignment(String id) async =>
      await _send('DELETE', '/api/v1/technicians/assignments/$id');

  static Future<void> suspendTechnician(String id) async =>
      await _send('POST', '/api/v1/admin/suspend/technician/$id');

  static Future<void> suspendDevice(String id) async =>
      await _send('POST', '/api/v1/admin/suspend/device/$id');

  static Future<void> suspendNetwork(String id) async =>
      await _send('POST', '/api/v1/networks/$id/suspend');

  static Future<void> suspendOrganization(String id) async =>
      await _send('POST', '/api/v1/admin/suspend/organization/$id');

  static Future<void> resumeTechnician(String id) async =>
      await _send('POST', '/api/v1/admin/resume/technician/$id');

  static Future<void> resumeDevice(String id) async =>
      await _send('POST', '/api/v1/admin/resume/device/$id');

  static Future<void> resumeNetwork(String id) async =>
      await _send('POST', '/api/v1/networks/$id/resume');

  static Future<void> resumeOrganization(String id) async =>
      await _send('POST', '/api/v1/admin/resume/organization/$id');

  static Future<void> deleteTechnician(String id) async =>
      await _send('DELETE', '/api/v1/technicians/$id');

  static Future<void> deleteNetwork(String id) async =>
      await _send('DELETE', '/api/v1/networks/$id');

  static Future<void> deleteOrganization(String id) async =>
      await _send('DELETE', '/api/v1/organizations/$id');

  static Future<void> rejectGuestDevice(String id) async =>
      await _send('DELETE', '/api/v1/admin/guest-devices/$id');

  static Future<List<dynamic>> auditLog() async =>
      await _send('GET', '/api/v1/admin/audit') as List<dynamic>;

  static Future<Map<String, dynamic>> deviceHealth(String deviceId) async =>
      await _send('GET', '/api/v1/devices/$deviceId/health')
          as Map<String, dynamic>;

  static Future<List<dynamic>> supportTickets() async =>
      await _send('GET', '/api/v1/support/tickets') as List<dynamic>;

  /// Fila do freelancer (ofertas disponíveis para aceite).
  static Future<List<dynamic>> supportOffers() async =>
      await _send('GET', '/api/v1/support/freelancer/queue') as List<dynamic>;

  /// Fila do supervisor (ofertas 'offered_supervisor' disponíveis para aceite).
  static Future<List<dynamic>> supervisorQueue() async =>
      await _send('GET', '/api/v1/support/supervisor/queue') as List<dynamic>;

  /// Abre um chamado como supervisor. Os dados vão no formato que o tipo
  /// declara — o servidor recusa chave que o tipo não tem e obrigatório em
  /// falta, então o que trafega aqui é contrato, não convenção.
  static Future<Map<String, dynamic>> createSupervisorSupportTicket({
    required String deviceId,
    required String title,
    required String modality,
    String? typeKey,
    Map<String, dynamic> structuredData = const {},
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/tickets',
        body: {
          'device_id': deviceId,
          'title': title,
          if (typeKey != null) 'type_key': typeKey,
          'structured_data': structuredData,
          'modality': modality,
        },
      ) as Map);

  // ---------------------------------------------------------------------
  // Catálogo de tipos e precificação — edição pelo admin.
  //
  // A leitura do catálogo não está aqui de propósito: ele chega pelo canal,
  // no snapshot e nos deltas — inclusive os tipos desativados, que só o
  // admin recebe. Aqui só há escrita.
  // ---------------------------------------------------------------------

  static Future<void> saveTicketType(Map<String, dynamic> type) async =>
      await _send('POST', '/api/v1/admin/ticket-types', body: type);

  static Future<void> deleteTicketType(String key) async =>
      await _send('DELETE', '/api/v1/admin/ticket-types/$key');

  static Future<void> saveTicketTypeField(Map<String, dynamic> field) async =>
      await _send('POST', '/api/v1/admin/ticket-type-fields', body: field);

  static Future<void> deleteTicketTypeField(String id) async =>
      await _send('DELETE', '/api/v1/admin/ticket-type-fields/$id');

  static Future<List<dynamic>> pricingRules() async =>
      await _send('GET', '/api/v1/admin/pricing-rules') as List<dynamic>;

  static Future<void> savePricingRule(Map<String, dynamic> rule) async =>
      await _send('POST', '/api/v1/admin/pricing-rules', body: rule);

  static Future<void> deletePricingRule(String id) async =>
      await _send('DELETE', '/api/v1/admin/pricing-rules/$id');

  static Future<void> acceptSupportOffer(String ticketId) async =>
      await _send('POST', '/api/v1/support/tickets/$ticketId/accept');

  static Future<void> transitionSupportTicket(
          String ticketId, String status) async =>
      await _send('POST', '/api/v1/support/tickets/$ticketId/transition',
          body: {'status': status});

  /// Supervisor aceita um chamado ofertado (status 'offered_supervisor').
  static Future<void> acceptSupportOfferSupervisor(String ticketId) async =>
      await _send(
          'POST', '/api/v1/support/tickets/$ticketId/accept-supervisor');

  /// Registra avaliação (1 a 5 estrelas) de uma das partes do chamado.
  static Future<Map<String, dynamic>> rateSupportTicket(
    String ticketId, {
    required String rateeRole,
    required String rateeId,
    required num stars,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/tickets/$ticketId/rate',
        body: {
          'ratee_role': rateeRole,
          'ratee_id': rateeId,
          'stars': stars,
        },
      ) as Map);

  static Future<void> convertTicketToServiceOrder(
    String ticketId, {
    required String scopeNotes,
    required String osType,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic> values = const {},
  }) async =>
      await _send('POST', '/api/v1/support/tickets/$ticketId/service-order',
          body: {
            'scope_notes': scopeNotes,
            'os_type': osType,
            'items': items,
            'values': values,
          });

  /// Perfil resumido do próprio freelancer logado: nota, disponibilidade,
  /// supervisor vinculado e quantidade de avaliações — ver
  /// MyFreelancerProfile em support.go.
  static Future<Map<String, dynamic>> myFreelancerProfile() async =>
      Map<String, dynamic>.from(
          await _send('GET', '/api/v1/support/freelancer/me') as Map);

  /// Alterna a disponibilidade do freelancer logado (usada no ranking de
  /// candidatos do DispatchTicket) — ver SetFreelancerAvailability.
  static Future<Map<String, dynamic>> setFreelancerAvailability(
          bool available) async =>
      Map<String, dynamic>.from(await _send(
        'PUT',
        '/api/v1/support/freelancer/me/availability',
        body: {'available': available},
      ) as Map);

  /// Histórico de eventos do chamado (aberturas, transições, mensagens de
  /// chat tipo 'message', OS gerada etc.) — ver TicketAudit em support.go.
  static Future<List<dynamic>> ticketAudit(String ticketId) async =>
      await _send('GET', '/api/v1/support/tickets/$ticketId/audit')
          as List<dynamic>;

  /// Envia uma mensagem de chat no chamado (disponível só após aceite) —
  /// ver AddTicketMessage em support.go.
  static Future<Map<String, dynamic>> addTicketMessage(
    String ticketId, {
    required String message,
    List<Map<String, dynamic>>? attachments,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/tickets/$ticketId/messages',
        body: {
          'message': message,
          if (attachments != null) 'attachments': attachments,
        },
      ) as Map);

  /// Permissões temporárias ativas do técnico logado sobre o ticket
  /// (acesso remoto e/ou testes de diagnóstico), ver TicketPermission em
  /// support.go. Retorna {'remote': bool, 'analysis': bool}.
  static Future<Map<String, dynamic>> ticketPermission(String ticketId) async =>
      Map<String, dynamic>.from(
          await _send('GET', '/api/v1/support/tickets/$ticketId/permission')
              as Map);

  /// Registra uma comprovação de atendimento presencial (foto, geolocalização,
  /// assinatura, etc.), ver AddOnsiteEvidence em support.go. idempotencyKey e
  /// contentHash são obrigatórios no backend.
  static Future<Map<String, dynamic>> addOnsiteEvidence(
    String ticketId, {
    required String type,
    required String idempotencyKey,
    required String contentHash,
    required String contentBase64,
    Map<String, dynamic>? metadata,
    DateTime? capturedAt,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/tickets/$ticketId/evidence',
        body: {
          'type': type,
          'idempotency_key': idempotencyKey,
          'content_hash': contentHash,
          'content_base64': contentBase64,
          if (metadata != null) 'metadata': metadata,
          'captured_at':
              (capturedAt ?? DateTime.now()).toUtc().toIso8601String(),
        },
      ) as Map);

  /// Exporta a ordem de serviço final do ticket com as evidências anexadas,
  /// ver ExportServiceOrder em support.go.
  static Future<Map<String, dynamic>> exportServiceOrder(
          String ticketId) async =>
      Map<String, dynamic>.from(
          await _send('GET', '/api/v1/support/tickets/$ticketId/export')
              as Map);

  /// Abertura de chamado pelo dispositivo (autenticado por device_id +
  /// device_token no corpo — não é um endpoint público sem autenticação).
  /// Endpoint real: POST /api/v1/support/client/tickets (ClientOpenTicket).
  /// Pedido em aberto deste dispositivo, para a tela mostrar o protocolo em vez
  /// de reoferecer o botão. Devolve `{'open': false}` quando não há nenhum.
  static Future<Map<String, dynamic>> clientOpenTicketStatus({
    required String deviceId,
    required String deviceToken,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/client/tickets/open',
        auth: false,
        privateControl: false,
        body: {'device_id': deviceId, 'device_token': deviceToken},
      ) as Map);

  /// Conversa do chamado do cliente. Envia `message` junto quando o cliente
  /// escreveu algo, para resolver leitura e escrita numa chamada só. Devolve
  /// também `remote_access_requests`: os pedidos de acesso remoto aguardando
  /// decisão dele.
  static Future<Map<String, dynamic>> clientTicketThread({
    required String deviceId,
    required String deviceToken,
    String? message,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/client/tickets/thread',
        auth: false,
        privateControl: false,
        body: {
          'device_id': deviceId,
          'device_token': deviceToken,
          if (message != null && message.trim().isNotEmpty) 'message': message,
        },
      ) as Map);

  /// Publica um chamado existente na fila de avulsos. Sem isto não havia como
  /// pôr nada na Fila A pela interface — o botão de publicar cria um chamado
  /// novo, não despacha este.
  static Future<void> dispatchTicket(String ticketId) async =>
      _send('POST', '/api/v1/support/tickets/$ticketId/dispatch', body: {});

  /// Início da execução da OS agendada.
  static Future<void> startServiceOrderExecution(String ticketId) async =>
      _send('POST', '/api/v1/support/tickets/$ticketId/os/start', body: {});

  /// Uma etapa de execução. O servidor recusa etapa fora de OS em andamento e
  /// fora do técnico atribuído: a tela oferece, quem valida é ele.
  static Future<void> recordServiceOrderStep(
    String ticketId, {
    required String etapa,
    Map<String, dynamic>? dados,
  }) async =>
      _send('POST', '/api/v1/support/tickets/$ticketId/os/step',
          body: {'etapa': etapa, if (dados != null) 'dados': dados});

  static Future<void> finishServiceOrder(String ticketId,
          {required String notas}) async =>
      _send('POST', '/api/v1/support/tickets/$ticketId/os/finish',
          body: {'notas': notas});

  /// Confirmação de fechamento do lado do técnico. O do cliente é
  /// [clientConfirmClosure]: o chamado só encerra quando as partes confirmam,
  /// e é isso que impede fechar por cima de quem não concordou.
  static Future<void> confirmTicketClosure(String ticketId) async =>
      _send('POST', '/api/v1/support/tickets/$ticketId/confirm-closure',
          body: {});

  /// Nome que o cliente dá ao próprio computador, pelo menu do TGDesk. É a
  /// mesma coluna que o técnico enxerga na lista — quem nomeia a máquina é
  /// quem senta nela.
  static Future<Map<String, dynamic>> clientRenameDevice({
    required String deviceId,
    required String deviceToken,
    required String displayName,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/client/device-name',
        auth: false,
        privateControl: false,
        body: {
          'device_id': deviceId,
          'device_token': deviceToken,
          'display_name': displayName,
        },
      ) as Map);

  /// Decisão do cliente sobre um pedido de acesso remoto. Só a concessão dele
  /// libera o controle da máquina.
  static Future<void> clientRespondRemoteAccess({
    required String deviceId,
    required String deviceToken,
    required String consentId,
    required bool grant,
  }) async =>
      await _send(
        'POST',
        '/api/v1/support/client/tickets/remote-access',
        auth: false,
        privateControl: false,
        body: {
          'device_id': deviceId,
          'device_token': deviceToken,
          'consent_id': consentId,
          'grant': grant,
        },
      );

  /// Confirmação de encerramento do cliente. O chamado só fecha quando todas
  /// as partes confirmam — técnico, supervisor e, no avulso, o cliente.
  static Future<Map<String, dynamic>> clientConfirmClosure({
    required String deviceId,
    required String deviceToken,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/client/tickets/confirm-closure',
        auth: false,
        privateControl: false,
        body: {'device_id': deviceId, 'device_token': deviceToken},
      ) as Map);

  /// O cliente não descreve nada: título e descrição são sintetizados pelo
  /// servidor a partir do diagnóstico de saúde do dispositivo, e a modalidade
  /// (virtual/presencial) é decisão do supervisor na triagem. `standalone`
  /// também é derivado no servidor, pela rede em que o dispositivo está.
  /// Devolve `already_open: true` quando já existe pedido em aberto.
  static Future<Map<String, dynamic>> createClientSupportTicket({
    required String deviceId,
    required String deviceToken,
    Map<String, dynamic>? location,
  }) async =>
      Map<String, dynamic>.from(await _send(
        'POST',
        '/api/v1/support/client/tickets',
        auth: false,
        privateControl: false,
        body: {
          'device_id': deviceId,
          'device_token': deviceToken,
          if (location != null) 'location': location,
        },
      ) as Map);

  static Future<void> wakeDevice(String deviceId) async =>
      await _send('POST', '/api/v1/devices/$deviceId/wake');

  static Future<List<dynamic>> diagnosticCatalog() async =>
      await _send('GET', '/api/v1/diagnostics/catalog') as List<dynamic>;

  static Future<List<dynamic>> diagnostics(String deviceId) async =>
      await _send('GET', '/api/v1/devices/$deviceId/diagnostics')
          as List<dynamic>;

  static Future<Map<String, dynamic>> startDiagnostic(
          String deviceId, String test) async =>
      await _send('POST', '/api/v1/devices/$deviceId/diagnostics',
          body: {'test': test}) as Map<String, dynamic>;

  static Future<Map<String, dynamic>> startDiagnosticQueue(
          String deviceId, List<String> tests) async =>
      await _send('POST', '/api/v1/devices/$deviceId/diagnostics',
          body: {'tests': tests}) as Map<String, dynamic>;

  static Future<Map<String, dynamic>> pauseDiagnostic(
          String deviceId, String runId) async =>
      await _send('POST', '/api/v1/devices/$deviceId/diagnostics/$runId/pause')
          as Map<String, dynamic>;

  static Future<Map<String, dynamic>> resumeDiagnostic(
          String deviceId, String runId) async =>
      await _send('POST', '/api/v1/devices/$deviceId/diagnostics/$runId/resume')
          as Map<String, dynamic>;

  static Future<Map<String, dynamic>> cancelDiagnostic(
          String deviceId, String runId) async =>
      await _send('POST', '/api/v1/devices/$deviceId/diagnostics/$runId/cancel')
          as Map<String, dynamic>;

  /// Conecta ao WebSocket de presença. Chama [onEvent] para cada mensagem recebida.
  static Future<WebSocket> connectPresenceWS(
      void Function(Map<String, dynamic>) onEvent) async {
    final base = Uri.parse(AppState.serverUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = Uri(
      scheme: scheme,
      host: base.host,
      port: base.port,
      path: '/ws/presence',
      queryParameters: {'token': AppState.token ?? ''},
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final ws = await WebSocket.connect(wsUri.toString(), customClient: client);
    ws.listen((data) {
      try {
        onEvent(jsonDecode(data as String) as Map<String, dynamic>);
      } catch (_) {}
    }, onError: (_) {}, cancelOnError: true);
    return ws;
  }

  /// Canal operacional do Técnico. O endereço é privado e só existe depois
  /// que o agente technician estabeleceu o WireGuard.
  static Future<WebSocket> connectPrivateControlWS(
      void Function(Map<String, dynamic>) onEvent,
      {Map<String, dynamic>? credential}) async {
    final wsUri = Uri(
      scheme: 'ws',
      host: '10.70.0.1',
      port: 8080,
      path: '/ws/control/technician',
      queryParameters:
          AppState.token == null ? null : {'token': AppState.token!},
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final ws = await WebSocket.connect(wsUri.toString(), customClient: client);
    final authenticated = Completer<Map<String, dynamic>>();
    ws.listen((data) {
      try {
        final event = jsonDecode(data as String) as Map<String, dynamic>;
        if (event['type'] == 'auth_result') {
          final status = event['status'] as int? ?? 500;
          if (status >= 200 && status < 300 && event['payload'] is Map) {
            authenticated
                .complete(Map<String, dynamic>.from(event['payload'] as Map));
          } else {
            authenticated.completeError(ApiException(
                status, event['error']?.toString() ?? 'credencial inválida'));
          }
          return;
        }
        if (event['type'] == 'rpc_response') {
          final id = event['id']?.toString() ?? '';
          _pending.remove(id)?.complete(event);
          return;
        }
        onEvent(event);
      } catch (_) {}
    }, onError: (Object error) {
      if (!authenticated.isCompleted && credential != null) {
        authenticated.completeError(error);
      }
    }, onDone: () {
      if (identical(_controlSocket, ws)) _controlSocket = null;
      for (final pending in _pending.values) {
        if (!pending.isCompleted) {
          pending.completeError(ApiException(503, 'WebSocket encerrado'));
        }
      }
      _pending.clear();
    }, cancelOnError: true);
    _controlSocket = ws;
    if (credential != null) {
      ws.add(jsonEncode({'type': 'authenticate', 'payload': credential}));
      final response =
          await authenticated.future.timeout(const Duration(seconds: 15));
      AppState.applyAuthentication(response);
    }
    return ws;
  }
}
