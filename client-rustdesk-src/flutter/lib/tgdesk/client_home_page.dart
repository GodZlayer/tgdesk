import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'agent_deploy.dart';
import 'api_client.dart';
import 'branding_window_icon.dart';
import 'health_text.dart';
import 'money.dart';
import 'theme.dart';
import 'ui_contract.dart';
import 'window_frame.dart';

class TgdeskClientHomePage extends StatefulWidget {
  const TgdeskClientHomePage(
      {super.key, this.embedded = false, this.onTechnicianActivated});
  final bool embedded;
  final VoidCallback? onTechnicianActivated;
  @override
  State<TgdeskClientHomePage> createState() => _TgdeskClientHomePageState();
}

class _TgdeskClientHomePageState extends State<TgdeskClientHomePage> {
  Timer? _pollTimer;
  Map<String, dynamic>? _status;
  bool _agentMissing = false;
  bool _serverOnline = false;
  bool _openingTicket = false;
  bool _selfBindAttempted = false;
  Map<String, dynamic>? _openTicket;
  final TextEditingController _chatController = TextEditingController();
  String _version = '';

  Map<String, dynamic> get _branding => _map(_status?['branding']);

  String get _productName {
    if (widget.embedded || _status?['state'] != 'ativo') return 'TGDesk';
    final branding = _branding;
    if (branding['enabled'] != true) return 'TGDesk';
    final name =
        (branding['application_name']?.toString().trim().isNotEmpty ?? false)
            ? branding['application_name']?.toString().trim() ?? ''
            : branding['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'TGDesk' : name;
  }

  String _brandText(String value) => value.replaceAll('TGDesk', _productName);

  Widget _clientBrandTitle() {
    final encoded = _branding['logo_base64']?.toString() ?? '';
    if (encoded.isNotEmpty) {
      return Image.memory(base64Decode(encoded),
          height: 25, width: 72, fit: BoxFit.contain);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(_productName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
    ]);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) {
      unawaited(_ensureTrayRunning());
    }
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    if (_canRequestSupport) {
      // A conversa chega por push no canal do dispositivo. A leitura inicial
      // existe só porque esta tela acabou de abrir e ainda não recebeu nada.
      TgdeskApi.onTicketThread = (thread) {
        if (mounted) {
          setState(() => _openTicket = thread['open'] == true ? thread : null);
        }
      };
      unawaited(_refreshOpenTicket());
    }
  }

  Future<void> _refreshOpenTicket({String? send}) async {
    try {
      final identity = await _deviceIdentity();
      final deviceId = identity['device_id']?.toString() ?? '';
      if (deviceId.isEmpty) return;
      // A thread já devolve protocolo, status, mensagens e pedidos de acesso
      // remoto — uma chamada resolve o painel inteiro.
      final result = await TgdeskApi.clientTicketThread(
        deviceId: deviceId,
        deviceToken: identity['device_token']?.toString() ?? '',
        message: send,
      );
      if (mounted) {
        setState(() => _openTicket = result['open'] == true ? result : null);
      }
    } catch (_) {
      // Sem chamado conhecido a tela apenas reoferece o botão; o servidor
      // deduplica de qualquer forma se o cliente pedir de novo.
    }
  }

  Future<void> _answerRemoteAccess(String consentId, bool grant) async {
    try {
      final identity = await _deviceIdentity();
      await TgdeskApi.clientRespondRemoteAccess(
        deviceId: identity['device_id']?.toString() ?? '',
        deviceToken: identity['device_token']?.toString() ?? '',
        consentId: consentId,
        grant: grant,
      );
      await _refreshOpenTicket();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(grant
                ? 'Acesso autorizado. O técnico já pode assumir o computador.'
                : 'Acesso negado. O técnico segue com os testes, sem controlar a máquina.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // O pedido de acesso remoto é a decisão mais sensível que o cliente toma na
  // tela, então aparece como bloco próprio e destacado — nunca embutido no
  // meio das mensagens, onde passaria batido.
  Widget _remoteAccessRequest(Map<String, dynamic> pedido) => Container(
        margin: const EdgeInsets.only(top: TgdeskSpacing.sm),
        padding: const EdgeInsets.all(TgdeskSpacing.md),
        decoration: BoxDecoration(
          color: TgdeskColors.warning.withOpacity(.10),
          border: Border.all(color: TgdeskColors.warning.withOpacity(.55)),
          borderRadius: BorderRadius.circular(TgdeskSpacing.sm),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_open_outlined,
                color: TgdeskColors.warning, size: 20),
            const SizedBox(width: TgdeskSpacing.sm),
            Expanded(
              child: Text(
                  '${pedido['requested_by'] ?? 'O técnico'} pediu para acessar seu computador',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          if ((pedido['motivo']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: TgdeskSpacing.xs),
            Text('Motivo: ${pedido['motivo']}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: TgdeskTextColors.strong)),
          ],
          const SizedBox(height: TgdeskSpacing.xs),
          Text(
              'Se você recusar, o técnico continua podendo fazer testes, mas não controla a máquina.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TgdeskTextColors.body)),
          const SizedBox(height: TgdeskSpacing.sm),
          Row(children: [
            FilledButton(
                onPressed: () =>
                    _answerRemoteAccess(pedido['id'].toString(), true),
                child: const Text('Autorizar')),
            const SizedBox(width: TgdeskSpacing.sm),
            TextButton(
                onPressed: () =>
                    _answerRemoteAccess(pedido['id'].toString(), false),
                child: const Text('Agora não')),
          ]),
        ]),
      );

  // A tela Cliente já é diferente por tier. Para quem está logado como
  // supervisor ou admin, ela oferece o resgate do convite: é assim que ele
  // passa a supervisionar a organização de outro, vendo a mesma fila.
  Widget _supervisorInvitePanel() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: TgdeskSpacing.md),
        padding: const EdgeInsets.symmetric(
            horizontal: TgdeskSpacing.lg, vertical: TgdeskSpacing.md),
        decoration: BoxDecoration(
          color: TgdeskColors.seed.withOpacity(.05),
          border: Border.all(color: TgdeskColors.seed.withOpacity(.3)),
          borderRadius: BorderRadius.circular(TgdeskSpacing.sm),
        ),
        child: Row(children: [
          Icon(Icons.group_add_outlined, color: TgdeskColors.seed),
          const SizedBox(width: TgdeskSpacing.sm),
          Expanded(
            child: Text(
                'Recebeu um código para supervisionar outra organização? '
                'Resgate aqui para passar a ver os chamados dela.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: TgdeskTextColors.strong)),
          ),
          TextButton(
            onPressed: _resgatarConviteSupervisor,
            child: const Text('Resgatar código'),
          ),
        ]),
      );

  Future<void> _resgatarConviteSupervisor() async {
    final campo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Supervisionar outra organização'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: campo,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
                labelText: 'Código recebido',
                helperText: 'Você passa a ver os chamados dessa organização.'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Resgatar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await TgdeskApi.redeemSupervisorInvite(campo.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Você agora supervisiona ${r['organization_name'] ?? 'a organização'}.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _confirmarEncerramento() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Confirmar o encerramento?'),
        content: const Text(
            'O técnico informou que concluiu o atendimento. Confirme só se o '
            'problema foi resolvido — o chamado é encerrado quando todas as '
            'partes confirmarem.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Ainda não')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final identity = await _deviceIdentity();
      final r = await TgdeskApi.clientConfirmClosure(
        deviceId: identity['device_id']?.toString() ?? '',
        deviceToken: identity['device_token']?.toString() ?? '',
      );
      await _refreshOpenTicket();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r['chamado_fechado'] == true
                ? 'Atendimento encerrado. Obrigado!'
                : 'Sua confirmação foi registrada. Aguardando as demais.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  // Estado do atendimento em linguagem de cliente: onde está e o que se espera
  // dele agora.
  Widget _servicePanel(Map<String, dynamic> os) {
    final status = os['status']?.toString() ?? '';
    final aguardaEle = os['aguarda_sua_confirmacao'] == true;
    final agendada = os['agendada_para']?.toString() ?? '';
    String texto;
    Color accentColor;
    IconData statusIcon;
    switch (status) {
      case 'offered':
        texto = 'Procurando um técnico disponível para o seu atendimento.';
        accentColor = TgdeskColors.seed;
        statusIcon = Icons.engineering_outlined;
        break;
      case 'assigned':
        texto = agendada.isEmpty
            ? 'Um técnico assumiu o atendimento.'
            : 'Atendimento agendado. Um técnico já está designado.';
        accentColor = TgdeskColors.seed;
        statusIcon = Icons.engineering_outlined;
        break;
      case 'in_progress':
        texto = 'O técnico está trabalhando no seu atendimento agora.';
        accentColor = TgdeskColors.online;
        statusIcon = Icons.engineering_outlined;
        break;
      case 'awaiting_confirmation':
        if (aguardaEle) {
          texto = 'O técnico concluiu. Confirme para encerrar o atendimento.';
          accentColor = TgdeskColors.online;
          statusIcon = Icons.task_alt;
        } else {
          texto = 'Concluído. Aguardando a confirmação dos responsáveis.';
          accentColor = TgdeskColors.seed;
          statusIcon = Icons.engineering_outlined;
        }
        break;
      case 'completed':
        texto = 'Atendimento concluído.';
        accentColor = TgdeskColors.online;
        statusIcon = Icons.verified_outlined;
        break;
      default:
        texto = 'Seu pedido foi registrado.';
        accentColor = TgdeskColors.seed;
        statusIcon = Icons.flag_outlined;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: TgdeskSpacing.md),
      padding: const EdgeInsets.all(TgdeskSpacing.md),
      decoration: BoxDecoration(
        color: aguardaEle
            ? TgdeskColors.online.withOpacity(.10)
            : TgdeskColors.suspended.withOpacity(.05),
        border: Border.all(
            color: aguardaEle
                ? TgdeskColors.online.withOpacity(.55)
                : TgdeskColors.seed.withOpacity(.3)),
        borderRadius: BorderRadius.circular(TgdeskSpacing.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(statusIcon, size: 20, color: accentColor),
          const SizedBox(width: TgdeskSpacing.sm),
          Expanded(
              child: Text(texto,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        if ((os['escopo']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: TgdeskSpacing.xs),
          Text('Serviço: ${os['escopo']}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TgdeskTextColors.body)),
        ],
        if ((os['instrucao']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: TgdeskSpacing.xs),
          Text(os['instrucao'].toString(),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TgdeskTextColors.body)),
        ],
        if (os['orcamento'] is Map) _orcamentoPanel(_map(os['orcamento'])),
        if (agendada.isNotEmpty) ...[
          const SizedBox(height: TgdeskSpacing.xs),
          Text('Agendado para ${_dataLegivel(agendada)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TgdeskTextColors.strong)),
        ],
        if (aguardaEle) ...[
          const SizedBox(height: TgdeskSpacing.sm),
          FilledButton.icon(
            onPressed: _confirmarEncerramento,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar encerramento'),
          ),
        ],
      ]),
    );
  }

  /// O orçamento como o cliente precisa vê-lo: o que foi feito e quanto custa.
  ///
  /// Só aparece depois de fechado — enquanto o técnico monta as linhas, o
  /// cliente não vê número nenhum. Valor em rascunho vira expectativa, e
  /// expectativa quebrada é pior do que silêncio.
  ///
  /// Cada linha traz rótulo, quantidade e total. Não traz o custo da peça:
  /// isso é conta de quem atende, não decisão de quem paga.
  Widget _orcamentoPanel(Map<String, dynamic> orcamento) {
    final itens = _list(orcamento['itens'])
        .map((item) => _map(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final total = (orcamento['total_cents'] as num?)?.toInt() ?? 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: TgdeskSpacing.sm),
      padding: const EdgeInsets.all(TgdeskSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(TgdeskSpacing.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Orçamento',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: TgdeskTextColors.strong)),
        const SizedBox(height: TgdeskSpacing.xs),
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(children: [
              Expanded(
                child: Text(
                  _quantidadeLegivel(item['quantity']) +
                      (item['label']?.toString() ?? ''),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: TgdeskTextColors.body),
                ),
              ),
              Text(moeda((item['total_cents'] as num?)?.toInt() ?? 0),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: TgdeskTextColors.body)),
            ]),
          ),
        const Divider(height: TgdeskSpacing.md),
        Row(children: [
          const Expanded(
              child:
                  Text('Total', style: TextStyle(fontWeight: FontWeight.w600))),
          Text(moeda(total),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      ]),
    );
  }

  /// "2× " para quantidades diferentes de um; vazio para uma unidade — dizer
  /// "1×" em toda linha só acrescenta ruído.
  String _quantidadeLegivel(dynamic raw) {
    final quantidade = (raw as num?)?.toDouble() ?? 1;
    if (quantidade == 1) return '';
    final inteiro = quantidade == quantidade.roundToDouble();
    return '${quantidade.toStringAsFixed(inteiro ? 0 : 2)}× ';
  }

  String _dataLegivel(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String dois(int v) => v.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)} às ${dois(d.hour)}:${dois(d.minute)}';
  }

  Widget _chatPanel() {
    final ticket = _openTicket!;
    final mensagens = _list(ticket['messages']);
    final pedidos = _list(ticket['remote_access_requests']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: TgdeskSpacing.lg),
      padding: const EdgeInsets.all(TgdeskSpacing.md),
      decoration: BoxDecoration(
        color: TgdeskColors.seed.withOpacity(.05),
        border: Border.all(color: TgdeskColors.seed.withOpacity(.3)),
        borderRadius: BorderRadius.circular(TgdeskSpacing.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.forum_outlined, color: TgdeskColors.seed, size: 20),
          const SizedBox(width: TgdeskSpacing.sm),
          Text('Conversa • ${ticket['protocol'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: TgdeskSpacing.sm),
        if (mensagens.isEmpty)
          Text('Assim que um técnico assumir, a conversa aparece aqui.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: TgdeskTextColors.body))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: mensagens.map((raw) {
                  final m = _map(raw);
                  final doCliente = m['from_client'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: TgdeskSpacing.xs),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              doCliente
                                  ? Icons.person_outline
                                  : Icons.support_agent_outlined,
                              size: 16,
                              color: TgdeskColors.seed),
                          const SizedBox(width: TgdeskSpacing.xs),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(doCliente ? 'Você' : 'Técnico',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: TgdeskColors.seed)),
                                  Text(m['message']?.toString() ?? '',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ]),
                          ),
                        ]),
                  );
                }).toList(),
              ),
            ),
          ),
        if (pedidos.isNotEmpty) ...[
          const SizedBox(height: TgdeskSpacing.sm),
          for (final pedido in pedidos) _remoteAccessRequest(pedido),
        ],
        const SizedBox(height: TgdeskSpacing.sm),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Escreva para o técnico (opcional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TgdeskSpacing.xs),
                      borderSide: BorderSide(
                          color: TgdeskColors.seed.withOpacity(.3)))),
              onSubmitted: (_) => _sendChat(),
            ),
          ),
          const SizedBox(width: TgdeskSpacing.sm),
          IconButton(onPressed: _sendChat, icon: const Icon(Icons.send)),
        ]),
      ]),
    );
  }

  Future<void> _sendChat() async {
    final texto = _chatController.text.trim();
    if (texto.isEmpty) return;
    _chatController.clear();
    await _refreshOpenTicket(send: texto);
  }

  // Instalar deixou de ser ação da tela: o servidor empurra a atualização
  // pelo canal do dispositivo, um de cada vez, e o agente aplica. O que a tela
  // faz é mostrar o andamento.
  TgdeskUpdateStatus? _updateStatus() {
    if (_status?['updating'] != true) return null;
    final progress = _map(_status!['update_progress']);
    return TgdeskUpdateStatus(
      updating: true,
      version: progress['version']?.toString() ?? '',
      totalBytes: (progress['total_bytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (progress['downloaded_bytes'] as num?)?.toInt() ?? 0,
      bytesPerSecond: (progress['bytes_per_second'] as num?)?.toInt() ?? 0,
      throttleKbps: (progress['throttle_kbps'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> _renameDevice(String name) async {
    final identity = await _deviceIdentity();
    await TgdeskApi.clientRenameDevice(
      deviceId: identity['device_id']?.toString() ??
          _status?['device_id']?.toString() ??
          '',
      deviceToken: identity['device_token']?.toString() ?? '',
      displayName: name,
    );
  }

  Future<void> _ensureTrayRunning() async {
    try {
      await Process.start(Platform.resolvedExecutable, const ['--tray'],
          mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  Future<void> _poll() async {
    try {
      final file = File(tgdeskStatusFilePath());
      if (!await file.exists()) {
        if (mounted) setState(() => _agentMissing = true);
        return;
      }
      final parsed =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final modified = await file.lastModified();
      final serverOnline = parsed['tunnel_up'] == true &&
          DateTime.now().difference(modified) < const Duration(seconds: 12);
      if (mounted) {
        if (!widget.embedded) {
          unawaited(applyClientBrandingWindowIcon(_map(parsed['branding'])));
        }
        setState(() {
          _status = parsed;
          _agentMissing = false;
          _serverOnline = serverOnline;
          _version = parsed['current_version']?.toString() ?? '';
        });
        unawaited(_maybeSelfBind(parsed));
      }
    } catch (_) {}
  }

  void _logSelfBind(String message) {
    try {
      final dir = Directory('${tgdeskDataHome()}${Platform.pathSeparator}logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File('${dir.path}${Platform.pathSeparator}ui.log').writeAsStringSync(
          '${DateTime.now().toIso8601String()} self-bind: $message\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  // Esta mesma máquina física já provou quem é através da credencial de
  // técnico (Admin/Tech), um vínculo bem mais forte que um código de
  // pareamento. Pedir aprovação manual de novo, agora na camada de
  // dispositivo, é só fricção redundante — então, quando a sessão logada é
  // supervisor/admin, resolve sozinho assim que aparece um código.
  Future<void> _maybeSelfBind(Map<String, dynamic> status) async {
    if (_selfBindAttempted) return;
    final state = status['state']?.toString() ?? '';
    if (state != 'guest') return;
    final code = status['pairing_code']?.toString() ?? '';
    if (code.isEmpty) {
      _logSelfBind('estado guest mas sem pairing_code no status local');
      return;
    }
    if (!AppState.isLoggedIn) {
      _logSelfBind('pulado: AppState.isLoggedIn=false (code=$code)');
      return;
    }
    if (!(AppState.isSupervisor || AppState.isSuperAdmin)) {
      _logSelfBind(
          'pulado: role=${AppState.role} não é supervisor/super_admin (code=$code)');
      return;
    }
    _selfBindAttempted = true;
    _logSelfBind('tentando vincular code=$code role=${AppState.role}');
    try {
      final result = await TgdeskApi.selfBindDevice(code);
      _logSelfBind('sucesso: $result');
    } catch (e) {
      _selfBindAttempted = false;
      _logSelfBind('falhou: $e — tentará de novo no próximo poll');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    TgdeskApi.onTicketThread = null;
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }
    return TgdeskWindowScaffold(
      title: _clientBrandTitle(),
      productName: _productName,
      deviceName: _status?['display_name']?.toString() ??
          _status?['hostname']?.toString() ??
          '',
      onRenameDevice: _renameDevice,
      updateStatus: _updateStatus(),
      actions: [
        if (_version.isNotEmpty)
          Center(
              child: Text('v$_version',
                  style: Theme.of(context).textTheme.labelSmall)),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_agentMissing || _status == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final state = _status!['state']?.toString() ?? '';
    if (state == 'guest') {
      return _buildEntryPending(_status!['pairing_code']?.toString() ?? '');
    }
    if (state != 'ativo') {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(state == 'suspenso' ? Icons.block : Icons.link, size: 42),
        const SizedBox(height: TgdeskSpacing.md),
        Text(state == 'suspenso'
            ? 'Contate a TG Devs para reativar o serviço'
            : 'Conectando ao TGDesk'),
      ]));
    }
    final hw = _map(_status!['hardware']);
    // A aba Cliente dentro de Tech/Admin é uma prévia fiel do que o cliente
    // enxerga. Diagnóstico técnico pertence ao dispositivo selecionado.
    return _buildClientReport(hw);
  }

  Future<Map<String, dynamic>> _deviceIdentity() async {
    final file = File(
        '${tgdeskDataHome()}${Platform.pathSeparator}identity${Platform.pathSeparator}device.json');
    if (!file.existsSync()) return const <String, dynamic>{};
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  // A bifurcação "empresa ou particular" saiu daqui: quem instalou já
  // respondeu isso no instalador, e o agente materializa a escolha assim que
  // houver conexão. O que resta é a espera — normalmente de segundos, e mais
  // longa só quando a máquina foi instalada sem rede.
  //
  // O código de pareamento continua visível porque ele é a saída manual: um
  // técnico ainda pode vincular este computador por código quando a intenção
  // gravada na instalação não puder ser aplicada.
  Widget _buildEntryPending(String code) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: TgdeskSpacing.lg),
          const Text('Conectando este computador ao TGDesk',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: TgdeskSpacing.sm),
          const Text(
              'Estamos aplicando a configuração escolhida na instalação.',
              style: TextStyle(color: TgdeskTextColors.body)),
          if (code.isNotEmpty) ...[
            const SizedBox(height: TgdeskSpacing.xl),
            const Text('Código deste computador',
                style: TextStyle(fontSize: 12, color: TgdeskTextColors.muted)),
            const SizedBox(height: TgdeskSpacing.xs),
            SelectableText(code,
                style: const TextStyle(fontSize: 20, letterSpacing: 3)),
          ],
        ]),
      );

  Widget _buildClientReport(Map<String, dynamic> hw) {
    final statistics = _map(_status!['statistics']);
    final health = _map(statistics['health']);
    // A gravidade vem do contrato, não de comparar texto aqui: era a terceira
    // cópia da mesma cadeia de ifs sobre 'client_level', e cópias de regra são
    // como as cores derivam.
    final severity = TgdeskClientUiPolicy.overallSeverity(health);
    final color = severity.color;
    final icon = switch (severity) {
      TgdeskSeverity.critical || TgdeskSeverity.maximum => Icons.error_outline,
      TgdeskSeverity.warning => Icons.warning_amber_rounded,
      TgdeskSeverity.normal => Icons.verified_outlined,
    };
    final healthMetrics = _map(health['metrics']);
    int metricLevel(String name) =>
        TgdeskClientUiPolicy.metricSeverity(health, name).rank;

    final disks = _list(hw['storage']);
    var storageUse = 0.0;
    var highestTemperature = 0.0;
    final temperatureLevel = metricLevel('temperature');
    for (final raw in disks) {
      final disk = _map(raw);
      storageUse = storageUse < _num(disk['used_pct'])
          ? _num(disk['used_pct'])
          : storageUse;
      highestTemperature = highestTemperature < _num(disk['temperature'])
          ? _num(disk['temperature'])
          : highestTemperature;
      for (final volumeRaw in _list(disk['volumes'])) {
        final volume = _map(volumeRaw);
        storageUse = storageUse < _num(volume['used_pct'])
            ? _num(volume['used_pct'])
            : storageUse;
      }
    }
    for (final raw in _list(hw['gpus'])) {
      final gpu = _map(raw);
      highestTemperature = highestTemperature < _num(gpu['temperature'])
          ? _num(gpu['temperature'])
          : highestTemperature;
    }
    // Status is authoritative from the server's rolling analysis. Current
    // readings remain display-only and never raise a client alert locally.
    final cpuLevel = metricLevel('processing');
    final memoryLevel = metricLevel('memory');
    final storageLevel = metricLevel('storage');
    final samples = (statistics['samples'] as num?)?.toInt() ?? 0;
    final processingState = cpuLevel == 3
        ? 'Uso no limite'
        : cpuLevel == 2
            ? 'Uso crítico'
            : cpuLevel == 1
                ? 'Uso elevado'
                : 'Desempenho estável';
    final memoryState = memoryLevel == 3
        ? 'Capacidade no limite'
        : memoryLevel == 2
            ? 'Uso crítico'
            : memoryLevel == 1
                ? 'Uso elevado'
                : 'Uso adequado';
    final storageState = disks.isEmpty
        ? 'Análise em andamento'
        : storageLevel == 3
            ? 'Espaço no limite'
            : storageLevel == 2
                ? 'Espaço crítico'
                : storageLevel == 1
                    ? 'Espaço reduzido'
                    : 'Espaço disponível';
    final temperatureState = highestTemperature == 0
        ? 'Sensores acompanhados'
        : temperatureLevel >= 2
            ? 'Temperatura crítica'
            : temperatureLevel == 1
                ? 'Temperatura elevada'
                : 'Dentro do esperado';
    return Container(
      color: TgdeskSurfaces.background,
      child: LayoutBuilder(
        builder: (context, viewport) => Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 960,
                height: 520,
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                          color: color.withOpacity(.12),
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, size: 36, color: color),
                    ),
                    const SizedBox(width: TgdeskSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TgdeskHealthText.clientTitle(
                                health['client_level']?.toString()),
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: TgdeskSpacing.xs),
                          Text(
                            _brandText(TgdeskHealthText.clientSummary(
                                health['client_level']?.toString())),
                            style: const TextStyle(
                                fontSize: 15, color: TgdeskTextColors.support),
                          ),
                        ],
                      ),
                    ),
                    _clientConnectionBadge(),
                  ]),
                  const SizedBox(height: TgdeskSpacing.xl),
                  // Os textos vêm do servidor, que é quem tem o histórico e
                  // sabe há quanto tempo a condição dura e para onde caminha.
                  // A tela só escolhe ícone e cor.
                  Row(children: [
                    Expanded(
                        child: _serverCard(
                            healthMetrics,
                            'processing',
                            'Experiência de uso',
                            Icons.speed_outlined,
                            processingState,
                            cpuLevel)),
                    const SizedBox(width: TgdeskSpacing.md),
                    Expanded(
                        child: _serverCard(
                            healthMetrics,
                            'memory',
                            'Memória',
                            Icons.view_module_outlined,
                            memoryState,
                            memoryLevel)),
                  ]),
                  const SizedBox(height: TgdeskSpacing.md),
                  Row(children: [
                    Expanded(
                        child: _serverCard(
                            healthMetrics,
                            'storage',
                            'Armazenamento',
                            Icons.storage_outlined,
                            storageState,
                            storageLevel)),
                    const SizedBox(width: TgdeskSpacing.md),
                    Expanded(
                        child: _clientInsightCard(
                            'Temperatura e estabilidade',
                            temperatureState,
                            temperatureLevel == 0
                                ? 'O $_productName acompanha os sensores disponíveis.'
                                : 'Uma alteração de temperatura foi identificada.',
                            Icons.thermostat_outlined,
                            _indicatorColor(temperatureLevel))),
                  ]),
                  const SizedBox(height: TgdeskSpacing.md),
                  _panel(
                    child: Row(children: [
                      const Icon(Icons.auto_graph_outlined,
                          color: TgdeskTextColors.accent, size: 30),
                      const SizedBox(width: TgdeskSpacing.md),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Acompanhamento contínuo',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: TgdeskSpacing.xs),
                              Text(
                                  samples == 0
                                      ? 'O histórico deste computador está sendo iniciado.'
                                      : '$samples verificações já fazem parte da análise deste computador.',
                                  style: const TextStyle(
                                      color: TgdeskTextColors.body)),
                            ]),
                      ),
                      Text(_collectedLabel(),
                          style:
                              const TextStyle(color: TgdeskTextColors.muted)),
                    ]),
                  ),
                  const SizedBox(height: TgdeskSpacing.md),
                  _supportPanel(color),
                  if (AppState.isSupervisor || AppState.isSuperAdmin)
                    _supervisorInvitePanel(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // O botão de chamado é regra de PAPEL, não de alvo: quem está logado como
  // técnico, supervisor ou admin não pede atendimento por esta tela, mesmo
  // vendo-a embutida no próprio shell. Ver MODELO-PRODUTO.md, "Exceções".
  bool get _canRequestSupport => !AppState.isLoggedIn;

  Widget _supportPanel(Color color) {
    if (!_canRequestSupport) return const SizedBox.shrink();
    final open = _openTicket;
    final hasOpen = open != null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _supportHeader(color, open, hasOpen),
      if (hasOpen && open['service_order'] is Map)
        _servicePanel(_map(open['service_order'])),
      if (hasOpen) _chatPanel(),
    ]);
  }

  Widget _supportHeader(Color color, Map<String, dynamic>? open, bool hasOpen) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.32)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.support_agent_outlined, color: color),
        const SizedBox(width: TgdeskSpacing.md),
        Text('Suporte $_productName',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: TgdeskSpacing.md),
        Expanded(
            child: Text(
                hasOpen
                    ? 'Seu pedido ${open?['protocol'] ?? ''} está aberto. Um técnico vai assumir e falar com você.'
                    : 'Precisa de ajuda? Peça atendimento — o $_productName envia sozinho o diagnóstico deste computador.',
                style: const TextStyle(color: TgdeskTextColors.strong))),
        if (!hasOpen)
          FilledButton.icon(
            onPressed: _openingTicket ? null : _requestSupport,
            icon: _openingTicket
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.support_agent_outlined),
            label: Text(_openingTicket ? 'Enviando…' : 'Pedir ajuda'),
          ),
      ]),
    );
  }

  // Pedir ajuda não faz pergunta nenhuma ao cliente: ele não sabe além do que
  // o próprio TGDesk diagnosticou, então quem redige o chamado é o servidor, a
  // partir do histórico de saúde do dispositivo.
  Future<void> _requestSupport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pedir ajuda ao seu técnico?'),
        content: const Text(
            'O TGDesk vai enviar o diagnóstico deste computador junto com o pedido. '
            'Você não precisa preencher nada.\n\n'
            'Nenhum acesso ao seu computador acontece sem que o chamado seja aceito.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Agora não')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Pedir ajuda')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _openingTicket = true);
    try {
      final identity = await _deviceIdentity();
      final result = await TgdeskApi.createClientSupportTicket(
        deviceId: identity['device_id']?.toString() ??
            _status?['device_id']?.toString() ??
            '',
        deviceToken: identity['device_token']?.toString() ?? '',
      );
      if (mounted) {
        setState(() => _openTicket = result);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['already_open'] == true
                ? 'Você já tem o pedido ${result['protocol'] ?? ''} em aberto.'
                : 'Pedido ${result['protocol'] ?? ''} enviado. Aguarde o contato do técnico.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _openingTicket = false);
    }
  }

  Color _indicatorColor(int level) {
    return TgdeskSeverityColors.of(level);
  }

  // Card cujo conteúdo vem da análise do servidor. Mantém os textos locais
  // como fallback: servidor antigo, ou dispositivo ainda sem histórico
  // suficiente, não pode deixar o card vazio.
  Widget _serverCard(Map<String, dynamic> healthMetrics, String categoria,
      String tituloPadrao, IconData icon, String estadoPadrao, int nivel) {
    final m = _map(healthMetrics[categoria]);
    // Título, estado e narrativa são desta camada. Do servidor vem o que
    // só ele sabe: nível, desde quando a condição dura e para onde caminha.
    final detalhe = TgdeskHealthText.cardNarrative(m, categoria);
    return _clientInsightCard(tituloPadrao, estadoPadrao, _brandText(detalhe),
        icon, _indicatorColor(nivel));
  }

  Widget _clientInsightCard(String title, String state, String detail,
          IconData icon, Color color) =>
      Container(
        height: 132,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: TgdeskSurfaces.panel,
          border: Border.all(color: color.withOpacity(.42)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color.withOpacity(.11),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color)),
          const SizedBox(width: TgdeskSpacing.md),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: TgdeskTextColors.muted, fontSize: 12)),
                const SizedBox(height: TgdeskSpacing.xs),
                Text(state,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: TgdeskSpacing.xs),
                Text(detail,
                    maxLines: 2,
                    style: const TextStyle(
                        color: TgdeskTextColors.body, fontSize: 12)),
              ])),
        ]),
      );

  Widget _clientConnectionBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: TgdeskSurfaces.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: TgdeskSurfaces.borderStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle,
              size: 9,
              color: _serverOnline ? TgdeskSeverityColors.ok : Colors.orange),
          const SizedBox(width: TgdeskSpacing.sm),
          Text(_serverOnline ? 'Proteção ativa' : 'Reconectando'),
        ]),
      );

  Widget _panel({required Widget child}) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: TgdeskSurfaces.panelAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgdeskSurfaces.border)),
      child: child);

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<dynamic> _list(dynamic v) => v is List ? v : const [];
  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _collectedLabel() {
    final raw = _status!['collected_at']?.toString() ?? '';
    final at = DateTime.tryParse(raw);
    if (at == null) return 'Aguardando telemetria';
    final age = DateTime.now().toUtc().difference(at).inSeconds;
    return age < 60 ? 'Atualizado agora' : 'Atualizado há ${age ~/ 60} min';
  }
}
