import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'api_client.dart';
import 'devices_page.dart';
import 'admin_page.dart';
import 'technicians_page.dart';
import 'window_frame.dart';
import 'client_home_page.dart';
import 'agent_deploy.dart';
import 'branding_page.dart';
import 'control_channel.dart';
import 'support_page.dart';
import 'ui_contract.dart';

class HubHomePage extends StatefulWidget {
  const HubHomePage({super.key});
  @override
  State<HubHomePage> createState() => _HubHomePageState();
}

class _HubHomePageState extends State<HubHomePage> {
  final _control = TgdeskControlChannel.instance;
  int _index = 0;
  Timer? _updateTimer;
  bool _updateAvailable = false;
  bool _updating = false;
  String _updateVersion = '';
  String _version = '';
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
      setState(() {
        _version = status['current_version']?.toString() ?? '';
        _updateVersion = status['update_version']?.toString() ?? '';
        _updateAvailable = TgdeskUpdatePolicy.shouldOffer(
          currentVersion: _version,
          availableVersion: _updateVersion,
          serverAdvertised: status['update_available'] == true,
        );
      });
    } catch (_) {}
  }

  Future<void> _installUpdate() async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final result = await Process.run(
          Platform.resolvedExecutable, const ['--tgdesk-update'],
          workingDirectory: File(Platform.resolvedExecutable).parent.path);
      if (result.exitCode == 10) {
        exit(0);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.stderr.toString().trim().isEmpty
                ? 'Não foi possível instalar a atualização.'
                : result.stderr.toString().trim())));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
      actions: [
        if (_version.isNotEmpty)
          Center(
              child: Text('v$_version',
                  style: Theme.of(context).textTheme.labelSmall)),
        if (_updateAvailable)
          Tooltip(
            message: 'Atualizar para v$_updateVersion',
            child: IconButton(
              onPressed: _updating ? null : _installUpdate,
              icon: _updating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.system_update_alt,
                      color: Color(0xff35a7ff)),
            ),
          ),
      ],
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
