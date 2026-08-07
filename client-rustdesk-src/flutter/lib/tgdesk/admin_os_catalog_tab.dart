import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'money.dart';
import 'theme.dart';

/// Onde o admin cadastra o que pode entrar num orçamento e por quanto.
///
/// É o que substitui o técnico digitando preço: uma vez cadastrado aqui, o
/// item aparece no construtor de OS com o valor já definido. Peça tem custo e
/// preço separados porque a margem é o que a precificação divide entre as
/// classes — sem custo não há margem para dividir. Serviço tem duração e
/// manual, que é o PDF que o técnico consulta antes de executar.
///
/// Como as outras abas do admin, lê do canal e escreve por rota: o que está na
/// tela é o mesmo dado que decide o comportamento em produção.
class AdminOsCatalogTab extends StatefulWidget {
  const AdminOsCatalogTab({super.key});

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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _channel.parts;
    final consumables = parts
        .where((part) => part['item_kind']?.toString() == 'consumable')
        .toList(growable: false);
    final physicalParts = parts
        .where((part) => part['item_kind']?.toString() != 'consumable')
        .toList(growable: false);
    final services = _channel.services;
    return Scaffold(
      floatingActionButton: Row(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.extended(
          heroTag: 'novo-servico',
          onPressed: () => _editService(null),
          icon: const Icon(Icons.build_outlined),
          label: const Text('Serviço'),
        ),
        const SizedBox(width: TgdeskSpacing.sm),
        FloatingActionButton.extended(
          heroTag: 'nova-peca',
          onPressed: () => _editPart(null),
          icon: const Icon(Icons.memory_outlined),
          label: const Text('Peça'),
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(TgdeskSpacing.md),
        children: [
          Text('Serviços', style: Theme.of(context).textTheme.titleSmall),
          if (services.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm),
              child: Text('Nenhum serviço cadastrado.'),
            )
          else
            ...services.map(_serviceCard),
          const SizedBox(height: TgdeskSpacing.lg),
          Text('Pe?as', style: Theme.of(context).textTheme.titleSmall),
          if (physicalParts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm),
              child: Text('Nenhuma pe?a cadastrada.'),
            )
          else
            ...physicalParts.map(_partCard),
          const SizedBox(height: TgdeskSpacing.lg),
          Text('Consum?veis', style: Theme.of(context).textTheme.titleSmall),
          if (consumables.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm),
              child: Text('Nenhum consum?vel cadastrado.'),
            )
          else
            ...consumables.map(_partCard),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _escopo(Map<String, dynamic> item) {
    final tipo = item['ticket_type_key']?.toString();
    final modo = item['os_type']?.toString();
    return <String>[
      if (tipo != null && tipo.isNotEmpty) tipo else 'todos os tipos',
      if (modo != null && modo.isNotEmpty)
        modo == 'onsite' ? 'presencial' : 'remoto',
    ].join(' · ');
  }

  Widget _serviceCard(Map<String, dynamic> service) {
    final ativo = service['active'] != false;
    final temManual = (service['manual_url']?.toString() ?? '').isNotEmpty;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.build_outlined),
        title: Text(service['label']?.toString() ?? ''),
        subtitle: Text('${_escopo(service)} · ${service['duration_min']} min'
            '${temManual ? ' · com manual' : ''}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(moeda((service['price_cents'] as num?)?.toInt() ?? 0),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ativo ? null : TgdeskColors.offline)),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editService(service),
          ),
          IconButton(
            tooltip: 'Remover',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () =>
                _run(() => TgdeskApi.deleteService(service['id'].toString())),
          ),
        ]),
      ),
    );
  }

  Widget _partCard(Map<String, dynamic> part) {
    final ativo = part['active'] != false;
    final custo = (part['cost_cents'] as num?)?.toInt() ?? 0;
    final consumable = part['item_kind']?.toString() == 'consumable';
    return Card(
      child: ListTile(
        leading:
            Icon(consumable ? Icons.cable_outlined : Icons.memory_outlined),
        title: Text('${part['sku']} — ${part['label']}'),
        subtitle: Text('${_escopo(part)}'
            '${custo > 0 ? ' · custo ${moeda(custo)}' : ''}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(moeda((part['price_cents'] as num?)?.toInt() ?? 0),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ativo ? null : TgdeskColors.offline)),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editPart(part),
          ),
          IconButton(
            tooltip: 'Remover',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () =>
                _run(() => TgdeskApi.deletePart(part['id'].toString())),
          ),
        ]),
      ),
    );
  }

  /// Menu de tipo de chamado com "todos" no topo. Os tipos vêm do canal, então
  /// um tipo novo cadastrado na outra aba aparece aqui sem recarregar nada.
  Widget _tipoDropdown(String? valor, ValueChanged<String?> aoMudar) =>
      DropdownButtonFormField<String?>(
        value: valor,
        decoration: const InputDecoration(labelText: 'Vale para o tipo'),
        items: [
          const DropdownMenuItem(value: null, child: Text('Todos os tipos')),
          for (final tipo in _channel.ticketTypes)
            DropdownMenuItem(
              value: tipo['key']?.toString(),
              child: Text(tipo['label']?.toString() ?? ''),
            ),
        ],
        onChanged: aoMudar,
      );

  Future<void> _editPart(Map<String, dynamic>? part) async {
    final sku = TextEditingController(text: part?['sku']?.toString() ?? '');
    final label = TextEditingController(text: part?['label']?.toString() ?? '');
    final unit = TextEditingController(text: part?['unit']?.toString() ?? 'un');
    final preco = TextEditingController(
        text: part == null
            ? ''
            : moeda((part['price_cents'] as num?)?.toInt() ?? 0));
    final custo = TextEditingController(
        text: part == null
            ? ''
            : moeda((part['cost_cents'] as num?)?.toInt() ?? 0));
    var tipo = part?['ticket_type_key']?.toString();
    var itemKind = part?['item_kind']?.toString() ?? 'part';
    var requiresInvoice = part?['requires_invoice_photo'] != false;
    var ativo = part?['active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(part == null ? 'Nova peça' : 'Editar peça'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: sku,
                  enabled: part == null,
                  decoration: const InputDecoration(
                      labelText: 'SKU',
                      helperText: 'Identidade da peça; não muda depois'),
                ),
                TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Rótulo')),
                TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: 'Unidade')),
                DropdownButtonFormField<String>(
                  value: itemKind,
                  decoration: const InputDecoration(labelText: 'Tipo de item'),
                  items: const [
                    DropdownMenuItem(value: 'part', child: Text('Peça')),
                    DropdownMenuItem(
                        value: 'consumable', child: Text('Consumível')),
                  ],
                  onChanged: (v) => setLocal(() => itemKind = v ?? 'part'),
                ),
                TextField(
                    controller: preco,
                    decoration:
                        const InputDecoration(labelText: 'Preço de venda')),
                TextField(
                  controller: custo,
                  decoration: const InputDecoration(
                      labelText: 'Custo',
                      helperText: 'É a margem que a precificação divide'),
                ),
                const SizedBox(height: TgdeskSpacing.sm),
                _tipoDropdown(tipo, (v) => setLocal(() => tipo = v)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exige foto da nota fiscal'),
                  subtitle: const Text(
                      'Obrigatória para entrar no custo final do atendimento.'),
                  value: requiresInvoice,
                  onChanged: (v) => setLocal(() => requiresInvoice = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativa'),
                  value: ativo,
                  onChanged: (v) => setLocal(() => ativo = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => TgdeskApi.savePart({
          'sku': sku.text.trim(),
          'label': label.text.trim(),
          'unit': unit.text.trim(),
          'item_kind': itemKind,
          'requires_invoice_photo': requiresInvoice,
          'price_cents': centavosDe(preco.text) ?? 0,
          'cost_cents': centavosDe(custo.text) ?? 0,
          'ticket_type_key': tipo,
          'active': ativo,
        }));
  }

  Future<void> _editService(Map<String, dynamic>? service) async {
    final key = TextEditingController(text: service?['key']?.toString() ?? '');
    final label =
        TextEditingController(text: service?['label']?.toString() ?? '');
    final preco = TextEditingController(
        text: service == null
            ? ''
            : moeda((service['price_cents'] as num?)?.toInt() ?? 0));
    final duracao = TextEditingController(
        text: (service?['duration_min'] ?? 60).toString());
    final manual =
        TextEditingController(text: service?['manual_url']?.toString() ?? '');
    var tipo = service?['ticket_type_key']?.toString();
    var modo = service?['os_type']?.toString();
    var ativo = service?['active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(service == null ? 'Novo serviço' : 'Editar serviço'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: key,
                  enabled: service == null,
                  decoration: const InputDecoration(
                      labelText: 'Chave',
                      helperText: 'Sem espaço nem barra; não muda depois'),
                ),
                TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Rótulo')),
                TextField(
                    controller: preco,
                    decoration: const InputDecoration(labelText: 'Preço')),
                TextField(
                    controller: duracao,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Duração (min)')),
                TextField(
                  controller: manual,
                  decoration: const InputDecoration(
                      labelText: 'Manual (URL do PDF)',
                      helperText: 'O que o técnico consulta antes de executar'),
                ),
                const SizedBox(height: TgdeskSpacing.sm),
                _tipoDropdown(tipo, (v) => setLocal(() => tipo = v)),
                DropdownButtonFormField<String?>(
                  value: modo,
                  decoration:
                      const InputDecoration(labelText: 'Modalidade da OS'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('As duas')),
                    DropdownMenuItem(value: 'virtual', child: Text('Remoto')),
                    DropdownMenuItem(
                        value: 'onsite', child: Text('Presencial')),
                  ],
                  onChanged: (v) => setLocal(() => modo = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: ativo,
                  onChanged: (v) => setLocal(() => ativo = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => TgdeskApi.saveService({
          'key': key.text.trim(),
          'label': label.text.trim(),
          'price_cents': centavosDe(preco.text) ?? 0,
          'duration_min': int.tryParse(duracao.text.trim()) ?? 60,
          'manual_url': manual.text.trim(),
          'ticket_type_key': tipo,
          'os_type': modo,
          'active': ativo,
        }));
  }
}
