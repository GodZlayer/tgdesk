import 'package:flutter/material.dart';

import 'admin_catalog_page.dart';
import 'api_client.dart';
import 'control_channel.dart';
import 'theme.dart';

enum OperationalCatalogSection { services, inventory }

/// Taxonomias operacionais. Valores pertencem somente a Precificação, onde são
/// definidos por região e faixa dinâmica de mínimo e máximo.
class AdminOperationalTypesTab extends StatelessWidget {
  const AdminOperationalTypesTab({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(tabs: [
              Tab(icon: Icon(Icons.category_outlined), text: 'Tipos de chamado'),
              Tab(icon: Icon(Icons.build_outlined), text: 'Tipos de serviço'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Peças / consumíveis'),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(TgdeskSpacing.md, TgdeskSpacing.sm, TgdeskSpacing.md, 0),
            child: Text('Use estas listas para organizar chamados e OS. Valores mínimos e máximos por região são definidos somente em Precificação.'),
          ),
          const Expanded(child: TabBarView(children: [
            AdminTicketTypesTab(),
            AdminOsCatalogTab(section: OperationalCatalogSection.services),
            AdminOsCatalogTab(section: OperationalCatalogSection.inventory),
          ])),
        ]),
      );
}

class AdminOsCatalogTab extends StatefulWidget {
  const AdminOsCatalogTab({super.key, required this.section});

  final OperationalCatalogSection section;

  @override
  State<AdminOsCatalogTab> createState() => _AdminOsCatalogTabState();
}

class _AdminOsCatalogTabState extends State<AdminOsCatalogTab> {
  final _channel = TgdeskControlChannel.instance;

  @override
  void initState() {
    super.initState();
    _channel.addListener(_onChannel);
  }

  @override
  void dispose() {
    _channel.removeListener(_onChannel);
    super.dispose();
  }

  void _onChannel() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServices = widget.section == OperationalCatalogSection.services;
    final consumables = _channel.parts.where((part) => part['item_kind']?.toString() == 'consumable').toList(growable: false);
    final parts = _channel.parts.where((part) => part['item_kind']?.toString() != 'consumable').toList(growable: false);
    final items = isServices ? _channel.services : <Map<String, dynamic>>[];
    return Scaffold(
      floatingActionButton: isServices
          ? FloatingActionButton.extended(heroTag: 'novo-servico', icon: const Icon(Icons.build_outlined), label: const Text('Tipo de serviço'), onPressed: () => _editService(null))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              FloatingActionButton.extended(heroTag: 'nova-peca', icon: const Icon(Icons.memory_outlined), label: const Text('Peça'), onPressed: () => _editPart(null)),
              const SizedBox(width: TgdeskSpacing.sm),
              FloatingActionButton.extended(heroTag: 'novo-consumivel', icon: const Icon(Icons.cable_outlined), label: const Text('Consumível'), onPressed: () => _editPart(null, initialKind: 'consumable')),
            ]),
      body: ListView(
        padding: const EdgeInsets.all(TgdeskSpacing.md),
        children: [
          if (isServices) ...[
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm), child: Text('Nenhum tipo de serviço cadastrado.'))
            else
              ...items.map(_serviceCard),
          ] else ...[
            Text('Tipos de peça', style: Theme.of(context).textTheme.titleSmall),
            if (parts.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm), child: Text('Nenhum tipo de peça cadastrado.'))
            else
              ...parts.map(_partCard),
            const SizedBox(height: TgdeskSpacing.lg),
            Text('Tipos de consumível', style: Theme.of(context).textTheme.titleSmall),
            if (consumables.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm), child: Text('Nenhum tipo de consumível cadastrado.'))
            else
              ...consumables.map(_partCard),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _scope(Map<String, dynamic> item) {
    final ticketType = item['ticket_type_key']?.toString();
    final mode = item['os_type']?.toString();
    return <String>[
      if (ticketType != null && ticketType.isNotEmpty) ticketType else 'todos os tipos',
      if (mode != null && mode.isNotEmpty) mode == 'onsite' ? 'presencial' : 'remoto',
    ].join(' · ');
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    final active = service['active'] != false;
    final manual = (service['manual_url']?.toString() ?? '').isNotEmpty;
    return Card(child: ListTile(
      leading: const Icon(Icons.build_outlined),
      title: Text(service['label']?.toString() ?? ''),
      subtitle: Text('${_scope(service)} · ${service['duration_min']} min${manual ? ' · com manual' : ''}'),
      enabled: active,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editService(service)),
        IconButton(tooltip: 'Remover', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _run(() => TgdeskApi.deleteService(service['id'].toString()))),
      ]),
    ));
  }

  Widget _partCard(Map<String, dynamic> part) {
    final active = part['active'] != false;
    final consumable = part['item_kind']?.toString() == 'consumable';
    return Card(child: ListTile(
      leading: Icon(consumable ? Icons.cable_outlined : Icons.memory_outlined),
      title: Text('${part['sku']} — ${part['label']}'),
      subtitle: Text(_scope(part)),
      enabled: active,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editPart(part)),
        IconButton(tooltip: 'Remover', icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _run(() => TgdeskApi.deletePart(part['id'].toString()))),
      ]),
    ));
  }

  Widget _ticketTypeDropdown(String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String?>(
    value: value,
    decoration: const InputDecoration(labelText: 'Vale para o tipo de chamado'),
    items: [
      const DropdownMenuItem(value: null, child: Text('Todos os tipos')),
      for (final type in _channel.ticketTypes) DropdownMenuItem(value: type['key']?.toString(), child: Text(type['label']?.toString() ?? '')),
    ],
    onChanged: onChanged,
  );

  Future<void> _editPart(Map<String, dynamic>? part, {String initialKind = 'part'}) async {
    final sku = TextEditingController(text: part?['sku']?.toString() ?? '');
    final label = TextEditingController(text: part?['label']?.toString() ?? '');
    final unit = TextEditingController(text: part?['unit']?.toString() ?? 'un');
    var ticketType = part?['ticket_type_key']?.toString();
    final itemKind = part?['item_kind']?.toString() ?? initialKind;
    var requiresInvoice = part?['requires_invoice_photo'] != false;
    var active = part?['active'] != false;
    final typeLabel = itemKind == 'consumable' ? 'consumível' : 'peça';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text(part == null ? 'Novo tipo de $typeLabel' : 'Editar tipo de $typeLabel'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: sku, enabled: part == null, decoration: const InputDecoration(labelText: 'SKU', helperText: 'Identidade do item; não muda depois')),
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Rótulo')),
        TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unidade')),
        const SizedBox(height: TgdeskSpacing.sm),
        _ticketTypeDropdown(ticketType, (value) => setLocal(() => ticketType = value)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Exige foto da nota fiscal'), value: requiresInvoice, onChanged: (value) => setLocal(() => requiresInvoice = value)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativo'), value: active, onChanged: (value) => setLocal(() => active = value)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar'))],
    )));
    if (ok != true) return;
    await _run(() => TgdeskApi.savePart({
      'sku': sku.text.trim(), 'label': label.text.trim(), 'unit': unit.text.trim(),
      'item_kind': itemKind, 'requires_invoice_photo': requiresInvoice,
      'ticket_type_key': ticketType, 'active': active,
    }));
  }

  Future<void> _editService(Map<String, dynamic>? service) async {
    final key = TextEditingController(text: service?['key']?.toString() ?? '');
    final label = TextEditingController(text: service?['label']?.toString() ?? '');
    final duration = TextEditingController(text: (service?['duration_min'] ?? 60).toString());
    final manual = TextEditingController(text: service?['manual_url']?.toString() ?? '');
    var ticketType = service?['ticket_type_key']?.toString();
    var mode = service?['os_type']?.toString();
    var active = service?['active'] != false;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
      title: Text(service == null ? 'Novo tipo de serviço' : 'Editar tipo de serviço'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: key, enabled: service == null, decoration: const InputDecoration(labelText: 'Chave', helperText: 'Sem espaço nem barra; não muda depois')),
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Rótulo')),
        TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duração (min)')),
        TextField(controller: manual, decoration: const InputDecoration(labelText: 'Manual (URL do PDF)', helperText: 'Material que o técnico consulta antes de executar')),
        const SizedBox(height: TgdeskSpacing.sm),
        _ticketTypeDropdown(ticketType, (value) => setLocal(() => ticketType = value)),
        DropdownButtonFormField<String?>(value: mode, decoration: const InputDecoration(labelText: 'Modalidade da OS'), items: const [DropdownMenuItem(value: null, child: Text('As duas')), DropdownMenuItem(value: 'virtual', child: Text('Remoto')), DropdownMenuItem(value: 'onsite', child: Text('Presencial'))], onChanged: (value) => setLocal(() => mode = value)),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Ativo'), value: active, onChanged: (value) => setLocal(() => active = value)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar'))],
    )));
    if (ok != true) return;
    await _run(() => TgdeskApi.saveService({
      'key': key.text.trim(), 'label': label.text.trim(),
      'duration_min': int.tryParse(duration.text.trim()) ?? 60, 'manual_url': manual.text.trim(),
      'ticket_type_key': ticketType, 'os_type': mode, 'active': active,
    }));
  }
}
