import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'agent_deploy.dart';
import 'api_client.dart';
import 'branding_window_icon.dart';
import 'health_text.dart';
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
    final name = branding['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'TGDesk' : name;
  }

  String _brandText(String value) => value.replaceAll('TGDesk', _productName);

  Widget _clientBrandTitle() {
    final encoded = _branding['logo_base64']?.toString() ?? '';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (encoded.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Image.memory(base64Decode(encoded),
              height: 25, width: 72, fit: BoxFit.contain),
        ),
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
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xffffb020).withOpacity(.10),
          border: Border.all(color: const Color(0xffffb020).withOpacity(.55)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.lock_open_outlined,
                color: Color(0xffffb020), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '${pedido['requested_by'] ?? 'O técnico'} pediu para acessar seu computador',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          if ((pedido['motivo']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Motivo: ${pedido['motivo']}',
                style: const TextStyle(color: Color(0xffb7c2d1), fontSize: 13)),
          ],
          const SizedBox(height: 6),
          const Text(
              'Se você recusar, o técnico continua podendo fazer testes, mas não controla a máquina.',
              style: TextStyle(color: Color(0xff9eacbf), fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton(
                onPressed: () =>
                    _answerRemoteAccess(pedido['id'].toString(), true),
                child: const Text('Autorizar')),
            const SizedBox(width: 10),
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
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xff111d29),
          border: Border.all(color: const Color(0xff25384b)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.group_add_outlined, color: Color(0xff8db8ee)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
                'Recebeu um código para supervisionar outra organização? '
                'Resgate aqui para passar a ver os chamados dela.',
                style: TextStyle(color: Color(0xffb7c2d1), fontSize: 13)),
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
    switch (status) {
      case 'offered':
        texto = 'Procurando um técnico disponível para o seu atendimento.';
        break;
      case 'assigned':
        texto = agendada.isEmpty
            ? 'Um técnico assumiu o atendimento.'
            : 'Atendimento agendado. Um técnico já está designado.';
        break;
      case 'in_progress':
        texto = 'O técnico está trabalhando no seu atendimento agora.';
        break;
      case 'awaiting_confirmation':
        texto = aguardaEle
            ? 'O técnico concluiu. Confirme para encerrar o atendimento.'
            : 'Concluído. Aguardando a confirmação dos responsáveis.';
        break;
      case 'completed':
        texto = 'Atendimento concluído.';
        break;
      default:
        texto = 'Seu pedido foi registrado.';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: aguardaEle
            ? const Color(0xff45c95a).withOpacity(.10)
            : const Color(0xff0b1520),
        border: Border.all(
            color: aguardaEle
                ? const Color(0xff45c95a).withOpacity(.55)
                : const Color(0xff25384b)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(aguardaEle ? Icons.task_alt : Icons.engineering_outlined,
              size: 20,
              color: aguardaEle
                  ? const Color(0xff45c95a)
                  : const Color(0xff8db8ee)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        if ((os['escopo']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Serviço: ${os['escopo']}',
              style: const TextStyle(color: Color(0xff9eacbf), fontSize: 12)),
        ],
        if (agendada.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Agendado para ${_dataLegivel(agendada)}',
              style: const TextStyle(color: Color(0xffb7c2d1), fontSize: 12)),
        ],
        if (aguardaEle) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _confirmarEncerramento,
            icon: const Icon(Icons.check),
            label: const Text('Confirmar encerramento'),
          ),
        ],
      ]),
    );
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
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xff111d29),
        border: Border.all(color: const Color(0xff25384b)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.forum_outlined, color: Color(0xff8db8ee), size: 20),
          const SizedBox(width: 8),
          Text('Conversa • ${ticket['protocol'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        if (mensagens.isEmpty)
          const Text('Assim que um técnico assumir, a conversa aparece aqui.',
              style: TextStyle(color: Color(0xff9eacbf), fontSize: 13))
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
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      '${doCliente ? "Você" : (m['author']?.toString().isNotEmpty == true ? m['author'] : "Técnico")}: ${m['message'] ?? ''}',
                      style: TextStyle(
                          fontSize: 13,
                          color: doCliente
                              ? const Color(0xff9eacbf)
                              : Colors.white),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ...pedidos.map((p) => _remoteAccessRequest(_map(p))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Escreva para o técnico (opcional)',
              ),
              onSubmitted: (_) => _sendChat(),
            ),
          ),
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
      final dir = Directory(
          '${tgdeskDataHome()}${Platform.pathSeparator}logs');
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
        const SizedBox(height: 12),
        Text(state == 'suspenso'
            ? 'Contate a TG Devs para reativar o serviço'
            : 'Conectando ao TGDesk'),
      ]));
    }
    final hw = _map(_status!['hardware']);
    // A aba Cliente dentro de Tech/Admin é uma prévia fiel do que o cliente
    // enxerga. Diagnóstico técnico pertence ao dispositivo selecionado.
    return _buildClientReport(hw);
    /*
    return Container(
      color: const Color(0xff07101b),
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          sliver: SliverList.list(children: [
            _header(),
            const SizedBox(height: 18),
            _processorCard('CPU', Icons.memory, const Color(0xff2787ff),
                _map(hw['cpu']), false),
            ..._list(hw['gpus']).map((g) => Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _processorCard('GPU', Icons.developer_board,
                      const Color(0xff66d83e), _map(g), true),
                )),
            const SizedBox(height: 14),
            _memorySection(hw),
            const SizedBox(height: 14),
            _storageSection(_list(hw['storage'])),
            const SizedBox(height: 14),
            _networkSection(_list(hw['networks'])),
          ]),
        ),
      ]),
    );
    */
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
          const SizedBox(height: 18),
          const Text('Conectando este computador ao TGDesk',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          const Text('Estamos aplicando a configuração escolhida na instalação.',
              style: TextStyle(color: Color(0xff9eacbf))),
          if (code.isNotEmpty) ...[
            const SizedBox(height: 26),
            const Text('Código deste computador',
                style: TextStyle(fontSize: 12, color: Color(0xff75849a))),
            const SizedBox(height: 6),
            SelectableText(code,
                style: const TextStyle(fontSize: 20, letterSpacing: 3)),
          ],
        ]),
      );

  Widget _buildClientReport(Map<String, dynamic> hw) {
    final statistics = _map(_status!['statistics']);
    final health = _map(statistics['health']);
    final level = health['client_level']?.toString() ?? 'normal';
    final color = level == 'critical' || level == 'maximum'
        ? const Color(0xffff5252)
        : level == 'warning'
            ? const Color(0xffffb020)
            : const Color(0xff45c95a);
    final icon = level == 'critical' || level == 'maximum'
        ? Icons.error_outline
        : level == 'warning'
            ? Icons.warning_amber_rounded
            : Icons.verified_outlined;
    final healthMetrics = _map(health['metrics']);
    int metricLevel(String name) {
      final value = _map(healthMetrics[name])['level']?.toString() ?? 'normal';
      if (value == 'maximum') return 3;
      if (value == 'critical') return 2;
      if (value == 'warning') return 1;
      return 0;
    }

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
      color: const Color(0xff07101b),
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
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            TgdeskHealthText.clientTitle(health['client_level']?.toString()),
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _brandText(TgdeskHealthText.clientSummary(health['client_level']?.toString())),
                            style: const TextStyle(
                                fontSize: 15, color: Color(0xffa9b5c6)),
                          ),
                        ],
                      ),
                    ),
                    _clientConnectionBadge(),
                  ]),
                  const SizedBox(height: 22),
                  // Os textos vêm do servidor, que é quem tem o histórico e
                  // sabe há quanto tempo a condição dura e para onde caminha.
                  // A tela só escolhe ícone e cor.
                  Row(children: [
                    Expanded(
                        child: _serverCard(healthMetrics, 'processing',
                            'Experiência de uso', Icons.speed_outlined,
                            processingState, cpuLevel)),
                    const SizedBox(width: 14),
                    Expanded(
                        child: _serverCard(healthMetrics, 'memory', 'Memória',
                            Icons.view_module_outlined, memoryState,
                            memoryLevel)),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: _serverCard(healthMetrics, 'storage',
                            'Armazenamento', Icons.storage_outlined,
                            storageState, storageLevel)),
                    const SizedBox(width: 14),
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
                  const SizedBox(height: 14),
                  _panel(
                    child: Row(children: [
                      const Icon(Icons.auto_graph_outlined,
                          color: Color(0xff8db8ee), size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Acompanhamento contínuo',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                  samples == 0
                                      ? 'O histórico deste computador está sendo iniciado.'
                                      : '$samples verificações já fazem parte da análise deste computador.',
                                  style: const TextStyle(
                                      color: Color(0xff9eacbf))),
                            ]),
                      ),
                      Text(_collectedLabel(),
                          style: const TextStyle(color: Color(0xff75849a))),
                    ]),
                  ),
                  const SizedBox(height: 14),
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
        const SizedBox(width: 12),
        Text('Suporte $_productName',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                hasOpen
                    ? 'Seu pedido ${open?['protocol'] ?? ''} está aberto. Um técnico vai assumir e falar com você.'
                    : 'Precisa de ajuda? Peça atendimento — o $_productName envia sozinho o diagnóstico deste computador.',
                style: const TextStyle(color: Color(0xffb7c2d1)))),
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
    if (level >= 2) return const Color(0xffff5252);
    if (level == 1) return const Color(0xffffb020);
    return const Color(0xff45c95a);
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
    return _clientInsightCard(tituloPadrao, estadoPadrao,
        _brandText(detalhe), icon, _indicatorColor(nivel));
  }

  Widget _clientInsightCard(String title, String state, String detail,
          IconData icon, Color color) =>
      Container(
        height: 132,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: const Color(0xff111d29),
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
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xff91a0b5), fontSize: 12)),
                const SizedBox(height: 4),
                Text(state,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(detail,
                    maxLines: 2,
                    style: const TextStyle(
                        color: Color(0xff9eacbf), fontSize: 12)),
              ])),
        ]),
      );

  Widget _clientConnectionBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xff111d29),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xff25384b)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle,
              size: 9,
              color: _serverOnline ? const Color(0xff45c95a) : Colors.orange),
          const SizedBox(width: 7),
          Text(_serverOnline ? 'Proteção ativa' : 'Reconectando'),
        ]),
      );

  // Mantido durante a transição para comparação visual.
  // ignore: unused_element
  Widget _buildClientSummary(Map<String, dynamic> hw) {
    final statistics = _map(_status!['statistics']);
    final health = _map(statistics['health']);
    final level = health['client_level']?.toString() ?? 'normal';
    final color = level == 'critical'
        ? const Color(0xffff5252)
        : level == 'warning'
            ? const Color(0xffffb020)
            : const Color(0xff45c95a);
    final icon = level == 'critical'
        ? Icons.error_outline
        : level == 'warning'
            ? Icons.warning_amber_rounded
            : Icons.verified_outlined;
    final disks = _list(hw['storage']);
    return Container(
      color: const Color(0xff07101b),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 70, color: color),
              const SizedBox(height: 18),
              Text(
                TgdeskHealthText.clientTitle(health['client_level']?.toString()),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                TgdeskHealthText.clientSummary(health['client_level']?.toString()),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Color(0xffa9b5c6)),
              ),
              const SizedBox(height: 28),
              _panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.desktop_windows_outlined,
                            color: Color(0xff2787ff)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              _status!['hostname']?.toString() ??
                                  'Este computador',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.circle,
                            size: 10,
                            color: _serverOnline
                                ? const Color(0xff45c95a)
                                : Colors.orange),
                        const SizedBox(width: 7),
                        Text(_serverOnline
                            ? 'Protegido pelo TGDesk'
                            : 'Reconectando')
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                            child: _clientMetric(
                                'Processamento', 'Monitorado', Icons.memory)),
                        Expanded(
                            child: _clientMetric('Memória', 'Monitorado',
                                Icons.view_module_outlined)),
                        Expanded(
                            child: _clientMetric(
                                'Armazenamento',
                                disks.isEmpty ? 'Analisando' : 'Monitorado',
                                Icons.storage_outlined)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(_collectedLabel(),
                  style: const TextStyle(color: Color(0xff75849a))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clientMetric(String label, String value, IconData icon) => Column(
        children: [
          Icon(icon, color: const Color(0xff88a8d5), size: 28),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xff9aa8ba))),
        ],
      );

  // Mantido temporariamente para a futura tela técnica dedicada.
  // ignore: unused_element
  Widget _header() {
    final online = _serverOnline;
    return Row(children: [
      const Icon(Icons.desktop_windows_outlined,
          color: Color(0xff2787ff), size: 38),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_status!['hostname']?.toString() ?? '',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text('IP: ${_status!['virtual_ip'] ?? "—"}',
            style: const TextStyle(color: Color(0xff91a0b5))),
      ]),
      const SizedBox(width: 18),
      Icon(Icons.circle,
          size: 10, color: online ? const Color(0xff45c95a) : Colors.orange),
      const SizedBox(width: 7),
      Text(online ? 'Conectado via VPN' : 'Reconectando',
          style: TextStyle(
              color: online ? const Color(0xff45c95a) : Colors.orange)),
      const Spacer(),
      _chip(Icons.schedule, _collectedLabel()),
    ]);
  }

  // ignore: unused_element
  Widget _processorCard(String title, IconData icon, Color color,
      Map<String, dynamic> current, bool gpu) {
    final id = current['id']?.toString() ?? '';
    final stats = _map(_status!['statistics']);
    final stat = gpu
        ? <String, dynamic>{
            'usage': _map(_map(stats['gpu_usage'])[id]),
            'clock_mhz': _map(_map(stats['gpu_clock_mhz'])[id])
          }
        : _map(stats['cpu']);
    final usage = _num(current['usage']);
    final usageStats = _map(stat['usage']);
    final clockStats = _map(stat['clock_mhz']);
    return _panel(
      child: Row(children: [
        SizedBox(
            width: 245,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: color, size: 34),
                const SizedBox(width: 14),
                Text(title, style: const TextStyle(fontSize: 20))
              ]),
              const SizedBox(height: 5),
              Text(current['name']?.toString() ?? 'Não identificado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xffa9b5c6))),
            ])),
        _gauge(usage, color, available: current['usage'] is num),
        const SizedBox(width: 28),
        Expanded(
            child: Wrap(runSpacing: 16, spacing: 28, children: [
          _metric('Pico de uso', _pct(_num(usageStats['peak'])),
              Icons.show_chart, color),
          _metric('Média de uso', _pct(_num(usageStats['average'])),
              Icons.multiline_chart, color),
          _metric('Temperatura', _temp(_num(current['temperature'])),
              Icons.thermostat, color),
          _metric('Clock atual', _clock(_num(current['clock_mhz'])),
              Icons.speed, color),
          _metric('Clock médio', _clock(_num(clockStats['average'])),
              Icons.query_stats, color),
          _metric('Clock pico', _clock(_num(clockStats['peak'])), Icons.bolt,
              color),
          if (!gpu) ...[
            _metric('Desempenho', _optionalPct(current['performance_percent']),
                Icons.speed, color),
            _metric('Fila da CPU', _optionalNumber(current['queue_length']),
                Icons.format_list_numbered, color),
            _metric('DPC', _optionalPct(current['dpc_time_percent']),
                Icons.settings_input_component, color),
          ] else ...[
            _metric(
                'Memória dedicada',
                _optionalBytes(current['dedicated_memory_bytes']),
                Icons.memory_outlined,
                color),
            _metric(
                'Memória compartilhada',
                _optionalBytes(current['shared_memory_bytes']),
                Icons.share_outlined,
                color),
          ],
        ])),
      ]),
    );
  }

  // ignore: unused_element
  Widget _memorySection(Map<String, dynamic> hw) {
    final memory = _list(hw['memory']);
    final summary = _map(hw['memory_summary']);
    final stats = _map(_map(_status!['statistics'])['memory_used_bytes']);
    final systemStats = _map(stats['system']);
    final cards = <Widget>[
      _smallCard(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Uso total do sistema',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          LinearProgressIndicator(
              value: (_num(summary['usage']) / 100).clamp(0, 1),
              color: const Color(0xffa451f2)),
          const SizedBox(height: 9),
          Text(
              '${_bytes(_num(summary['used_bytes']))} de ${_bytes(_num(summary['total_bytes']))}'),
          Text('Média: ${_bytes(_num(systemStats['average']))}',
              style: const TextStyle(color: Color(0xff9aa8ba), fontSize: 12)),
          Text('Pico: ${_bytes(_num(systemStats['peak']))}',
              style: const TextStyle(color: Color(0xff9aa8ba), fontSize: 12)),
        ],
      ))
    ];
    cards.addAll(memory.map((raw) {
      final m = _map(raw);
      return _smallCard(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m['slot']?.toString() ?? 'Slot',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_bytes(_num(m['total_bytes'])),
            style: const TextStyle(fontSize: 20)),
        Text('${m['type'] ?? "DDR"} • ${m['speed_mhz'] ?? 0} MHz',
            style: const TextStyle(color: Color(0xff9aa8ba), fontSize: 12)),
        Text(m['manufacturer']?.toString() ?? '',
            style: const TextStyle(color: Color(0xff75849a), fontSize: 11)),
      ]));
    }));
    return _section(Icons.view_module_outlined, 'Memória RAM',
        const Color(0xffa451f2), cards);
  }

  // ignore: unused_element
  Widget _storageSection(List<dynamic> disks) => _section(
      Icons.storage_outlined,
      'Armazenamento',
      const Color(0xffff9914),
      disks.isEmpty
          ? [const Text('Nenhum disco físico identificado')]
          : disks.map((raw) {
              final d = _map(raw),
                  health = d['smart_status']?.toString() ?? 'Desconhecido';
              final healthy = health.toLowerCase() == 'healthy';
              return _smallCard(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(d['model']?.toString() ?? 'Disco',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      _tag(
                          '${d['bus_type'] ?? ""} ${d['media_type'] ?? ""}'
                              .trim(),
                          const Color(0xff1a7434))
                    ]),
                    Text(_bytes(_num(d['total_bytes'])),
                        style: const TextStyle(color: Color(0xff9aa8ba))),
                    const SizedBox(height: 12),
                    Row(children: [
                      _gauge(_num(d['used_pct']), const Color(0xffff9914),
                          compact: true),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Usado: ${_bytes(_num(d['used_bytes']))}'),
                            Text('SMART: $health',
                                style: TextStyle(
                                    color: healthy
                                        ? const Color(0xff45c95a)
                                        : Colors.orange)),
                            Text(
                                'Vida útil: ${_num(d['life_pct']) > 0 ? "${_num(d['life_pct']).toStringAsFixed(0)}%" : "não informada"}'),
                          ])),
                    ]),
                  ]));
            }).toList());

  // ignore: unused_element
  Widget _networkSection(List<dynamic> networks) {
    final stats = _map(_map(_status!['statistics'])['networks']);
    return _section(
        Icons.lan_outlined,
        'Rede',
        const Color(0xff2cc7e9),
        networks.isEmpty
            ? [const Text('Nenhum adaptador físico identificado')]
            : networks.map((raw) {
                final n = _map(raw),
                    st = _map(stats[n['id']?.toString() ?? '']);
                final up = n['status']?.toString().toLowerCase() == 'up';
                return _smallCard(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(n['name']?.toString() ?? 'Adaptador',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        Icon(
                            up
                                ? Icons.wifi_tethering
                                : Icons.signal_wifi_connected_no_internet_4,
                            color: up ? const Color(0xff45c95a) : Colors.orange)
                      ]),
                      Text(n['description']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xff9aa8ba), fontSize: 12)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 20, runSpacing: 8, children: [
                        _tinyMetric(
                            'Link', _bitSpeed(_num(n['link_speed_bps']))),
                        _tinyMetric('Máxima', _speed(_num(st['max_bps']))),
                        _tinyMetric('Mínima', _speed(_num(st['min_bps']))),
                        _tinyMetric('Média', _speed(_num(st['average_bps']))),
                      ]),
                      const SizedBox(height: 9),
                      Text(
                          up
                              ? 'Status estável'
                              : 'Rede caiu${st['last_down_at'] == null ? "" : " em ${st['last_down_at']}"}',
                          style: TextStyle(
                              color: up
                                  ? const Color(0xff45c95a)
                                  : Colors.orange)),
                      if (_num(st['downtime_seconds']) > 0)
                        Text(
                            'Tempo total indisponível: ${_duration(_num(st['downtime_seconds']).round())}',
                            style: const TextStyle(
                                color: Color(0xff9aa8ba), fontSize: 12)),
                    ]));
              }).toList());
  }

  Widget _section(
          IconData icon, String title, Color color, List<Widget> cards) =>
      _panel(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 245,
            child: Row(children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(width: 14),
              Text(title, style: const TextStyle(fontSize: 19))
            ])),
        Expanded(child: Wrap(spacing: 12, runSpacing: 12, children: cards)),
      ]));

  Widget _panel({required Widget child}) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xff111c28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xff263444))),
      child: child);

  Widget _smallCard(Widget child) => Container(
      width: 285,
      constraints: const BoxConstraints(minHeight: 142),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xff0b1520),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xff263444))),
      child: child);

  Widget _gauge(double value, Color color,
      {bool compact = false, bool available = true}) {
    final size = compact ? 74.0 : 112.0;
    return SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                  value: (value / 100).clamp(0, 1),
                  strokeWidth: compact ? 5 : 7,
                  backgroundColor: const Color(0xff293541),
                  color: color)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(available ? '${value.toStringAsFixed(0)}%' : 'N/D',
                style: TextStyle(fontSize: compact ? 17 : 25)),
            if (!compact)
              const Text('Uso atual',
                  style: TextStyle(fontSize: 11, color: Color(0xff9aa8ba)))
          ]),
        ]));
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      SizedBox(
          width: 145,
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xff9aa8ba))),
              Text(value, style: const TextStyle(fontSize: 18))
            ]),
          ]));
  Widget _tinyMetric(String label, String value) => SizedBox(
      width: 105,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xff9aa8ba))),
        Text(value)
      ]));
  Widget _chip(IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xff111c28),
          borderRadius: BorderRadius.circular(9)),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xff88a8d5)),
        const SizedBox(width: 7),
        Text(text)
      ]));
  Widget _tag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(.35),
          borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: const TextStyle(fontSize: 10)));

  Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<dynamic> _list(dynamic v) => v is List ? v : const [];
  double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _pct(double v) => '${v.toStringAsFixed(0)}%';
  String _optionalPct(dynamic v) =>
      v is num ? '${v.toDouble().toStringAsFixed(0)}%' : 'N/D';
  String _optionalNumber(dynamic v) =>
      v is num ? v.toDouble().toStringAsFixed(1) : 'N/D';
  String _optionalBytes(dynamic v) => v is num ? _bytes(v.toDouble()) : 'N/D';
  String _temp(double v) => v > 0 ? '${v.toStringAsFixed(0)}°C' : 'N/D';
  String _clock(double mhz) => mhz <= 0
      ? 'N/D'
      : mhz >= 1000
          ? '${(mhz / 1000).toStringAsFixed(2)} GHz'
          : '${mhz.toStringAsFixed(0)} MHz';
  String _bytes(double b) {
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = b, i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i < 3 ? 0 : 1)} ${u[i]}';
  }

  String _speed(double bps) {
    if (bps <= 0) return '0 bps';
    final bits = bps * 8;
    if (bits >= 1e9) return '${(bits / 1e9).toStringAsFixed(1)} Gbps';
    if (bits >= 1e6) return '${(bits / 1e6).toStringAsFixed(0)} Mbps';
    return '${(bits / 1e3).toStringAsFixed(0)} Kbps';
  }

  String _bitSpeed(double bps) {
    if (bps <= 0) return '0 bps';
    if (bps >= 1e9) return '${(bps / 1e9).toStringAsFixed(1)} Gbps';
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(0)} Mbps';
    return '${(bps / 1e3).toStringAsFixed(0)} Kbps';
  }

  String _duration(int s) {
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    return d > 0
        ? '${d}d ${h}h'
        : h > 0
            ? '${h}h ${m}min'
            : '${m}min';
  }

  String _collectedLabel() {
    final raw = _status!['collected_at']?.toString() ?? '';
    final at = DateTime.tryParse(raw);
    if (at == null) return 'Aguardando telemetria';
    final age = DateTime.now().toUtc().difference(at).inSeconds;
    return age < 60 ? 'Atualizado agora' : 'Atualizado há ${age ~/ 60} min';
  }
}
