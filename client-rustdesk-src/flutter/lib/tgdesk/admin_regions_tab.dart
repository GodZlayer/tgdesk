import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'theme.dart';

/// Onde o admin define os lugares em que o produto opera.
///
/// A região é o recorte que o preço dinâmico mede: quantos chamados esperam,
/// quantos técnicos existem e quantos clientes o lugar tem. Rede não serve para
/// isso — é fronteira administrativa, e duas redes da mesma empresa podem estar
/// em cidades diferentes.
///
/// Centro e raio, e não desenho de mapa: a única pergunta que o produto faz é
/// se um ponto pertence à região, e um círculo responde. Região sem centro
/// existe e é legítima — vale para quem foi posto nela à mão, quando o
/// agrupamento é por contrato e não por geografia.
class AdminRegionsTab extends StatefulWidget {
  const AdminRegionsTab({super.key});

  @override
  State<AdminRegionsTab> createState() => _AdminRegionsTabState();
}

class _AdminRegionsTabState extends State<AdminRegionsTab> {
  final _channel = TgdeskControlChannel.instance;
  Map<String, Map<String, dynamic>> _costByRegion = const {};
  Map<String, dynamic>? _selectedRegion;

  @override
  void initState() {
    super.initState();
    _channel.addListener(_onChannel);
    _loadRegionalCosts();
  }

  Future<void> _loadRegionalCosts() async {
    try {
      final rows = await TgdeskApi.regionalCostIndex();
      if (!mounted) return;
      setState(() => _costByRegion = {
            for (final row in rows)
              if (row is Map && row['region_id'] != null)
                row['region_id'].toString(): Map<String, dynamic>.from(row),
          });
    } catch (_) {}
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
    final regions = _channel.regions;
    final active = regions.where((item) => item['active'] != false).length;
    final mapped = regions
        .where((item) => item['center_lat'] is num && item['center_lon'] is num)
        .length;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nova-regiao',
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Região'),
      ),
      body: regions.isEmpty
          ? Center(
              child: Text(_channel.connected
                  ? 'Nenhuma região cadastrada — o preço não varia por lugar.'
                  : 'Reconectando ao servidor...'))
          : ListView(
              padding: const EdgeInsets.all(TgdeskSpacing.md),
              children: [
                _RegionMapDashboard(
                    regions: regions,
                    active: active,
                    mapped: mapped,
                    costByRegion: _costByRegion,
                    selectedRegion: _selectedRegion,
                    onSelectRegion: (region) =>
                        setState(() => _selectedRegion = region)),
                const SizedBox(height: TgdeskSpacing.md),
                ...regions.map((region) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _card(region),
                    )),
              ],
            ),
    );
  }

  Widget _card(Map<String, dynamic> region) {
    final ativo = region['active'] != false;
    final lat = region['center_lat'] as num?;
    final lon = region['center_lon'] as num?;
    final temCentro = lat != null && lon != null;
    return Card(
      child: ExpansionTile(
        dense: true,
        leading: Icon(temCentro
            ? Icons.my_location_outlined
            : Icons.location_off_outlined),
        title: Text(region['label']?.toString() ?? ''),
        subtitle: Text(
            '${temCentro ? 'região geográfica' : 'região por cidades'} · ${ativo ? 'ativa' : 'inativa'}'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(children: [
              Expanded(
                  child: Text(temCentro
                      ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)} · raio ${region['radius_km']} km'
                      : 'Cidades vinculadas definem a cobertura.')),
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _edit(region),
              ),
              IconButton(
                tooltip: 'Faixas por serviço',
                icon: const Icon(Icons.price_change_outlined, size: 18),
                onPressed: () => _municipalities(region),
              ),
              IconButton(
                tooltip: 'Municípios IBGE',
                icon: const Icon(Icons.location_city_outlined, size: 18),
                onPressed: () => _municipalities(region),
              ),
              IconButton(
                tooltip: 'Remover',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _confirmarRemocao(region),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Apagar uma região solta quem estava nela — técnico, dispositivo e chamado
  /// voltam ao preço global. É reversível recadastrando, mas a atribuição de
  /// cada um se perde, então vale perguntar antes.
  Future<void> _confirmarRemocao(Map<String, dynamic> region) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar ${region['label']}?'),
        content: const Text(
            'Técnicos, dispositivos e chamados desta região ficam sem região, '
            'e o preço deles volta ao global. A atribuição de cada um se perde.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => TgdeskApi.deleteRegion(region['id'].toString()));
  }

  Future<void> _edit(Map<String, dynamic>? region) async {
    final key = TextEditingController(text: region?['key']?.toString() ?? '');
    final label =
        TextEditingController(text: region?['label']?.toString() ?? '');
    final lat =
        TextEditingController(text: region?['center_lat']?.toString() ?? '');
    final lon =
        TextEditingController(text: region?['center_lon']?.toString() ?? '');
    final raio =
        TextEditingController(text: (region?['radius_km'] ?? 50).toString());
    var ativo = region?['active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(region == null ? 'Nova região' : 'Editar região'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: key,
                  enabled: region == null,
                  decoration: const InputDecoration(
                      labelText: 'Chave',
                      helperText: 'Sem espaço nem barra; não muda depois'),
                ),
                TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Nome')),
                TextField(
                    controller: lat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Latitude do centro',
                        helperText: 'Deixe as duas vazias para região só por '
                            'atribuição')),
                TextField(
                    controller: lon,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Longitude do centro')),
                TextField(
                    controller: raio,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Raio (km)')),
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

    final latitude = double.tryParse(lat.text.trim().replaceAll(',', '.'));
    final longitude = double.tryParse(lon.text.trim().replaceAll(',', '.'));
    // Meio centro não é centro. O servidor recusa, mas dizer aqui evita a ida
    // e volta só para receber a mesma resposta.
    if ((latitude == null) != (longitude == null)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Informe latitude e longitude, ou nenhuma das duas.')));
      }
      return;
    }
    await _run(() => TgdeskApi.saveRegion({
          'key': key.text.trim(),
          'label': label.text.trim(),
          'center_lat': latitude,
          'center_lon': longitude,
          'radius_km':
              double.tryParse(raio.text.trim().replaceAll(',', '.')) ?? 50,
          'active': ativo,
        }));
  }

  Future<void> _municipalities(Map<String, dynamic> region) async {
    final regionId = region['id']?.toString() ?? '';
    final search = TextEditingController();
    final uf = TextEditingController();
    var linked = <dynamic>[];
    var results = <dynamic>[];
    var relationKind = 'commercial';
    var loading = true;
    var loadRequested = false;

    Future<void> load(StateSetter setLocal) async {
      linked = await TgdeskApi.regionMunicipalities(regionId);
      loading = false;
      setLocal(() {});
    }

    Future<void> runSearch(StateSetter setLocal) async {
      results = await TgdeskApi.brazilMunicipalities(
        query: search.text,
        uf: uf.text,
        limit: 160,
      );
      setLocal(() {});
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (loading) {
            if (!loadRequested) {
              loadRequested = true;
              Future.microtask(() => load(setLocal));
            }
          }
          return AlertDialog(
            title: Text('Municípios de ${region['label']}'),
            content: SizedBox(
              width: 760,
              height: 620,
              child: Column(
                children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: search,
                        decoration: const InputDecoration(
                          labelText: 'Buscar município ou região',
                          hintText: 'Ex.: Manhumirim, Manhuaçu, Belo Horizonte',
                        ),
                        onSubmitted: (_) => runSearch(setLocal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: uf,
                        decoration: const InputDecoration(labelText: 'UF'),
                        onSubmitted: (_) => runSearch(setLocal),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Buscar',
                      icon: const Icon(Icons.search),
                      onPressed: () => runSearch(setLocal),
                    ),
                  ]),
                  DropdownButtonFormField<String>(
                    value: relationKind,
                    decoration:
                        const InputDecoration(labelText: 'Relação da cidade'),
                    items: const [
                      DropdownMenuItem(
                          value: 'commercial', child: Text('Região comercial')),
                      DropdownMenuItem(
                          value: 'metropolitan',
                          child: Text('Região metropolitana')),
                      DropdownMenuItem(
                          value: 'immediate', child: Text('Região imediata')),
                      DropdownMenuItem(
                          value: 'intermediate',
                          child: Text('Região intermediária')),
                      DropdownMenuItem(
                          value: 'capital', child: Text('Capital')),
                    ],
                    onChanged: (v) =>
                        setLocal(() => relationKind = v ?? 'commercial'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(children: [
                      Expanded(
                        child: _MunicipalityList(
                          title: 'Vinculados',
                          items: linked,
                          trailingBuilder: (item) => IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await TgdeskApi.deleteRegionMunicipality(
                                regionId,
                                (item['ibge_id'] as num).toInt(),
                                item['relation_kind']?.toString() ??
                                    'commercial',
                              );
                              await load(setLocal);
                            },
                          ),
                        ),
                      ),
                      const VerticalDivider(),
                      Expanded(
                        child: _MunicipalityList(
                          title: 'Resultado IBGE',
                          items: results,
                          trailingBuilder: (item) => IconButton(
                            icon: const Icon(Icons.add_location_alt_outlined),
                            onPressed: () async {
                              await TgdeskApi.addRegionMunicipality(
                                regionId,
                                (item['ibge_id'] as num).toInt(),
                                relationKind,
                              );
                              await load(setLocal);
                            },
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fechar')),
            ],
          );
        },
      ),
    );
  }
}

class _RegionMapDashboard extends StatelessWidget {
  const _RegionMapDashboard(
      {required this.regions,
      required this.active,
      required this.mapped,
      required this.costByRegion,
      required this.selectedRegion,
      required this.onSelectRegion});

  final List<Map<String, dynamic>> regions;
  final int active;
  final int mapped;
  final Map<String, Map<String, dynamic>> costByRegion;
  final Map<String, dynamic>? selectedRegion;
  final ValueChanged<Map<String, dynamic>> onSelectRegion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: 390,
        padding: const EdgeInsets.all(TgdeskSpacing.lg),
        decoration: BoxDecoration(
          gradient:
              LinearGradient(colors: [scheme.primaryContainer, scheme.surface]),
        ),
        child: Row(children: [
          Expanded(
              flex: 7,
              child: _BrazilMap(
                  regions: regions,
                  costByRegion: costByRegion,
                  selectedRegion: selectedRegion,
                  onSelect: onSelectRegion)),
          const SizedBox(width: TgdeskSpacing.lg),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.public, color: scheme.primary, size: 30),
              const SizedBox(height: 8),
              Text(
                  selectedRegion == null
                      ? 'Brasil'
                      : selectedRegion!['label'].toString(),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(selectedRegion == null
                  ? 'Selecione um estado no mapa para abrir suas regiões comerciais.'
                  : 'Região selecionada. Abra para administrar cidades, bairros, ruas e CEPs de cobertura.'),
              const Spacer(),
              _MapMetric(
                  label: selectedRegion == null
                      ? 'Regiões ativas'
                      : 'Cidades da região',
                  value:
                      selectedRegion == null ? active.toString() : 'Gerenciar',
                  icon: Icons.check_circle_outline),
              _MapMetric(
                  label: 'Com coordenadas',
                  value: mapped.toString(),
                  icon: Icons.location_on_outlined),
              _MapMetric(
                  label: 'Escala',
                  value: 'Brasil → cidade',
                  icon: Icons.zoom_in_map_outlined),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MapMetric extends StatelessWidget {
  const _MapMetric(
      {required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(label),
      );
}

class _BrazilMap extends StatefulWidget {
  const _BrazilMap(
      {required this.regions,
      required this.costByRegion,
      required this.selectedRegion,
      required this.onSelect});
  final List<Map<String, dynamic>> regions;
  final Map<String, Map<String, dynamic>> costByRegion;
  final Map<String, dynamic>? selectedRegion;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  State<_BrazilMap> createState() => _BrazilMapState();
}

class _BrazilMapState extends State<_BrazilMap> {
  static const _uf = <String>[
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '31',
    '32',
    '33',
    '35',
    '41',
    '42',
    '43',
    '50',
    '51',
    '52',
    '53'
  ];
  late final Future<List<_IbgeShape>> _shapes = _load();

  Future<List<_IbgeShape>> _load() async {
    final client = HttpClient();
    try {
      final responses = await Future.wait(_uf.map((id) async {
        final request = await client.getUrl(Uri.parse(
            'https://servicodados.ibge.gov.br/api/v2/malhas/$id?formato=application/vnd.geo+json&qualidade=minima'));
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        return _IbgeShape.fromGeoJson(jsonDecode(text) as Map);
      }));
      return responses;
    } finally {
      client.close(force: true);
    }
  }

  /* Future<void> _serviceBounds(Map<String, dynamic> region) async {
    final regionId = region['id'].toString();
    var rows = <dynamic>[]; var loading = true;
    int cents(String text) => ((double.tryParse(text.replaceAll(',', '.')) ?? 0) * 100).round();
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      if (loading) { loading = false; Future.microtask(() async { rows = await TgdeskApi.regionalServiceBounds(regionId); setLocal(() {}); }); }
      return AlertDialog(title: Text('Faixas de ${region['label']}'), content: SizedBox(width: 680, height: 560, child: rows.isEmpty ? const Center(child: CircularProgressIndicator()) : ListView(children: [
        const Text('Cada serviço possui mínimo e máximo próprios nesta região. Cidades vinculadas herdam a mesma faixa.'),
        const SizedBox(height: 12),
        for (final raw in rows) () { final row = Map<String,dynamic>.from(raw as Map); final min = TextEditingController(text: (((row['min_cents'] as num?)?.toDouble() ?? 0) / 100).toString()); final max = TextEditingController(text: (((row['max_cents'] as num?)?.toDouble() ?? 0) / 100).toString()); return ListTile(title: Text(row['label'].toString()), subtitle: Row(children:[Expanded(child: TextField(controller:min, decoration:const InputDecoration(labelText:'Mínimo R$'))), const SizedBox(width:8), Expanded(child: TextField(controller:max, decoration:const InputDecoration(labelText:'Máximo R$')))]), trailing: IconButton(icon:const Icon(Icons.save_outlined), onPressed:() async { await TgdeskApi.saveRegionalServiceBounds(regionId, {'service_key':row['service_key'],'min_cents':cents(min.text),'max_cents':cents(max.text)}); })); }(),
      ])), actions:[TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('Fechar'))]);
    }));
  }

  } */

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_IbgeShape>>(
        future: _shapes,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          return LayoutBuilder(
              builder: (context, constraints) => Stack(children: [
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _BrazilMapPainter(
                                Theme.of(context).colorScheme,
                                snapshot.data!))),
                    ...widget.regions
                        .where((item) =>
                            item['center_lat'] is num &&
                            item['center_lon'] is num)
                        .map((item) {
                      final lat = (item['center_lat'] as num).toDouble();
                      final lon = (item['center_lon'] as num).toDouble();
                      final x =
                          ((lon + 74.2) / 40.2).clamp(0.05, .95).toDouble();
                      final y =
                          ((5.4 - lat) / 40.2).clamp(0.05, .95).toDouble();
                      final color = item['active'] == false
                          ? TgdeskColors.offline
                          : Theme.of(context).colorScheme.primary;
                      final cost = widget.costByRegion[item['id']?.toString()];
                      final index = cost?['cost_index'];
                      return Positioned(
                          left: constraints.maxWidth * x - 9,
                          top: constraints.maxHeight * y - 9,
                          child: Tooltip(
                              message: index == null
                                  ? item['label']?.toString() ?? 'Região'
                                  : '${item['label'] ?? 'Região'}\nÍndice regional: $index',
                              child: InkWell(
                                  onTap: () => widget.onSelect(item),
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: color.withOpacity(.45),
                                                blurRadius: 14,
                                                spreadRadius: 4)
                                          ])))));
                    }),
                  ]));
        },
      );
}

class _BrazilMapPainter extends CustomPainter {
  const _BrazilMapPainter(this.scheme, this.shapes);
  final ColorScheme scheme;
  final List<_IbgeShape> shapes;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = scheme.primaryContainer;
    final border = Paint()
      ..color = scheme.outline.withOpacity(.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final shape in shapes) {
      final path = Path();
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i++) {
          final p = ring[i];
          final x = (p.$1 + 74.0) / 40.0 * size.width;
          final y = (5.0 - p.$2) / 40.0 * size.height;
          if (i == 0)
            path.moveTo(x, y);
          else
            path.lineTo(x, y);
        }
        path.close();
      }
      canvas.drawPath(path, fill);
      canvas.drawPath(path, border);
    }
  }

  @override
  bool shouldRepaint(covariant _BrazilMapPainter oldDelegate) =>
      oldDelegate.scheme != scheme || oldDelegate.shapes != shapes;
}

class _IbgeShape {
  const _IbgeShape(this.rings);
  final List<List<(double, double)>> rings;
  factory _IbgeShape.fromGeoJson(Map json) {
    final geometry =
        ((json['features'] as List).first as Map)['geometry'] as Map;
    final raw = geometry['coordinates'] as List;
    final polygons = geometry['type'] == 'MultiPolygon'
        ? raw.expand((p) => p as List).toList()
        : raw;
    return _IbgeShape(polygons
        .map<List<(double, double)>>(
            (ring) => (ring as List).map<(double, double)>((point) {
                  final p = point as List;
                  return ((p[0] as num).toDouble(), (p[1] as num).toDouble());
                }).toList())
        .toList());
  }
}

class _MunicipalityList extends StatelessWidget {
  const _MunicipalityList({
    required this.title,
    required this.items,
    required this.trailingBuilder,
  });

  final String title;
  final List<dynamic> items;
  final Widget Function(Map<String, dynamic> item) trailingBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = Map<String, dynamic>.from(items[index] as Map);
            return ListTile(
              dense: true,
              title: Text('${item['name']} / ${item['uf_sigla']}'),
              subtitle: Text([
                if (item['relation_kind'] != null) item['relation_kind'],
                item['immediate_region_name'],
                item['intermediate_region_name'],
              ]
                  .where((value) => value != null && '$value'.isNotEmpty)
                  .join(' · ')),
              trailing: trailingBuilder(item),
            );
          },
        ),
      ),
    ]);
  }
}
