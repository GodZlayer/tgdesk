import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'admin_catalog_page.dart';
import 'admin_crm_services_tab.dart';
import 'admin_os_catalog_tab.dart';
import 'admin_regions_tab.dart';
import 'api_client.dart';
import 'theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminPage> {
  int _selected = 0;

  static const _items = <({String title, String subtitle, IconData icon})>[
    (
      title: 'Auditoria',
      subtitle: 'Eventos, rela\u{00e7}\u{00f5}es e vis\u{00e3}o executiva',
      icon: Icons.timeline_outlined
    ),
    (
      title: 'Regi\u{00f5}es',
      subtitle: 'Mapa, cidades e pre\u{00e7}o din\u{00e2}mico',
      icon: Icons.map_outlined
    ),
    (
      title: 'Cat\u{00e1}logo operacional',
      subtitle: 'Chamados, servi\u{00e7}os, pe\u{00e7}as e consum\u{00ed}veis',
      icon: Icons.inventory_2_outlined
    ),
    (
      title: 'Precifica\u{00e7}\u{00e3}o',
      subtitle: 'Percentuais e distribui\u{00e7}\u{00e3}o da OS',
      icon: Icons.percent_outlined
    ),
    (
      title: 'Taxas',
      subtitle: 'Distribui\u{00e7}\u{00e3}o do valor do servi\u{00e7}o',
      icon: Icons.account_balance_wallet_outlined
    ),
    (
      title: 'Vinculados',
      subtitle: 'Organiza\u{00e7}\u{00f5}es, redes e pessoas',
      icon: Icons.account_tree_outlined
    ),
    (
      title: 'Servi\u{00e7}os / CRM',
      subtitle: 'M\u{00e1}quinas-servidor dentro da VPN',
      icon: Icons.dns_outlined
    ),
  ];

  Widget _content() {
    switch (_selected) {
      case 0:
        return const _AuditEditor();
      case 1:
        return const AdminRegionsTab();
      case 2:
        return const AdminOperationalTypesTab();
      case 3:
        return const AdminPricingTab();
      case 4:
        return const _FeesEditor();
      case 5:
        return const _LinkedEditor();
      case 6:
        return const AdminCrmServicesTab();
      default:
        return const _LinkedEditor();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _items[_selected];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Row(children: [
        SizedBox(
          width: 292,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(right: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.dashboard_customize_outlined,
                              color: scheme.primary, size: 34),
                          const SizedBox(height: 12),
                          Text('Painel administrativo',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          const Text(
                              'Uma mesa visual para governar toda a operação TGDesk.'),
                        ]),
                  ),
                  Expanded(
                      child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final nav = _items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          selected: index == _selected,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          leading: Icon(nav.icon),
                          title: Text(nav.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(nav.subtitle),
                          onTap: () => setState(() => _selected = index),
                        ),
                      );
                    },
                  )),
                ]),
          ),
        ),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
                child: Row(children: [
                  Icon(item.icon, color: scheme.primary, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(item.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text(item.subtitle),
                      ])),
                  _KpiChip(
                      label: 'Servidor',
                      value: 'tempo real',
                      color: scheme.primary),
                  const SizedBox(width: 10),
                  _KpiChip(
                      label: 'Fonte',
                      value: 'regras server-side',
                      color: scheme.tertiary),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.all(20), child: _content())),
            ])),
      ]),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _LegacyAdminPage extends StatefulWidget {
  const _LegacyAdminPage({super.key});

  @override
  State<_LegacyAdminPage> createState() => _AdminPageState();
}

class _AdminSection {
  const _AdminSection({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.builder,
    this.badge,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
  final WidgetBuilder builder;
  final String? badge;
}

class _AdminPageState extends State<_LegacyAdminPage> {
  int _selected = 0;
  String _filter = '';
  String _slideTemplate = 'investor';
  int _slideDays = 30;
  bool _exporting = false;

  late final List<_AdminSection> _sections = [
    _AdminSection(
      key: 'audit',
      title: 'Auditoria',
      description:
          'Log separado por grau de relação para relatório comercial, compliance e captação.',
      icon: Icons.manage_search_outlined,
      builder: (_) => const _AuditEditor(),
      badge: 'somente leitura',
    ),
    _AdminSection(
      key: 'territory',
      title: 'Regiões',
      description:
          'Brasil, estados, municípios, capitais, regiões imediatas, intermediárias e metropolitanas.',
      icon: Icons.map_outlined,
      builder: (_) => const AdminRegionsTab(),
    ),
    _AdminSection(
      key: 'catalog',
      title: 'Serviços, peças e consumíveis',
      description:
          'Catálogo sem marca e sem preço final; usado pela OS para montar escopo e exigir evidências.',
      icon: Icons.inventory_2_outlined,
      builder: (_) =>
          const AdminOsCatalogTab(section: OperationalCatalogSection.services),
    ),
    _AdminSection(
      key: 'pricing',
      title: 'Percentuais e precificação',
      description:
          'Percentuais, escopos, vigência, mínimo/máximo regional e distribuição da grade de pagamento.',
      icon: Icons.percent_outlined,
      builder: (_) => const AdminPricingTab(),
    ),
    _AdminSection(
      key: 'ticket_types',
      title: 'Tipos de chamado',
      description:
          'Tipificação pré-planejada para software, hardware, troca de componentes e variações futuras.',
      icon: Icons.category_outlined,
      builder: (_) => const AdminTicketTypesTab(),
    ),
    _AdminSection(
      key: 'linked',
      title: 'Vinculados',
      description:
          'Organizações, redes, técnicos, supervisores e dispositivos no mesmo mapa operacional.',
      icon: Icons.account_tree_outlined,
      builder: (_) => const _LinkedEditor(),
    ),
    _AdminSection(
      key: 'crm_services',
      title: 'Serviços / CRM',
      description:
          'Máquinas-servidor que vivem dentro da VPN e podem ser alcançadas por qualquer dispositivo que peça.',
      icon: Icons.dns_outlined,
      builder: (_) => const AdminCrmServicesTab(),
    ),
    _AdminSection(
      key: 'quotas',
      title: 'Cotas e direito de uso',
      description:
          'Limites por organização e padrão do produto, separados da lógica de dinheiro.',
      icon: Icons.rule_folder_outlined,
      builder: (_) => const _QuotaEditor(),
    ),
  ];

  List<_AdminSection> get _visibleSections {
    final query = _filter.trim().toLowerCase();
    if (query.isEmpty) return _sections;
    return _sections
        .where((section) =>
            section.title.toLowerCase().contains(query) ||
            section.description.toLowerCase().contains(query) ||
            section.key.toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleSections;
    final selectedIndex =
        visible.isEmpty ? 0 : _selected.clamp(0, visible.length - 1).toInt();
    final selectedSection = visible.isEmpty ? null : visible[selectedIndex];
    return Row(
      children: [
        SizedBox(
          width: 330,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Painel administrativo absoluto',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          SizedBox(height: 6),
                          Text(
                              'Auditoria, regiões, catálogo, preço, chamados, vinculados e cotas em uma única mesa de decisão.'),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar configuração',
                      helperText: 'Um editor; sete domínios de configuração.',
                    ),
                    onChanged: (value) => setState(() {
                      _filter = value;
                      _selected = 0;
                    }),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final section = visible[index];
                      final selected = section.key == selectedSection?.key;
                      return _SectionTile(
                        section: section,
                        selected: selected,
                        onTap: () => setState(() => _selected = index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedSection == null
              ? const Center(child: Text('Nenhuma configuração encontrada.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                      child: _SectionHeader(
                        section: selectedSection,
                        template: _slideTemplate,
                        days: _slideDays,
                        exporting: _exporting,
                        onTemplateChanged: (value) =>
                            setState(() => _slideTemplate = value),
                        onDaysChanged: (value) =>
                            setState(() => _slideDays = value),
                        onExport: _exportSlideshow,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: selectedSection.builder(context)),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _exportSlideshow() async {
    setState(() => _exporting = true);
    try {
      final bytes = await TgdeskApi.downloadSlideshowPdf(
          template: _slideTemplate, days: _slideDays);
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          Directory.current.path;
      final dir = Directory('$home\\Downloads');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(
          '${dir.path}\\tgdesk-admin-$_slideTemplate-${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('PDF exportado: $file.path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao exportar PDF: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final _AdminSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: selected ? 2 : 0,
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surface,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(section.icon,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.primary),
        ),
        title: Text(section.title,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(section.description, maxLines: 2),
        trailing: section.badge == null
            ? null
            : Chip(
                label: Text(section.badge!),
                visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.template,
    required this.days,
    required this.exporting,
    required this.onTemplateChanged,
    required this.onDaysChanged,
    required this.onExport,
  });

  final _AdminSection section;
  final String template;
  final int days;
  final bool exporting;
  final ValueChanged<String> onTemplateChanged;
  final ValueChanged<int> onDaysChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(section.icon, size: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(section.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(section.description),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: template,
              items: const [
                DropdownMenuItem(value: 'investor', child: Text('Investidor')),
                DropdownMenuItem(value: 'board', child: Text('Conselho')),
                DropdownMenuItem(value: 'operations', child: Text('Operação')),
                DropdownMenuItem(value: 'commercial', child: Text('Comercial')),
              ],
              onChanged: (value) {
                if (value != null) onTemplateChanged(value);
              },
            ),
            DropdownButton<int>(
              value: days,
              items: const [7, 30, 90, 180, 365]
                  .map((value) => DropdownMenuItem(
                      value: value, child: Text('$value dias')))
                  .toList(),
              onChanged: (value) {
                if (value != null) onDaysChanged(value);
              },
            ),
            FilledButton.icon(
              onPressed: exporting ? null : onExport,
              icon: exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar slides PDF'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeesEditor extends StatefulWidget {
  const _FeesEditor();
  @override
  State<_FeesEditor> createState() => _FeesEditorState();
}

class _FeesEditorState extends State<_FeesEditor> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rules = const [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await TgdeskApi.pricingRules();
      if (mounted)
        setState(() {
          _rules = rows
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .where((r) => r['kind'] == 'share' || r['kind'] == 'fee')
              .toList();
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = '$e';
          _loading = false;
        });
    }
  }

  String _roleLabel(String role) =>
      const {
        'tgdesk': 'Taxa TGDesk',
        'supervisor': 'Supervisor da OS',
        'referrer_supervisor': 'Supervisor vinculador',
        'technician': 'Técnico executor'
      }[role] ??
      role;
  Future<void> _edit(String role, Map<String, dynamic>? previous) async {
    final percent = TextEditingController(text: '${previous?['percent'] ?? 0}');
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(role == 'payment'
                    ? 'Taxa do sistema de pagamento'
                    : _roleLabel(role)),
                content: TextField(
                    controller: percent,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Percentual sobre o serviço')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Salvar'))
                ]));
    if (ok == true) {
      final value = double.tryParse(percent.text.replaceAll(',', '.'));
      if (value == null || value < 0 || value > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Informe um percentual entre 0 e 100.')));
        }
        return;
      }
      double configured(String ruleRole) =>
          (_rules
                  .where((r) => r['kind'] == 'share' && r['role'] == ruleRole)
                  .firstOrNull?['percent'] as num?)
              ?.toDouble() ??
          0;
      final otherShares = ['tgdesk', 'supervisor', 'referrer_supervisor']
          .where((item) => item != role)
          .fold<double>(0, (sum, item) => sum + configured(item));
      final currentPayment = (_rules
                  .where((r) => r['kind'] == 'fee')
                  .firstOrNull?['percent'] as num?)
              ?.toDouble() ??
          0;
      final otherPayment = role == 'payment' ? 0 : currentPayment;
      if (role != 'technician' && value + otherShares + otherPayment > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('A soma das taxas não pode ultrapassar 100%.')));
        }
        return;
      }
      await TgdeskApi.savePricingRule({
        'id': previous?['id'],
        'kind': role == 'payment' ? 'fee' : 'share',
        'role': role == 'payment' ? null : role,
        'percent': value,
        'active': true,
        'note': 'Taxa de fluxo de pagamento'
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText(_error!));
    final roles = ['tgdesk', 'supervisor', 'referrer_supervisor', 'technician'];
    final payment = _rules.where((r) => r['kind'] == 'fee').firstOrNull;
    double share(String role) => ((_rules
                .where((r) => r['kind'] == 'share' && r['role'] == role)
                .firstOrNull?['percent'] as num?)
            ?.toDouble() ??
        0);
    final paymentPercent = (payment?['percent'] as num?)?.toDouble() ?? 0;
    final reserved = share('tgdesk') +
        share('supervisor') +
        share('referrer_supervisor') +
        paymentPercent;
    final technicianRemainder = (100 - reserved).clamp(0, 100).toDouble();
    return ListView(padding: const EdgeInsets.all(TgdeskSpacing.lg), children: [
      Text('Taxas e distribuição',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text(
          'Somente o valor de serviço é distribuído. Produtos e consumíveis ficam fora das taxas de comissão.'),
      const SizedBox(height: 20),
      for (final role in roles)
        () {
          var rule = _rules
              .where((r) => r['kind'] == 'share' && r['role'] == role)
              .firstOrNull;
          final isTechnician = role == 'technician';
          final shownPercent = isTechnician ? technicianRemainder : share(role);
          if (isTechnician) rule = {'percent': shownPercent};
          return Card(
              child: ListTile(
                  leading: Icon(isTechnician
                      ? Icons.engineering_outlined
                      : Icons.account_balance_wallet_outlined),
                  title: Text(_roleLabel(role)),
                  subtitle:
                      Text('${rule?['percent'] ?? 0}% do valor do serviço'),
                  trailing: isTechnician
                      ? const Icon(Icons.lock_outline)
                      : IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(role, rule))));
        }(),
      Card(
          child: ListTile(
              leading: const Icon(Icons.credit_card_outlined),
              title: const Text('Taxa do sistema de pagamento'),
              subtitle: Text(
                  '${payment?['percent'] ?? payment?['amount_cents'] ?? 0}${payment?['percent'] != null ? '%' : ' centavos'}'),
              trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit('payment', payment))))
    ]);
  }
}

class _AuditEditor extends StatefulWidget {
  const _AuditEditor();

  @override
  State<_AuditEditor> createState() => _AuditEditorState();
}

class _AuditEditorState extends State<_AuditEditor> {
  Map<String, dynamic>? _report;
  String? _error;
  bool _loading = true;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final report = await TgdeskApi.auditLiveReport(days: _days);
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = null;
      });
    } catch (e) {
      // A auditoria não pode virar uma tela cinza quando o agregado ainda não
      // está disponível: o log bruto continua sendo uma fonte válida de visão
      // operacional e mantém o painel útil durante recuperação do servidor.
      try {
        final events = await TgdeskApi.auditLog();
        final rows = events
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        final bySeverity = <String, int>{};
        final byDomain = <String, int>{};
        for (final row in rows) {
          final severity = row['severity']?.toString() ?? 'info';
          final domain = row['domain']?.toString() ??
              row['event_type']?.toString() ??
              'sistema';
          bySeverity[severity] = (bySeverity[severity] ?? 0) + 1;
          byDomain[domain] = (byDomain[domain] ?? 0) + 1;
        }
        if (mounted)
          setState(() {
            _report = {
              'title': 'Auditoria operacional TGDesk',
              'subtitle':
                  'Visão ao vivo baseada nos logs disponíveis do sistema.',
              'metrics': {'events': rows.length, ...bySeverity},
              'sections': [
                for (final entry in byDomain.entries)
                  {'key': entry.key, 'title': entry.key, 'count': entry.value}
              ],
              'recent_events': rows,
            };
            _error = null;
          });
      } catch (_) {
        if (mounted) setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    final report = _report ?? const <String, dynamic>{};
    final sections = (report['sections'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final events = (report['recent_events'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final metrics = Map<String, dynamic>.from(report['metrics'] as Map? ?? {});
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(TgdeskSpacing.lg),
        children: [
          _ExecutiveHero(
            title: report['title']?.toString() ?? 'Auditoria executiva TGDesk',
            subtitle: report['subtitle']?.toString() ?? '',
            days: _days,
            onDaysChanged: (days) {
              setState(() => _days = days);
              _load();
            },
          ),
          const SizedBox(height: TgdeskSpacing.lg),
          _MetricGrid(metrics: metrics),
          const SizedBox(height: TgdeskSpacing.lg),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 980;
            final chart = _DomainPieCard(
              sections: sections,
              onTap: _openDomain,
            );
            final domains = _DomainCards(
              sections: sections,
              onTap: _openDomain,
            );
            if (!wide) {
              return Column(
                  children: [chart, const SizedBox(height: 12), domains]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 390, child: chart),
              const SizedBox(width: 12),
              Expanded(child: domains),
            ]);
          }),
          const SizedBox(height: TgdeskSpacing.lg),
          _TimelineCard(events: events, onTap: _openEvent),
        ],
      ),
    );
  }

  Future<void> _openDomain(Map<String, dynamic> section) async {
    final domain = section['key']?.toString() ?? '';
    if (domain.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final events = await TgdeskApi.auditDomainEvents(domain, days: _days);
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (_) => _DomainDetailDialog(
          section: section,
          events: events
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
          onEvent: _openEvent,
        ),
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _openEvent(Map<String, dynamic> event) async {
    final id = event['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final detail = await TgdeskApi.auditEventDetail(id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _EventDetailDialog(detail: detail),
    );
  }
}

class _ExecutiveHero extends StatelessWidget {
  const _ExecutiveHero({
    required this.title,
    required this.subtitle,
    required this.days,
    required this.onDaysChanged,
  });

  final String title;
  final String subtitle;
  final int days;
  final ValueChanged<int> onDaysChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 12),
              const Wrap(spacing: 8, children: [
                Chip(label: Text('apresentação executiva')),
                Chip(label: Text('gráficos de pizza')),
                Chip(label: Text('drill-down por popup')),
                Chip(label: Text('dados do servidor')),
              ]),
            ]),
          ),
          DropdownButton<int>(
            value: days,
            items: const [7, 30, 90, 180, 365]
                .map((d) => DropdownMenuItem(value: d, child: Text('$d dias')))
                .toList(),
            onChanged: (value) {
              if (value != null) onDaysChanged(value);
            },
          ),
        ]),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final Map<String, dynamic> metrics;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Chamados',
        metrics['tickets_opened'],
        Icons.confirmation_number_outlined
      ),
      (
        'OS criadas',
        metrics['service_orders_created'],
        Icons.assignment_outlined
      ),
      (
        'Volume OS',
        _money(metrics['service_orders_total_cents']),
        Icons.payments_outlined
      ),
      (
        'Dispositivos ativos',
        metrics['active_devices'],
        Icons.devices_outlined
      ),
      (
        'Técnicos disponíveis',
        metrics['available_technicians'],
        Icons.engineering_outlined
      ),
      ('Regiões ativas', metrics['active_regions'], Icons.map_outlined),
      ('Organizações', metrics['organizations'], Icons.business_outlined),
      ('Riscos', metrics['risk_events'], Icons.warning_amber_outlined),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 1100
          ? 4
          : constraints.maxWidth > 720
              ? 2
              : 1;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3.2,
        children: [
          for (final item in items)
            Card(
              child: ListTile(
                leading: Icon(item.$3),
                title: Text(item.$1),
                subtitle: Text('${item.$2 ?? 0}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      );
    });
  }
}

class _DomainPieCard extends StatelessWidget {
  const _DomainPieCard({required this.sections, required this.onTap});
  final List<Map<String, dynamic>> sections;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Distribuição por domínio',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(
              height: 260,
              child: CustomPaint(
                  painter: _PiePainter(sections),
                  child: Center(
                      child: Text('${_total(sections)}\neventos',
                          textAlign: TextAlign.center)))),
          const SizedBox(height: 12),
          for (final section in sections.take(8))
            ListTile(
              dense: true,
              onTap: () => onTap(section),
              leading: Icon(Icons.circle,
                  color: _domainColor(section['key']?.toString() ?? '')),
              title: Text(section['label']?.toString() ??
                  section['key']?.toString() ??
                  ''),
              trailing: Text('${section['total_events'] ?? 0}'),
            ),
        ]),
      ),
    );
  }
}

class _DomainCards extends StatelessWidget {
  const _DomainCards({required this.sections, required this.onTap});
  final List<Map<String, dynamic>> sections;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: [
        for (final section in sections)
          Card(
            child: InkWell(
              onTap: () => onTap(section),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.circle,
                            size: 14,
                            color:
                                _domainColor(section['key']?.toString() ?? '')),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(section['label']?.toString() ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        Text('${section['recent_events'] ?? 0}'),
                      ]),
                      const SizedBox(height: 8),
                      Text(section['description']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      Text(
                          'riscos: ${section['risk_events'] ?? 0} · total: ${section['total_events'] ?? 0}'),
                    ]),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.events, required this.onTap});
  final List<Map<String, dynamic>> events;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Linha do tempo executiva',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final event in events)
            ListTile(
              onTap: () => onTap(event),
              leading:
                  Icon(_severityIcon(event['severity']?.toString() ?? 'info')),
              title: Text(event['event_type']?.toString() ?? 'evento'),
              subtitle: Text(
                  '${event['domain_label'] ?? event['domain_key']} · ${event['relation_degree'] ?? '-'}'),
              trailing: Text(_shortDate(event['created_at'])),
            ),
          if (events.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Sem eventos no período.')),
        ]),
      ),
    );
  }
}

class _DomainDetailDialog extends StatelessWidget {
  const _DomainDetailDialog(
      {required this.section, required this.events, required this.onEvent});
  final Map<String, dynamic> section;
  final List<Map<String, dynamic>> events;
  final ValueChanged<Map<String, dynamic>> onEvent;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(section['label']?.toString() ?? 'Domínio'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: ListView(children: [
          Text(section['description']?.toString() ?? ''),
          const SizedBox(height: 12),
          for (final event in events)
            ListTile(
              onTap: () => onEvent(event),
              leading:
                  Icon(_severityIcon(event['severity']?.toString() ?? 'info')),
              title: Text(event['event_type']?.toString() ?? 'evento'),
              subtitle: Text(
                  'entidade: ${event['entity_type'] ?? '-'} · ${event['entity_id'] ?? '-'}'),
              trailing: Text(_shortDate(event['created_at'])),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'))
      ],
    );
  }
}

class _EventDetailDialog extends StatelessWidget {
  const _EventDetailDialog({required this.detail});
  final Map<String, dynamic> detail;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(detail['event_type']?.toString() ?? 'Evento'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DetailLine(
                'Domínio', '${detail['domain_label'] ?? detail['domain_key']}'),
            _DetailLine('Relação', '${detail['relation_degree'] ?? '-'}'),
            _DetailLine('Severidade', '${detail['severity'] ?? '-'}'),
            _DetailLine('Entidade',
                '${detail['entity_type'] ?? '-'} · ${detail['entity_id'] ?? '-'}'),
            _DetailLine(
                'Ator técnico', '${detail['actor_technician_id'] ?? '-'}'),
            _DetailLine(
                'Dispositivo ator', '${detail['actor_device_id'] ?? '-'}'),
            _DetailLine('Organização', '${detail['organization_id'] ?? '-'}'),
            _DetailLine('Região', '${detail['region_id'] ?? '-'}'),
            const Divider(),
            Text('Payload profundo',
                style: Theme.of(context).textTheme.titleSmall),
            SelectableText('${detail['payload'] ?? {}}'),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'))
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: SelectableText(value)),
        ]),
      );
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.sections);
  final List<Map<String, dynamic>> sections;

  @override
  void paint(Canvas canvas, Size size) {
    final total = _total(sections);
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    var start = -1.5708;
    if (total <= 0) {
      paint.color = Colors.grey.shade300;
      canvas.drawArc(rect.deflate(18), 0, 6.283, true, paint);
      return;
    }
    for (final section in sections) {
      final value = (section['total_events'] as num?)?.toDouble() ?? 0;
      if (value <= 0) continue;
      final sweep = 6.28318530718 * value / total;
      paint.color = _domainColor(section['key']?.toString() ?? '');
      canvas.drawArc(rect.deflate(18), start, sweep, true, paint);
      start += sweep;
    }
    paint.color = Colors.white;
    canvas.drawCircle(rect.center, size.shortestSide * 0.23, paint);
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) =>
      oldDelegate.sections != sections;
}

int _total(List<Map<String, dynamic>> sections) => sections.fold<int>(0,
    (sum, section) => sum + ((section['total_events'] as num?)?.toInt() ?? 0));

Color _domainColor(String key) {
  const colors = <String, Color>{
    'connections': Color(0xFF2563EB),
    'bindings': Color(0xFF7C3AED),
    'financial': Color(0xFF059669),
    'service_orders': Color(0xFFF97316),
    'diagnostics': Color(0xFFDC2626),
    'territory': Color(0xFF0891B2),
    'catalog': Color(0xFF4B5563),
    'security': Color(0xFFB91C1C),
    'system': Color(0xFF64748B),
  };
  return colors[key] ?? Colors.blueGrey;
}

IconData _severityIcon(String severity) {
  switch (severity) {
    case 'critical':
    case 'warning':
      return Icons.warning_amber_outlined;
    case 'notice':
      return Icons.insights_outlined;
    default:
      return Icons.timeline_outlined;
  }
}

String _shortDate(dynamic value) {
  final text = value?.toString() ?? '';
  return text.length >= 16
      ? text.substring(0, 16).replaceFirst('T', ' ')
      : text;
}

String _money(dynamic cents) {
  final value = (cents as num?)?.toInt() ?? 0;
  return 'R\$ ${(value / 100).toStringAsFixed(2).replaceAll('.', ',')}';
}

class _LinkedEditor extends StatefulWidget {
  const _LinkedEditor();

  @override
  State<_LinkedEditor> createState() => _LinkedEditorState();
}

class _LinkedEditorState extends State<_LinkedEditor> {
  Map<String, dynamic>? _map;
  Map<String, dynamic>? _quotas;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _kind = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final loaded = await Future.wait<dynamic>([
        TgdeskApi.linkedMap(),
        TgdeskApi.quotas(),
      ]);
      final linked = loaded[0] as Map<String, dynamic>;
      final quotas = loaded[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _map = linked;
        _quotas = quotas;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      (_map?[key] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    final summary = Map<String, dynamic>.from(_map?['summary'] as Map? ?? {});
    final organizations = _list('organizations');
    final networks = _list('networks');
    final subnetworks = _list('subnetworks');
    final devices = _list('devices');
    final technicians = _list('technicians');
    final links = _list('links');
    final quotas = (_quotas?['organizations'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final all = <Map<String, dynamic>>[
      ...organizations,
      ...networks,
      ...subnetworks,
      ...devices,
      ...technicians,
    ].where(_matches).toList(growable: false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(TgdeskSpacing.lg),
        children: [
          _LinkedHero(summary: summary, nodes: all, onNode: _openNode),
          const SizedBox(height: TgdeskSpacing.md),
          Row(children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Buscar vinculado',
                  helperText:
                      'Organização, rede, subrede, dispositivo, técnico ou supervisor.',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _kind,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(
                    value: 'organization', child: Text('Organizações')),
                DropdownMenuItem(value: 'network', child: Text('Redes')),
                DropdownMenuItem(value: 'subnetwork', child: Text('Subredes')),
                DropdownMenuItem(value: 'device', child: Text('Dispositivos')),
                DropdownMenuItem(
                    value: 'technician', child: Text('Supervisores')),
              ],
              onChanged: (value) => setState(() => _kind = value ?? 'all'),
            ),
          ]),
          const SizedBox(height: TgdeskSpacing.lg),
          _OrganizationTree(
            organizations: organizations,
            networks: networks,
            subnetworks: subnetworks,
            devices: devices,
            technicians: technicians,
            quotas: quotas,
            onNode: _openNode,
            onQuota: _editQuota,
          ),
          const SizedBox(height: TgdeskSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(TgdeskSpacing.md),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.badge_outlined),
                      const SizedBox(width: 10),
                      Text('Técnicos, supervisores e permissões',
                          style: Theme.of(context).textTheme.titleLarge),
                    ]),
                    const SizedBox(height: 8),
                    const Text(
                        'Esta gestão saiu do menu lateral e agora pertence a Vinculados: técnicos, supervisores, branding, estilos de nome, chaves e vínculos ficam no mesmo contexto operacional.'),
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  bool _matches(Map<String, dynamic> node) {
    final kind = node['kind']?.toString() ?? '';
    if (_kind != 'all' && kind != _kind) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return node.values
        .any((value) => value?.toString().toLowerCase().contains(q) == true);
  }

  Future<void> _openNode(Map<String, dynamic> node) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LinkedNodeDialog(node: node, onAction: _runAction),
    );
  }

  Future<void> _runAction(String action, Map<String, dynamic> node) async {
    final id = node['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    if (action.startsWith('suspend_')) {
      final confirmed = await showTgdeskConfirmSuspendDialog(context,
          'o ${_linkedKindLabel(node['kind']?.toString() ?? '').toLowerCase()} "${_nodeTitle(node)}"');
      if (!confirmed) return;
    }
    try {
      if (action == 'suspend_device') {
        await TgdeskApi.suspendDevice(id);
      }
      if (action == 'suspend_technician') {
        await TgdeskApi.suspendTechnician(id);
      }
      if (action == 'suspend_organization') {
        await TgdeskApi.suspendOrganization(id);
      }
      if (action == 'suspend_network') {
        await TgdeskApi.suspendNetwork(id);
      }
      if (action == 'resume_device') {
        await TgdeskApi.resumeDevice(id);
      }
      if (action == 'resume_technician') {
        await TgdeskApi.resumeTechnician(id);
      }
      if (action == 'resume_organization') {
        await TgdeskApi.resumeOrganization(id);
      }
      if (action == 'resume_network') {
        await TgdeskApi.resumeNetwork(id);
      }
      if (action == 'suspend_subnetwork') {
        await TgdeskApi.suspendSubnetwork(id);
      }
      if (action == 'resume_subnetwork') {
        await TgdeskApi.resumeSubnetwork(id);
      }
      if (mounted) Navigator.pop(context);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(action.startsWith('resume_')
                ? '${_linkedKindLabel(node['kind']?.toString() ?? '')} reativado.'
                : '${_linkedKindLabel(node['kind']?.toString() ?? '')} suspenso.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Não foi possível concluir a ação: $error')));
      }
    }
  }

  Future<void> _editQuota(
      Map<String, dynamic> organization, Map<String, dynamic>? quota) async {
    final controllers = <String, TextEditingController>{
      'supervisors': TextEditingController(
          text: '${quota?['max_affiliated_supervisors'] ?? 0}'),
      'devices': TextEditingController(text: '${quota?['max_devices'] ?? ''}'),
    };
    final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Gerenciar ${_nodeTitle(organization)}'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: controllers['supervisors'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Cota de supervisores')),
                TextField(
                    controller: controllers['devices'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Cota de dispositivos')),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Salvar'))
              ],
            ));
    if (save == true) {
      await TgdeskApi.saveQuota({
        'organization_id': organization['id'],
        'max_affiliated_supervisors':
            int.tryParse(controllers['supervisors']!.text) ?? 0,
        'max_devices': int.tryParse(controllers['devices']!.text),
        'max_technicians': quota?['max_technicians'],
        'note': quota?['note']?.toString() ?? '',
      });
      await _load();
    }
  }
}

class _LinkedHero extends StatelessWidget {
  const _LinkedHero(
      {required this.summary, required this.nodes, required this.onNode});
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> nodes;
  final ValueChanged<Map<String, dynamic>> onNode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Estrutura operacional',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Gerencie a organização e seu supervisor no mesmo ponto. Redes, subredes e dispositivos ficam sob esse mesmo guarda-chuva.'),
          const SizedBox(height: 14),
          _OperationalMap(nodes: nodes, onNode: onNode),
        ]),
      ),
    );
  }
}

class _OperationalMap extends StatelessWidget {
  const _OperationalMap({required this.nodes, required this.onNode});
  final List<Map<String, dynamic>> nodes;
  final ValueChanged<Map<String, dynamic>> onNode;

  @override
  Widget build(BuildContext context) {
    const kinds = [
      'organization',
      'technician',
      'network',
      'subnetwork',
      'device'
    ];
    final total = nodes.length == 0 ? 1 : nodes.length;
    return SizedBox(
      height: 300,
      child: LayoutBuilder(
          builder: (context, constraints) => Stack(
                children: [
                  for (var i = 0; i < kinds.length; i++)
                    () {
                      final kind = kinds[i];
                      final entries =
                          nodes.where((node) => node['kind'] == kind).toList();
                      final count = entries.length;
                      final diameter = (76 + 110 * count / total)
                          .clamp(76.0, 150.0)
                          .toDouble();
                      final alignment = const [
                        Alignment(-.52, -.42),
                        Alignment(.52, -.52),
                        Alignment(.58, .38),
                        Alignment(-.42, .48),
                        Alignment(0, 0),
                      ][i];
                      return Align(
                        alignment: alignment,
                        child: Tooltip(
                          message:
                              'Abrir ${_linkedKindLabel(kind).toLowerCase()}s',
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: entries.isEmpty
                                ? null
                                : () => onNode(entries.first),
                            child: Container(
                              width: diameter,
                              height: diameter,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _linkedColor(kind).withOpacity(.28),
                                border: Border.all(
                                    color: _linkedColor(kind), width: 2),
                              ),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_linkedIcon(kind),
                                        color: _linkedColor(kind)),
                                    Text('$count',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800)),
                                    Text(_linkedKindLabel(kind),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ]),
                            ),
                          ),
                        ),
                      );
                    }(),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Text(
                        'Clique em uma bolha para abrir a gestão do grupo.',
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ],
              )),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label),
            const SizedBox(height: 6),
            Text('$value',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _LinkedGraphCard extends StatelessWidget {
  const _LinkedGraphCard(
      {required this.nodes, required this.links, required this.onTap});
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> links;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    final byKind = <String, int>{};
    for (final node in nodes) {
      final kind = node['kind']?.toString() ?? 'unknown';
      byKind[kind] = (byKind[kind] ?? 0) + 1;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mapa operacional',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
              height: 280,
              child: CustomPaint(
                  painter: _LinkedMapPainter(byKind),
                  child: Center(
                      child: Text(
                          '${nodes.length}\nnós\n${links.length} vínculos',
                          textAlign: TextAlign.center)))),
          const SizedBox(height: 12),
          for (final entry in byKind.entries)
            ListTile(
              dense: true,
              leading:
                  Icon(_linkedIcon(entry.key), color: _linkedColor(entry.key)),
              title: Text(_linkedKindLabel(entry.key)),
              trailing: Text('${entry.value}'),
            ),
        ]),
      ),
    );
  }
}

class _LinkedListCard extends StatelessWidget {
  const _LinkedListCard(
      {required this.nodes, required this.links, required this.onTap});
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> links;
  final ValueChanged<Map<String, dynamic>> onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Todos os vinculados',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final node in nodes.take(220))
            ListTile(
              onTap: () => onTap(node),
              leading: Icon(_linkedIcon(node['kind']?.toString() ?? ''),
                  color: _linkedColor(node['kind']?.toString() ?? '')),
              title: Text(_nodeTitle(node)),
              subtitle: Text(_nodeSubtitle(node, links)),
              trailing: const Icon(Icons.chevron_right),
            ),
          if (nodes.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhum vinculado encontrado.')),
        ]),
      ),
    );
  }
}

class _OrganizationTree extends StatelessWidget {
  const _OrganizationTree(
      {required this.organizations,
      required this.networks,
      required this.subnetworks,
      required this.devices,
      required this.technicians,
      required this.quotas,
      required this.onNode,
      required this.onQuota});
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> networks;
  final List<Map<String, dynamic>> subnetworks;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> technicians;
  final List<Map<String, dynamic>> quotas;
  final ValueChanged<Map<String, dynamic>> onNode;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>?)
      onQuota;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Árvore de vínculo',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final org in organizations)
            () {
              final quota = quotas.where((item) =>
                  item['organization_id']?.toString() == org['id']?.toString());
              final organizationQuota = quota.isEmpty ? null : quota.first;
              return ExpansionTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(_nodeTitle(org)),
                subtitle: Text(
                    'redes: ${org['networks_count'] ?? 0} · dispositivos: ${org['devices_count'] ?? 0} · supervisores: ${org['technicians_count'] ?? 0}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Cotas e supervisor',
                      icon: const Icon(Icons.tune_outlined),
                      onPressed: () => onQuota(org, organizationQuota)),
                  IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => onNode(org)),
                ]),
                children: [
                  for (final tech in technicians.where((t) =>
                      t['organization_id']?.toString() ==
                      org['id']?.toString()))
                    ListTile(
                        contentPadding:
                            const EdgeInsets.only(left: 48, right: 16),
                        leading: const Icon(Icons.engineering_outlined),
                        title: Text(_nodeTitle(tech)),
                        subtitle:
                            Text('supervisor: ${tech['supervisor_id'] ?? '-'}'),
                        onTap: () => onNode(tech),
                        trailing: IconButton(
                            tooltip: 'Gerenciar supervisor',
                            icon: const Icon(Icons.tune_outlined),
                            onPressed: () => onNode(tech))),
                  for (final net in networks.where((n) =>
                      n['organization_id']?.toString() ==
                      org['id']?.toString()))
                    ExpansionTile(
                      leading: const Icon(Icons.lan_outlined),
                      title: Text(_nodeTitle(net)),
                      subtitle: Text('status: ${net['status'] ?? '-'}'),
                      trailing: IconButton(
                          tooltip: 'Gerenciar rede',
                          icon: const Icon(Icons.tune_outlined),
                          onPressed: () => onNode(net)),
                      children: [
                        for (final sub in subnetworks.where((s) =>
                            s['network_id']?.toString() ==
                            net['id']?.toString()))
                          ExpansionTile(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: Text(_nodeTitle(sub)),
                            subtitle: Text('status: ${sub['status'] ?? '-'}'),
                            trailing: IconButton(
                                tooltip: 'Gerenciar sub-rede',
                                icon: const Icon(Icons.tune_outlined),
                                onPressed: () => onNode(sub)),
                            children: [
                              for (final dev in devices.where((d) =>
                                  d['subnetwork_id']?.toString() ==
                                  sub['id']?.toString()))
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                      left: 108, right: 16),
                                  leading: const Icon(Icons.computer_outlined),
                                  title: Text(_nodeTitle(dev)),
                                  subtitle:
                                      Text('estado: ${dev['state'] ?? '-'}'),
                                  onTap: () => onNode(dev),
                                  trailing: IconButton(
                                      tooltip: 'Gerenciar dispositivo',
                                      icon: const Icon(Icons.tune_outlined),
                                      onPressed: () => onNode(dev)),
                                ),
                            ],
                          ),
                        for (final dev in devices.where((d) =>
                            d['network_id']?.toString() ==
                                net['id']?.toString() &&
                            (d['subnetwork_id'] == null ||
                                d['subnetwork_id'].toString().isEmpty)))
                          ListTile(
                              contentPadding:
                                  const EdgeInsets.only(left: 72, right: 16),
                              leading: const Icon(Icons.computer_outlined),
                              title: Text(_nodeTitle(dev)),
                              subtitle: Text(
                                  'estado: ${dev['state'] ?? '-'} · RustDesk: ${dev['rustdesk_id'] ?? '-'}'),
                              onTap: () => onNode(dev),
                              trailing: IconButton(
                                  tooltip: 'Gerenciar dispositivo',
                                  icon: const Icon(Icons.tune_outlined),
                                  onPressed: () => onNode(dev))),
                      ],
                    ),
                ],
              );
            }(),
        ]),
      ),
    );
  }
}

class _LinkedNodeDialog extends StatelessWidget {
  const _LinkedNodeDialog({required this.node, required this.onAction});
  final Map<String, dynamic> node;
  final Future<void> Function(String action, Map<String, dynamic> node)
      onAction;

  @override
  Widget build(BuildContext context) {
    final kind = node['kind']?.toString() ?? '';
    final suspended = _nodeIsSuspended(node);
    final action = suspended ? 'resume_$kind' : 'suspend_$kind';
    return AlertDialog(
      title: Text(_nodeTitle(node)),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DetailLine('Tipo', _linkedKindLabel(kind)),
            _DetailLine('ID', '${node['id'] ?? '-'}'),
            for (final entry in node.entries)
              if (!['kind', 'id'].contains(entry.key))
                _DetailLine(entry.key, '${entry.value ?? '-'}'),
          ]),
        ),
      ),
      actions: [
        if (const {
          'device',
          'technician',
          'organization',
          'network',
          'subnetwork'
        }.contains(kind))
          TextButton(
            onPressed: () => onAction(action, node),
            child: Text(suspended
                ? 'Reativar ${_linkedKindLabel(kind).toLowerCase()}'
                : 'Suspender ${_linkedKindLabel(kind).toLowerCase()}'),
          ),
        if (kind == '__legacy_device__')
          TextButton(
              onPressed: () => onAction(action, node),
              child: Text(suspended
                  ? 'Reativar dispositivo'
                  : 'Suspender dispositivo')),
        if (kind == '__legacy_technician__')
          TextButton(
              onPressed: () => onAction(action, node),
              child: const Text('Suspender técnico')),
        if (kind == '__legacy_organization__')
          TextButton(
              onPressed: () => onAction(action, node),
              child: const Text('Suspender organização')),
        if (kind == '__legacy_network__')
          TextButton(
              onPressed: () => onAction(action, node),
              child: Text(suspended ? 'Reativar rede' : 'Suspender rede')),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar')),
      ],
    );
  }
}

bool _nodeIsSuspended(Map<String, dynamic> node) {
  final kind = node['kind']?.toString();
  final state = node['state']?.toString();
  final status = node['status']?.toString();
  if (kind == 'device') return state == 'suspenso';
  // Supervisors/technicians use the masculine status (`suspenso`), while
  // organizations and networks use the feminine status (`suspensa`). Keep
  // both forms here so the action button always mirrors the server state.
  if (kind == 'technician') {
    return status == 'suspenso' || status == 'suspensa';
  }
  return status == 'suspensa' || state == 'suspenso';
}

class _LinkedMapPainter extends CustomPainter {
  _LinkedMapPainter(this.byKind);
  final Map<String, int> byKind;

  @override
  void paint(Canvas canvas, Size size) {
    final total = byKind.values.fold<int>(0, (a, b) => a + b);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.36;
    final paint = Paint()..style = PaintingStyle.fill;
    var index = 0;
    for (final entry in byKind.entries) {
      final angle =
          byKind.length <= 1 ? 0.0 : 6.28318530718 * index / byKind.length;
      final distance =
          total == 0 ? 0.0 : radius * (0.55 + 0.45 * entry.value / total);
      final offset = center +
          Offset(distance * math.cos(angle), distance * math.sin(angle));
      paint.color = _linkedColor(entry.key).withOpacity(0.24);
      canvas.drawCircle(
          offset, 30 + entry.value.clamp(0, 60).toDouble(), paint);
      paint.color = _linkedColor(entry.key);
      canvas.drawCircle(offset, 9, paint);
      paint.color = Colors.grey.withOpacity(0.35);
      paint.strokeWidth = 2;
      canvas.drawLine(center, offset, paint..style = PaintingStyle.stroke);
      paint.style = PaintingStyle.fill;
      index++;
    }
    paint.color = Colors.black.withOpacity(0.08);
    canvas.drawCircle(center, 54, paint);
  }

  @override
  bool shouldRepaint(covariant _LinkedMapPainter oldDelegate) =>
      oldDelegate.byKind != byKind;
}

String _nodeTitle(Map<String, dynamic> node) {
  return (node['name'] ??
          node['display_name'] ??
          node['hostname'] ??
          node['username'] ??
          node['id'] ??
          'Vinculado')
      .toString();
}

String _nodeSubtitle(
    Map<String, dynamic> node, List<Map<String, dynamic>> links) {
  final id = node['id']?.toString();
  final related = links
      .where((link) =>
          link['from_id']?.toString() == id || link['to_id']?.toString() == id)
      .length;
  return '${_linkedKindLabel(node['kind']?.toString() ?? '')} · vínculos: $related · status: ${node['status'] ?? node['state'] ?? '-'}';
}

String _linkedKindLabel(String kind) {
  switch (kind) {
    case 'organization':
      return 'Organização';
    case 'network':
      return 'Rede';
    case 'subnetwork':
      return 'Subrede';
    case 'device':
      return 'Dispositivo';
    case 'technician':
      return 'Supervisor';
    default:
      return 'Vinculado';
  }
}

IconData _linkedIcon(String kind) {
  switch (kind) {
    case 'organization':
      return Icons.business_outlined;
    case 'network':
      return Icons.lan_outlined;
    case 'subnetwork':
      return Icons.account_tree_outlined;
    case 'device':
      return Icons.computer_outlined;
    case 'technician':
      return Icons.engineering_outlined;
    default:
      return Icons.hub_outlined;
  }
}

Color _linkedColor(String kind) {
  switch (kind) {
    case 'organization':
      return const Color(0xFF2563EB);
    case 'network':
      return const Color(0xFF0891B2);
    case 'subnetwork':
      return const Color(0xFF7C3AED);
    case 'device':
      return const Color(0xFF059669);
    case 'technician':
      return const Color(0xFFF97316);
    default:
      return Colors.blueGrey;
  }
}

class _QuotaEditor extends StatefulWidget {
  const _QuotaEditor();

  @override
  State<_QuotaEditor> createState() => _QuotaEditorState();
}

class _QuotaEditorState extends State<_QuotaEditor> {
  Map<String, dynamic>? _quotas;
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
      final quotas = await TgdeskApi.quotas();
      if (!mounted) return;
      setState(() {
        _quotas = quotas;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDefault() async {
    final current = _quotas?['default_max_affiliated_supervisors'] ?? 0;
    final controller = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Padrão do produto'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Supervisores vinculados por organização',
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
    );
    if (ok != true) return;
    await TgdeskApi.saveProductDefaults(int.tryParse(controller.text) ?? 0);
    await _load();
  }

  Future<void> _editQuota(Map<String, dynamic> quota) async {
    final maxAffiliated = TextEditingController(
        text: '${quota['max_affiliated_supervisors'] ?? 0}');
    final maxTechnicians =
        TextEditingController(text: quota['max_technicians']?.toString() ?? '');
    final maxDevices =
        TextEditingController(text: quota['max_devices']?.toString() ?? '');
    final note = TextEditingController(text: quota['note']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cota de ${quota['organization_name']}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: maxAffiliated,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Supervisores vinculados'),
              ),
              TextField(
                controller: maxTechnicians,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Técnicos máximos'),
              ),
              TextField(
                controller: maxDevices,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Dispositivos máximos'),
              ),
              TextField(
                controller: note,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Observação comercial'),
              ),
            ],
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
    );
    if (ok != true) return;
    await TgdeskApi.saveQuota({
      'organization_id': quota['organization_id'],
      'max_affiliated_supervisors': int.tryParse(maxAffiliated.text) ?? 0,
      'max_technicians': int.tryParse(maxTechnicians.text),
      'max_devices': int.tryParse(maxDevices.text),
      'note': note.text.trim(),
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: TgdeskErrorText('Erro: $_error'));
    final organizations = (_quotas?['organizations'] as List? ?? const []);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(TgdeskSpacing.md),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Padrão do produto'),
              subtitle: Text(
                  '${_quotas?['default_max_affiliated_supervisors'] ?? 0} supervisor(es) vinculado(s) quando a organização herda o padrão.'),
              trailing: FilledButton.icon(
                onPressed: _editDefault,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final quota in organizations.cast<Map>())
            Card(
              child: ListTile(
                leading: Icon(quota['using_default'] == true
                    ? Icons.link_outlined
                    : Icons.tune_outlined),
                title: Text(
                    quota['organization_name']?.toString() ?? 'Organização'),
                subtitle: Text([
                  'uso: ${quota['used_affiliated_supervisors'] ?? 0}/${quota['max_affiliated_supervisors'] ?? 0} supervisores',
                  quota['using_default'] == true
                      ? 'herdando padrão'
                      : 'cota própria',
                  if ((quota['note']?.toString() ?? '').isNotEmpty)
                    quota['note'].toString(),
                ].join(' · ')),
                trailing: IconButton(
                  tooltip: 'Editar cota',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editQuota(Map<String, dynamic>.from(quota)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
