import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'client_home_page.dart';
import 'support_contract.dart';
import 'support_page.dart';
import 'theme.dart';
import 'window_frame.dart';

/// Shell próprio do técnico (freelancer) — distinto do HubHomePage usado por
/// supervisor/admin (ver MODELO-PRODUTO.md, "As 4 interfaces do TGDesk" e
/// "Interface do técnico"). Combina fila de ofertas, histórico de chamados
/// (com chat pós-aceite e avaliação pós-fechamento), perfil/disponibilidade
/// e a aba "Cliente" (base comum a todo dispositivo).
class TgdeskTechnicianHomePage extends StatefulWidget {
  const TgdeskTechnicianHomePage({super.key});

  @override
  State<TgdeskTechnicianHomePage> createState() =>
      _TgdeskTechnicianHomePageState();
}

class _TgdeskTechnicianHomePageState extends State<TgdeskTechnicianHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationRailDestination(
          icon: Icon(Icons.inbox_outlined), label: Text('Fila')),
      NavigationRailDestination(
          icon: Icon(Icons.history), label: Text('Histórico')),
      NavigationRailDestination(
          icon: Icon(Icons.person_outline), label: Text('Perfil')),
      NavigationRailDestination(
          icon: Icon(Icons.monitor_heart_outlined), label: Text('Cliente')),
    ];

    final pages = const [
      _TechnicianQueueTab(),
      SupportPage(),
      _TechnicianProfileTab(),
      TgdeskClientHomePage(embedded: true),
    ];

    return TgdeskWindowScaffold(
      child: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}

/// Aba "Fila": ofertas da Fila B (dispatch_offers) — ver FreelancerQueue em
/// support.go. Cada card mostra os dados liberados pelo supervisor
/// (structured_data/location, incluindo endereço da loja quando presente)
/// ANTES do aceite, requisito explícito do modelo de produto.
class _TechnicianQueueTab extends StatefulWidget {
  const _TechnicianQueueTab();

  @override
  State<_TechnicianQueueTab> createState() => _TechnicianQueueTabState();
}

class _TechnicianQueueTabState extends State<_TechnicianQueueTab> {
  List<Map<String, dynamic>> _offers = [];
  bool _loading = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await TgdeskApi.supportOffers();
      final offers = result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (mounted) setState(() => _offers = offers);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String ticketId) async {
    try {
      await TgdeskApi.acceptSupportOffer(ticketId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chamado aceito.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao aceitar: $e')));
      }
    }
  }

  String? _addressFrom(Map<String, dynamic> offer) {
    final location = offer['location'];
    final structured = offer['structured_data'];
    for (final source in [structured, location]) {
      if (source is Map) {
        final address = source['address'] ??
            source['endereco'] ??
            source['store_address'] ??
            source['loja_endereco'];
        if (address != null && address.toString().trim().isNotEmpty) {
          return address.toString();
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Fila de atendimentos disponíveis',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                  'Veja os dados liberados pelo supervisor antes de aceitar.'),
            ]),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ]),
      ),
      const Divider(height: 1),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(TgdeskSpacing.md),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      Expanded(
        child: _offers.isEmpty
            ? Center(
                child: Text(_loading
                    ? 'Carregando...'
                    : 'Nenhum atendimento ofertado no momento.'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _offers.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TgdeskSpacing.sm),
                itemBuilder: (_, index) {
                  final offer = _offers[index];
                  final address = _addressFrom(offer);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(TgdeskSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.inbox_outlined,
                                color: TgdeskColors.seed),
                            const SizedBox(width: TgdeskSpacing.sm),
                            Expanded(
                              child: Text(
                                  offer['title']?.toString() ??
                                      'Chamado',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                            ),
                            Chip(
                                label: Text(
                                    'Modalidade: ${offer['modality'] ?? '—'}')),
                          ]),
                          const SizedBox(height: TgdeskSpacing.sm),
                          Text('Rank na fila: ${offer['rank'] ?? '—'}'),
                          if (address != null) ...[
                            const SizedBox(height: TgdeskSpacing.xs),
                            Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 16, color: TgdeskColors.seed),
                              const SizedBox(width: 4),
                              Expanded(child: Text(address)),
                            ]),
                          ],
                          const SizedBox(height: TgdeskSpacing.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _accept(offer['ticket_id'].toString()),
                              icon: const Icon(Icons.check),
                              label: const Text('Aceitar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

/// Aba "Histórico": ListTickets (já filtrado certo pro freelancer). Ao tocar,
/// abre um diálogo de detalhe com os eventos (TicketAudit), chat pós-aceite
/// (AddTicketMessage) e avaliação pós-fechamento (RateTicket).
class _TechnicianHistoryTab extends StatefulWidget {
  const _TechnicianHistoryTab();

  @override
  State<_TechnicianHistoryTab> createState() => _TechnicianHistoryTabState();
}

class _TechnicianHistoryTabState extends State<_TechnicianHistoryTab> {
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result = await TgdeskApi.supportTickets();
      final tickets = result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (mounted) setState(() => _tickets = tickets);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          Expanded(
            child: Text('Histórico de chamados',
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
          ),
        ]),
      ),
      const Divider(height: 1),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(TgdeskSpacing.md),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      Expanded(
        child: _tickets.isEmpty
            ? Center(
                child: Text(
                    _loading ? 'Carregando...' : 'Nenhum chamado ainda.'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _tickets.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: TgdeskSpacing.sm),
                itemBuilder: (_, index) {
                  final ticket = _tickets[index];
                  TgdeskTicketState? state;
                  try {
                    state = ticketStateFromServer(
                        ticket['status']?.toString());
                  } catch (_) {}
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.support_agent_outlined,
                          color: TgdeskColors.seed),
                      title: Text(
                          ticket['title']?.toString() ?? 'Chamado'),
                      subtitle: Text(
                          'Status: ${ticket['status'] ?? '—'} • Modalidade: ${ticket['modality'] ?? '—'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetail(ticket, state),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Future<void> _openDetail(
      Map<String, dynamic> ticket, TgdeskTicketState? state) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TicketDetailDialog(ticket: ticket, state: state),
    );
    await _load();
  }
}

/// Diálogo de detalhe de um chamado do histórico: eventos (TicketAudit),
/// chat (se aceito/em progresso) e avaliação por estrelas (se fechado).
class _TicketDetailDialog extends StatefulWidget {
  const _TicketDetailDialog({required this.ticket, required this.state});

  final Map<String, dynamic> ticket;
  final TgdeskTicketState? state;

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;
  final _messageController = TextEditingController();
  bool _sending = false;

  bool get _canChat =>
      widget.state == TgdeskTicketState.accepted ||
      widget.state == TgdeskTicketState.inProgress;
  bool get _canRate => widget.state == TgdeskTicketState.closed;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result =
          await TgdeskApi.ticketAudit(widget.ticket['id'].toString());
      final events = result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      if (mounted) setState(() => _events = events);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await TgdeskApi.addTicketMessage(widget.ticket['id'].toString(),
          message: text);
      _messageController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _rate() async {
    final supervisorId = widget.ticket['supervisor_id']?.toString();
    if (supervisorId == null || supervisorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Chamado sem supervisor associado para avaliar.')));
      return;
    }
    var stars = 5;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Avaliar supervisor'),
          content: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setDialogState(() => stars = i),
                icon: Icon(i <= stars ? Icons.star : Icons.star_border,
                    color: TgdeskColors.seed),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await TgdeskApi.rateSupportTicket(
                      widget.ticket['id'].toString(),
                      rateeRole: 'supervisor',
                      rateeId: supervisorId,
                      stars: stars);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Avaliação registrada.')));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao avaliar: $e')));
                  }
                }
              },
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.ticket['title']?.toString() ?? 'Chamado'),
      content: SizedBox(
        width: 520,
        height: 480,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                if (_error != null) Text(_error!),
                Expanded(
                  child: ListView(children: [
                    for (final event in _events) _eventTile(event),
                  ]),
                ),
                if (_canChat) ...[
                  const Divider(),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                            hintText: 'Mensagem para o supervisor...'),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                  ]),
                ],
                if (_canRate) ...[
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _rate,
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Avaliar atendimento'),
                    ),
                  ),
                ],
              ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (type == 'message') {
      final payload = event['payload'];
      final message = payload is Map ? payload['message']?.toString() : null;
      return ListTile(
        dense: true,
        leading: const Icon(Icons.chat_bubble_outline, size: 18),
        title: Text(message ?? '—'),
        subtitle: Text(event['created_at']?.toString() ?? ''),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.circle, size: 8),
      title: Text(type),
      subtitle: Text(event['created_at']?.toString() ?? ''),
    );
  }
}

/// Aba "Perfil": MyFreelancerProfile (nota, supervisor) + toggle de
/// disponibilidade (SetFreelancerAvailability).
class _TechnicianProfileTab extends StatefulWidget {
  const _TechnicianProfileTab();

  @override
  State<_TechnicianProfileTab> createState() => _TechnicianProfileTabState();
}

class _TechnicianProfileTabState extends State<_TechnicianProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await TgdeskApi.myFreelancerProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    setState(() => _updating = true);
    try {
      final result = await TgdeskApi.setFreelancerAvailability(value);
      if (mounted) {
        setState(() {
          _profile = {..._profile ?? {}, 'availability': result['availability']};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao atualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Erro ao carregar perfil: $_error'));
    }
    final profile = _profile ?? const {};
    final quality = (profile['quality_score'] as num?)?.toDouble() ?? 0;
    final availability = profile['availability'] == true;
    final supervisorName = profile['supervisor_name']?.toString() ?? '—';
    final ratingCount = profile['rating_count'] ?? 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(TgdeskSpacing.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(TgdeskSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Meu perfil',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: TgdeskSpacing.lg),
                  Row(children: [
                    const Icon(Icons.star, color: TgdeskColors.seed),
                    const SizedBox(width: TgdeskSpacing.sm),
                    Text('Nota: ${quality.toStringAsFixed(1)}/100',
                        style: Theme.of(context).textTheme.titleMedium),
                  ]),
                  const SizedBox(height: TgdeskSpacing.xs),
                  Text('$ratingCount avaliações recebidas'),
                  const SizedBox(height: TgdeskSpacing.md),
                  Row(children: [
                    const Icon(Icons.supervisor_account_outlined,
                        color: TgdeskColors.seed),
                    const SizedBox(width: TgdeskSpacing.sm),
                    Text('Supervisor: $supervisorName'),
                  ]),
                  const SizedBox(height: TgdeskSpacing.lg),
                  const Divider(),
                  const SizedBox(height: TgdeskSpacing.md),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponível para novos atendimentos'),
                    value: availability,
                    onChanged: _updating ? null : _toggleAvailability,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
