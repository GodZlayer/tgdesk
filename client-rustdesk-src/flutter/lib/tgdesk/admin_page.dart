import 'package:flutter/material.dart';
import 'api_client.dart';
import 'theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<dynamic> _orgs = [];
  List<dynamic> _nets = [];
  List<dynamic> _devices = [];
  List<dynamic> _audit = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgs = await TgdeskApi.organizations();
      final nets = await TgdeskApi.networks();
      final devices = await TgdeskApi.devices();
      final audit = await TgdeskApi.auditLog();
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _nets = nets;
        _devices = devices;
        _audit = audit;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmSuspend(
      String label, Future<void> Function() action) async {
    final ok = await showTgdeskConfirmSuspendDialog(context, label);
    if (!ok) return;
    try {
      await action();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _confirmDelete(
      String label, Future<void> Function() action) async {
    final ok = await showTgdeskConfirmDeleteDialog(context, label);
    if (!ok) return;
    try {
      await action();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openCreateOrgDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova organização'),
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nome')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              try {
                await TgdeskApi.createOrganization(nameCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('Erro: $e')));
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateNetDialog() async {
    final nameCtrl = TextEditingController();
    String? orgId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Nova rede'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: orgId,
              decoration: const InputDecoration(labelText: 'Organização'),
              items: _orgs
                  .map<DropdownMenuItem<String>>((o) => DropdownMenuItem(
                      value: o['id'] as String,
                      child: Text(o['name'] as String)))
                  .toList(),
              onChanged: (v) => setLocal(() => orgId = v),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Nome da rede/loja')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (orgId == null || nameCtrl.text.trim().isEmpty) return;
                try {
                  await TgdeskApi.createNetwork(
                      orgId!, nameCtrl.text.trim(), '');
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
              child: const Text('Criar'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _openRenameDialog({
    required String title,
    required String currentName,
    required Future<void> Function(String name) onSave,
  }) async {
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Novo nome'),
          onSubmitted: (_) {},
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
                await onSave(name);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Organizações & Redes'),
          Tab(text: 'Auditoria'),
        ]),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            _buildOrgsTab(),
            _buildAuditTab(),
          ]),
        ),
      ],
    );
  }

  Widget _buildOrgsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    return Scaffold(
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'new-org',
            onPressed: _openCreateOrgDialog,
            icon: const Icon(Icons.add_business),
            label: const Text('Organização'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'new-net',
            onPressed: _openCreateNetDialog,
            icon: const Icon(Icons.add_location_alt),
            label: const Text('Rede'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          for (final org in _orgs) _buildOrgCard(org),
        ]),
      ),
    );
  }

  Widget _buildOrgCard(dynamic org) {
    final nets = _nets.where((n) => n['organization_id'] == org['id']).toList();
    final suspended = org['status'] == 'suspensa';
    return Card(
      child: ExpansionTile(
        title: Text(org['name'] as String,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('status: ${org['status']}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (org['owner_technician_id'] == null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Renomear organização',
              onPressed: () => _openRenameDialog(
                title: 'Renomear organização',
                currentName: org['name'] as String,
                onSave: (name) =>
                    TgdeskApi.renameOrganization(org['id'] as String, name),
              ),
            ),
          IconButton(
            icon: Icon(
                suspended ? Icons.play_circle_outline : Icons.pause_circle,
                color:
                    suspended ? TgdeskColors.online : TgdeskColors.suspended),
            tooltip:
                suspended ? 'Reativar organização' : 'Suspender organização',
            onPressed: () => suspended
                ? _runAction(
                    () => TgdeskApi.resumeOrganization(org['id'] as String))
                : _confirmSuspend('a organização "${org['name']}"',
                    () => TgdeskApi.suspendOrganization(org['id'] as String)),
          ),
          IconButton(
            icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
            tooltip: 'Excluir organização, redes e desvincular dispositivos',
            onPressed: () => _confirmDelete(
                'a organização "${org['name']}", suas redes e desvincular todos os dispositivos',
                () => TgdeskApi.deleteOrganization(org['id'] as String)),
          ),
        ]),
        children: nets.map<Widget>(_buildNetworkAdminTile).toList(),
      ),
    );
  }

  Widget _buildNetworkAdminTile(dynamic network) {
    final devices =
        _devices.where((d) => d['network_id'] == network['id']).toList();
    final suspended = network['status'] == 'suspensa';
    return ExpansionTile(
      leading: Icon(Icons.lan_outlined,
          color: suspended ? TgdeskColors.suspended : TgdeskColors.online),
      title: Text('${network['name']}  (${network['cidr_virtual'] ?? '-'})'),
      subtitle: Text(
          'status: ${network['status']} · ${devices.length} dispositivo(s)'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Renomear rede',
          onPressed: () => _openRenameDialog(
            title: 'Renomear rede',
            currentName: network['name'] as String,
            onSave: (name) =>
                TgdeskApi.renameNetwork(network['id'] as String, name),
          ),
        ),
        IconButton(
          icon: Icon(suspended ? Icons.play_circle_outline : Icons.pause_circle,
              color: suspended ? TgdeskColors.online : TgdeskColors.warning),
          tooltip: suspended ? 'Reativar rede' : 'Suspender rede',
          onPressed: () => suspended
              ? _runAction(
                  () => TgdeskApi.resumeNetwork(network['id'] as String))
              : _confirmSuspend('a rede "${network['name']}"',
                  () => TgdeskApi.suspendNetwork(network['id'] as String)),
        ),
        IconButton(
          icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
          tooltip: 'Excluir rede e desvincular dispositivos',
          onPressed: () => _confirmDelete(
              'a rede "${network['name']}". Seus dispositivos voltarão ao pareamento',
              () => TgdeskApi.deleteNetwork(network['id'] as String)),
        ),
      ]),
      children: devices.map<Widget>((device) {
        final deviceSuspended = device['state'] == 'suspenso';
        final hostname = device['hostname']?.toString() ?? '?';
        final alias = device['display_name']?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 54, right: 18),
          leading: Icon(Icons.computer,
              color: deviceSuspended
                  ? TgdeskColors.suspended
                  : TgdeskColors.online),
          title: Text(alias.isEmpty ? hostname : alias),
          subtitle: Text(alias.isEmpty
              ? 'status: ${device['state']}'
              : 'Windows: $hostname · status: ${device['state']}'),
          trailing: IconButton(
            icon: Icon(
                deviceSuspended
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                color: deviceSuspended
                    ? TgdeskColors.online
                    : TgdeskColors.warning),
            tooltip: deviceSuspended
                ? 'Reativar dispositivo'
                : 'Suspender dispositivo',
            onPressed: () => deviceSuspended
                ? _runAction(
                    () => TgdeskApi.resumeDevice(device['id'] as String))
                : _confirmSuspend(
                    'o dispositivo "${alias.isEmpty ? hostname : alias}"',
                    () => TgdeskApi.suspendDevice(device['id'] as String)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAuditTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _audit.length,
        itemBuilder: (ctx, i) {
          final a = _audit[i];
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(a['tipo'] as String),
            subtitle: Text('alvo: ${a['alvo_id']} · ator: ${a['actor_id']}'),
            trailing: Text((a['timestamp'] as String)
                .substring(0, 19)
                .replaceFirst('T', ' ')),
          );
        },
      ),
    );
  }
}
