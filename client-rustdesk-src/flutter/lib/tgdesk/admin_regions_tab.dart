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
    final regions = _channel.regions;
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
          : ListView.separated(
              padding: const EdgeInsets.all(TgdeskSpacing.md),
              itemCount: regions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (_, index) => _card(regions[index]),
            ),
    );
  }

  Widget _card(Map<String, dynamic> region) {
    final ativo = region['active'] != false;
    final lat = region['center_lat'] as num?;
    final lon = region['center_lon'] as num?;
    final temCentro = lat != null && lon != null;
    return Card(
      child: ListTile(
        leading: Icon(temCentro
            ? Icons.my_location_outlined
            : Icons.location_off_outlined),
        title: Text(region['label']?.toString() ?? ''),
        subtitle: Text(temCentro
            ? '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)} · '
                'raio ${region['radius_km']} km'
            : 'sem centro — só por atribuição'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!ativo)
            const Padding(
              padding: EdgeInsets.only(right: TgdeskSpacing.sm),
              child: Text('inativa',
                  style: TextStyle(color: TgdeskColors.offline)),
            ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _edit(region),
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
