import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'theme.dart';

/// Onde o admin edita o que o produto sabe atender e por quanto.
///
/// As duas abas leem do canal e escrevem por rota. O que elas mostram é o
/// mesmo dado que decide o comportamento em produção — não há um segundo
/// lugar onde tipo ou preço estejam escritos.

// ---------------------------------------------------------------------------
// Tipos de chamado
// ---------------------------------------------------------------------------

class AdminTicketTypesTab extends StatefulWidget {
  const AdminTicketTypesTab({super.key});

  @override
  State<AdminTicketTypesTab> createState() => _AdminTicketTypesTabState();
}

class _AdminTicketTypesTabState extends State<AdminTicketTypesTab> {
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
    final tipos = _channel.ticketTypes;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'novo-tipo',
        onPressed: () => _editType(null),
        icon: const Icon(Icons.add),
        label: const Text('Tipo de chamado'),
      ),
      body: tipos.isEmpty
          ? Center(
              child: Text(_channel.connected
                  ? 'Nenhum tipo cadastrado.'
                  : 'Reconectando ao servidor...'))
          : ListView(
              padding: const EdgeInsets.all(TgdeskSpacing.md),
              children: [
                for (final tipo in tipos) _typeCard(tipo),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _typeCard(Map<String, dynamic> tipo) {
    final ativo = tipo['active'] != false;
    final campos = (tipo['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    return Card(
      margin: const EdgeInsets.only(bottom: TgdeskSpacing.sm),
      child: ExpansionTile(
        leading: Icon(Icons.category_outlined,
            color: ativo ? TgdeskColors.seed : Colors.grey),
        title: Text(tipo['label']?.toString() ?? ''),
        subtitle: Text(ativo
            ? '${tipo['key']} — ${campos.length} campo(s)'
            : '${tipo['key']} — desativado'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Editar tipo',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editType(tipo),
          ),
          IconButton(
            tooltip: 'Excluir tipo',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _run(() =>
                TgdeskApi.deleteTicketType(tipo['key'].toString())),
          ),
        ]),
        children: [
          for (final campo in campos)
            ListTile(
              dense: true,
              leading: Icon(
                  campo['required'] == true
                      ? Icons.star
                      : Icons.star_border_outlined,
                  size: 18),
              title: Text(campo['label']?.toString() ?? ''),
              subtitle: Text([
                campo['field_key']?.toString() ?? '',
                campo['kind']?.toString() ?? '',
                if ((campo['depends_on']?.toString() ?? '').isNotEmpty)
                  'só quando ${campo['depends_on']} = ${campo['depends_value']}',
                if (campo['active'] == false) 'desativado',
              ].join(' · ')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () =>
                      _editField(tipo['key'].toString(), campo),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _run(() => TgdeskApi
                      .deleteTicketTypeField(campo['id'].toString())),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(TgdeskSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editField(tipo['key'].toString(), null),
                icon: const Icon(Icons.add),
                label: const Text('Campo'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editType(Map<String, dynamic>? tipo) async {
    final novo = tipo == null;
    final key = TextEditingController(text: tipo?['key']?.toString() ?? '');
    final label = TextEditingController(text: tipo?['label']?.toString() ?? '');
    final icon = TextEditingController(
        text: tipo?['icon']?.toString() ?? 'devices_other');
    final position =
        TextEditingController(text: (tipo?['position'] ?? 100).toString());
    var ativo = tipo?['active'] != false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(novo ? 'Novo tipo de chamado' : 'Editar tipo'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: key,
                enabled: novo,
                decoration: const InputDecoration(
                  labelText: 'Chave',
                  helperText: 'Não muda depois: os chamados apontam para ela.',
                ),
              ),
              TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Rótulo')),
              TextField(
                controller: icon,
                decoration: const InputDecoration(
                    labelText: 'Ícone', helperText: 'Nome do ícone Material.'),
              ),
              TextField(
                  controller: position,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ordem')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo'),
                subtitle: const Text(
                    'Desativado some dos formulários sem apagar o histórico.'),
                value: ativo,
                onChanged: (value) => setDialogState(() => ativo = value),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _run(() => TgdeskApi.saveTicketType({
                      'key': key.text.trim(),
                      'label': label.text.trim(),
                      'icon': icon.text.trim(),
                      'position': int.tryParse(position.text) ?? 100,
                      'active': ativo,
                    }));
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editField(String typeKey, Map<String, dynamic>? campo) async {
    final novo = campo == null;
    final fieldKey =
        TextEditingController(text: campo?['field_key']?.toString() ?? '');
    final label = TextEditingController(text: campo?['label']?.toString() ?? '');
    final help = TextEditingController(text: campo?['help']?.toString() ?? '');
    final position =
        TextEditingController(text: (campo?['position'] ?? 100).toString());
    final dependsOn =
        TextEditingController(text: campo?['depends_on']?.toString() ?? '');
    final dependsValue =
        TextEditingController(text: campo?['depends_value']?.toString() ?? '');
    // Uma opção por linha, "valor|rótulo" — o formato mais curto que ainda
    // deixa o rótulo diferente do valor guardado.
    final options = TextEditingController(
        text: (campo?['options'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => '${item['value']}|${item['label']}')
            .join('\n'));
    var kind = campo?['kind']?.toString() ?? 'text';
    var required = campo?['required'] == true;
    var ativo = campo?['active'] != false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(novo ? 'Novo campo' : 'Editar campo'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: fieldKey,
                    enabled: novo,
                    decoration:
                        const InputDecoration(labelText: 'Chave do campo')),
                TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Rótulo')),
                TextField(
                    controller: help,
                    decoration:
                        const InputDecoration(labelText: 'Texto de ajuda')),
                DropdownButtonFormField<String>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Natureza'),
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Texto')),
                    DropdownMenuItem(
                        value: 'multiline', child: Text('Texto longo')),
                    DropdownMenuItem(value: 'number', child: Text('Número')),
                    DropdownMenuItem(value: 'bool', child: Text('Sim/Não')),
                    DropdownMenuItem(value: 'choice', child: Text('Escolha')),
                    DropdownMenuItem(value: 'date', child: Text('Data')),
                    DropdownMenuItem(
                        value: 'attachment', child: Text('Anexo')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? 'text'),
                ),
                if (kind == 'choice')
                  TextField(
                    controller: options,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Opções',
                      helperText: 'Uma por linha, no formato valor|rótulo.',
                    ),
                  ),
                TextField(
                    controller: position,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Ordem')),
                const SizedBox(height: TgdeskSpacing.sm),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Condição — deixe em branco para o campo sempre aparecer.'),
                ),
                TextField(
                  controller: dependsOn,
                  decoration: const InputDecoration(
                    labelText: 'Só aparece quando o campo',
                    helperText:
                        'Outro campo deste tipo, ou modality/standalone/priority.',
                  ),
                ),
                TextField(
                    controller: dependsValue,
                    decoration:
                        const InputDecoration(labelText: 'estiver com o valor')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Obrigatório'),
                  subtitle: const Text(
                      'Só cobra quando a condição acima está satisfeita.'),
                  value: required,
                  onChanged: (value) => setDialogState(() => required = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  value: ativo,
                  onChanged: (value) => setDialogState(() => ativo = value),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _run(() => TgdeskApi.saveTicketTypeField({
                      'type_key': typeKey,
                      'field_key': fieldKey.text.trim(),
                      'label': label.text.trim(),
                      'help': help.text.trim(),
                      'kind': kind,
                      'options': _parseOptions(options.text),
                      'required': required,
                      'depends_on': dependsOn.text.trim().isEmpty
                          ? null
                          : dependsOn.text.trim(),
                      'depends_value': dependsValue.text.trim().isEmpty
                          ? null
                          : dependsValue.text.trim(),
                      'position': int.tryParse(position.text) ?? 100,
                      'active': ativo,
                    }));
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, String>> _parseOptions(String raw) => raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        final parts = line.split('|');
        final value = parts.first.trim();
        return {
          'value': value,
          'label': parts.length > 1 ? parts[1].trim() : value,
        };
      })
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Precificação
// ---------------------------------------------------------------------------

/// Cada linha aqui é uma regra: quanto uma classe recebe, quanto o admin
/// retira, uma promoção, ou os limites entre os quais o valor dinâmico varia.
/// Vence a mais específica que casa com o chamado e está vigente — a lista
/// aparece nessa mesma ordem, então o que está em cima é o que manda.
class AdminPricingTab extends StatefulWidget {
  const AdminPricingTab({super.key});

  @override
  State<AdminPricingTab> createState() => _AdminPricingTabState();
}

class _AdminPricingTabState extends State<AdminPricingTab> {
  final _channel = TgdeskControlChannel.instance;

  static const _kinds = {
    'share': 'Percentual de uma classe',
    'fee': 'Taxa do admin',
    'promo': 'Promoção',
    'bounds': 'Limites do valor dinâmico',
  };

  static const _roles = {
    'super_admin': 'Admin',
    'supervisor': 'Supervisor',
    'freelancer': 'Técnico',
    'cliente': 'Cliente',
    'cliente_avulso': 'Cliente avulso',
  };

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
    final rules = _channel.pricingRules;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nova-regra',
        onPressed: () => _editRule(null),
        icon: const Icon(Icons.add),
        label: const Text('Regra'),
      ),
      body: rules.isEmpty
          ? Center(
              child: Text(_channel.connected
                  ? 'Nenhuma regra cadastrada — vale o padrão do sistema.'
                  : 'Reconectando ao servidor...'))
          : ListView.separated(
              padding: const EdgeInsets.all(TgdeskSpacing.md),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, index) => _ruleCard(rules[index]),
            ),
    );
  }

  Widget _ruleCard(Map<String, dynamic> rule) {
    final kind = rule['kind']?.toString() ?? '';
    final ativo = rule['active'] != false;
    return Card(
      child: ListTile(
        leading: Icon(
          switch (kind) {
            'share' => Icons.pie_chart_outline,
            'fee' => Icons.account_balance_outlined,
            'promo' => Icons.local_offer_outlined,
            _ => Icons.straighten,
          },
          color: ativo ? TgdeskColors.seed : Colors.grey,
        ),
        title: Text(_ruleTitle(rule)),
        subtitle: Text([
          _scopeOf(rule),
          if (!ativo) 'inativa',
          'especificidade ${rule['specificity'] ?? 0}',
          if (rule['note']?.toString().isNotEmpty == true) rule['note'],
        ].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editRule(rule),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () =>
                _run(() => TgdeskApi.deletePricingRule(rule['id'].toString())),
          ),
        ]),
      ),
    );
  }

  String _ruleTitle(Map<String, dynamic> rule) {
    final percent = rule['percent'];
    final amount = rule['amount_cents'];
    switch (rule['kind']?.toString()) {
      case 'share':
        return '${_roles[rule['role']] ?? rule['role']} recebe $percent%';
      case 'fee':
        return percent != null
            ? 'Taxa do admin: $percent%'
            : 'Taxa do admin: ${_money(amount)}';
      case 'promo':
        return percent != null
            ? 'Promoção: $percent% de desconto'
            : 'Promoção: ${_money(amount)} de desconto';
      default:
        return 'Valor entre ${_money(rule['min_cents'])} e '
            '${_money(rule['max_cents'])}';
    }
  }

  String _money(dynamic cents) {
    if (cents == null) return '—';
    final value = (cents is num ? cents : num.tryParse('$cents') ?? 0) / 100;
    return 'R\$ ${value.toStringAsFixed(2)}';
  }

  /// O escopo em palavras. "Tudo" significa regra global: nenhuma coluna de
  /// escopo preenchida, então ela vale enquanto nenhuma mais específica casar.
  String _scopeOf(Map<String, dynamic> rule) {
    final partes = <String>[
      if (rule['ticket_type_key'] != null) 'tipo ${rule['ticket_type_key']}',
      if (rule['organization_id'] != null) 'organização',
      if (rule['network_id'] != null) 'rede',
      if (rule['subnetwork_id'] != null) 'subrede',
      if (rule['technician_id'] != null) 'técnico',
      if (rule['standalone'] == true) 'avulso',
      if (rule['standalone'] == false) 'empresarial',
    ];
    final vigencia = [
      if (rule['valid_from'] != null)
        'de ${rule['valid_from'].toString().split('T').first}',
      if (rule['valid_until'] != null)
        'até ${rule['valid_until'].toString().split('T').first}',
    ].join(' ');
    return [
      partes.isEmpty ? 'tudo' : partes.join(' + '),
      if (vigencia.isNotEmpty) vigencia,
    ].join(' · ');
  }

  Future<void> _editRule(Map<String, dynamic>? rule) async {
    var kind = rule?['kind']?.toString() ?? 'share';
    var role = rule?['role']?.toString();
    String? typeKey = rule?['ticket_type_key']?.toString();
    // 'null' = os dois; true = só avulso; false = só empresarial.
    bool? standalone = rule?['standalone'] as bool?;
    var ativo = rule?['active'] != false;

    final percent =
        TextEditingController(text: rule?['percent']?.toString() ?? '');
    final amount = TextEditingController(
        text: _reais(rule?['amount_cents']));
    final minimo = TextEditingController(text: _reais(rule?['min_cents']));
    final maximo = TextEditingController(text: _reais(rule?['max_cents']));
    final note = TextEditingController(text: rule?['note']?.toString() ?? '');
    final from = TextEditingController(
        text: rule?['valid_from']?.toString().split('T').first ?? '');
    final until = TextEditingController(
        text: rule?['valid_until']?.toString().split('T').first ?? '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule == null ? 'Nova regra' : 'Editar regra'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: kind,
                  decoration: const InputDecoration(labelText: 'Natureza'),
                  items: _kinds.entries
                      .map((entry) => DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => kind = value ?? 'share'),
                ),
                if (kind == 'share')
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Classe'),
                    items: _roles.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) => setDialogState(() => role = value),
                  ),
                if (kind != 'bounds')
                  TextField(
                      controller: percent,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Percentual (%)')),
                if (kind == 'fee' || kind == 'promo')
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Valor fixo (R\$)',
                      helperText: 'Use percentual ou valor fixo.',
                    ),
                  ),
                if (kind == 'bounds') ...[
                  TextField(
                      controller: minimo,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Mínimo (R\$)')),
                  TextField(
                    controller: maximo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Máximo (R\$)',
                      helperText: 'A dinâmica trabalha entre esses valores.',
                    ),
                  ),
                ],
                const Divider(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Escopo — em branco vale para tudo. Quanto mais preenchido, '
                      'mais específico, e o mais específico vence.'),
                ),
                DropdownButtonFormField<String>(
                  value: typeKey,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de chamado (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ..._channel.ticketTypes.map((tipo) => DropdownMenuItem(
                        value: tipo['key']?.toString(),
                        child: Text(tipo['label']?.toString() ?? ''))),
                  ],
                  onChanged: (value) => setDialogState(() => typeKey = value),
                ),
                DropdownButtonFormField<bool?>(
                  value: standalone,
                  decoration:
                      const InputDecoration(labelText: 'Origem do chamado'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Ambos')),
                    DropdownMenuItem(value: false, child: Text('Empresarial')),
                    DropdownMenuItem(value: true, child: Text('Avulso')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => standalone = value),
                ),
                // Organização, rede, subrede e técnico ficam de fora deste
                // diálogo por enquanto: escolhê-los pede um seletor com busca,
                // e o esquema já aceita os quatro — é tela, não modelo.
                const Divider(height: 24),
                TextField(
                  controller: from,
                  decoration: const InputDecoration(
                    labelText: 'Vale a partir de (AAAA-MM-DD)',
                    helperText: 'Em branco: desde sempre.',
                  ),
                ),
                TextField(
                  controller: until,
                  decoration: const InputDecoration(
                    labelText: 'Vale até (AAAA-MM-DD)',
                    helperText: 'Em branco: sem prazo.',
                  ),
                ),
                TextField(
                    controller: note,
                    decoration: const InputDecoration(labelText: 'Observação')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativa'),
                  value: ativo,
                  onChanged: (value) => setDialogState(() => ativo = value),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _run(() => TgdeskApi.savePricingRule({
                      if (rule?['id'] != null) 'id': rule!['id'],
                      'kind': kind,
                      'role': kind == 'share' ? role : null,
                      'ticket_type_key': typeKey,
                      'standalone': standalone,
                      'percent': double.tryParse(percent.text.trim()),
                      'amount_cents': _cents(amount.text),
                      'min_cents': _cents(minimo.text),
                      'max_cents': _cents(maximo.text),
                      'valid_from': _date(from.text),
                      'valid_until': _date(until.text),
                      'note': note.text.trim(),
                      'active': ativo,
                    }));
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  String _reais(dynamic cents) {
    if (cents == null) return '';
    final value = (cents is num ? cents : num.tryParse('$cents') ?? 0) / 100;
    return value.toStringAsFixed(2);
  }

  int? _cents(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    return value == null ? null : (value * 100).round();
  }

  /// A data vira instante em UTC: o servidor guarda TIMESTAMPTZ, e mandar só
  /// "AAAA-MM-DD" deixaria o fuso a cargo de quem lê.
  String? _date(String raw) {
    return DateTime.tryParse(raw.trim())?.toUtc().toIso8601String();
  }
}
