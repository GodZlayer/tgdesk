import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'agent_deploy.dart';
import 'api_client.dart';
import 'health_text.dart';
import 'theme.dart';
import 'control_channel.dart';
import 'diagnostics_dialog.dart';
import 'remote_session_page.dart';
import 'ui_contract.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});
  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  List<dynamic> _orgs = [];
  List<dynamic> _nets = [];
  List<dynamic> _subnets = [];
  List<dynamic> _devices = [];
  bool _loading = true;
  final _control = TgdeskControlChannel.instance;
  bool _pairingContextLoading = true;
  String _localDeviceId = '';

  @override
  void initState() {
    super.initState();
    _control.addListener(_onControlChanged);
    _copyControlState();
    _loadPairingContext();
    unawaited(_loadLocalDeviceId());
  }

  Future<void> _loadLocalDeviceId() async {
    try {
      final file = File(tgdeskStatusFilePath());
      final status =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final id = status['device_id']?.toString() ?? '';
      if (id.isEmpty) return;
      if (mounted) setState(() => _localDeviceId = id);
      await TgdeskApi.claimControlMachine(id);
    } catch (_) {}
  }

  @override
  void dispose() {
    _control.removeListener(_onControlChanged);
    super.dispose();
  }

  void _onControlChanged() {
    if (!mounted) return;
    setState(_copyControlState);
    if (_control.connected && _localDeviceId.isNotEmpty) {
      unawaited(TgdeskApi.claimControlMachine(_localDeviceId));
    }
  }

  void _copyControlState() {
    _orgs = _control.organizations;
    _nets = _control.networks;
    _subnets = _control.subnetworks;
    _devices = _control.devices;
    _loading = _control.loading;
  }

  Future<void> _load({bool silent = false}) async {
    await _control.refresh();
  }

  Future<void> _loadPairingContext() async {
    try {
      final context = await TgdeskApi.pairingContext();
      if (!mounted || _control.connected) return;
      setState(() {
        _orgs =
            List<dynamic>.from(context['organizations'] as List? ?? const []);
        _nets = List<dynamic>.from(context['networks'] as List? ?? const []);
        _subnets =
            List<dynamic>.from(context['subnetworks'] as List? ?? const []);
      });
    } catch (_) {
      // O canal privado continuará tentando conectar.
    } finally {
      if (mounted) setState(() => _pairingContextLoading = false);
    }
  }

  Future<void> _openBindDialog() async {
    final codeCtrl = TextEditingController();
    String? selectedNetworkId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Vincular dispositivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Código de pareamento'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedNetworkId,
                decoration: const InputDecoration(labelText: 'Rede de destino'),
                items: _nets.map<DropdownMenuItem<String>>((n) {
                  final org = _orgs.firstWhere(
                      (o) => o['id'] == n['organization_id'],
                      orElse: () => {'name': '?'});
                  return DropdownMenuItem(
                    value: n['id'] as String,
                    child: Text('${org['name']} — ${n['name']}'),
                  );
                }).toList(),
                onChanged: (v) => setLocal(() => selectedNetworkId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (codeCtrl.text.trim().isEmpty || selectedNetworkId == null) {
                  return;
                }
                try {
                  await TgdeskApi.bindDevice(
                      codeCtrl.text.trim(), selectedNetworkId!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
              child: const Text('Vincular'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_control.connected && _devices.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: TgdeskSpacing.md),
          const Text('Conectando à rede privada TGDesk...'),
          const SizedBox(height: TgdeskSpacing.sm),
          Text('O Windows pode solicitar permissão de administrador.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: TgdeskSpacing.md),
          FilledButton.icon(
            onPressed: _pairingContextLoading || _nets.isEmpty
                ? null
                : _openBindDialog,
            icon: const Icon(Icons.link),
            label: const Text('Aprovar dispositivo por código'),
          ),
        ]),
      );
    }

    // Organiza dispositivos sem rede (guest, ninguém vinculado ainda) à parte.
    final unbound = _devices.where((d) => d['network_id'] == null).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openBindDialog,
                icon: const Icon(Icons.link),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Vincular dispositivo'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final org in _orgs) _buildOrgTile(org),
            if (unbound.isNotEmpty) _buildUnboundTile(unbound),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgTile(dynamic org) {
    final netsOfOrg =
        _nets.where((n) => n['organization_id'] == org['id']).toList();
    return Card(
      child: ExpansionTile(
        title: Row(children: [
          Expanded(
            child: Text(org['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (org['can_manage'] == true) ...[
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Criar rede nesta organização',
              onPressed: () => _openCreateNetworkDialog(org),
            ),
            IconButton(
              icon: const Icon(Icons.group_add_outlined),
              tooltip: 'Vincular outro supervisor a esta organização',
              onPressed: () => _openSupervisorInviteDialog(org),
            ),
          ],
        ]),
        subtitle: Text('status: ${org['status']}'),
        children: netsOfOrg.map<Widget>((n) => _buildNetTile(n)).toList(),
      ),
    );
  }

  Widget _buildNetTile(dynamic net) {
    final devicesOfNet = _devices.where((d) {
      final ids = d['network_ids'];
      return ids is List
          ? ids.map((value) => value.toString()).contains(net['id'])
          : d['network_id'] == net['id'];
    }).toList();
    final networkLevel = devicesOfNet.fold<int>(
        0,
        (current, device) =>
            _healthRank(device['health_level']?.toString()) > current
                ? _healthRank(device['health_level']?.toString())
                : current);
    final subnetsOfNet =
        _subnets.where((s) => s['network_id'] == net['id']).toList();
    final subnetIds = subnetsOfNet
        .map((subnet) => subnet['id']?.toString())
        .whereType<String>()
        .toSet();
    final devicesWithoutSubnet = devicesOfNet.where((device) {
      final assigned = <String>{
        ...((device['subnetwork_ids'] as List?) ?? const [])
            .map((value) => value.toString()),
        if (device['subnetwork_id'] != null) device['subnetwork_id'].toString(),
      };
      return assigned.intersection(subnetIds).isEmpty;
    }).toList();
    return ExpansionTile(
      title: Row(children: [
        Expanded(
            child: Text('${net['name']}  (${net['cidr_virtual'] ?? '-'})')),
        if (networkLevel > 0)
          _alertBadge(
              networkLevel, networkLevel == 2 ? 'Alerta crítico' : 'Atenção'),
        if (net['can_manage'] == true)
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Criar sub-rede',
            onPressed: () => _openCreateSubnetworkDialog(net),
          ),
        if (net['can_manage'] == true)
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Renomear esta rede',
            onPressed: () => _openRenameNetworkDialog(net),
          ),
        if (net['can_manage'] == true)
          IconButton(
            icon: Icon(net['status'] == 'suspensa'
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline),
            tooltip: net['status'] == 'suspensa'
                ? 'Reativar esta rede'
                : 'Suspender esta rede',
            onPressed: () => _toggleOwnedNetwork(net),
          ),
        if (net['can_manage'] == true)
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: TgdeskColors.suspended),
            tooltip: 'Excluir esta rede',
            onPressed: () => _deleteOwnedNetwork(net),
          ),
      ]),
      subtitle: Text(
          'status: ${net['status']} · ${devicesOfNet.length} dispositivo(s)'),
      children: [
        for (final subnet in subnetsOfNet)
          _buildSubnetTile(subnet, devicesOfNet),
        if (devicesWithoutSubnet.isNotEmpty)
          _buildNetworkDevicesTile(
              devicesWithoutSubnet, subnetsOfNet.isNotEmpty),
      ],
    );
  }

  Widget _buildNetworkDevicesTile(
      List<dynamic> devices, bool networkHasSubnetworks) {
    if (!networkHasSubnetworks) {
      return Padding(
        padding: const EdgeInsets.only(left: 18),
        child: Column(
          children: devices.map<Widget>(_buildDeviceTile).toList(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: ExpansionTile(
        leading: const Icon(Icons.devices_outlined),
        title: const Text('Sem sub-rede'),
        subtitle: Text('${devices.length} dispositivo(s)'),
        children: devices.map<Widget>(_buildDeviceTile).toList(),
      ),
    );
  }

  Widget _buildSubnetTile(dynamic subnet, List<dynamic> devicesOfNet) {
    final devices = devicesOfNet.where((d) {
      final ids = ((d['subnetwork_ids'] as List?) ?? const [])
          .map((value) => value.toString());
      return ids.contains(subnet['id']?.toString()) ||
          d['subnetwork_id'] == subnet['id'];
    }).toList();
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: ExpansionTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: Row(children: [
          Expanded(child: Text(subnet['name']?.toString() ?? 'Sub-rede')),
          if (subnet['can_manage'] == true)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Renomear sub-rede',
              onPressed: () => _openRenameSubnetworkDialog(subnet),
            ),
        ]),
        subtitle: Text('${devices.length} dispositivo(s)'),
        children: devices.map<Widget>((d) => _buildDeviceTile(d)).toList(),
      ),
    );
  }

  Widget _buildUnboundTile(List<dynamic> unbound) {
    return Card(
      child: ExpansionTile(
        title: const Text('Aguardando vinculação',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${unbound.length} dispositivo(s) em estado guest'),
        children: unbound.map<Widget>((d) => _buildDeviceTile(d)).toList(),
      ),
    );
  }

  // Uma organização pode ter vários supervisores. A fila de chamados sempre
  // foi da org, então quem entra passa a ver os mesmos chamados ao mesmo
  // tempo — não é uma cópia nem um repasse.
  Future<void> _openSupervisorInviteDialog(dynamic organization) async {
    final orgId = organization['id'] as String;
    String? codigo;
    List<dynamic> supervisores = [];
    try {
      supervisores = await TgdeskApi.organizationSupervisors(orgId);
    } catch (_) {}
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Supervisores de ${organization['name']}'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (supervisores.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Já supervisionam esta organização:',
                      style: Theme.of(ctx).textTheme.bodySmall),
                ),
                const SizedBox(height: 6),
                ...supervisores.map((s) => ListTile(
                      dense: true,
                      leading: Icon(s['dono'] == true
                          ? Icons.star
                          : Icons.person_outline),
                      title: Text(s['username']?.toString() ?? ''),
                      subtitle: Text(s['dono'] == true
                          ? 'dono da organização'
                          : s['role']?.toString() ?? ''),
                    )),
                const Divider(),
              ],
              const Text(
                  'Gere um código e entregue ao outro supervisor. Ele resgata '
                  'na tela Cliente da máquina dele e passa a ver os mesmos '
                  'chamados desta organização.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              if (codigo == null)
                FilledButton.icon(
                  icon: const Icon(Icons.key),
                  label: const Text('Gerar código'),
                  onPressed: () async {
                    try {
                      final r = await TgdeskApi.createSupervisorInvite(orgId);
                      setDialog(() => codigo = r['code']?.toString());
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                )
              else
                Column(children: [
                  SelectableText(codigo!,
                      style: const TextStyle(
                          fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Válido por 7 dias, uso único.',
                      style: TextStyle(fontSize: 11)),
                ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar')),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateNetworkDialog(dynamic organization) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nova rede de ${organization['name']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da rede'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await TgdeskApi.createNetwork(
                    organization['id'] as String, name, '');
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateSubnetworkDialog(dynamic network) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nova sub-rede de ${network['name']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome da sub-rede'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await TgdeskApi.createSubnetwork(network['id'] as String, name);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRenameSubnetworkDialog(dynamic subnet) async {
    final controller =
        TextEditingController(text: subnet['name']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear sub-rede'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await TgdeskApi.renameSubnetwork(subnet['id'] as String, name);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRenameNetworkDialog(dynamic network) async {
    final currentName = network['name']?.toString() ?? '';
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear rede'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Novo nome'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty || name == currentName) return;
              try {
                await TgdeskApi.renameNetwork(network['id'] as String, name);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOwnedNetwork(dynamic network) async {
    try {
      if (network['status'] == 'suspensa') {
        await TgdeskApi.resumeNetwork(network['id'] as String);
      } else {
        final confirmed = await showTgdeskConfirmSuspendDialog(
            context, 'a rede "${network['name']}"');
        if (!confirmed) return;
        await TgdeskApi.suspendNetwork(network['id'] as String);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _deleteOwnedNetwork(dynamic network) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir rede?'),
            content: Text(
                'A rede "${network['name']}" será removida. Dispositivos sem outra rede voltarão ao código de vinculação.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: TgdeskColors.suspended),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await TgdeskApi.deleteNetwork(network['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openDeviceNetworksDialog(dynamic device) async {
    final selected = <String>{
      ...((device['network_ids'] as List?) ?? const [])
          .map((value) => value.toString()),
    };
    if (selected.isEmpty && device['network_id'] != null) {
      selected.add(device['network_id'].toString());
    }
    String organizationOfSubnetwork(dynamic subnet) {
      final network = _nets.where(
          (item) => item['id']?.toString() == subnet['network_id']?.toString());
      return network.isEmpty
          ? ''
          : network.first['organization_id']?.toString() ?? '';
    }

    final selectedSubnetworkByOrganization = <String, String>{};
    final currentSubnetworkIds = <String>{
      ...((device['subnetwork_ids'] as List?) ?? const [])
          .map((value) => value.toString()),
      if (device['subnetwork_id'] != null) device['subnetwork_id'].toString(),
    };
    for (final subnet in _subnets.where(
        (item) => currentSubnetworkIds.contains(item['id']?.toString()))) {
      final organizationId = organizationOfSubnetwork(subnet);
      if (organizationId.isNotEmpty) {
        selectedSubnetworkByOrganization[organizationId] =
            subnet['id'].toString();
      }
    }
    final tgdevsOrgs = _orgs
        .where((org) => org['name']?.toString().toLowerCase() == 'tgdevs')
        .toList();
    final tgdevsId =
        tgdevsOrgs.isEmpty ? null : tgdevsOrgs.first['id']?.toString();
    final manageableNetworks = _nets
        .where((network) =>
            network['can_manage'] == true ||
            (AppState.isSuperAdmin &&
                network['organization_id']?.toString() == tgdevsId))
        .toList();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Redes e sub-redes'),
          content: SizedBox(
            width: 560,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text(
                    'Selecione redes e sub-redes dentro da organização atual. O vínculo obrigatório com TGDevs é mantido automaticamente.'),
                const SizedBox(height: 12),
                for (final org in _orgs) ...[
                  if (manageableNetworks.any(
                      (network) => network['organization_id'] == org['id']))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(org['name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  for (final network in manageableNetworks.where((network) =>
                      network['organization_id'] == org['id'])) ...[
                    CheckboxListTile(
                      value: selected.contains(network['id']),
                      title: Text(network['name']?.toString() ?? ''),
                      subtitle: const Text('Rede'),
                      onChanged: (checked) => setLocal(() {
                        final networkId = network['id'].toString();
                        if (checked == true) {
                          final organizationId =
                              network['organization_id']?.toString() ?? '';
                          for (final other in manageableNetworks.where((item) =>
                              item['organization_id']?.toString() ==
                              organizationId)) {
                            selected.remove(other['id']?.toString());
                          }
                          selectedSubnetworkByOrganization
                              .remove(organizationId);
                          selected.add(networkId);
                        } else {
                          selected.remove(networkId);
                          final organizationId =
                              network['organization_id']?.toString() ?? '';
                          final selectedSubnetId =
                              selectedSubnetworkByOrganization[organizationId];
                          final selectedSubnet = _subnets.where((subnet) =>
                              subnet['id']?.toString() == selectedSubnetId);
                          if (selectedSubnet.isNotEmpty &&
                              selectedSubnet.first['network_id']?.toString() ==
                                  networkId) {
                            selectedSubnetworkByOrganization
                                .remove(organizationId);
                          }
                        }
                      }),
                    ),
                    for (final subnet in _subnets.where(
                        (subnet) => subnet['network_id'] == network['id']))
                      Padding(
                        padding: const EdgeInsets.only(left: 28),
                        child: RadioListTile<String>(
                          value: subnet['id'].toString(),
                          groupValue: selectedSubnetworkByOrganization[
                              network['organization_id']?.toString() ?? ''],
                          title: Text(subnet['name']?.toString() ?? ''),
                          subtitle: const Text('Sub-rede principal'),
                          onChanged: selected.contains(network['id'])
                              ? (value) => setLocal(() {
                                    if (value != null) {
                                      selectedSubnetworkByOrganization[
                                          network['organization_id']
                                                  ?.toString() ??
                                              ''] = value;
                                    }
                                  })
                              : null,
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      try {
                        await TgdeskApi.updateDeviceNetworks(
                            device['id'] as String, selected.toList());
                        if (selectedSubnetworkByOrganization.isNotEmpty) {
                          await TgdeskApi.updateDeviceSubnetworks(
                              device['id'] as String,
                              selectedSubnetworkByOrganization.values.toList());
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _load();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erro: $e')));
                        }
                      }
                    },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectGuestDevice(dynamic device) async {
    final hostname = device['hostname']?.toString() ?? 'este computador';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Recusar dispositivo?'),
            content: Text(
                'O pedido de vínculo de “$hostname” será removido da lista.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: TgdeskColors.suspended),
                child: const Text('Recusar e remover'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await TgdeskApi.rejectGuestDevice(device['id'] as String);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível recusar: $e')),
      );
    }
  }

  Future<void> _openMoveSubnetworkDialog(dynamic device) async {
    final networkIds = <String>{
      ...((device['network_ids'] as List?) ?? const [])
          .map((value) => value.toString()),
      if (device['network_id'] != null) device['network_id'].toString(),
    };
    final options =
        _subnets.where((s) => networkIds.contains(s['network_id'])).toList();
    String organizationOfSubnet(dynamic subnet) {
      final network = _nets.where(
          (item) => item['id']?.toString() == subnet['network_id']?.toString());
      return network.isEmpty
          ? ''
          : network.first['organization_id']?.toString() ?? '';
    }

    final selected = <String>{
      ...((device['subnetwork_ids'] as List?) ?? const [])
          .map((value) => value.toString()),
      if (device['subnetwork_id'] != null) device['subnetwork_id'].toString(),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Sub-redes do dispositivo'),
          content: SizedBox(
            width: 430,
            child: ListView(
              shrinkWrap: true,
              children: options.map((subnet) {
                final id = subnet['id'].toString();
                final network = _nets.cast<Map>().where((item) =>
                    item['id']?.toString() == subnet['network_id']?.toString());
                final networkName = network.isEmpty
                    ? 'Rede'
                    : network.first['name']?.toString() ?? 'Rede';
                return CheckboxListTile(
                  value: selected.contains(id),
                  title: Text(subnet['name']?.toString() ?? 'Sub-rede'),
                  subtitle: Text(networkName),
                  onChanged: (checked) => setLocal(() {
                    if (checked == true) {
                      final organizationId = organizationOfSubnet(subnet);
                      selected.removeWhere((selectedId) {
                        final previous = options.where(
                            (item) => item['id']?.toString() == selectedId);
                        return previous.isNotEmpty &&
                            organizationOfSubnet(previous.first) ==
                                organizationId;
                      });
                      selected.add(id);
                    } else {
                      selected.remove(id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () async {
                      try {
                        await TgdeskApi.updateDeviceSubnetworks(
                            device['id'] as String, selected.toList());
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _load();
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Erro: $e')));
                        }
                      }
                    },
              child: const Text('Salvar vínculos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(dynamic d) {
    final presence = (d['presence'] ?? d['state'] ?? '') as String;
    final healthLevel = _healthRank(d['health_level']?.toString());
    final hostname = d['hostname'] as String? ?? '?';
    final alias = d['display_name']?.toString().trim() ?? '';
    final displayName = alias.isEmpty ? hostname : alias;
    return ListTile(
      leading:
          CircleAvatar(radius: 6, backgroundColor: presenceColor(presence)),
      title: Row(children: [
        Text(displayName),
        const SizedBox(width: 10),
        if (d['id'] == _localDeviceId)
          const Chip(
            avatar: Icon(Icons.person_pin_circle_outlined, size: 16),
            label: Text('Este dispositivo'),
            visualDensity: VisualDensity.compact,
          ),
        if (d['id'] == _localDeviceId) const SizedBox(width: 8),
        if (healthLevel > 0)
          _alertBadge(healthLevel, healthLevel == 2 ? 'Crítico' : 'Atenção'),
      ]),
      subtitle: Text([
        'estado: ${d['state']}',
        if (alias.isNotEmpty) 'Windows: $hostname',
        if (d['id'] != _localDeviceId &&
            presence == 'online' &&
            d['remote_ready'] == true &&
            d['rustdesk_id'] != null &&
            (d['rustdesk_id'] as String).isNotEmpty)
          'Acesso remoto disponível',
        if (d['pairing_code'] != null) 'código: ${d['pairing_code']}',
      ].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (d['state'] == 'guest')
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: TgdeskColors.suspended),
            tooltip: 'Recusar e remover pedido',
            onPressed: () => _rejectGuestDevice(d),
          ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Alterar nome no TGDesk',
          onPressed: () => _openRenameDialog(d),
        ),
        if (d['state'] == 'ativo' && _subnets.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Mover para outra sub-rede',
            onPressed: () => _openMoveSubnetworkDialog(d),
          ),
        if (d['can_manage'] == true)
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: 'Organizações, redes e sub-redes deste dispositivo',
            onPressed: () => _openDeviceNetworksDialog(d),
          ),
        if (TgdeskDeviceUiPolicy.canOfferRemote(
            localDeviceId: _localDeviceId,
            device: Map<String, dynamic>.from(d as Map)))
          IconButton(
            icon: const Icon(Icons.desktop_windows_outlined,
                color: TgdeskColors.seed),
            tooltip: 'Abrir acesso remoto no TGDesk',
            onPressed: () async {
              try {
                final credential =
                    await TgdeskApi.remoteCredential(d['id'] as String);
                if (credential.isEmpty) {
                  throw Exception('autorização remota indisponível');
                }
                if (!mounted) return;
                RemoteSessionsManager.instance.open(RemoteSessionEntry(
                  deviceId: d['id'] as String,
                  remoteId: d['rustdesk_id'] as String,
                  hostname: displayName,
                  credential: credential,
                ));
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Acesso remoto indisponível: $e')),
                  );
                }
              }
            },
          ),
        if (d['state'] == 'ativo')
          IconButton(
            icon: const Icon(Icons.monitor_heart_outlined),
            tooltip: 'Saúde do dispositivo',
            onPressed: () => _openHealthDialog(d['id'] as String, displayName),
          ),
        if (d['state'] == 'ativo')
          IconButton(
            icon: const Icon(Icons.science_outlined, color: TgdeskColors.seed),
            tooltip: 'Diagnóstico avançado',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DiagnosticDialog(
                deviceId: d['id'] as String,
                deviceName: displayName,
                online: presence == 'online',
              ),
            ),
          ),
        if (d['state'] == 'ativo' && presence == 'offline')
          IconButton(
            icon: const Icon(Icons.flash_on, color: TgdeskColors.warning),
            tooltip: 'Ligar (Wake-on-LAN)',
            onPressed: () async {
              try {
                await TgdeskApi.wakeDevice(d['id'] as String);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Magic packet enviado')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
          ),
        if (AppState.isSuperAdmin)
          IconButton(
            icon: Icon(
                d['state'] == 'suspenso'
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                color: d['state'] == 'suspenso'
                    ? TgdeskColors.online
                    : TgdeskColors.warning),
            tooltip: d['state'] == 'suspenso'
                ? 'Reativar dispositivo'
                : 'Suspender dispositivo',
            onPressed: () async {
              try {
                if (d['state'] == 'suspenso') {
                  await TgdeskApi.resumeDevice(d['id'] as String);
                } else {
                  final ok = await showTgdeskConfirmSuspendDialog(context,
                      'o dispositivo "${d['display_name'] ?? d['hostname']}"');
                  if (!ok) return;
                  await TgdeskApi.suspendDevice(d['id'] as String);
                }
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
          ),
      ]),
    );
  }

  Future<void> _openRenameDialog(dynamic device) async {
    final hostname = device['hostname']?.toString() ?? '';
    final controller =
        TextEditingController(text: device['display_name']?.toString() ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome do dispositivo no TGDesk'),
        content: SizedBox(
          width: 430,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Nome de exibição',
                hintText: 'Ex.: Caixa 01, Servidor da loja',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Nome informado pelo Windows: $hostname\n'
                'Esse dado não será alterado.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              try {
                await TgdeskApi.updateDeviceDisplayName(
                    device['id'] as String, '');
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Usar nome do Windows'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await TgdeskApi.updateDeviceDisplayName(
                    device['id'] as String, name);
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  int _healthRank(String? level) {
    if (level == 'maximum') return 3;
    if (level == 'critical') return 2;
    if (level == 'warning') return 1;
    return 0;
  }

  Color _healthColor(int level) => level >= 2
      ? const Color(0xffff5252)
      : level == 1
          ? const Color(0xffffb020)
          : TgdeskColors.online;

  Widget _alertBadge(int level, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _healthColor(level).withOpacity(.13),
          border: Border.all(color: _healthColor(level).withOpacity(.55)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              level >= 2
                  ? Icons.error_outline
                  : level == 1
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
              size: 15,
              color: _healthColor(level)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: _healthColor(level))),
        ]),
      );

  // Resgate de telemetria por dispositivo, guardado por id.
  //
  // O diálogo se redesenha a cada notificação do canal — e são muitas, porque
  // qualquer telemetria de qualquer máquina notifica. Criar a chamada dentro
  // do builder criava uma nova a cada redesenho: abrir o painel de uma máquina
  // que ainda não reportou disparava uma rajada de pedidos enquanto a janela
  // estivesse aberta. Guardada aqui, é uma só por dispositivo.
  final Map<String, Future<Map<String, dynamic>>> _healthFallback = {};

  Future<void> _openHealthDialog(String deviceId, String hostname) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Expanded(child: Text('Painel técnico — $hostname')),
          AnimatedBuilder(
            animation: _control,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle,
                  size: 9,
                  color: _control.connected
                      ? TgdeskColors.online
                      : TgdeskColors.warning),
              const SizedBox(width: 7),
              Text(_control.connected ? 'Tempo real' : 'Reconectando',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
        content: AnimatedBuilder(
          animation: _control,
          builder: (ctx, _) {
            final live = _control.deviceHealth[deviceId];
            if (live != null) return _technicalHealth(live);
            // Só quando o canal ainda não recebeu telemetria desta máquina:
            // um pedido pelo próprio canal, guardado para não repetir.
            return FutureBuilder<Map<String, dynamic>>(
              future: _healthFallback.putIfAbsent(
                  deviceId, () => TgdeskApi.deviceHealth(deviceId)),
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return TgdeskErrorText('Erro: ${snap.error}');
                }
                return _technicalHealth(snap.data!);
              },
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Widget _technicalHealth(Map<String, dynamic> response) {
    final hardware = _map(response['hardware']);
    final statistics = _map(response['statistics']);
    final health = _map(statistics['health']);
    final healthMetrics = _map(health['metrics']);
    int metricRank(String name) =>
        _healthRank(_map(healthMetrics[name])['level']?.toString());
    final cpu = _map(hardware['cpu']);
    final memory = _map(hardware['memory_summary']);
    final cpuStats = _map(_map(statistics['cpu'])['usage']);
    final issues = _list(health['issues']);
    final storages = _list(hardware['storage']);
    final networks = _list(hardware['networks']);
    final gpus = _list(hardware['gpus']);
    final cpuPct = _num(cpu['usage']);
    final memoryPct = _num(memory['usage']);
    var storagePct = 0.0;
    var highestTemperature = 0.0;
    for (final raw in storages) {
      final disk = _map(raw);
      storagePct = storagePct > _num(disk['used_pct'])
          ? storagePct
          : _num(disk['used_pct']);
      highestTemperature = highestTemperature > _num(disk['temperature'])
          ? highestTemperature
          : _num(disk['temperature']);
      for (final volumeRaw in _list(disk['volumes'])) {
        final volume = _map(volumeRaw);
        storagePct = storagePct > _num(volume['used_pct'])
            ? storagePct
            : _num(volume['used_pct']);
      }
    }
    for (final raw in gpus) {
      highestTemperature = highestTemperature > _num(_map(raw)['temperature'])
          ? highestTemperature
          : _num(_map(raw)['temperature']);
    }
    return SizedBox(
      width: 860,
      height: 610,
      child: DefaultTabController(
        length: 4,
        child: Column(children: [
          Row(children: [
            Icon(
                health['level'] == 'critical' || health['level'] == 'maximum'
                    ? Icons.error_outline
                    : health['level'] == 'warning'
                        ? Icons.warning_amber_rounded
                        : Icons.verified_outlined,
                color: health['level'] == 'critical' ||
                        health['level'] == 'maximum'
                    ? TgdeskColors.suspended
                    : health['level'] == 'warning'
                        ? TgdeskColors.warning
                        : TgdeskColors.online),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    TgdeskHealthText.technicalTitle(health['level']?.toString()),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600))),
            Text(response['collected_at']?.toString() ?? '',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 12),
          const TabBar(tabs: [
            Tab(text: 'Visão geral'),
            Tab(text: 'Hardware'),
            Tab(text: 'Rede'),
            Tab(text: 'Alertas'),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(children: [
              ListView(children: [
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _visualMetric('Processador', cpuPct, '%',
                      Icons.memory_outlined, metricRank('processing')),
                  _visualMetric('Memória', memoryPct, '%',
                      Icons.view_module_outlined, metricRank('memory')),
                  _visualMetric('Armazenamento', storagePct, '%',
                      Icons.storage_outlined, metricRank('storage')),
                  _visualMetric(
                      'Temperatura',
                      highestTemperature,
                      highestTemperature == 0 ? '' : '°C',
                      Icons.thermostat_outlined,
                      metricRank('temperature')),
                ]),
              ]),
              ListView(children: [
                _componentVisualCard(
                    'Processador',
                    cpu['name']?.toString() ?? 'Não identificado',
                    Icons.memory_outlined,
                    cpuPct, [
                  'Atual ${_optionalPct(cpu['usage'])}',
                  'Média ${_optionalPct(cpuStats['average'])}',
                  'Pico ${_optionalPct(cpuStats['peak'])}',
                  _clock(cpu['clock_mhz']),
                ]),
                _componentVisualCard(
                    'Memória',
                    '${_bytes(memory['used_bytes'])} de ${_bytes(memory['total_bytes'])}',
                    Icons.view_module_outlined,
                    memoryPct, [
                  '${_bytes(memory['available_bytes'])} disponíveis',
                  '${_list(hardware['memory']).length} módulo(s)',
                  'Uso ${_optionalPct(memory['usage'])}',
                ]),
                for (final raw in gpus)
                  _componentVisualCard(
                      'Placa gráfica',
                      _map(raw)['name']?.toString() ?? 'Não identificada',
                      Icons.developer_board_outlined,
                      _num(_map(raw)['usage']), [
                    'Uso ${_optionalPct(_map(raw)['usage'])}',
                    _clock(_map(raw)['clock_mhz']),
                    'Temperatura ${_map(raw)['temperature'] ?? "N/D"} °C',
                  ]),
                for (final raw in storages) _storageVisual(_map(raw)),
              ]),
              ListView(children: [
                for (final raw in networks)
                  _networkVisual(_map(raw), statistics),
              ]),
              issues.isEmpty
                  ? _emptyAlerts()
                  : ListView(children: [
                      for (final raw in issues) _alertVisual(_map(raw)),
                    ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _componentVisualCard(String title, String subtitle, IconData icon,
      double usage, List<String> facts) {
    final level = usage >= 95
        ? 2
        : usage >= 85
            ? 1
            : 0;
    final color = _healthColor(level);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color, size: 31),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: TgdeskColors.offline)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (usage / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withOpacity(.14),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 4,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fact in facts)
                  Chip(
                    avatar: Icon(Icons.check_circle_outline,
                        size: 16, color: color),
                    label: Text(fact),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _storageVisual(Map<String, dynamic> disk) {
    var used = _num(disk['used_pct']);
    for (final raw in _list(disk['volumes'])) {
      final value = _num(_map(raw)['used_pct']);
      if (value > used) used = value;
    }
    final healthy =
        (disk['smart_status']?.toString().toLowerCase() ?? 'healthy') ==
            'healthy';
    final facts = <String>[
      '${disk['media_type'] ?? "Disco"} ${disk['bus_type'] ?? ""}'.trim(),
      _bytes(disk['total_bytes']),
      healthy ? 'Saúde normal' : 'Falha de saúde',
      disk['temperature'] is num
          ? '${disk['temperature']} °C'
          : 'Sem temperatura',
    ];
    return _componentVisualCard(
      'Armazenamento',
      disk['model']?.toString() ?? 'Não identificado',
      Icons.storage_outlined,
      healthy ? used : 100,
      facts,
    );
  }

  Widget _networkVisual(
      Map<String, dynamic> network, Map<String, dynamic> statistics) {
    final id = network['id']?.toString() ?? '';
    final stats = _map(_map(statistics['networks'])[id]);
    final online = network['status']?.toString().toLowerCase() == 'up';
    final max = _num(stats['max_bps']);
    final average = _num(stats['average_bps']);
    final ratio = max <= 0 ? 0.0 : (average / max).clamp(0, 1).toDouble();
    final color = online ? TgdeskColors.online : TgdeskColors.warning;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.lan_outlined, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(network['name']?.toString() ?? 'Adaptador',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(network['description']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: TgdeskColors.offline)),
                ])),
            _alertBadge(online ? 0 : 1, online ? 'Ativa' : 'Indisponível'),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: _networkValue(
                    'Velocidade', _bitSpeed(network['link_speed_bps']))),
            Expanded(child: _networkValue('Tráfego médio', _byteRate(average))),
            Expanded(child: _networkValue('Pico', _byteRate(max))),
            Expanded(
                child: _networkValue('Indisponível',
                    '${_num(stats['downtime_seconds']).round()} s')),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                color: color,
                backgroundColor: color.withOpacity(.14)),
          ),
        ]),
      ),
    );
  }

  Widget _networkValue(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ]);

  Widget _alertVisual(Map<String, dynamic> issue) {
    final level = _healthRank(issue['severity']?.toString());
    final color = _healthColor(level);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: color.withOpacity(.09),
        border: Border.all(color: color.withOpacity(.48)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: color.withOpacity(.15), shape: BoxShape.circle),
          child: Icon(
              level >= 2 ? Icons.error_outline : Icons.warning_amber_rounded,
              color: color),
        ),
        const SizedBox(width: 15),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(level >= 2 ? 'Ação prioritária' : 'Acompanhamento recomendado',
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(TgdeskHealthText.technical(Map<String, dynamic>.from(issue))),
        ])),
        Chip(label: Text(TgdeskHealthText.categoryLabel(issue['category']?.toString()))),
      ]),
    );
  }

  Widget _emptyAlerts() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
                color: TgdeskColors.online.withOpacity(.12),
                shape: BoxShape.circle),
            child: const Icon(Icons.verified_outlined,
                color: TgdeskColors.online, size: 46),
          ),
          const SizedBox(height: 16),
          const Text('Nenhum alerta técnico ativo',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          const Text('Todos os indicadores estão dentro do esperado.',
              style: TextStyle(color: Colors.grey)),
        ]),
      );

  Widget _visualMetric(
      String title, double value, String suffix, IconData icon, int level) {
    final unavailable = suffix.isEmpty;
    final color = unavailable ? TgdeskColors.guest : _healthColor(level);
    final progress = unavailable ? 0.0 : (value / 100).clamp(0, 1).toDouble();
    final state = unavailable
        ? 'Sem leitura'
        : level == 3
            ? 'Alerta máximo'
            : level == 2
                ? 'Crítico'
                : level == 1
                    ? 'Atenção'
                    : 'Normal';
    return Container(
      width: 198,
      height: 142,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        border: Border.all(color: color.withOpacity(.42)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ]),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(unavailable ? '—' : value.toStringAsFixed(1),
              style:
                  const TextStyle(fontSize: 27, fontWeight: FontWeight.w700)),
          if (!unavailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Text(suffix, style: TextStyle(color: TgdeskColors.offline)),
            ),
          const Spacer(),
          Text(state, style: TextStyle(color: color, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: progress,
            color: color,
            backgroundColor: color.withOpacity(.15),
          ),
        ),
      ]),
    );
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<dynamic> _list(dynamic value) => value is List ? value : const [];
  double _num(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  String _optionalPct(dynamic value) =>
      value is num ? '${value.toDouble().toStringAsFixed(1)}%' : 'N/D';
  String _clock(dynamic value) {
    if (value is! num || value <= 0) return 'N/D';
    final mhz = value.toDouble();
    return mhz >= 1000
        ? '${(mhz / 1000).toStringAsFixed(2)} GHz'
        : '${mhz.toStringAsFixed(0)} MHz';
  }

  String _bytes(dynamic value) {
    if (value is! num) return 'N/D';
    var bytes = value.toDouble();
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var unit = 0;
    while (bytes >= 1024 && unit < units.length - 1) {
      bytes /= 1024;
      unit++;
    }
       return '${bytes.toStringAsFixed(unit < 3 ? 0 : 1)} ${units[unit]}';
  }

  String _bitSpeed(dynamic value) {
    final bps = _num(value);
    if (bps >= 1e9) return '${(bps / 1e9).toStringAsFixed(1)} Gbps';
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(0)} Mbps';
    if (bps > 0) return '${(bps / 1e3).toStringAsFixed(0)} Kbps';
    return 'N/D';
  }

  String _byteRate(dynamic value) {
    final bytes = _num(value);
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB/s';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(1)} KB/s';
    return bytes > 0 ? '${bytes.toStringAsFixed(0)} B/s' : '0 B/s';
  }
}
