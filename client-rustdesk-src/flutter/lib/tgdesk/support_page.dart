import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'diagnostic_text.dart';
import 'health_text.dart';
import 'control_channel.dart';
import 'diagnostics_dialog.dart';
import 'os_builder_page.dart';
import 'remote_session_page.dart';
import 'support_contract.dart';
import 'theme.dart';
import 'ticket_type_form.dart';

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

  /// Chamado aberto no painel da direita. Chamado não é item de lista:
  /// tem histórico, conversa, diagnóstico e partes, e isso pede espaço
  /// próprio em vez de nove botões espremidos num card fechado.
  String? _selectedId;

  /// Seção aberta no dossiê. A conversa é uma delas, não uma coluna
  /// permanente: chat fixo ao lado de uma lista é a forma de um
  /// mensageiro, e o que se gerencia aqui é trabalho, não conversa.
  String _detailTab = 'geral';
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
                : _listAndDetail(tickets),
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
    final controller =
        _chatControllers.putIfAbsent(id, () => TextEditingController());
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

  /// Abre o construtor de orçamento da OS deste chamado.
  ///
  /// O tipo e a modalidade vão junto porque é o que recorta o catálogo: um
  /// toner não entra numa OS de rede, e serviço presencial não entra em
  /// atendimento remoto. O recorte é do catálogo, não da tela — ela só passa
  /// adiante o que o chamado já declara.
  Future<void> _showOsBuilder(Map<String, dynamic> ticket) async {
    final ticketId = ticket['id'].toString();
    final os = _control.serviceOrderOf(ticketId);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Orçamento — ${ticket['title'] ?? ticketId}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: OsBuilderPage(
              ticketId: ticketId,
              typeKey: ticket['type_key']?.toString(),
              osType: os?['os_type']?.toString() ??
                  ticket['modality']?.toString() ??
                  'virtual',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar')),
        ],
      ),
    );
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
        ticket['id'].toString(),
        etapa: etapa.text.trim()));
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
    await _action(() => TgdeskApi.finishServiceOrder(ticket['id'].toString(),
        notas: notas.text.trim()));
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

  /// Lista à esquerda, chamado aberto à direita. A lista responde "o que está
  /// acontecendo"; o painel responde "o que houve neste".
  Widget _listAndDetail(List<Map<String, dynamic>> tickets) {
    if (tickets.isEmpty) return Center(child: Text(_emptyLabel()));
    final selecionado = tickets.firstWhere(
        (item) => item['id']?.toString() == _selectedId,
        orElse: () => tickets.first);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: 320,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: tickets.length,
          itemBuilder: (_, index) => _ticketRow(
              tickets[index],
              tickets[index]['id']?.toString() ==
                  selecionado['id']?.toString()),
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: _ticketDetail(selecionado)),
    ]);
  }

  /// Linha da lista: só o que decide para onde olhar — gravidade, computador,
  /// protocolo e estado. O resto mora no painel.
  Widget _ticketRow(Map<String, dynamic> ticket, bool ativo) {
    final state = ticketStateFromServer(ticket['status']?.toString());
    final prioridade = (ticket['priority'] as num?)?.toInt() ?? 2;
    return Material(
      color: ativo
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedId = ticket['id']?.toString()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _priorityColor(prioridade)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ticket['title']?.toString() ?? 'Computador',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          ticket['protocol']?.toString() ?? '',
                          _stateLabel(state),
                        ].where((v) => v.isNotEmpty).join('  \u00b7  '),
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            Icon(
                ticket['modality'] == 'onsite'
                    ? Icons.location_on_outlined
                    : Icons.desktop_windows_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.outline),
          ]),
        ),
      ),
    );
  }

  Color _priorityColor(int prioridade) {
    if (prioridade >= 4) return TgdeskSeverityColors.critical;
    if (prioridade == 3) return TgdeskSeverityColors.warning;
    return TgdeskSeverityColors.ok;
  }

  /// Painel do chamado: cabeçalho denso mais seções.
  ///
  /// A versão anterior era lista estreita, conteúdo e chat fixo — exatamente
  /// a forma de um mensageiro. Um gerenciador de chamado abre com os fatos:
  /// protocolo, quem, onde, desde quando, quem responde. A conversa é uma
  /// seção entre outras.
  Widget _ticketDetail(Map<String, dynamic> ticket) {
    final state = ticketStateFromServer(ticket['status']?.toString());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _detailHeader(ticket, state),
      const Divider(height: 1),
      _detailTabs(ticket),
      const Divider(height: 1),
      Expanded(child: _detailBody(ticket)),
    ]);
  }

  Widget _detailHeader(Map<String, dynamic> ticket, TgdeskTicketState state) {
    final acoes = _ticketActions(ticket, state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Text(ticket['title']?.toString() ?? 'Computador',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Text(ticket['protocol']?.toString() ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline)),
            ]),
          ),
          _statusChip(state),
        ]),
        const SizedBox(height: 14),
        _factGrid(ticket),
        if (acoes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: acoes),
        ],
      ]),
    );
  }

  /// Os fatos do chamado em grade, no lugar de uma linha de texto separada por
  /// pontos. É o que um gerenciador mostra antes de qualquer outra coisa.
  Widget _factGrid(Map<String, dynamic> ticket) {
    final rede = _networkLabel(ticket) ?? '—';
    final prioridade = (ticket['priority'] as num?)?.toInt() ?? 2;
    final aberto = _relativeDate(ticket['created_at']?.toString());
    final responsavel = ticket['supervisor_id'] == null &&
            ticket['assigned_freelancer_id'] == null
        ? 'Sem respons\u00e1vel'
        : 'Atribu\u00eddo';
    return Wrap(spacing: 32, runSpacing: 12, children: [
      _fact('Modalidade',
          ticket['modality'] == 'onsite' ? 'Presencial' : 'Remoto'),
      _fact('Origem', ticket['standalone'] == true ? 'Avulso' : 'Empresarial'),
      _fact('Rede', rede),
      _fact('Prioridade', _priorityLabel(prioridade),
          cor: _priorityColor(prioridade)),
      _fact('Aberto', aberto),
      _fact('Respons\u00e1vel', responsavel),
    ]);
  }

  Widget _fact(String rotulo, String valor, {Color? cor}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(letterSpacing: .8)),
          const SizedBox(height: 2),
          Text(valor,
              style: TextStyle(fontWeight: FontWeight.w600, color: cor)),
        ],
      );

  String _priorityLabel(int prioridade) {
    if (prioridade >= 4) return 'Alta';
    if (prioridade == 3) return 'M\u00e9dia';
    return 'Normal';
  }

  String _relativeDate(String? iso) {
    final at = DateTime.tryParse(iso ?? '');
    if (at == null) return '\u2014';
    final d = DateTime.now().difference(at.toLocal());
    if (d.inMinutes < 60) return 'h\u00e1 ${d.inMinutes} min';
    if (d.inHours < 24) return 'h\u00e1 ${d.inHours} h';
    return 'h\u00e1 ${d.inDays} d';
  }

  Widget _detailTabs(Map<String, dynamic> ticket) {
    final id = ticket['id']?.toString() ?? '';
    final mensagens = (_control.ticketEvents[id] ?? const []).where((evento) =>
        evento['type'] == 'message' || evento['type'] == 'client_message');
    final abas = <String, String>{
      'geral': 'Vis\u00e3o geral',
      'hardware': 'Hardware',
      'testes': 'Testes',
      'historico': 'Hist\u00f3rico',
      'conversa':
          mensagens.isEmpty ? 'Conversa' : 'Conversa (${mensagens.length})',
    };
    return SizedBox(
      height: 44,
      child: Row(
          children: abas.entries.map((aba) {
        final ativo = _detailTab == aba.key;
        return InkWell(
          onTap: () => setState(() => _detailTab = aba.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    width: 2,
                    color: ativo
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent),
              ),
            ),
            child: Text(aba.value,
                style: TextStyle(
                    fontWeight: ativo ? FontWeight.w600 : FontWeight.w400)),
          ),
        );
      }).toList(growable: false)),
    );
  }

  Widget _detailBody(Map<String, dynamic> ticket) {
    switch (_detailTab) {
      case 'hardware':
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [_hardwareSection(ticket)],
        );
      case 'testes':
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [_testsSection(ticket)],
        );
      case 'historico':
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [_timelineSection(ticket)],
        );
      case 'conversa':
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: _ticketThread(ticket),
        );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      children: [
        _relatoSection(ticket),
        _diagnosisSection(ticket),
        _osDecisionSection(ticket),
      ],
    );
  }

  /// Inventário do computador dentro do chamado. O dado já chega pela telemetria
  /// e vivia só na tela de Dispositivos — quem atende tinha que sair daqui para
  /// saber com que máquina está lidando.
  Widget _hardwareSection(Map<String, dynamic> ticket) {
    final deviceId = ticket['device_id']?.toString();
    final hardware = deviceId == null ? null : _control.deviceHealth[deviceId];
    if (hardware == null) {
      return _emptyNote(
          'Invent\u00e1rio ainda n\u00e3o recebido deste computador.');
    }
    final cpu = _mapOf(hardware['cpu']);
    final memoria = _mapOf(hardware['memory_summary']);
    final discos = _listOf(hardware['storage']);
    final gpus = _listOf(hardware['gpus']);
    final redes = _listOf(hardware['networks']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Computador'),
      Wrap(spacing: 32, runSpacing: 14, children: [
        _fact('Processador', cpu['model']?.toString() ?? '\u2014'),
        _fact('N\u00facleos', cpu['cores']?.toString() ?? '\u2014'),
        _fact('Mem\u00f3ria', _bytes(memoria['total_bytes'])),
        _fact('Discos', '${discos.length}'),
        _fact('Gr\u00e1ficos', gpus.isEmpty ? '\u2014' : '${gpus.length}'),
        _fact('Interfaces de rede', '${redes.length}'),
      ]),
      if (discos.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionTitle('Armazenamento'),
        ...discos.map((disco) {
          final item = _mapOf(disco);
          final uso = (item['used_pct'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(item['model']?.toString() ?? 'Disco',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('${uso.round()}%'),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                  value: (uso / 100).clamp(0.0, 1.0),
                  color: _severityColor(uso >= 90
                      ? 'critical'
                      : uso >= 80
                          ? 'warning'
                          : 'normal')),
            ]),
          );
        }),
      ],
    ]);
  }

  /// Testes do chamado. O catálogo e a execução já existiam num diálogo
  /// separado; aqui ficam os resultados visíveis sem clicar, e o botão só para
  /// rodar algo novo.
  Widget _testsSection(Map<String, dynamic> ticket) {
    final deviceId = ticket['device_id']?.toString();
    final execucoes = deviceId == null
        ? const <String, Map<String, dynamic>>{}
        : (_control.diagnosticRuns[deviceId] ??
            const <String, Map<String, dynamic>>{});
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionTitle('Testes executados')),
        FilledButton.tonalIcon(
          onPressed: _loading ? null : () => _openAuthorizedDiagnostics(ticket),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Executar testes'),
        ),
      ]),
      const SizedBox(height: 8),
      if (execucoes.isEmpty)
        _emptyNote('Nenhum teste executado neste computador ainda.')
      else
        ...execucoes.entries.map((entrada) {
          final run = entrada.value;
          final status = run['status']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(
                  status == 'completed'
                      ? Icons.check_circle_outline
                      : status == 'failed'
                          ? Icons.error_outline
                          : Icons.timelapse,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(TgdeskDiagnosticText.name(
                      run['test']?.toString() ?? entrada.key))),
              Text(status, style: Theme.of(context).textTheme.bodySmall),
            ]),
          );
        }),
    ]);
  }

  Widget _emptyNote(String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
      );

  Map<String, dynamic> _mapOf(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  List<dynamic> _listOf(dynamic v) => v is List ? v : const [];

  String _bytes(dynamic valor) {
    final n = (valor as num?)?.toDouble();
    if (n == null || n <= 0) return '\u2014';
    final gb = n / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }

  Widget _sectionTitle(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texto.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.1)),
      );

  Widget _relatoSection(Map<String, dynamic> ticket) {
    final relato = ticket['description']?.toString().trim() ?? '';
    if (relato.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Relato do cliente'),
        Text(relato, style: const TextStyle(fontSize: 15)),
      ]),
    );
  }

  /// O diagnóstico já chega estruturado no evento 'diagnosis' — código mais
  /// números. A frase é montada aqui, como manda a regra do sistema.
  Widget _diagnosisSection(Map<String, dynamic> ticket) {
    final id = ticket['id']?.toString() ?? '';
    final eventos = _control.ticketEvents[id] ?? const [];
    Map<String, dynamic>? diagnosis;
    for (final evento in eventos) {
      if (evento['type'] == 'diagnosis' && evento['payload'] is Map) {
        diagnosis = Map<String, dynamic>.from(evento['payload'] as Map);
      }
    }
    if (diagnosis == null) return const SizedBox.shrink();
    final issues = (diagnosis['issues'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final level = diagnosis['level']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('An\u00e1lise autom\u00e1tica'),
        Text(TgdeskHealthText.technicalTitle(level),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(TgdeskHealthText.technicalSummary(level),
            style: Theme.of(context).textTheme.bodySmall),
        if (issues.isNotEmpty) const SizedBox(height: 12),
        ...issues.map((issue) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 6, right: 10),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _severityColor(issue['severity']?.toString())),
                ),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            TgdeskHealthText.categoryLabel(
                                issue['category']?.toString()),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(TgdeskHealthText.technical(issue),
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                ),
              ]),
            )),
        if (diagnosis['samples'] != null)
          Text(
              'Baseado em ${diagnosis['samples']} verifica\u00e7\u00f5es '
              'de ${diagnosis['window_minutes'] ?? '?'} minutos.',
              style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _osDecisionSection(Map<String, dynamic> ticket) {
    final context = _diagnosticContextForOs(ticket);
    if (context.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(this.context)
              .colorScheme
              .primaryContainer
              .withOpacity(.32),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  Theme.of(this.context).colorScheme.primary.withOpacity(.22)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.assignment_outlined,
                color: Theme.of(this.context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('Base para construir a OS',
                style: Theme.of(this.context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(context),
        ]),
      ),
    );
  }

  String _diagnosticContextForOs(Map<String, dynamic> ticket) {
    final buffer = StringBuffer();
    final deviceId = ticket['device_id']?.toString();
    final hardware = deviceId == null ? null : _control.deviceHealth[deviceId];
    final events =
        _control.ticketEvents[ticket['id']?.toString() ?? ''] ?? const [];
    Map<String, dynamic>? diagnosis;
    for (final event in events) {
      if (event['type'] == 'diagnosis' && event['payload'] is Map) {
        diagnosis = Map<String, dynamic>.from(event['payload'] as Map);
      }
    }
    if (diagnosis != null) {
      final level = diagnosis['level']?.toString();
      buffer.writeln(
          'Diagnóstico automático: ${TgdeskHealthText.technicalTitle(level)}.');
      final issues = (diagnosis['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .take(4);
      for (final issue in issues) {
        buffer.writeln(
            '- ${TgdeskHealthText.categoryLabel(issue['category']?.toString())}: ${TgdeskHealthText.technical(issue)}');
      }
    }
    final hardwareMap = _mapOf(hardware);
    if (hardwareMap.isNotEmpty) {
      final cpu = _mapOf(hardwareMap['cpu']);
      final memory = _mapOf(hardwareMap['memory_summary']);
      final storage = _listOf(hardwareMap['storage']);
      final gpus = _listOf(hardwareMap['gpus']);
      if (cpu.isNotEmpty ||
          memory.isNotEmpty ||
          storage.isNotEmpty ||
          gpus.isNotEmpty) {
        buffer.writeln(
            'Inventário: ${cpu['model'] ?? 'CPU não identificada'}, memória ${_bytes(memory['total_bytes'])}, ${storage.length} disco(s), ${gpus.length} GPU(s).');
      }
    }
    final runs = deviceId == null
        ? const <String, Map<String, dynamic>>{}
        : (_control.diagnosticRuns[deviceId] ??
            const <String, Map<String, dynamic>>{});
    if (runs.isNotEmpty) {
      final completed =
          runs.values.where((run) => run['status'] == 'completed').length;
      buffer.writeln(
          'Testes executados: ${runs.length}, concluídos: $completed.');
    }
    return buffer.toString().trim();
  }

  Color _severityColor(String? severity) {
    switch (severity) {
      case 'maximum':
      case 'critical':
        return TgdeskSeverityColors.critical;
      case 'warning':
        return TgdeskSeverityColors.warning;
    }
    return TgdeskSeverityColors.ok;
  }

  /// Linha do tempo: cada acontecimento com seu \u00edcone. Antes era texto corrido
  /// misturado com a conversa, e etapa de OS ficava igual a mensagem.
  Widget _timelineSection(Map<String, dynamic> ticket) {
    final id = ticket['id']?.toString() ?? '';
    final eventos = (_control.ticketEvents[id] ?? const [])
        .where((evento) =>
            evento['type'] != 'message' && evento['type'] != 'client_message')
        .toList(growable: false);
    if (eventos.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Hist\u00f3rico'),
      ...eventos.map((evento) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_eventIcon(evento['type']?.toString()),
                  size: 18, color: Theme.of(context).colorScheme.outline),
              const SizedBox(width: 10),
              Expanded(child: Text(_eventLine(evento))),
            ]),
          )),
    ]);
  }

  IconData _eventIcon(String? tipo) {
    switch (tipo) {
      case 'opened':
        return Icons.flag_outlined;
      case 'diagnosis':
        return Icons.monitor_heart_outlined;
      case 'os_started':
        return Icons.play_circle_outline;
      case 'os_step':
        return Icons.checklist_rtl;
      case 'os_finished':
        return Icons.task_alt;
      case 'closure_confirmed':
        return Icons.how_to_reg_outlined;
      case 'remote_access_requested':
        return Icons.lock_open_outlined;
      case 'remote_access_response':
        return Icons.verified_user_outlined;
    }
    return Icons.circle_outlined;
  }

  /// Ações do chamado, na ordem do fluxo. Cada uma aparece só no estado
  /// que a habilita — quem olha não precisa adivinhar o que pode fazer.
  List<Widget> _ticketActions(
      Map<String, dynamic> ticket, TgdeskTicketState state) {
    final mode = ticket['modality'] == 'onsite'
        ? TgdeskServiceMode.onsite
        : TgdeskServiceMode.virtual;
    final mine =
        ticket['assigned_freelancer_id']?.toString() == AppState.technicianId;
    return [
      if (_role == TgdeskSupportRole.freelancer &&
          state == TgdeskTicketState.offered)
        FilledButton(
          onPressed: _loading
              ? null
              : () => _action(
                  () => TgdeskApi.acceptSupportOffer(ticket['id'].toString())),
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
          role: _role, mode: mode, state: state, assignedToCurrentUser: mine))
        FilledButton.tonalIcon(
          onPressed: _loading ? null : () => _openTemporaryRemote(ticket),
          icon: const Icon(Icons.desktop_windows),
          label: const Text('Acesso temporário'),
        ),
      if (TgdeskSupportPolicy.canUseTicketDiagnostics(
          role: _role, state: state, assignedToCurrentUser: mine))
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _openAuthorizedDiagnostics(ticket),
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
          onPressed: _loading ? null : () => _showServiceOrderDialog(ticket),
          child: const Text('Converter em OS'),
        ),
      // O orçamento só existe depois que a OS existe, e é aqui que ele é
      // montado: peças e serviços do catálogo, com o valor resolvido pelo
      // servidor. Sem OS, o botão não aparece — não há o que orçar.
      if (TgdeskSupportPolicy.canManageQueue(_role) &&
          _control.serviceOrderOf(ticket['id'].toString()) != null)
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _showOsBuilder(ticket),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Orçamento'),
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
              : () => _action(
                  () => TgdeskApi.dispatchTicket(ticket['id'].toString())),
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('Publicar na fila'),
        ),
      if (state == TgdeskTicketState.inProgress && mine)
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => _action(() => TgdeskApi.startServiceOrderExecution(
                  ticket['id'].toString())),
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
              : () => _action(() =>
                  TgdeskApi.confirmTicketClosure(ticket['id'].toString())),
          icon: const Icon(Icons.how_to_reg_outlined),
          label: const Text('Confirmar fechamento'),
        ),
    ];
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
  /// de abrir a sessão — reaproveita o mesmo manager usado em
  /// devices_page.dart (RemoteSessionsManager + remoteCredential).
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
      final hostname =
          device?['display_name']?.toString().trim().isNotEmpty == true
              ? device!['display_name'].toString()
              : (device?['hostname']?.toString() ?? 'Dispositivo');
      RemoteSessionsManager.instance.open(RemoteSessionEntry(
        deviceId: deviceId,
        remoteId: device?['rustdesk_id']?.toString() ?? '',
        hostname: hostname,
        credential: credential,
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
      final deviceName =
          device?['display_name']?.toString().trim().isNotEmpty == true
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
    var mode = TgdeskServiceMode.virtual;
    final devices = _control.devices
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['state'] == 'ativo')
        .toList(growable: false);
    String? deviceId = devices.isEmpty ? null : devices.first['id']?.toString();
    // Os tipos vêm do canal, e o primeiro do catálogo é o padrão. O app não
    // conhece tipo nenhum por dentro.
    final tipos = _control.ticketTypes;
    String? typeKey = tipos.isEmpty ? null : tipos.first['key']?.toString();
    var dados = <String, dynamic>{};
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
                          child: Text(device['display_name']
                                      ?.toString()
                                      .trim()
                                      .isNotEmpty ==
                                  true
                              ? device['display_name'].toString()
                              : device['hostname']?.toString() ??
                                  'Dispositivo'),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => deviceId = value),
              ),
              DropdownButtonFormField<String>(
                value: typeKey,
                decoration: const InputDecoration(labelText: 'Tipo de chamado'),
                items: tipos
                    .map((tipo) => DropdownMenuItem(
                          value: tipo['key']?.toString(),
                          child: Text(tipo['label']?.toString() ??
                              tipo['key']?.toString() ??
                              ''),
                        ))
                    .toList(),
                // Trocar o tipo troca o formulário inteiro, então os valores
                // do tipo anterior não sobrevivem: eles não existem no novo.
                onChanged: (value) => setDialogState(() {
                  typeKey = value;
                  dados = <String, dynamic>{};
                }),
              ),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Título')),
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
              // Daqui para baixo quem manda é o esquema do tipo. A modalidade
              // vai como atributo do chamado para que campos condicionais —
              // endereço só no presencial — saibam se devem aparecer.
              TicketTypeForm(
                typeKey: typeKey,
                values: dados,
                ambient: {'modality': mode.name},
                onChanged: (value) => setDialogState(() => dados = value),
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
                      // Avisa antes de enviar o que o servidor recusaria: a
                      // verificação que vale continua sendo a de lá.
                      final falta = ticketTypeFormPending(
                          typeKey, dados, {'modality': mode.name});
                      if (falta != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(falta)));
                        return;
                      }
                      Navigator.pop(context);
                      await _action(() async {
                        await TgdeskApi.createSupervisorSupportTicket(
                          deviceId: selectedDevice,
                          title: title.text.trim(),
                          typeKey: typeKey,
                          structuredData: dados,
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
    final idempotencyKey = '$type-${DateTime.now().microsecondsSinceEpoch}';
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
    // O tipo de OS vem do catálogo. O admin cadastra tipos "os_*" com os campos
    // que a OS precisa: peças, serviços, local, instrução, manual, etc.
    final osTypes = _control.ticketTypes
        .where((t) =>
            (t['key']?.toString() ?? '').startsWith('os_') &&
            t['active'] == true)
        .toList(growable: false);
    if (osTypes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Nenhum tipo de OS cadastrado. Peça ao admin para criar em Catálogo > Tipos.')));
      }
      return;
    }

    var selectedOsType = osTypes.first['key']?.toString() ?? '';
    final osFormData = <String, dynamic>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Transformar chamado em OS'),
          content: SizedBox(
            width: 600,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_diagnosticContextForOs(ticket).isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _diagnosticContextForOs(ticket),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                value: selectedOsType,
                decoration: const InputDecoration(labelText: 'Tipo de OS'),
                items: osTypes
                    .map((tipo) => DropdownMenuItem(
                          value: tipo['key']?.toString(),
                          child: Text(tipo['label']?.toString() ?? ''),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  selectedOsType = value ?? '';
                  osFormData.clear();
                }),
              ),
              const SizedBox(height: 12),
              // A modalidade do chamado define atributos ambientais para campos condicionais
              TicketTypeForm(
                typeKey: selectedOsType,
                values: osFormData,
                ambient: {
                  'modality': ticket['modality'] ?? 'virtual',
                  'standalone': (ticket['standalone'] == true).toString(),
                  'priority': (ticket['priority'] as num? ?? 2).toString(),
                },
                onChanged: (value) => setDialogState(() => osFormData
                  ..clear()
                  ..addAll(value)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final falta =
                    ticketTypeFormPending(selectedOsType, osFormData, {
                  'modality': ticket['modality'] ?? 'virtual',
                  'standalone': (ticket['standalone'] == true).toString(),
                  'priority': (ticket['priority'] as num? ?? 2).toString(),
                });
                if (falta != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(falta)));
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Criar OS'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    // Mapear dados do formulário para os campos da OS
    final scopeNotes = osFormData['escopo']?.toString() ??
        osFormData['scope_notes']?.toString() ??
        osFormData['instrucao']?.toString() ??
        '';
    final diagnosticContext = _diagnosticContextForOs(ticket);
    final enrichedScopeNotes = [
      if (scopeNotes.trim().isNotEmpty) scopeNotes.trim(),
      if (diagnosticContext.isNotEmpty) 'Contexto técnico:\n$diagnosticContext',
    ].join('\n\n');
    final osType = osFormData['os_type']?.toString() ??
        (ticket['modality'] == 'onsite' ? 'onsite' : 'virtual');
    final items = _parseOsItems(osFormData);
    final values = _parseOsValues(osFormData);
    final scheduledAt = _parseDateTime(osFormData['agendada_para']);
    final scheduledLocation =
        _parseLocation(osFormData['local'] ?? osFormData['location']);

    await _action(() async {
      await TgdeskApi.convertTicketToServiceOrder(
        ticket['id'].toString(),
        scopeNotes: enrichedScopeNotes,
        osType: osType,
        items: items,
        values: values,
        scheduledAt: scheduledAt,
        scheduledLocation: scheduledLocation,
        osTypeKey: selectedOsType,
        osStructuredData: osFormData,
      );
    });
  }

  List<Map<String, dynamic>> _parseOsItems(Map<String, dynamic> data) {
    final raw = data['pecas'] ?? data['servicos'] ?? data['items'];
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) return [Map<String, dynamic>.from(raw)];
    return const [];
  }

  Map<String, dynamic> _parseOsValues(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final key in [
      'valor',
      'valor_estimado',
      'estimated',
      'preco',
      'price'
    ]) {
      if (data[key] != null) {
        final v = num.tryParse(data[key].toString());
        if (v != null) out['estimated'] = v.toDouble();
      }
    }
    return out;
  }

  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  Map<String, dynamic>? _parseLocation(dynamic v) {
    if (v == null) return null;
    if (v is Map) return Map<String, dynamic>.from(v);
    return {'address': v.toString()};
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
            await run(
                label,
                () => _sendEvidence(
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
                                    final os =
                                        await TgdeskApi.exportServiceOrder(
                                            ticketId);
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
              if (path != null) {
                await File(path).writeAsString(pretty, flush: true);
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir'),
            onPressed: () async {
              final file = File(
                  '${Directory.systemTemp.path}${Platform.pathSeparator}TGDesk-OS-${order['service_order_id']}.txt');
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
            onPressed: done ? null : () => setDialogState(() => stars[key] = i),
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
