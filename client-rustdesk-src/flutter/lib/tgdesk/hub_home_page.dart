import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../models/state_model.dart';
import 'package:get/get.dart';
import 'api_client.dart';
import 'branding_window_icon.dart';
import 'devices_page.dart';
import 'admin_page.dart';
import 'window_frame.dart';
import 'client_home_page.dart';
import 'agent_deploy.dart';
import 'branding_page.dart';
import 'control_channel.dart';
import 'remote_session_page.dart';
import 'support_page.dart';

class HubHomePage extends StatefulWidget {
  const HubHomePage({super.key});
  @override
  State<HubHomePage> createState() => _HubHomePageState();
}

class _HubHomePageState extends State<HubHomePage> {
  final _control = TgdeskControlChannel.instance;
  int _index = 0;
  String _version = '';
  TgdeskUpdateStatus? _updateStatus;
  Map<String, dynamic> _branding = {};

  String get _productName {
    if (_branding['enabled'] != true) return 'TGDesk';
    final name =
        (_branding['application_name']?.toString().trim().isNotEmpty ?? false)
            ? _branding['application_name']?.toString().trim() ?? ''
            : _branding['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'TGDesk' : name;
  }

  Widget? _brandTitle() {
    if (_branding['enabled'] != true) return null;
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

  static String _text(dynamic map, String key) =>
      map is Map ? (map[key]?.toString() ?? '') : '';
  static int _int(dynamic map, String key) =>
      map is Map ? ((map[key] as num?)?.toInt() ?? 0) : 0;
  bool _brandingEnabled = false;

  TgdeskUpdateStatus? _parseUpdateStatus(Map<String, dynamic> status) {
    if (status['updating'] != true) return null;
    final progress = status['update_progress'];
    return TgdeskUpdateStatus(
      updating: true,
      version: _text(progress, 'version'),
      totalBytes: _int(progress, 'total_bytes'),
      downloadedBytes: _int(progress, 'downloaded_bytes'),
      bytesPerSecond: _int(progress, 'bytes_per_second'),
      throttleKbps: _int(progress, 'throttle_kbps'),
    );
  }

  bool _sameUpdateStatus(TgdeskUpdateStatus? a, TgdeskUpdateStatus? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    return a.updating == b.updating &&
        a.version == b.version &&
        a.totalBytes == b.totalBytes &&
        a.downloadedBytes == b.downloadedBytes &&
        a.bytesPerSecond == b.bytesPerSecond &&
        a.throttleKbps == b.throttleKbps;
  }

  @override
  void initState() {
    super.initState();
    _control.addListener(_onControl);
    TgdeskApi.addDeviceEventListener(_onDeviceEvent);
    _readUpdateState();
    _readBrandingAccess();
  }

  // O ouvinte que trocava _index para o destino "Acesso remoto" saiu junto com
  // o destino. A troca de tela agora é do AnimatedBuilder no corpo, que
  // desenha a sessão à frente quando existe uma — e o índice contado à mão a
  // partir de quais destinos estavam visíveis, que quebrava a cada destino
  // novo, deixou de existir.

  Future<void> _readBrandingAccess() async {
    if (AppState.isSuperAdmin) return;
    try {
      final branding = await TgdeskApi.myBranding();
      if (mounted) {
        setState(() => _brandingEnabled = branding['enabled'] == true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _control.removeListener(_onControl);
    TgdeskApi.removeDeviceEventListener(_onDeviceEvent);
    super.dispose();
  }

  void _onControl() {
    final enabled = _control.brandingEnabled;
    if (enabled != null && mounted && enabled != _brandingEnabled) {
      setState(() => _brandingEnabled = enabled);
    }
  }

  void _onDeviceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type']?.toString();
    if (type == 'update_status') {
      final payload = event['payload'];
      if (payload is Map) {
        final status = Map<String, dynamic>.from(payload);
        final next = _parseUpdateStatus(status);
        if (!_sameUpdateStatus(next, _updateStatus)) {
          setState(() => _updateStatus = next);
        }
      }
      return;
    }
    if (type == 'branding') {
      final payload = event['payload'];
      if (payload is Map) {
        final next = Map<String, dynamic>.from(payload);
        if (jsonEncode(next) != jsonEncode(_branding)) {
          setState(() => _branding = next);
          unawaited(applyClientBrandingWindowIcon(next));
        }
      }
    }
  }

  Future<void> _requestForcedUpdate() async {
    try {
      await TgdeskApi.requestLocalUpdate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pedido de atualização enviado pelo WebSocket.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _readUpdateState() async {
    try {
      final file = File(tgdeskStatusFilePath());
      if (!await file.exists()) return;
      final status =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (!mounted) return;
      // A marca vale para o computador do próprio técnico. Ela já chega aqui
      // pelo canal de controle — deviceBranding resolve pela organização dona
      // da rede do dispositivo, que no caso dele é a própria.
      final branding = status['branding'];
      final nextBranding = branding is Map
          ? Map<String, dynamic>.from(branding)
          : <String, dynamic>{};
      final nextVersion = status['current_version']?.toString() ?? '';
      final nextUpdateStatus = _parseUpdateStatus(status);
      final brandingChanged = jsonEncode(nextBranding) != jsonEncode(_branding);
      final changed = brandingChanged ||
          nextVersion != _version ||
          !_sameUpdateStatus(nextUpdateStatus, _updateStatus);
      if (brandingChanged) {
        unawaited(applyClientBrandingWindowIcon(nextBranding));
      }
      if (!changed) return;
      setState(() {
        _branding = nextBranding;
        _version = nextVersion;
        // O computador do técnico também é um dispositivo, e a atualização
        // dele é empurrada pelo servidor como a de qualquer outro. A barra só
        // acompanha.
        _updateStatus = nextUpdateStatus;
      });
    } catch (_) {}
  }

  Future<void> _closeRemoteSessions() async {
    stateGlobal.setFullscreen(false, procWnd: false);
    RemoteSessionsManager.instance.closeAll();
    // Let IndexedStack remove the RemotePage children so their asynchronous
    // FFI/session cleanup starts before the window is hidden.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = AppState.isSuperAdmin;
    final canManageNetworks = AppState.canManageNetworks;

    final destinations = <NavigationRailDestination>[
      if (canManageNetworks)
        const NavigationRailDestination(
            icon: Icon(Icons.devices), label: Text('Dispositivos')),
      const NavigationRailDestination(
          icon: Icon(Icons.monitor_heart_outlined), label: Text('Cliente')),
      const NavigationRailDestination(
          icon: Icon(Icons.support_agent_outlined), label: Text('Chamados')),
      if (isSuperAdmin)
        const NavigationRailDestination(
            icon: Icon(Icons.admin_panel_settings), label: Text('Admin')),
      if (!isSuperAdmin && _brandingEnabled)
        const NavigationRailDestination(
            icon: Icon(Icons.palette_outlined), label: Text('Minha marca')),
    ];

    final pages = <Widget>[
      if (canManageNetworks) const DevicesPage(),
      const TgdeskClientHomePage(embedded: true),
      const SupportPage(),
      if (isSuperAdmin) const AdminPage(),
      if (!isSuperAdmin && _brandingEnabled) const BrandingPage(),
    ];

    if (_index >= pages.length) _index = 0;

    return TgdeskWindowScaffold(
      title: _brandTitle(),
      productName: _productName,
      updateStatus: _updateStatus,
      onForceUpdate: _requestForcedUpdate,
      onBeforeClose: _closeRemoteSessions,
      actions: [
        if (_version.isNotEmpty)
          Center(
              child: Text('v$_version',
                  style: Theme.of(context).textTheme.labelSmall)),
      ],
      // Em tela cheia o Hub some inteiro: sem barra lateral e sem barra de
      // título. A tela remota passa a ocupar a janela toda, e o que aparece
      // por cima dela é só o toolbar flutuante, que sobrepõe em vez de empurrar.
      //
      // Era o oposto: a barra do Hub continuava lá em tela cheia, empurrando o
      // desktop remoto para baixo — a imagem ficava deslocada justamente no
      // modo que existe para não ter nada em volta.
      hideChrome: () => stateGlobal.fullscreen.isTrue,
      // Obx por fora do AnimatedBuilder: um escuta a tela cheia (observável do
      // core), o outro escuta as abas. Sem o Obx aqui, sair da tela cheia
      // devolvia a barra de título mas deixava o corpo como estava.
      child: Obx(() {
        // A leitura tem que acontecer AQUI, no corpo do Obx.
        //
        // Obx registra o observável pelo ato de lê-lo enquanto o próprio
        // callback roda. O builder do AnimatedBuilder roda depois, já fora
        // desse escopo — ler lá dentro não registra nada, e Obx que não lê
        // observável nenhum não emite aviso: lança exceção, e a janela inteira
        // fica cinza. Foi o que aconteceu na 1.1.61.
        final emTelaCheia = stateGlobal.fullscreen.isTrue;
        return AnimatedBuilder(
          animation: RemoteSessionsManager.instance,
          builder: (context, _) {
            final gerente = RemoteSessionsManager.instance;
            final sessoes = gerente.sessions;
            final ativa = gerente.activeIndex;

            // Todas as sessões ficam vivas ao mesmo tempo, num IndexedStack.
            //
            // Antes eu construía só a que estava à frente. Isso derrubava a
            // conexão a cada troca de aba, a cada entrada e saída de tela
            // cheia, e deixava o fundo cinza aparecendo enquanto a próxima
            // reconectava — o widget saía da árvore e levava a sessão junto.
            //
            // Aba de navegador não recarrega a página quando você volta para
            // ela, e sessão de acesso remoto muito menos: reconectar é lento,
            // pisca, e desfaz o que estava na tela.
            //
            // O Hub é o primeiro filho da pilha, então "nenhuma sessão à
            // frente" também é só trocar o índice — ninguém é destruído.
            final conteudo = IndexedStack(
              index: ativa < 0 ? 0 : ativa + 1,
              children: [
                pages[_index],
                for (final sessao in sessoes)
                  TgdeskRemoteSessionPage(
                    // A chave é o dispositivo: sem ela o Flutter reaproveitaria
                    // o estado de uma sessão para outra ao reordenar as abas —
                    // duas máquinas na mesma tela.
                    key: ValueKey(sessao.deviceId),
                    deviceId: sessao.deviceId,
                    remoteId: sessao.remoteId,
                    hostname: sessao.hostname,
                    credential: sessao.credential,
                    embedded: true,
                  ),
              ],
            );

            // A posição de `conteudo` na árvore precisa permanecer idêntica
            // nos dois modos. Retorná-lo diretamente em tela cheia e dentro
            // do Row em janela troca seu ancestral de Expanded para o próprio
            // Obx; o Flutter então desmonta RemotePage e o dispose fecha a
            // sessão FFI. Tela cheia é apenas uma mudança de layout, nunca de
            // ciclo de vida da conexão.
            return Row(
              children: [
                // Offstage still lays out its child. In fullscreen that left
                // the rail in the Row constraints even though it was not
                // painted, so remove it from layout entirely.
                if (emTelaCheia && ativa >= 0)
                  const SizedBox.shrink()
                else
                  NavigationRail(
                    // Com uma sessão à frente, nenhum destino fica marcado: o que
                    // a tela mostra é a máquina remota, não uma das telas do Hub.
                    selectedIndex: ativa < 0 ? _index : null,
                    onDestinationSelected: (i) {
                      gerente.blur();
                      setState(() => _index = i);
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations,
                  ),
                SizedBox(
                  width: emTelaCheia && ativa >= 0 ? 0 : 1,
                  child: const VerticalDivider(width: 1),
                ),
                Expanded(child: conteudo),
              ],
            );
          },
        );
      }),
    );
  }
}
