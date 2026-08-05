import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'diagnostics_dialog.dart';
import 'remote_session_page.dart';
import 'support_contract.dart';
import 'theme.dart';

/// Hash criptográfico (SHA-256) usado como content_hash nas comprovações de
/// atendimento presencial, gerado a partir dos bytes reais do arquivo/texto
/// capturado (ver AddOnsiteEvidence em support.go).
String _sha256Hex(List<int> bytes) {
  return sha256.convert(bytes).toString();
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _control = TgdeskControlChannel.instance;
  /// Aba corrente: active | queue | done | billing.
  String _tab = 'active';
  final Map<String, TextEditingController> _chatControllers = {};
  bool _loading = false;
  List<Map<String, dynamic>> _supervisorQueue = [];
  bool _queueLoading = false;

  TgdeskSupportRole get _role => supportRoleFromServer(AppState.role);

  @override
  void initState() {
    super.initState();
    _control.addListener(_changed);
  }

  @override
  void dispose() {
    _control.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSupervisorQueue() async {
    if (_queueLoading) return;
    setState(() => _queueLoading = true);
    try {
      final result = await TgdeskApi.supervisorQueue();
      _supervisorQueue = result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao carregar fila: $e')));
      }
    } finally {
      if (mounted) setState(() => _queueLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = TgdeskSupportPolicy.canManageQueue(_role);
    final source = _role == TgdeskSupportRole.freelancer
        ? _control.offers
        : _control.tickets;
    // O servidor devolve o campo como 'status' (ListTickets em support.go).
    // Lendo 'state' o filtro achava null em tudo, caía no padrão 'open' e
    // Concluídos nunca mostrava nada.
    const encerrados = {'closed', 'cancelled', 'expired'};
    final tickets = source.where((item) {
      final status = item['status']?.toString() ?? 'open';
      return _tab == 'done'
          ? encerrados.contains(status)
          : !encerrados.contains(status);
    }).toList(growable: false);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tabTitle(),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(_control.connected
                  ? 'Atualizações em tempo real'
                  : 'Reconectando ao servidor'),
            ]),
          ),
          // Um segmentado só, no lugar de dois empilhados: o antigo obrigava
          // a combinar duas escolhas para chegar num lugar.
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'active', label: Text('Ativos')),
              if (canManage)
                const ButtonSegment(value: 'queue', label: Text('Fila')),
              const ButtonSegment(value: 'done', label: Text('Concluídos')),
              if (canManage)
                const ButtonSegment(
                    value: 'billing', label: Text('Faturamento')),
            ],
            selected: {_tab},
            onSelectionChanged: (value) {
              setState(() => _tab = value.first);
              if (_tab == 'queue') unawaited(_loadSupervisorQueue());
            },
          ),
          // Abrir atendimento não depende de onde a pessoa está olhando.
          if (canManage) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _showDispatchDialog,
              icon: const Icon(Icons.add_task),
              label: const Text('Novo atendimento'),
            ),
          ],
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _tab == 'queue'
            ? _supervisorQueueList()
            : _tab == 'billing'
                ? _billingPlaceholder()
                : (tickets.isEmpty
                    ? Center(child: Text(_emptyLabel()))
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: tickets.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, index) =>
                            _ticketCard(tickets[index]),
                      )),
      ),
    ]);
  }

  String _tabTitle() {
    if (_role == TgdeskSupportRole.freelancer) {
      return 'Atendimentos disponíveis';
    }
    switch (_tab) {
      case 'queue':
        return 'Fila de avulsos';
      case 'done':
        return 'Atendimentos concluídos';
      case 'billing':
        return 'Faturamento';
    }
    return 'Chamados e ordens de serviço';
  }

  String _emptyLabel() => _tab == 'done'
      ? 'Nenhum atendimento concluído ainda.'
      : 'Nenhum atendimento em andamento.';

  /// A aba existe para reservar o lugar; a lógica vem depois.
  Widget _billingPlaceholder() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined, size: 42),
          SizedBox(height: 12),
          Text('Conteúdo em construção'),
        ]),
      );

  /// Conversa e histórico do chamado. São a mesma lista de eventos vista de
  /// dois jeitos — mensagem é um tipo de evento entre outros — e ela chega
  /// empurrada pelo canal, evento a evento. A tela nunca vai buscar.
  ///
  /// O cliente já escrevia; sem isto ninguém do outro lado lia.
  Widget _ticketThread(Map<String, dynamic> ticket) {
    final id = ticket['id']?.toString() ?? '';
    final eventos = _control.ticketEvents[id] ?? const [];
    final controller = _chatControllers.putIfAbsent(
        id, () => TextEditingController());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(height: 24),
      if (eventos.isEmpty)
        Text('Nenhuma mensagem ainda.',
            style: Theme.of(context).textTheme.bodySmall)
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(
            shrinkWrap: true,
            children: eventos
                .map((evento) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(_eventLine(evento)),
                    ))
                .toList(growable: false),
          ),
        ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Escrever para o cliente',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _sendMessage(id, controller),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _loading ? null : () => _sendMessage(id, controller),
          icon: const Icon(Icons.send),
          tooltip: 'Enviar',
        ),
      ]),
    ]);
  }

  Future<void> _sendMessage(
      String ticketId, TextEditingController controller) async {
    final texto = controller.text.trim();
    if (texto.isEmpty) return;
    controller.clear();
    await _action(() => TgdeskApi.addTicketMessage(ticketId, message: texto));
  }

  /// O rótulo de cada evento é desta camada: do servidor vem o tipo e o
  /// dado, nunca a frase.
  String _eventLine(Map<String, dynamic> evento) {
    final payload = evento['payload'];
    final corpo = payload is Map ? payload['message']?.toString() : null;
    switch (evento['type']?.toString()) {
      case 'message':
        return 'Técnico: ${corpo ?? ''}';
      case 'client_message':
        return 'Cliente: ${corpo ?? ''}';
      case 'opened':
        return 'Chamado aberto.';
      case 'diagnosis':
        return 'Diagnóstico automático registrado.';
      case 'os_step':
        return 'Etapa da OS registrada.';
      case 'closure_confirmed':
        return 'Fechamento confirmado.';
      case 'remote_access_requested':
        return 'Acesso remoto solicitado.';
      case 'remote_access_response':
        return 'Cliente respondeu ao pedido de acesso.';
    }
    return evento['type']?.toString() ?? '';
  }

  Future<void> _showStepDialog(Map<String, dynamic> ticket) async {
    final etapa = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar etapa'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: etapa,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'O que foi feito',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true || etapa.text.trim().isEmpty) return;
    await _action(() => TgdeskApi.recordServiceOrderStep(
        ticket['id'].toString(), etapa: etapa.text.trim()));
  }

  Future<void> _showFinishDialog(Map<String, dynamic> ticket) async {
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Encerrar ordem de serviço'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: notas,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas de encerramento',
              helperText: 'O cliente confirma depois disto.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _action(() => TgdeskApi.finishServiceOrder(
        ticket['id'].toString(), notas: notas.text.trim()));
  }

  Widget _supervisorQueueList() {
    if (_queueLoading && _supervisorQueue.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_supervisorQueue.isEmpty) {
      return const Center(
          child: Text('Nenhum chamado avulso ofertado no momento.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _supervisorQueue.length,
      separatorBuilder: (_, __) => const SizedBox(height: TgdeskSpacing.sm),
      itemBuilder: (_, index) {
        final offer = _supervisorQueue[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: TgdeskSpacing.lg, vertical: TgdeskSpacing.sm),
            leading: const Icon(Icons.inbox_outlined, color: TgdeskColors.seed),
            title: Text(offer['title']?.toString() ?? 'Chamado avulso'),
            subtitle: Text(
                'Modalidade: ${offer['modality'] ?? '—'} • Rank ${offer['rank'] ?? '—'}'),
            trailing: FilledButton(
              onPressed: _loading
                  ? null
                  : () => _action(() async {
                        await TgdeskApi.acceptSupportOfferSupervisor(
                            offer['ticket_id'].toString());
                        await _loadSupervisorQueue();
                      }),
              child: const Text('Aceitar'),
            ),
          ),
        );
      },
    );
  }

  /// Busca o nome da rede (e, quando disponível via o dispositivo do
  /// chamado, da sub-rede) de origem do ticket — reaproveita as listas já
  /// carregadas em _control.networks/_control.subnetworks (mesma fonte usada
  /// em devices_page.dart), sem chamada extra ao servidor. Só faz sentido
  /// para chamados da própria org do supervisor: a fila de avulsos
  /// (supervisorQueue) não passa por aqui, é uma lista renderizada à parte.
  String? _networkLabel(Map<String, dynamic> ticket) {
    final networkId = ticket['network_id']?.toString();
    if (networkId == null || networkId.isEmpty) return null;
    Map<String, dynamic>? network;
    for (final item in _control.networks) {
      if (item is Map && item['id']?.toString() == networkId) {
        network = Map<String, dynamic>.from(item);
        break;
      }
    }
    final networkName = network?['name']?.toString();
    if (networkName == null || networkName.isEmpty) return null;

    String? subnetName;
    final deviceId = ticket['device_id']?.toString();
    final device = _findDevice(deviceId);
    final subnetworkId = device?['subnetwork_id']?.toString();
    if (subnetworkId != null && subnetworkId.isNotEmpty) {
      for (final item in _control.subnetworks) {
        if (item is Map && item['id']?.toString() == subnetworkId) {
          subnetName = Map<String, dynamic>.from(item)['name']?.toString();
          break;
        }
      }
    }
    return subnetName != null && subnetName.isNotEmpty
        ? '$networkName • $subnetName'
        : networkName;
  }

  Widget _ticketCard(Map<String, dynamic> ticket) {
    // Servidor retorna o campo como "status" (ver ListTickets em support.go),
    // não "state" — corrigido aqui porque ticketStateFromServer agora lança
    // em vez de mascarar silenciosamente estados desconhecidos.
    final state = ticketStateFromServer(ticket['status']?.toString());
    final mode = ticket['modality'] == 'onsite'
        ? TgdeskServiceMode.onsite
        : TgdeskServiceMode.virtual;
    final mine = ticket['assigned_freelancer_id']?.toString() ==
        AppState.technicianId;
    final networkLabel = _networkLabel(ticket);
    return Card(
      child: ExpansionTile(
        leading: Icon(mode == TgdeskServiceMode.virtual
            ? Icons.desktop_windows_outlined
            : Icons.location_on_outlined),
        title: Text(ticket['title']?.toString() ?? 'Solicitação de suporte'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                [
                  if ((ticket['protocol']?.toString() ?? '').isNotEmpty)
                    ticket['protocol'].toString(),
                  ticket['customer_name']?.toString() ?? 'Cliente',
                  _stateLabel(state),
                ].join(' • ')),
            if (networkLabel != null) ...[
              const SizedBox(height: TgdeskSpacing.xs),
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.lan_outlined, size: 16),
                label: Text(networkLabel),
                backgroundColor: TgdeskColors.seed.withOpacity(.08),
              ),
            ],
          ],
        ),
        trailing: _statusChip(state),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(ticket['description']?.toString() ??
                'Sem detalhes adicionais.'),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (_role == TgdeskSupportRole.freelancer &&
                state == TgdeskTicketState.offered)
              FilledButton(
                onPressed: _loading
                    ? null
                    : () => _action(() =>
                        TgdeskApi.acceptSupportOffer(ticket['id'].toString())),
                child: const Text('Aceitar atendimento'),
              ),
            if (state == TgdeskTicketState.accepted &&
                (mine || TgdeskSupportPolicy.canManageQueue(_role)))
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () => _action(() async {
                          await TgdeskApi.transitionSupportTicket(
                              ticket['id'].toString(), 'in_progress');
                        }),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Iniciar atendimento'),
              ),
            if (state == TgdeskTicketState.inProgress &&
                (mine || TgdeskSupportPolicy.canManageQueue(_role)))
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () => _action(() async {
                          await TgdeskApi.transitionSupportTicket(
                              ticket['id'].toString(), 'closed');
                        }),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Concluir atendimento'),
              ),
            if (TgdeskSupportPolicy.canUseTemporaryRemote(
                role: _role,
                mode: mode,
                state: state,
                assignedToCurrentUser: mine))
              FilledButton.tonalIcon(
                onPressed:
                    _loading ? null : () => _openTemporaryRemote(ticket),
                icon: const Icon(Icons.desktop_windows),
                label: const Text('Acesso temporário'),
              ),
            if (TgdeskSupportPolicy.canUseTicketDiagnostics(
                role: _role, state: state, assignedToCurrentUser: mine))
              OutlinedButton.icon(
                onPressed:
                    _loading ? null : () => _openAuthorizedDiagnostics(ticket),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Testes autorizados'),
              ),
            if (mode == TgdeskServiceMode.onsite && mine)
              OutlinedButton.icon(
                onPressed: () => _showEvidenceDialog(ticket),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Comprovações'),
              ),
            if (TgdeskSupportPolicy.canManageQueue(_role) &&
                (state == TgdeskTicketState.accepted ||
                    state == TgdeskTicketState.inProgress))
              OutlinedButton(
                onPressed:
                    _loading ? null : () => _showServiceOrderDialog(ticket),
                child: const Text('Converter em OS'),
              ),
            if (state == TgdeskTicketState.closed)
              OutlinedButton.icon(
                onPressed: () => _showRatingDialog(ticket),
                icon: const Icon(Icons.star_outline),
                label: const Text('Avaliar atendimento'),
              ),
            // Sem isto não havia como pôr um chamado existente na Fila A
            // pela interface — o botão de publicar cria outro, não despacha
            // este.
            if (TgdeskSupportPolicy.canManageQueue(_role) &&
                state == TgdeskTicketState.open)
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _action(() => TgdeskApi.dispatchTicket(
                        ticket['id'].toString())),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Publicar na fila'),
              ),
            if (state == TgdeskTicketState.inProgress && mine)
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => _action(() => TgdeskApi
                        .startServiceOrderExecution(ticket['id'].toString())),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Iniciar OS'),
              ),
            if (state == TgdeskTicketState.inProgress && mine)
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _showStepDialog(ticket),
                icon: const Icon(Icons.checklist_rtl),
                label: const Text('Registrar etapa'),
              ),
            if (state == TgdeskTicketState.inProgress && mine)
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _showFinishDialog(ticket),
                icon: const Icon(Icons.task_alt),
                label: const Text('Encerrar OS'),
              ),
            // O chamado só encerra quando as partes confirmam — é o que
            // impede fechar por cima de quem não concordou.
            if (state == TgdeskTicketState.awaitingConfirmation)
              FilledButton.tonalIcon(
                onPressed: _loading
                    ? null
                    : () => _action(() => TgdeskApi
                        .confirmTicketClosure(ticket['id'].toString())),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Confirmar fechamento'),
              ),
          ]),
          _ticketThread(ticket),
        ],
      ),
    );
  }

  Map<String, dynamic>? _findDevice(String? deviceId) {
    if (deviceId == null) return null;
    for (final item in _control.devices) {
      if (item is Map && item['id']?.toString() == deviceId) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  /// Botão "Acesso temporário": confirma junto ao servidor que a permissão
  /// temporária (temporary_ticket_permissions.allow_remote) está ativa antes
  /// de abrir a sessão — reaproveita a mesma navegação usada em
  /// devices_page.dart (TgdeskRemoteSessionPage + remoteCredential).
  Future<void> _openTemporaryRemote(Map<String, dynamic> ticket) async {
    await _action(() async {
      final ticketId = ticket['id'].toString();
      final permission = await TgdeskApi.ticketPermission(ticketId);
      if (permission['remote'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Ainda não há permissão de acesso remoto ativa para este chamado (aguardando aceite/autorização).')));
        }
        return;
      }
      final deviceId = ticket['device_id']?.toString();
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('chamado sem dispositivo associado');
      }
      final device = _findDevice(deviceId);
      final credential = await TgdeskApi.remoteCredential(deviceId);
      if (credential.isEmpty) {
        throw Exception('autorização remota indisponível');
      }
      if (!mounted) return;
      final hostname = device?['display_name']?.toString().trim().isNotEmpty ==
              true
          ? device!['display_name'].toString()
          : (device?['hostname']?.toString() ?? 'Dispositivo');
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TgdeskRemoteSessionPage(
          deviceId: deviceId,
          remoteId: device?['rustdesk_id']?.toString() ?? '',
          hostname: hostname,
          credential: credential,
        ),
      ));
    });
  }

  /// Botão "Testes autorizados": mesma checagem de permissão, mas para
  /// allow_analysis, abrindo o mesmo DiagnosticDialog usado em
  /// devices_page.dart / remote_session_page.dart.
  Future<void> _openAuthorizedDiagnostics(Map<String, dynamic> ticket) async {
    await _action(() async {
      final ticketId = ticket['id'].toString();
      final permission = await TgdeskApi.ticketPermission(ticketId);
      if (permission['analysis'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Ainda não há autorização de testes de diagnóstico para este chamado.')));
        }
        return;
      }
      final deviceId = ticket['device_id']?.toString();
      if (deviceId == null || deviceId.isEmpty) {
        throw Exception('chamado sem dispositivo associado');
      }
      final device = _findDevice(deviceId);
      final deviceName = device?['display_name']?.toString().trim().isNotEmpty ==
              true
          ? device!['display_name'].toString()
          : (device?['hostname']?.toString() ?? 'Dispositivo');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => DiagnosticDialog(
          deviceId: deviceId,
          deviceName: deviceName,
          online: device?['presence']?.toString() == 'online',
        ),
      );
    });
  }

  Future<void> _showDispatchDialog() async {
    final title = TextEditingController();
    final description = TextEditingController();
    var mode = TgdeskServiceMode.virtual;
    final devices = _control.devices
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['state'] == 'ativo')
        .toList(growable: false);
    String? deviceId = devices.isEmpty ? null : devices.first['id']?.toString();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Publicar atendimento'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: deviceId,
                decoration: const InputDecoration(labelText: 'Dispositivo'),
                items: devices
                    .map((device) => DropdownMenuItem(
                          value: device['id']?.toString(),
                          child: Text(device['display_name']?.toString().trim().isNotEmpty == true
                              ? device['display_name'].toString()
                              : device['hostname']?.toString() ?? 'Dispositivo'),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => deviceId = value),
              ),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Título')),
              TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Dados técnicos e localização')),
              const SizedBox(height: 12),
              SegmentedButton<TgdeskServiceMode>(
                segments: const [
                  ButtonSegment(
                      value: TgdeskServiceMode.virtual, label: Text('Virtual')),
                  ButtonSegment(
                      value: TgdeskServiceMode.onsite,
                      label: Text('Presencial')),
                ],
                selected: {mode},
                onSelectionChanged: (value) =>
                    setDialogState(() => mode = value.first),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: deviceId == null
                  ? null
                  : () async {
                      final selectedDevice = deviceId!;
                      Navigator.pop(context);
                      await _action(() async {
                        await TgdeskApi.createSupervisorSupportTicket(
                          deviceId: selectedDevice,
                          title: title.text.trim(),
                          description: description.text.trim(),
                          modality: mode.name,
                        );
                      });
                    },
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Envia uma comprovação e trata erros com um SnackBar — usado por todos
  /// os botões de captura do diálogo de comprovações.
  Future<void> _sendEvidence({
    required String ticketId,
    required String type,
    required List<int> bytes,
    Map<String, dynamic>? metadata,
  }) async {
    final idempotencyKey =
        '$type-${DateTime.now().microsecondsSinceEpoch}';
    final hash = _sha256Hex(bytes);
    await TgdeskApi.addOnsiteEvidence(
      ticketId,
      type: type,
      idempotencyKey: idempotencyKey,
      contentHash: hash,
      contentBase64: base64Encode(bytes),
      metadata: metadata,
      capturedAt: DateTime.now(),
    );
  }

  Future<void> _showServiceOrderDialog(Map<String, dynamic> ticket) async {
    final scope = TextEditingController();
    final item = TextEditingController();
    final value = TextEditingController();
    var osType = ticket['modality'] == 'onsite' ? 'onsite' : 'virtual';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Transformar chamado em OS'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: scope,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Escopo acordado',
                    hintText: 'Descreva exatamente o que será executado'),
              ),
              TextField(
                controller: item,
                decoration:
                    const InputDecoration(labelText: 'Item ou serviço'),
              ),
              TextField(
                controller: value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Valor estimado'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'virtual', label: Text('Virtual')),
                  ButtonSegment(value: 'onsite', label: Text('Presencial')),
                ],
                selected: {osType},
                onSelectionChanged: (selection) =>
                    setDialogState(() => osType = selection.first),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Criar OS')),
          ],
        ),
      ),
    );
    if (confirmed != true || scope.text.trim().isEmpty) return;
    await _action(() async {
      await TgdeskApi.convertTicketToServiceOrder(
        ticket['id'].toString(),
        scopeNotes: scope.text.trim(),
        osType: osType,
        items: item.text.trim().isEmpty
            ? const []
            : [<String, dynamic>{'description': item.text.trim()}],
        values: {
          'estimated': double.tryParse(value.text.replaceAll(',', '.')) ?? 0
        },
      );
    });
  }

  Future<void> _showEvidenceDialog(Map<String, dynamic> ticket) async {
    final ticketId = ticket['id'].toString();
    final latController = TextEditingController();
    final lonController = TextEditingController();
    var busy = false;
    String? status;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> run(String kind, Future<void> Function() op) async {
            setDialogState(() {
              busy = true;
              status = null;
            });
            try {
              await op();
              setDialogState(() => status = '$kind registrada com sucesso.');
            } catch (e) {
              setDialogState(() => status = 'Erro ao registrar $kind: $e');
            } finally {
              setDialogState(() => busy = false);
            }
          }

          Future<void> pickAndSendPhoto(String type, String label) async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              withData: true,
            );
            final file = result?.files.firstOrNull;
            if (file?.bytes == null) return;
            await run(label, () => _sendEvidence(
                  ticketId: ticketId,
                  type: type,
                  bytes: file!.bytes!,
                  metadata: {'filename': file.name},
                ));
          }

          return AlertDialog(
            title: const Text('Comprovações do atendimento'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Geolocalização (informe manualmente — sem '
                          'GPS nativo em desktop; captura por app móvel do '
                          'freelancer fica para uma fase futura do produto).'),
                      const SizedBox(height: TgdeskSpacing.sm),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: latController,
                            decoration:
                                const InputDecoration(labelText: 'Latitude'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                          ),
                        ),
                        const SizedBox(width: TgdeskSpacing.sm),
                        Expanded(
                          child: TextField(
                            controller: lonController,
                            decoration:
                                const InputDecoration(labelText: 'Longitude'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                          ),
                        ),
                      ]),
                      const SizedBox(height: TgdeskSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () {
                                  final lat =
                                      double.tryParse(latController.text);
                                  final lon =
                                      double.tryParse(lonController.text);
                                  if (lat == null || lon == null) {
                                    setDialogState(() => status =
                                        'Informe latitude e longitude válidas.');
                                    return;
                                  }
                                  run(
                                      'Geolocalização',
                                      () => _sendEvidence(
                                            ticketId: ticketId,
                                            type: 'geolocation',
                                            bytes: utf8.encode(
                                                '$lat,$lon,${DateTime.now().toIso8601String()}'),
                                            metadata: {
                                              'latitude': lat,
                                              'longitude': lon,
                                            },
                                          ));
                                },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Registrar geolocalização'),
                        ),
                      ),
                      const Divider(height: TgdeskSpacing.xl),
                      const Text('Fotos'),
                      const SizedBox(height: TgdeskSpacing.sm),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => pickAndSendPhoto(
                                  'arrival_photo', 'Foto de chegada'),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Chegada'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => pickAndSendPhoto(
                                  'execution_photo', 'Foto de execução'),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Execução'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => pickAndSendPhoto(
                                  'completion_photo', 'Foto de conclusão'),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Conclusão'),
                        ),
                      ]),
                      const Divider(height: TgdeskSpacing.xl),
                      const Text(
                          'Assinatura (upload de imagem/PDF já assinado — '
                          'sem canvas de assinatura nesta fase, pacote '
                          '"signature" não está nas dependências do projeto).'),
                      const SizedBox(height: TgdeskSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  final result =
                                      await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: [
                                      'png',
                                      'jpg',
                                      'jpeg',
                                      'pdf'
                                    ],
                                    withData: true,
                                  );
                                  final file = result?.files.firstOrNull;
                                  if (file?.bytes == null) return;
                                  await run(
                                      'Assinatura',
                                      () => _sendEvidence(
                                            ticketId: ticketId,
                                            type: 'signature',
                                            bytes: file!.bytes!,
                                            metadata: {'filename': file.name},
                                          ));
                                },
                          icon: const Icon(Icons.draw_outlined),
                          label: const Text('Anexar assinatura'),
                        ),
                      ),
                      const Divider(height: TgdeskSpacing.xl),
                      const Text('Documento final'),
                      const SizedBox(height: TgdeskSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setDialogState(() => busy = true);
                                  try {
                                    final os = await TgdeskApi
                                        .exportServiceOrder(ticketId);
                                    if (context.mounted) {
                                      await _showExportedOrderDialog(os);
                                    }
                                  } catch (e) {
                                    setDialogState(() =>
                                        status = 'Erro ao exportar OS: $e');
                                  } finally {
                                    setDialogState(() => busy = false);
                                  }
                                },
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Exportar ordem de serviço'),
                        ),
                      ),
                      if (busy) ...[
                        const SizedBox(height: TgdeskSpacing.md),
                        const LinearProgressIndicator(),
                      ],
                      if (status != null) ...[
                        const SizedBox(height: TgdeskSpacing.sm),
                        Text(status!),
                      ],
                    ]),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showExportedOrderDialog(Map<String, dynamic> order) async {
    final pretty = const JsonEncoder.withIndent('  ').convert(order);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ordem de serviço exportada'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(pretty),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('Salvar arquivo'),
            onPressed: () async {
              final path = await FilePicker.platform.saveFile(
                dialogTitle: 'Exportar ordem de serviço',
                fileName: 'TGDesk-OS-${order['service_order_id']}.json',
                type: FileType.custom,
                allowedExtensions: const ['json'],
              );
              if (path != null) await File(path).writeAsString(pretty, flush: true);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
            onPressed: () async {
              final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}TGDesk-OS-${order['service_order_id']}.txt');
              await file.writeAsString(pretty, flush: true);
              await Process.start('notepad.exe', ['/p', file.path]);
            },
          ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar')),
        ],
      ),
    );
  }

  /// Diálogo de avaliação pós-fechamento (1-5 estrelas por participante).
  Future<void> _showRatingDialog(Map<String, dynamic> ticket) async {
    final ticketId = ticket['id'].toString();
    final freelancerId = ticket['assigned_freelancer_id']?.toString();
    final deviceId = ticket['device_id']?.toString();
    final clientRole =
        ticket['standalone'] == true ? 'cliente_avulso' : 'cliente';
    final supervisorId = ticket['supervisor_id']?.toString();
    final stars = <String, int>{};
    final sent = <String>{};
    String? status;

    Future<void> submit(
        StateSetter setDialogState, String role, String id) async {
      final value = stars['$role:$id'] ?? 0;
      if (value < 1) {
        setDialogState(() => status = 'Selecione de 1 a 5 estrelas.');
        return;
      }
      try {
        await TgdeskApi.rateSupportTicket(ticketId,
            rateeRole: role, rateeId: id, stars: value);
        setDialogState(() {
          sent.add('$role:$id');
          status = 'Avaliação registrada.';
        });
      } catch (e) {
        setDialogState(() => status = 'Erro ao avaliar: $e');
      }
    }

    Widget starsRow(StateSetter setDialogState, String role, String id) {
      final key = '$role:$id';
      final value = stars[key] ?? 0;
      final done = sent.contains(key);
      return Row(children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            onPressed: done
                ? null
                : () => setDialogState(() => stars[key] = i),
            icon: Icon(i <= value ? Icons.star : Icons.star_border,
                color: TgdeskColors.seed),
          ),
        const SizedBox(width: TgdeskSpacing.sm),
        FilledButton(
          onPressed: done ? null : () => submit(setDialogState, role, id),
          child: Text(done ? 'Enviado' : 'Enviar'),
        ),
      ]);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Avaliar atendimento'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (freelancerId != null && freelancerId.isNotEmpty) ...[
                  const Text('Freelancer'),
                  starsRow(setDialogState, 'freelancer', freelancerId),
                  const SizedBox(height: TgdeskSpacing.md),
                ],
                if (deviceId != null && deviceId.isNotEmpty) ...[
                  const Text('Cliente'),
                  starsRow(setDialogState, clientRole, deviceId),
                  const SizedBox(height: TgdeskSpacing.md),
                ],
                if (supervisorId != null && supervisorId.isNotEmpty) ...[
                  const Text('Supervisor'),
                  starsRow(setDialogState, 'supervisor', supervisorId),
                ],
                if (status != null) ...[
                  const SizedBox(height: TgdeskSpacing.sm),
                  Text(status!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar')),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(TgdeskTicketState state) =>
      Chip(label: Text(_stateLabel(state)));

  String _stateLabel(TgdeskTicketState state) => switch (state) {
        TgdeskTicketState.open => 'Aberto',
        TgdeskTicketState.offeredSupervisor => 'Ofertado (supervisor)',
        TgdeskTicketState.offered => 'Ofertado',
        TgdeskTicketState.accepted => 'Atribuído',
        TgdeskTicketState.inProgress => 'Em atendimento',
        TgdeskTicketState.awaitingConfirmation => 'Aguardando confirmação',
        TgdeskTicketState.closed => 'Encerrado',
        TgdeskTicketState.cancelled => 'Cancelado',
        TgdeskTicketState.expired => 'Expirado',
        TgdeskTicketState.reopened => 'Reaberto',
      };
}
