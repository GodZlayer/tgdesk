import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'theme.dart';
import 'branding_page.dart';

class TechniciansPage extends StatefulWidget {
  const TechniciansPage({super.key});
  @override
  State<TechniciansPage> createState() => _TechniciansPageState();
}

class _TechniciansPageState extends State<TechniciansPage> {
  List<dynamic> _techs = [];
  List<dynamic> _orgs = [];
  List<dynamic> _nets = [];
  List<dynamic> _assignments = [];
  List<dynamic> _nameStyles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final techs = await TgdeskApi.technicians();
      final orgs = await TgdeskApi.organizations();
      final nets = await TgdeskApi.networks();
      final assignments = await TgdeskApi.technicianAssignments();
      final styles = await TgdeskApi.technicianNameStyles();
      if (!mounted) return;
      setState(() {
        _techs = techs;
        _orgs = orgs;
        _nets = nets;
        _assignments = assignments;
        _nameStyles = styles;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickNameStyle(dynamic tech, String? style) async {
    try {
      if (style == null) {
        await TgdeskApi.clearTechnicianNameStyle(tech['id'] as String);
      } else {
        await TgdeskApi.setTechnicianNameStyle(tech['id'] as String, style);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openNameStyleDialog(dynamic tech) async {
    final username = tech['username']?.toString() ?? '';
    String? selected = tech['name_style']?.toString();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text('Como "${tech['display_name'] ?? tech['username']}" é exibido'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Escolha o padrão do nome. {nome} vira o apelido do técnico.'),
              const SizedBox(height: 12),
              RadioListTile<String?>(
                value: null,
                groupValue: selected,
                title: Text('Só o nome — sem extra'),
                onChanged: (v) => setLocal(() => selected = v),
              ),
              const Divider(height: 8),
              for (final st in _nameStyles)
                RadioListTile<String>(
                  value: st['key'] as String,
                  groupValue: selected,
                  title: Text(st['label'] as String),
                  subtitle: Text((st['template'] as String)
                      .replaceAll('{nome}', username)),
                  onChanged: (v) => setLocal(() => selected = v),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _pickNameStyle(tech, selected);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _openCreateDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Novo técnico'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                try {
                  await TgdeskApi.createTechnician(nameCtrl.text.trim());
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

  Future<void> _openAssignDialog(dynamic tech) async {
    String? orgId;
    String? netId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final netsOfOrg = orgId == null
            ? []
            : _nets.where((n) => n['organization_id'] == orgId).toList();
        return AlertDialog(
          title: Text('Atribuir escopo a "${tech['username']}"'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: orgId,
              decoration: const InputDecoration(labelText: 'Organização'),
              items: _orgs
                  .map<DropdownMenuItem<String>>((o) => DropdownMenuItem(
                      value: o['id'] as String,
                      child: Text(o['name'] as String)))
                  .toList(),
              onChanged: (v) => setLocal(() {
                orgId = v;
                netId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: netId,
              decoration: const InputDecoration(
                  labelText: 'Rede (opcional — vazio = organização inteira)'),
              items: netsOfOrg
                  .map<DropdownMenuItem<String>>((n) => DropdownMenuItem(
                      value: n['id'] as String,
                      child: Text(n['name'] as String)))
                  .toList(),
              onChanged: (v) => setLocal(() => netId = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (orgId == null) return;
                try {
                  await TgdeskApi.createAssignment(
                      tech['id'] as String, orgId, netId);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Atribuição criada')));
                } catch (e) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
              child: const Text('Atribuir'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _confirmSuspendTechnician(dynamic tech) async {
    final ok = await showTgdeskConfirmSuspendDialog(
        context, 'o técnico "${tech['username']}"');
    if (!ok) return;
    try {
      await TgdeskApi.suspendTechnician(tech['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _generateEnrollmentKey(dynamic tech) async {
    try {
      final key =
          await TgdeskApi.createTechnicianEnrollmentKey(tech['id'] as String);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar chave de técnico',
        fileName: 'TGDesk-${tech['username']}.tgdesk-key',
        type: FileType.custom,
        allowedExtensions: const ['tgdesk-key'],
      );
      if (path == null) return;
      await File(path).writeAsString(
          const JsonEncoder.withIndent('  ').convert(key),
          flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Chave criada. Ela poderá ser aplicada em um único computador.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _confirmDeleteTechnician(dynamic tech) async {
    final ok = await showTgdeskConfirmDeleteDialog(
        context, 'o técnico "${tech['username']}"');
    if (!ok) return;
    try {
      await TgdeskApi.deleteTechnician(tech['id'] as String);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _toggleBranding(dynamic tech) async {
    final enabled = tech['branding_enabled'] == true;
    try {
      await TgdeskApi.setTechnicianBrandingEnabled(
          tech['id'] as String, !enabled);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!enabled
              ? 'Personalização liberada para ${tech['username']}.'
              : 'Personalização desabilitada para ${tech['username']}.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openTechnicianBranding(dynamic tech) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 940,
          height: 650,
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: BrandingPage(
                technicianId: tech['id'] as String,
                technicianName: tech['username']?.toString(),
              ),
            ),
          ]),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo técnico'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _techs.length,
          itemBuilder: (ctx, i) {
            final t = _techs[i];
            final suspenso = t['status'] == 'suspenso';
            final scopes = _assignments
                .where((a) => a['technician_id'] == t['id'])
                .map((a) {
              final org = a['organization_name']?.toString() ?? '';
              final net = a['network_name']?.toString() ?? '';
              return net.isEmpty ? '$org (toda a organização)' : '$org / $net';
            }).toList();
            return Card(
              child: ListTile(
                leading: Icon(
                    t['role'] == 'super_admin' ? Icons.shield : Icons.person,
                    color: suspenso ? TgdeskColors.offline : null),
                title: Text(
                    (t['display_name']?.toString() ?? t['username']).toString()),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['role'] == 'super_admin'
                      ? 'Administrador · acesso total'
                      : scopes.isEmpty
                          ? 'Sem redes atribuídas · nenhum dispositivo ficará visível'
                          : 'Atende: ${scopes.join(' · ')}'),
                  if (t['name_style'] != null && t['display_name']?.toString() != t['username']?.toString())
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Exibido como "${t['display_name']}"',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TgdeskColors.online),
                      ),
                    ),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (t['role'] != 'super_admin')
                    IconButton(
                      icon: const Icon(Icons.badge_outlined),
                      tooltip: 'Escolher como o nome é exibido',
                      onPressed: suspenso
                          ? null
                          : () => _openNameStyleDialog(t),
                    ),
                  IconButton(
                    icon: const Icon(Icons.vpn_key_outlined),
                    tooltip: 'Gerar chave de uso único',
                    onPressed:
                        suspenso ? null : () => _generateEnrollmentKey(t),
                  ),
                  if (t['role'] != 'super_admin')
                    IconButton(
                      icon: const Icon(Icons.link),
                      tooltip: 'Atribuir organização/rede',
                      onPressed: () => _openAssignDialog(t),
                    ),
                  if (t['role'] != 'super_admin')
                    IconButton(
                      icon: Icon(
                        t['branding_enabled'] == true
                            ? Icons.toggle_on
                            : Icons.toggle_off,
                        color: t['branding_enabled'] == true
                            ? TgdeskColors.online
                            : TgdeskColors.offline,
                      ),
                      tooltip: t['branding_enabled'] == true
                          ? 'Desabilitar marca personalizada'
                          : 'Habilitar marca personalizada',
                      onPressed: suspenso ? null : () => _toggleBranding(t),
                    ),
                  if (t['role'] != 'super_admin')
                    IconButton(
                      icon: const Icon(Icons.palette_outlined),
                      tooltip: 'Editar identidade visual como administrador',
                      onPressed: () => _openTechnicianBranding(t),
                    ),
                  IconButton(
                    icon: Icon(
                        suspenso
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        color: suspenso
                            ? TgdeskColors.online
                            : TgdeskColors.suspended),
                    tooltip:
                        suspenso ? 'Reativar técnico' : 'Suspender técnico',
                    onPressed: () async {
                      if (suspenso) {
                        await TgdeskApi.resumeTechnician(t['id'] as String);
                        _load();
                      } else {
                        _confirmSuspendTechnician(t);
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_forever,
                        color: t['username'] == AppState.username
                            ? TgdeskColors.offline
                            : Colors.red.shade700),
                    tooltip: t['username'] == AppState.username
                        ? 'Não é possível apagar a própria conta'
                        : 'Apagar técnico',
                    onPressed: t['username'] == AppState.username
                        ? null
                        : () => _confirmDeleteTechnician(t),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
