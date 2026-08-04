import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'theme.dart';
import 'ui_contract.dart';

class DiagnosticDialog extends StatefulWidget {
  const DiagnosticDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.online,
  });

  final String deviceId;
  final String deviceName;
  final bool online;

  @override
  State<DiagnosticDialog> createState() => _DiagnosticDialogState();
}

class _DiagnosticDialogState extends State<DiagnosticDialog> {
  final _control = TgdeskControlChannel.instance;
  List<dynamic> _catalog = const [];
  List<Map<String, dynamic>> _runs = const [];
  Map<String, dynamic> _health = const {};
  bool _loading = true;
  bool _catalogCollapsed = false;
  bool _selectionMode = false;
  final Set<String> _selectedTests = {};
  final Map<String, bool> _expandedGroups = {};
  String? _error;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _control.addListener(_onControl);
    unawaited(_load());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _control.removeListener(_onControl);
    super.dispose();
  }

  Future<T> _withRetry<T>(Future<T> Function() request) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await request().timeout(TgdeskDiagnosticPolicy.loadTimeout);
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 500 << attempt));
        }
      }
    }
    throw lastError!;
  }

  void _scheduleAutomaticRetry() {
    if (!widget.online || _retryTimer?.isActive == true) return;
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _error != null) unawaited(_load(showLoading: false));
    });
  }

  Future<void> _load({bool showLoading = true}) async {
    if (mounted && showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await Future.wait([
        _withRetry(TgdeskApi.diagnosticCatalog),
        _withRetry(() => TgdeskApi.diagnostics(widget.deviceId)),
        _withRetry(() => TgdeskApi.deviceHealth(widget.deviceId)),
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = List<dynamic>.from(data[0] as List);
        _runs = (data[1] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _health = Map<String, dynamic>.from(data[2] as Map);
        _error = null;
      });
      _retryTimer?.cancel();
    } catch (e) {
      if (mounted) {
        setState(() => _error = TgdeskDiagnosticPolicy.loadErrorMessage(e));
        _scheduleAutomaticRetry();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onControl() {
    if (!mounted) return;
    final updates = _control.diagnosticRuns[widget.deviceId];
    if (updates == null || updates.isEmpty) return;
    setState(() {
      final byId = {for (final run in _runs) run['id']?.toString(): run};
      for (final entry in updates.entries) {
        byId[entry.key] = <String, dynamic>{
          ...?byId[entry.key],
          ...entry.value,
        };
      }
      _runs = byId.values.toList()
        ..sort((a, b) => (b['created_at']?.toString() ?? '')
            .compareTo(a['created_at']?.toString() ?? ''));
    });
  }

  Future<void> _start(Map<String, dynamic> test) async {
    final impact = test['impact']?.toString() ?? 'low';
    if (!widget.online) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O dispositivo precisa estar online.')));
      return;
    }
    if (impact == 'high') {
      final completeSuite = test['id']?.toString() == 'all_tests';
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(completeSuite
                  ? 'Confirmar todos os testes'
                  : 'Confirmar teste de alto impacto'),
              content: Text(completeSuite
                  ? 'A suíte executará todo o catálogo disponível, inclusive cargas de CPU/GPU e leitura integral dos discos. Pode levar horas ou dias, não altera dados e pode ser cancelada.'
                  : '${test['name']} pode reduzir temporariamente o desempenho do computador. O teste será executado somente agora e não ficará agendado.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Executar este teste')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    try {
      final run = await TgdeskApi.startDiagnostic(
          widget.deviceId, test['id'].toString());
      if (!mounted) return;
      setState(() => _runs = [run, ..._runs]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha ao iniciar: $e')));
      }
    }
  }

  Future<void> _startSelectedQueue() async {
    if (_selectedTests.isEmpty) return;
    if (!widget.online) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O dispositivo precisa estar online.')));
      return;
    }
    final ordered = _catalog
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((test) => _selectedTests.contains(test['id']?.toString()))
        .toList();
    final highImpact = ordered.any((test) => test['impact'] == 'high');
    if (highImpact) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirmar fila personalizada'),
              content: Text(
                  'A fila executará ${ordered.length} testes na ordem técnica definida pelo TGDesk e contém teste(s) de alto impacto.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Executar fila')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    try {
      final ids = ordered.map((test) => test['id'].toString()).toList();
      final run = await TgdeskApi.startDiagnosticQueue(widget.deviceId, ids);
      if (!mounted) return;
      setState(() {
        _runs = [run, ..._runs];
        _selectedTests.clear();
        _selectionMode = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha ao iniciar fila: $e')));
      }
    }
  }

  Future<void> _changeRunState(Map<String, dynamic> run, String action) async {
    final id = run['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final updated = switch (action) {
        'pause' => await TgdeskApi.pauseDiagnostic(widget.deviceId, id),
        'resume' => await TgdeskApi.resumeDiagnostic(widget.deviceId, id),
        _ => await TgdeskApi.cancelDiagnostic(widget.deviceId, id),
      };
      if (!mounted) return;
      setState(() {
        final index = _runs.indexWhere((item) => item['id']?.toString() == id);
        if (index >= 0) _runs[index] = {..._runs[index], ...updated};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível alterar o teste: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: SizedBox(
        width: 1050,
        height: 720,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
            child: Row(children: [
              const Icon(Icons.science_outlined,
                  color: TgdeskColors.seed, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Diagnóstico avançado',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600)),
                      Text(widget.deviceName,
                          style: const TextStyle(color: Colors.grey)),
                    ]),
              ),
              Chip(
                avatar: Icon(Icons.circle,
                    size: 10,
                    color: widget.online
                        ? TgdeskColors.online
                        : TgdeskColors.warning),
                label: Text(widget.online ? 'Online' : 'Offline'),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline,
                      color: TgdeskColors.warning, size: 36),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ]),
              ),
            )
          else
            Expanded(
              child: Row(children: [
                if (!_catalogCollapsed)
                  Expanded(
                    flex: 6,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(children: [
                          const Expanded(
                            child: Text('Testes disponíveis',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600)),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _selectionMode = !_selectionMode;
                              if (!_selectionMode) _selectedTests.clear();
                            }),
                            icon: Icon(_selectionMode
                                ? Icons.close
                                : Icons.playlist_add_check),
                            label: Text(_selectionMode
                                ? 'Cancelar seleção'
                                : 'Selecionar vários'),
                          ),
                          IconButton(
                            tooltip: 'Recolher lista de testes',
                            onPressed: () =>
                                setState(() => _catalogCollapsed = true),
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ]),
                        if (_selectionMode) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _selectedTests.isEmpty
                                  ? null
                                  : _startSelectedQueue,
                              icon: const Icon(Icons.queue_play_next),
                              label: Text(
                                  'Executar fila própria (${_selectedTests.length})'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        const Text(
                            'Todos os testes executa o catálogo completo do TGDesk. Os testes também podem ser iniciados individualmente; não há estimativa artificial de duração.',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        if (_catalog.isEmpty)
                          const Text(
                              'Nenhum teste está disponível para este dispositivo.')
                        else
                          ..._catalogSections(),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: 52,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: IconButton(
                          tooltip: 'Exibir lista de testes',
                          onPressed: () =>
                              setState(() => _catalogCollapsed = false),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ),
                  ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text('Histórico e resultados',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 14),
                      if (_runs.isEmpty)
                        const _EmptyHistory()
                      else
                        ..._runs.map(_runCard),
                    ],
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _testCard(Map<String, dynamic> test) {
    final impact = test['impact']?.toString() ?? 'low';
    final color = impact == 'high'
        ? TgdeskColors.warning
        : impact == 'medium'
            ? Colors.amber
            : TgdeskColors.online;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(children: [
          if (_selectionMode && test['id'] != 'all_tests') ...[
            Checkbox(
              value: _selectedTests.contains(test['id']?.toString()),
              onChanged: (selected) => setState(() {
                final id = test['id']?.toString() ?? '';
                if (selected == true) {
                  _selectedTests.add(id);
                } else {
                  _selectedTests.remove(id);
                }
              }),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(_testIcon(test['category']?.toString()), color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(test['name']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(test['description']?.toString() ?? '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          if (!_selectionMode || test['id'] == 'all_tests')
            FilledButton.tonalIcon(
              onPressed: widget.online ? () => _start(test) : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Executar'),
            ),
        ]),
      ),
    );
  }

  List<Widget> _catalogSections() {
    final tests = _catalog
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final complete = tests.where((test) => test['id'] == 'all_tests');
    final individual =
        tests.where((test) => test['id'] != 'all_tests').toList();
    final recommendedIds = _telemetryRecommendedTests();
    final recommended = individual
        .where((test) => recommendedIds.contains(test['id']?.toString()))
        .toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final test in individual) {
      if (recommendedIds.contains(test['id']?.toString())) continue;
      groups
          .putIfAbsent(test['category']?.toString() ?? 'Outros', () => [])
          .add(test);
    }
    for (final tests in groups.values) {
      tests.sort((a, b) => (a['name']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['name']?.toString() ?? '').toLowerCase()));
    }
    recommended.sort((a, b) => (a['name']?.toString() ?? '')
        .toLowerCase()
        .compareTo((b['name']?.toString() ?? '').toLowerCase()));
    final rebootGroups =
        groups.entries.where((entry) => _isRebootGroup(entry.key)).toList();
    final alphabeticalGroups = groups.entries
        .where((entry) => !_isRebootGroup(entry.key))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return [
      ...complete.map(_testCard),
      if (recommended.isNotEmpty)
        _catalogGroup('Problemas indicados pela telemetria', recommended,
            icon: Icons.monitor_heart_outlined, highlighted: true),
      for (final entry in rebootGroups)
        _catalogGroup(entry.key, entry.value, icon: _testIcon(entry.key)),
      for (final entry in alphabeticalGroups)
        _catalogGroup(entry.key, entry.value, icon: _testIcon(entry.key)),
    ];
  }

  bool _isRebootGroup(String title) {
    final normalized = title.toLowerCase();
    return normalized.contains('reinício') ||
        normalized.contains('reinicio') ||
        normalized.contains('reinicializa') ||
        normalized.contains('reboot');
  }

  Set<String> _telemetryRecommendedTests() {
    final source = _control.deviceHealth[widget.deviceId] ?? _health;
    final statistics = source['statistics'];
    final health = statistics is Map ? statistics['health'] : null;
    final issues = health is Map ? health['issues'] : null;
    if (issues is! List) return const {};
    const mapping = <String, Set<String>>{
      'storage': {
        'storage_volumes',
        'smart_extended',
        'filesystem_scan',
        'filesystem_deep_scan',
        'disk_random_performance',
        'badblocks-read'
      },
      'processing': {'cpu_stress', 'process_pressure'},
      'memory': {'memory_integrity', 'memory_extended', 'process_pressure'},
      'temperature': {'temperature_sensors', 'cpu_stress', 'gpu_stress'},
      'network': {
        'internet_quality',
        'network_latency_series',
        'network_adapters',
        'dns_diagnostics',
        'route_table'
      },
      'security': {
        'security_posture',
        'defender_quick_scan',
        'windows_integrity',
        'update_status'
      },
    };
    final selected = <String>{};
    for (final issue in issues.whereType<Map>()) {
      selected.addAll(mapping[issue['category']?.toString()] ?? const {});
    }
    return selected;
  }

  Widget _catalogGroup(String title, List<Map<String, dynamic>> tests,
      {required IconData icon, bool highlighted = false}) {
    return Card(
      color: highlighted ? TgdeskColors.warning.withOpacity(.08) : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: PageStorageKey<String>('diagnostic-group-$title'),
        initiallyExpanded: _expandedGroups[title] ?? false,
        onExpansionChanged: (expanded) => _expandedGroups[title] = expanded,
        leading: Icon(icon,
            color: highlighted ? TgdeskColors.warning : TgdeskColors.seed),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${tests.length} teste(s)'),
        children: tests.map(_testCard).toList(),
      ),
    );
  }

  Widget _runCard(Map<String, dynamic> run) {
    final status = run['status']?.toString() ?? 'queued';
    final progress = (run['progress'] as num?)?.toInt() ?? 0;
    final color = status == 'completed'
        ? TgdeskColors.online
        : status == 'failed'
            ? TgdeskColors.suspended
            : status == 'paused'
                ? TgdeskColors.warning
                : TgdeskColors.seed;
    final results = run['results'];
    final resultMap = results is Map
        ? Map<String, dynamic>.from(results)
        : <String, dynamic>{};
    final test = resultMap['test']?.toString() ??
        (run['test']?.toString() ??
            ((run['tests'] is List && (run['tests'] as List).isNotEmpty)
                ? (run['tests'] as List).first.toString()
                : 'teste'));
    final runTests = run['tests'] is List
        ? (run['tests'] as List).map((item) => item.toString()).toList()
        : <String>[];
    final isSuite =
        test == 'all_tests' || test == 'custom_queue' || runTests.length > 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
            status == 'completed'
                ? Icons.check_circle_outline
                : status == 'failed'
                    ? Icons.error_outline
                    : status == 'paused'
                        ? Icons.pause_circle_outline
                        : Icons.pending_outlined,
            color: color),
        title: Text(
            runTests.length > 1
                ? 'Fila personalizada (${runTests.length} testes)'
                : _testName(test),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_statusName(status)),
          if (status == 'queued' ||
              status == 'running' ||
              status == 'paused') ...[
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progress / 100),
            const SizedBox(height: 3),
            Text(
                'Progresso total: $progress% · '
                '${_testName(run['current_test']?.toString() ?? '')}',
                style: const TextStyle(fontSize: 11)),
          ],
          if (status == 'paused')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Pausado no ponto seguro atual. O progresso foi preservado.',
                  style: TextStyle(fontSize: 11, color: TgdeskColors.warning)),
            ),
        ]),
        children: [
          if (status == 'running' || status == 'paused' || status == 'queued')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                if (status == 'running')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _changeRunState(run, 'pause'),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pausar'),
                    ),
                  ),
                if (status == 'paused')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _changeRunState(run, 'resume'),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Continuar'),
                    ),
                  ),
                if (status != 'queued') const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _changeRunState(run, 'cancel'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                        isSuite ? 'Cancelar teste e fila' : 'Cancelar teste'),
                  ),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: resultMap.isEmpty
                ? const Text('Aguardando dados do dispositivo.',
                    style: TextStyle(color: Colors.grey))
                : isSuite
                    ? _suiteResultVisual(resultMap,
                        running: status == 'running', runOrder: runTests)
                    : _resultVisual(resultMap),
          ),
        ],
      ),
    );
  }

  Widget _resultVisual(Map<String, dynamic> result) {
    final log = result['log']?.toString();
    final values = result.entries
        .where((entry) =>
            entry.key != 'log' &&
            entry.key != 'snapshot' &&
            entry.value is! Map &&
            entry.value is! List)
        .toList();
    final structured = result.entries.where((entry) =>
        entry.key != 'log' &&
        entry.key != 'test' &&
        (entry.value is Map || entry.value is List));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: values
            .map((entry) => ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 170),
                  child: _visualMetric(_label(entry.key), entry.value),
                ))
            .toList(),
      ),
      if (log != null && log.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Log técnico',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(10),
          color: Colors.black26,
          child: SingleChildScrollView(
              child: SelectableText(log,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        ),
      ],
      if (structured.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Resultado visual',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...structured.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _visualValue(_label(entry.key), entry.value),
            )),
      ],
    ]);
  }

  Widget _visualValue(String title, dynamic value, {int depth = 0}) {
    if (value is List) return _visualList(title, value, depth: depth);
    if (value is Map) {
      final data = Map<String, dynamic>.from(value);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 9),
          for (final entry in data.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: entry.value is Map || entry.value is List
                  ? _visualValue(_label(entry.key), entry.value,
                      depth: depth + 1)
                  : _visualMetric(_label(entry.key), entry.value),
            ),
        ]),
      );
    }
    return _visualMetric(title, value);
  }

  Widget _visualList(String title, List<dynamic> values, {required int depth}) {
    final rows = values
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    if (rows.isNotEmpty &&
        rows.every((row) => row.containsKey('status')) &&
        rows.any((row) => row.containsKey('offset'))) {
      return _surfaceMap(title, rows);
    }
    final numeric =
        values.whereType<num>().map((value) => value.toDouble()).toList();
    if (numeric.length == values.length && numeric.length > 1) {
      return _lineChart(title, numeric);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${values.length}', style: const TextStyle(color: Colors.grey)),
        ]),
        const SizedBox(height: 9),
        if (values.isEmpty)
          const Text('Nenhum item encontrado.',
              style: TextStyle(color: Colors.grey))
        else
          for (var index = 0; index < values.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: values[index] is Map || values[index] is List
                  ? _visualValue('Item ${index + 1}', values[index],
                      depth: depth + 1)
                  : _visualMetric('Item ${index + 1}', values[index]),
            ),
      ]),
    );
  }

  Widget _visualMetric(String label, dynamic value) {
    final normalized = value?.toString().toLowerCase() ?? '';
    final problem = normalized.contains('fail') ||
        normalized.contains('error') ||
        normalized.contains('critical') ||
        normalized == 'false';
    final healthy = normalized == 'ok' ||
        normalized == 'healthy' ||
        normalized == 'completed' ||
        normalized == 'true';
    final color = problem
        ? TgdeskColors.suspended
        : healthy
            ? TgdeskColors.online
            : TgdeskColors.seed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey))),
        const SizedBox(width: 8),
        Flexible(
            child: Text(_formatMetric(label, value),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _surfaceMap(String title, List<Map<String, dynamic>> regions) {
    Color regionColor(String status) => switch (status) {
          'error' || 'failed' => TgdeskColors.suspended,
          'very_slow' => Colors.deepOrange,
          'slow' => TgdeskColors.warning,
          _ => TgdeskColors.online,
        };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        LayoutBuilder(builder: (context, constraints) {
          const cell = 13.0;
          final columns = (constraints.maxWidth / cell).floor().clamp(1, 60);
          return Wrap(
            spacing: 3,
            runSpacing: 3,
            children: regions
                .map((region) => Tooltip(
                      message: '${_formatMetric('offset', region['offset'])} · '
                          '${(region['mbps'] as num?)?.toStringAsFixed(1) ?? '-'} MB/s · '
                          '${(region['latency_ms'] as num?)?.toStringAsFixed(1) ?? '-'} ms',
                      child: Container(
                        width: (constraints.maxWidth - ((columns - 1) * 3)) /
                            columns,
                        height: 10,
                        decoration: BoxDecoration(
                          color: regionColor(
                              region['status']?.toString() ?? 'healthy'),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ))
                .toList(),
          );
        }),
        const SizedBox(height: 9),
        const Wrap(spacing: 12, runSpacing: 5, children: [
          _Legend(color: TgdeskColors.online, label: 'Saudável'),
          _Legend(color: TgdeskColors.warning, label: 'Lento'),
          _Legend(color: Colors.deepOrange, label: 'Muito lento'),
          _Legend(color: TgdeskColors.suspended, label: 'Erro'),
        ]),
      ]),
    );
  }

  Widget _lineChart(String title, List<double> values) => Container(
        height: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.035),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(child: CustomPaint(painter: _DiagnosticLinePainter(values))),
        ]),
      );

  String _formatMetric(String key, dynamic value) {
    final lowered = key.toLowerCase();
    if (value is num &&
        (lowered.contains('byte') ||
            lowered.contains('size') ||
            lowered.contains('memory') ||
            lowered.contains('offset'))) {
      const units = ['B', 'KB', 'MB', 'GB', 'TB'];
      var amount = value.toDouble();
      var unit = 0;
      while (amount.abs() >= 1024 && unit < units.length - 1) {
        amount /= 1024;
        unit++;
      }
      return '${amount.toStringAsFixed(unit == 0 ? 0 : 1).replaceAll('.', ',')} ${units[unit]}';
    }
    if (value is num) {
      final suffix = lowered.contains('mbps')
          ? ' MB/s'
          : lowered.contains('latency') || lowered.endsWith(' ms')
              ? ' ms'
              : lowered.contains('percent') || lowered.contains('porcentagem')
                  ? '%'
                  : lowered.contains('temperature') ||
                          lowered.contains('celsius')
                      ? ' °C'
                      : '';
      return '${value.toDouble().toStringAsFixed(value is int ? 0 : 2).replaceAll('.', ',')}$suffix';
    }
    if (value == null || value.toString().isEmpty) return 'Não disponível';
    const translations = {
      'healthy': 'Saudável',
      'completed': 'Concluído',
      'failed': 'Falhou',
      'running': 'Em execução',
      'paused': 'Pausado',
      'queued': 'Na fila',
      'ok': 'Normal',
      'true': 'Sim',
      'false': 'Não',
      'unknown': 'Desconhecido',
    };
    return translations[value.toString().toLowerCase()] ?? value.toString();
  }

  int _suiteEntryProgress(Map<String, dynamic> entry) {
    final explicit = (entry['progress'] as num?)?.toInt();
    if (explicit != null) return explicit.clamp(0, 100);
    return entry['status'] == 'completed' || entry['status'] == 'failed'
        ? 100
        : 0;
  }

  Widget _suiteResultVisual(Map<String, dynamic> result,
      {required bool running, List<String> runOrder = const []}) {
    final rawTests = result['tests'];
    final tests = <String, Map<String, dynamic>>{};
    if (rawTests is Map) {
      for (final raw in rawTests.entries) {
        if (raw.value is Map) {
          tests[raw.key.toString()] =
              Map<String, dynamic>.from(raw.value as Map);
        }
      }
    }
    final resultOrder = result['order'] is List
        ? (result['order'] as List).map((item) => item.toString()).toList()
        : <String>[];
    final order = resultOrder.isNotEmpty ? resultOrder : runOrder;
    final orderedTests = <MapEntry<String, Map<String, dynamic>>>[
      for (final id in order)
        if (tests.containsKey(id)) MapEntry(id, tests[id]!),
      for (final entry in tests.entries)
        if (!order.contains(entry.key)) entry,
    ];
    final grouped = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final entry in orderedTests) {
      var group = entry.value['group']?.toString() ?? '';
      if (group.isEmpty) {
        for (final raw in _catalog.whereType<Map>()) {
          if (raw['id']?.toString() == entry.key) {
            group = raw['category']?.toString() ?? 'Outros';
            break;
          }
        }
      }
      grouped
          .putIfAbsent(group.isEmpty ? 'Outros' : group, () => [])
          .add(entry);
    }
    final assessment = result['assessment'];
    final executed = (result['executed'] as num?)?.toInt() ??
        tests.values.where((entry) => entry['status'] != 'queued').length;
    final completed = (result['completed'] as num?)?.toInt() ??
        tests.values.where((entry) => entry['status'] == 'completed').length;
    final failed = (result['failed'] as num?)?.toInt() ??
        tests.values.where((entry) => entry['status'] == 'failed').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!running && assessment is Map)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: (failed > 0 ? TgdeskColors.warning : TgdeskColors.online)
                .withOpacity(.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(assessment['title']?.toString() ?? 'Resultado geral',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(assessment['summary']?.toString() ?? ''),
          ]),
        ),
      Text('$executed executados · $completed concluídos · $failed com falha',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      for (final group in grouped.entries)
        Card(
          child: ExpansionTile(
            title: Text(group.key),
            subtitle: LinearProgressIndicator(
              value: group.value.isEmpty
                  ? 0
                  : group.value.fold<int>(
                          0,
                          (sum, entry) =>
                              sum + _suiteEntryProgress(entry.value)) /
                      (group.value.length * 100),
            ),
            children: [
              for (final entry in group.value)
                ExpansionTile(
                  dense: true,
                  leading: Icon(
                    entry.value['status'] == 'completed'
                        ? Icons.check_circle_outline
                        : entry.value['status'] == 'failed'
                            ? Icons.error_outline
                            : entry.value['status'] == 'running'
                                ? Icons.pending_outlined
                                : Icons.schedule,
                  ),
                  title: Text(_testName(entry.key)),
                  subtitle: Text(_statusName(
                      entry.value['status']?.toString() ?? 'queued')),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: entry.value['results'] is Map
                          ? _resultVisual(Map<String, dynamic>.from(
                              entry.value['results'] as Map))
                          : Text(entry.value['message']?.toString() ??
                              'Aguardando execução.'),
                    ),
                  ],
                ),
            ],
          ),
        ),
    ]);
  }

  String _testName(String id) {
    for (final raw in _catalog.whereType<Map>()) {
      if (raw['id']?.toString() == id) return raw['name']?.toString() ?? id;
    }
    return id;
  }

  String _statusName(String status) => switch (status) {
        'queued' => 'Aguardando execução',
        'running' => 'Em execução',
        'paused' => 'Pausado',
        'completed' => 'Concluído',
        'failed' => 'Falhou',
        _ => status,
      };

  String _label(String value) {
    const labels = <String, String>{
      'bytestested': 'Dados testados',
      'bytesread': 'Dados lidos',
      'readmbps': 'Velocidade de leitura',
      'writembps': 'Velocidade de gravação',
      'averagelatencyms': 'Latência média',
      'maximumlatencyms': 'Latência máxima',
      'latencyms': 'Histórico de latência',
      'averagems': 'Latência média',
      'jitterms': 'Variação da latência',
      'losspercent': 'Perda de conexão',
      'logicalprocessors': 'Processadores lógicos',
      'sha256operations': 'Operações realizadas',
      'operationssecond': 'Operações por segundo',
      'operations': 'Operações',
      'blockbytes': 'Tamanho do bloco',
      'iops': 'Operações de entrada e saída por segundo',
      'exitcode': 'Código de conclusão',
      'durationseconds': 'Duração em segundos',
      'finishedat': 'Conclusão',
      'status': 'Estado',
      'health': 'Saúde',
      'operational': 'Estado operacional',
      'temperature': 'Temperatura',
      'wear': 'Desgaste',
      'readerrors': 'Erros de leitura',
      'writeerrors': 'Erros de gravação',
      'readerrorstotal': 'Total de erros de leitura',
      'readerrorsuncorrected': 'Erros de leitura não corrigidos',
      'readerrorscorrected': 'Erros de leitura corrigidos',
      'deviceid': 'Dispositivo',
      'model': 'Modelo',
      'size': 'Capacidade',
      'regions': 'Mapa da superfície',
      'offset': 'Posição',
      'mbps': 'Velocidade',
      'patterns': 'Padrões executados',
      'passes': 'Passes',
      'pass': 'Passe',
      'pattern': 'Padrão',
      'mismatches': 'Divergências',
      'firsterroroffset': 'Primeiro erro',
      'limitations': 'Limitações',
      'target': 'Destino',
      'samples': 'Amostras',
      'failed': 'Falhas',
      'items': 'Itens encontrados',
      'volumes': 'Volumes',
      'filesystemevents': 'Eventos do sistema de arquivos',
      'controllers': 'Controladores gráficos',
      'enginesamples': 'Atividade gráfica',
      'threats': 'Ameaças',
      'threatcount': 'Quantidade de ameaças',
      'antivirusenabled': 'Antivírus ativo',
      'lastquickscan': 'Última verificação rápida',
      'name': 'Nome',
      'error': 'Erro',
      'drive': 'Unidade',
      'filesystem': 'Sistema de arquivos',
      'scanned': 'Volumes verificados',
    };
    final normalized = value.replaceAll('_', '').toLowerCase();
    if (labels.containsKey(normalized)) return labels[normalized]!;
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  IconData _testIcon(String? category) => switch (category) {
        'Processamento' => Icons.memory,
        'Memória' => Icons.view_module_outlined,
        'Rede' => Icons.public,
        'Armazenamento' => Icons.storage,
        'Vídeo' => Icons.developer_board_outlined,
        _ => Icons.fact_check_outlined,
      };
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]);
}

class _DiagnosticLinePainter extends CustomPainter {
  const _DiagnosticLinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minimum = values.reduce((a, b) => a < b ? a : b);
    final maximum = values.reduce((a, b) => a > b ? a : b);
    final range = maximum == minimum ? 1.0 : maximum - minimum;
    final grid = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = size.height * row / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height - ((values[index] - minimum) / range * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = TgdeskColors.seed
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _DiagnosticLinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(12)),
        child: const Column(children: [
          Icon(Icons.history, size: 42, color: Colors.grey),
          SizedBox(height: 10),
          Text('Nenhum teste executado'),
          SizedBox(height: 4),
          Text('Os resultados aparecerão aqui.',
              style: TextStyle(color: Colors.grey)),
        ]),
      );
}
