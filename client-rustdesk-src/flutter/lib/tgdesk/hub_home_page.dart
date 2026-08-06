import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'api_client.dart';
import 'branding_window_icon.dart';
import 'devices_page.dart';
import 'admin_page.dart';
import 'technicians_page.dart';
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
  Timer? _updateTimer;
  String _version = '';
  TgdeskUpdateStatus? _updateStatus;
  Map<String, dynamic> _branding = {};

  String get _productName {
    if (_branding['enabled'] != true) return 'TGDesk';
    final name = _branding['name']?.toString().trim() ?? '';
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

  @override
  void initState() {
    super.initState();
    _control.addListener(_onControl);
    _readUpdateState();
    _readBrandingAccess();
    _updateTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _readUpdateState());
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
    _updateTimer?.cancel();
    super.dispose();
  }

  void _onControl() {
    final enabled = _control.brandingEnabled;
    if (enabled != null && mounted && enabled != _brandingEnabled) {
      setState(() => _brandingEnabled = enabled);
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
      if (branding is Map) {
        unawaited(applyClientBrandingWindowIcon(
            Map<String, dynamic>.from(branding)));
      }
      setState(() {
        _branding = branding is Map ? Map<String, dynamic>.from(branding) : {};
        _version = status['current_version']?.toString() ?? '';
        // O computador do técnico também é um dispositivo, e a atualização
        // dele é empurrada pelo servidor como a de qualquer outro. A barra só
        // acompanha.
        _updateStatus = status['updating'] != true
            ? null
            : TgdeskUpdateStatus(
                updating: true,
                version: _text(status['update_progress'], 'version'),
                totalBytes: _int(status['update_progress'], 'total_bytes'),
                downloadedBytes:
                    _int(status['update_progress'], 'downloaded_bytes'),
                bytesPerSecond:
                    _int(status['update_progress'], 'bytes_per_second'),
                throttleKbps: _int(status['update_progress'], 'throttle_kbps'),
              );
      });
    } catch (_) {}
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
      if (isSuperAdmin)
        const NavigationRailDestination(
            icon: Icon(Icons.badge), label: Text('Técnicos')),
      if (!isSuperAdmin && _brandingEnabled)
        const NavigationRailDestination(
            icon: Icon(Icons.palette_outlined), label: Text('Minha marca')),
    ];

    final pages = <Widget>[
      if (canManageNetworks) const DevicesPage(),
      const TgdeskClientHomePage(embedded: true),
      const SupportPage(),
      if (isSuperAdmin) const AdminPage(),
      if (isSuperAdmin) const TechniciansPage(),
      if (!isSuperAdmin && _brandingEnabled) const BrandingPage(),
    ];

    if (_index >= pages.length) _index = 0;

    return TgdeskWindowScaffold(
      title: _brandTitle(),
      productName: _productName,
      updateStatus: _updateStatus,
      actions: [
        if (_version.isNotEmpty)
          Center(
              child: Text('v$_version',
                  style: Theme.of(context).textTheme.labelSmall)),
      ],
      child: AnimatedBuilder(
        animation: RemoteSessionsManager.instance,
        builder: (context, _) {
          final sessao = RemoteSessionsManager.instance.active;
          return Row(
            children: [
              NavigationRail(
                // Com uma sessão à frente, nenhum destino está selecionado: o
                // que a tela mostra é a máquina remota, não uma das telas do
                // Hub. Marcar um destino ali seria dizer que o usuário está
                // num lugar em que ele não está.
                selectedIndex: sessao == null ? _index : null,
                onDestinationSelected: (i) {
                  RemoteSessionsManager.instance.blur();
                  setState(() => _index = i);
                },
                labelType: NavigationRailLabelType.all,
                destinations: destinations,
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: sessao == null
                    ? pages[_index]
                    // A sessão é mantida viva por chave: trocar de aba não
                    // pode derrubar a conexão da que sai de cena, e sem chave
                    // o Flutter reaproveitaria o estado da anterior para a
                    // seguinte — duas máquinas na mesma tela.
                    : TgdeskRemoteSessionPage(
                        key: ValueKey(sessao.deviceId),
                        deviceId: sessao.deviceId,
                        remoteId: sessao.remoteId,
                        hostname: sessao.hostname,
                        credential: sessao.credential,
                        embedded: true,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
