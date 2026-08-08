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
  String? _selectedState;
  List<dynamic> _selectedMunicipalities = const [];
  List<Map<String, dynamic>> _stateRegions = const [];
  bool _stateRegionsLoading = false;

  static const _stateUf = <String, String>{
    '11': 'RO',
    '12': 'AC',
    '13': 'AM',
    '14': 'RR',
    '15': 'PA',
    '16': 'AP',
    '17': 'TO',
    '21': 'MA',
    '22': 'PI',
    '23': 'CE',
    '24': 'RN',
    '25': 'PB',
    '26': 'PE',
    '27': 'AL',
    '28': 'SE',
    '29': 'BA',
    '31': 'MG',
    '32': 'ES',
    '33': 'RJ',
    '35': 'SP',
    '41': 'PR',
    '42': 'SC',
    '43': 'RS',
    '50': 'MS',
    '51': 'MT',
    '52': 'GO',
    '53': 'DF',
  };

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
    final mapRegions =
        _selectedState == null ? const <Map<String, dynamic>>[] : _stateRegions;
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
                    regions: mapRegions,
                    active: active,
                    mapped: mapped,
                    costByRegion: _costByRegion,
                    selectedRegion: _selectedRegion,
                    selectedState: _selectedState,
                    municipalities: _selectedMunicipalities,
                    stateRegionsLoading: _stateRegionsLoading,
                    onSelectState: _selectState,
                    onReset: () => setState(() {
                          _selectedState = null;
                          _selectedRegion = null;
                          _selectedMunicipalities = const [];
                          _stateRegions = const [];
                          _stateRegionsLoading = false;
                        }),
                    onSelectRegion: _selectRegion),
                const SizedBox(height: TgdeskSpacing.md),
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: _selectedState != null,
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(_selectedState == null
                        ? 'Cobertura do país'
                        : _selectedRegion == null
                            ? 'Regiões do estado'
                            : 'Região selecionada'),
                    subtitle: Text(_selectedState == null
                        ? 'Selecione um estado no mapa para abrir as regiões.'
                        : _selectedRegion == null
                            ? '${_stateRegions.length} região(ões) encontrada(s)'
                            : 'Edite faixas, cidades, bairros, ruas e CEPs abaixo.'),
                    children: [
                      if (_selectedState == null)
                        const ListTile(
                          leading: Icon(Icons.touch_app_outlined),
                          title: Text('Aguardando seleção do estado'),
                        )
                      else
                        ...(_selectedRegion == null
                                ? _stateRegions
                                : [_selectedRegion!])
                            .map((region) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: _card(region),
                                )),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _selectRegion(Map<String, dynamic> region) async {
    setState(() {
      _selectedRegion = region;
      _selectedMunicipalities = const [];
    });
    try {
      final rows =
          await TgdeskApi.regionMunicipalities(region['id'].toString());
      if (mounted &&
          _selectedRegion?['id']?.toString() == region['id']?.toString()) {
        setState(() => _selectedMunicipalities = rows);
      }
    } catch (_) {}
  }

  Future<void> _selectState(String state) async {
    setState(() {
      _selectedState = state;
      _selectedRegion = null;
      _selectedMunicipalities = const [];
      _stateRegions = const [];
      _stateRegionsLoading = true;
    });
    final uf = _stateUf[state];
    if (uf == null) {
      if (mounted) setState(() => _stateRegionsLoading = false);
      return;
    }
    final regions = _channel.regions
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    final matches = await Future.wait(regions.map((region) async {
      try {
        final municipalities =
            await TgdeskApi.regionMunicipalities(region['id'].toString());
        return municipalities.any((raw) =>
                raw is Map && raw['uf_sigla']?.toString().toUpperCase() == uf)
            ? region
            : null;
      } catch (_) {
        return null;
      }
    }));
    if (mounted && _selectedState == state) {
      setState(() {
        _stateRegions = matches.whereType<Map<String, dynamic>>().toList();
        _stateRegionsLoading = false;
      });
    }
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
                onPressed: () => _serviceBounds(region),
              ),
              IconButton(
                tooltip: 'Municípios IBGE',
                icon: const Icon(Icons.location_city_outlined, size: 18),
                onPressed: () => _municipalities(region),
              ),
              IconButton(
                tooltip: 'Bairros, ruas e CEPs',
                icon: const Icon(Icons.signpost_outlined, size: 18),
                onPressed: () => _coverageAddresses(region),
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

  Future<void> _serviceBounds(Map<String, dynamic> region) async {
    final regionId = region['id']?.toString() ?? '';
    var loading = true;
    var rows = <dynamic>[];
    final controllers =
        <String, ({TextEditingController min, TextEditingController max})>{};
    int cents(String value) =>
        ((double.tryParse(value.replaceAll(',', '.')) ?? 0) * 100).round();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (loading) {
            loading = false;
            Future.microtask(() async {
              try {
                rows = await TgdeskApi.regionalServiceBounds(regionId);
              } finally {
                if (ctx.mounted) setLocal(() {});
              }
            });
          }
          return AlertDialog(
            title: Text('Faixas de ${region['label']}'),
            content: SizedBox(
              width: 700,
              height: 560,
              child: rows.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        const Text(
                            'Cada serviço possui mínimo e máximo próprios nesta região. As cidades vinculadas herdam a mesma faixa.'),
                        const SizedBox(height: 12),
                        for (final raw in rows)
                          () {
                            final row = Map<String, dynamic>.from(raw as Map);
                            final key = row['service_key']?.toString() ??
                                row['key']?.toString() ??
                                '';
                            final pair = controllers.putIfAbsent(
                                key,
                                () => (
                                      min: TextEditingController(
                                          text: (((row['min_cents'] as num?)
                                                          ?.toDouble() ??
                                                      0) /
                                                  100)
                                              .toStringAsFixed(2)),
                                      max: TextEditingController(
                                          text: (((row['max_cents'] as num?)
                                                          ?.toDouble() ??
                                                      0) /
                                                  100)
                                              .toStringAsFixed(2)),
                                    ));
                            return Card(
                              child: ListTile(
                                title: Text(row['label']?.toString() ?? key),
                                subtitle: Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: pair.min,
                                          decoration: const InputDecoration(
                                              labelText: 'Minimo (R\$)'))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextField(
                                          controller: pair.max,
                                          decoration: const InputDecoration(
                                              labelText: 'Maximo (R\$)'))),
                                ]),
                                trailing: IconButton(
                                  icon: const Icon(Icons.save_outlined),
                                  tooltip: 'Salvar faixa',
                                  onPressed: () async {
                                    final min = cents(pair.min.text);
                                    final max = cents(pair.max.text);
                                    if (min < 0 || max < min) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'O mínimo deve ser menor ou igual ao máximo.')));
                                      return;
                                    }
                                    await TgdeskApi.saveRegionalServiceBounds(
                                        regionId, {
                                      'service_key': key,
                                      'min_cents': min,
                                      'max_cents': max,
                                    });
                                    if (ctx.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('Faixa salva.')));
                                  },
                                ),
                              ),
                            );
                          }(),
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
    for (final pair in controllers.values) {
      pair.min.dispose();
      pair.max.dispose();
    }
  }

  Future<void> _coverageAddresses(Map<String, dynamic> region) async {
    final regionId = region['id']?.toString() ?? '';
    final municipalities = await TgdeskApi.regionMunicipalities(regionId);
    var addresses = await TgdeskApi.regionCoverageAddresses(regionId);
    final neighborhood = TextEditingController();
    final street = TextEditingController();
    final cep = TextEditingController();
    int? municipalityId = municipalities.isEmpty
        ? null
        : (municipalities.first as Map)['ibge_id'] as int?;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Cobertura de ${region['label']}'),
          content: SizedBox(
            width: 760,
            height: 620,
            child: Column(children: [
              const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'País > estado > região > cidade > bairro > rua > CEP')),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: municipalityId,
                decoration: const InputDecoration(labelText: 'Cidade'),
                items: [
                  for (final raw in municipalities)
                    DropdownMenuItem<int>(
                      value: (raw as Map)['ibge_id'] as int,
                      child: Text('${raw['name']} / ${raw['uf_sigla']}'),
                    ),
                ],
                onChanged: (value) => setLocal(() => municipalityId = value),
              ),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: neighborhood,
                        decoration:
                            const InputDecoration(labelText: 'Bairro'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: street,
                        decoration: const InputDecoration(labelText: 'Rua'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 130,
                    child: TextField(
                        controller: cep,
                        decoration: const InputDecoration(labelText: 'CEP'))),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Adicionar rua',
                  onPressed: municipalityId == null
                      ? null
                      : () async {
                          await TgdeskApi.saveRegionCoverageAddress(regionId, {
                            'country_code': 'BR',
                            'state_code': ((municipalities.firstWhere((item) =>
                                        (item as Map)['ibge_id'] ==
                                        municipalityId) as Map)['uf_sigla'] ??
                                    '')
                                .toString(),
                            'municipality_id': municipalityId,
                            'neighborhood': neighborhood.text.trim(),
                            'street': street.text.trim(),
                            'cep': cep.text.trim(),
                          });
                          addresses =
                              await TgdeskApi.regionCoverageAddresses(regionId);
                          neighborhood.clear();
                          street.clear();
                          cep.clear();
                          setLocal(() {});
                        },
                ),
              ]),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final item =
                        Map<String, dynamic>.from(addresses[index] as Map);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.route_outlined),
                      title:
                          Text('${item['street']} — ${item['neighborhood']}'),
                      subtitle: Text(
                          '${item['municipality_name']} / ${item['state_code']} · CEP ${item['cep']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await TgdeskApi.deleteRegionCoverageAddress(
                              regionId, item['id'].toString());
                          addresses =
                              await TgdeskApi.regionCoverageAddresses(regionId);
                          setLocal(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'))
          ],
        ),
      ),
    );
    neighborhood.dispose();
    street.dispose();
    cep.dispose();
  }
}

class _RegionMapDashboard extends StatelessWidget {
  const _RegionMapDashboard(
      {required this.regions,
      required this.active,
      required this.mapped,
      required this.costByRegion,
      required this.selectedRegion,
      required this.selectedState,
      required this.municipalities,
      required this.stateRegionsLoading,
      required this.onSelectState,
      required this.onReset,
      required this.onSelectRegion});

  final List<Map<String, dynamic>> regions;
  final int active;
  final int mapped;
  final Map<String, Map<String, dynamic>> costByRegion;
  final Map<String, dynamic>? selectedRegion;
  final String? selectedState;
  final List<dynamic> municipalities;
  final bool stateRegionsLoading;
  final ValueChanged<String> onSelectState;
  final VoidCallback onReset;
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
                  selectedState: selectedState,
                  municipalities: municipalities,
                  onSelectState: onSelectState,
                  onSelect: onSelectRegion)),
          const SizedBox(width: TgdeskSpacing.lg),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.public, color: scheme.primary, size: 30),
              const SizedBox(height: 8),
              Row(children: [
                if (selectedState != null)
                  IconButton(
                    tooltip: 'Voltar ao país',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onReset,
                  ),
                Expanded(
                  child: Text(
                      selectedRegion != null
                          ? selectedRegion!['label'].toString()
                          : selectedState == null
                              ? 'Brasil'
                              : 'Estado selecionado',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(selectedRegion == null && selectedState == null
                  ? 'Selecione um estado no mapa para abrir suas regiões comerciais.'
                  : 'Região selecionada. Abra para administrar cidades, bairros, ruas e CEPs de cobertura.'),
              if (selectedState != null && selectedRegion == null) ...[
                Text('Regiões comerciais',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Expanded(
                  child: regions.isEmpty && stateRegionsLoading
                      ? const Center(child: CircularProgressIndicator())
                      : regions.isEmpty
                          ? const Center(
                              child: Text(
                                  'Nenhuma região cadastrada neste estado.'))
                          : ListView(
                              children: [
                                for (final region in regions)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.location_on_outlined,
                                        size: 18),
                                    title: Text(region['label']?.toString() ??
                                        'Região'),
                                    onTap: () => onSelectRegion(region),
                                  ),
                              ],
                            ),
                ),
              ] else if (selectedRegion != null) ...[
                Text('Cidades da região',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Expanded(
                  child: municipalities.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          children: [
                            for (final raw in municipalities)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                    Icons.location_city_outlined,
                                    size: 18),
                                title: Text((raw as Map)['name']?.toString() ??
                                    'Cidade'),
                                subtitle: Text(
                                    '${(raw)['uf_sigla'] ?? ''} · IBGE ${(raw)['ibge_id'] ?? '-'}'),
                              ),
                          ],
                        ),
                ),
              ] else
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
      required this.selectedState,
      required this.municipalities,
      required this.onSelectState,
      required this.onSelect});
  final List<Map<String, dynamic>> regions;
  final Map<String, Map<String, dynamic>> costByRegion;
  final Map<String, dynamic>? selectedRegion;
  final String? selectedState;
  final List<dynamic> municipalities;
  final ValueChanged<String> onSelectState;
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
  List<_IbgeShape> _municipalityShapes = const [];
  String? _municipalitiesForRegion;

  @override
  void initState() {
    super.initState();
    _loadMunicipalityShapes(widget.selectedRegion);
  }

  @override
  void didUpdateWidget(covariant _BrazilMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.selectedRegion?['id']?.toString();
    final newId = widget.selectedRegion?['id']?.toString();
    if (oldId != newId) _loadMunicipalityShapes(widget.selectedRegion);
  }

  Future<void> _loadMunicipalityShapes(Map<String, dynamic>? region) async {
    final regionId = region?['id']?.toString();
    if (regionId == null || regionId.isEmpty) {
      if (mounted)
        setState(() {
          _municipalitiesForRegion = null;
          _municipalityShapes = const [];
        });
      return;
    }
    _municipalitiesForRegion = regionId;
    try {
      final rows = await TgdeskApi.regionMunicipalities(regionId);
      final ids = rows
          .whereType<Map>()
          .map((row) => row['ibge_id'])
          .whereType<num>()
          .map((id) => id.toString())
          .toSet();
      final client = HttpClient();
      try {
        final shapes = await Future.wait(ids.map((id) async {
          final request = await client.getUrl(Uri.parse(
              'https://servicodados.ibge.gov.br/api/v2/malhas/$id?formato=application/vnd.geo+json&qualidade=minima'));
          final response = await request.close();
          final text = await utf8.decoder.bind(response).join();
          return _IbgeShape.fromGeoJson(id, jsonDecode(text) as Map);
        }));
        if (mounted && _municipalitiesForRegion == regionId) {
          setState(() => _municipalityShapes = shapes);
        }
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      if (mounted && _municipalitiesForRegion == regionId) {
        setState(() => _municipalityShapes = const []);
      }
    }
  }

  Future<List<_IbgeShape>> _load() async {
    final client = HttpClient();
    try {
      final responses = await Future.wait(_uf.map((id) async {
        final request = await client.getUrl(Uri.parse(
            'https://servicodados.ibge.gov.br/api/v2/malhas/$id?formato=application/vnd.geo+json&qualidade=minima'));
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        return _IbgeShape.fromGeoJson(id, jsonDecode(text) as Map);
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
          return LayoutBuilder(builder: (context, constraints) {
            final selected = widget.selectedState == null
                ? null
                : snapshot.data!
                    .where((shape) => shape.id == widget.selectedState)
                    .firstOrNull;
            final selectedPoints =
                selected?.rings.expand((ring) => ring).toList() ??
                    const <(double, double)>[];
            final minLon = selectedPoints.isEmpty
                ? 0.0
                : selectedPoints
                    .map((p) => p.$1)
                    .reduce((a, b) => a < b ? a : b);
            final maxLon = selectedPoints.isEmpty
                ? 0.0
                : selectedPoints
                    .map((p) => p.$1)
                    .reduce((a, b) => a > b ? a : b);
            final minLat = selectedPoints.isEmpty
                ? 0.0
                : selectedPoints
                    .map((p) => p.$2)
                    .reduce((a, b) => a < b ? a : b);
            final maxLat = selectedPoints.isEmpty
                ? 0.0
                : selectedPoints
                    .map((p) => p.$2)
                    .reduce((a, b) => a > b ? a : b);
            final lonSpan = (maxLon - minLon).abs().clamp(.1, double.infinity);
            final latSpan = (maxLat - minLat).abs().clamp(.1, double.infinity);
            return GestureDetector(
                onTapUp: (details) {
                  if (widget.selectedState != null) return;
                  final lon =
                      details.localPosition.dx / constraints.maxWidth * 40 - 74;
                  final lat =
                      5 - details.localPosition.dy / constraints.maxHeight * 40;
                  for (final shape in snapshot.data!) {
                    if (shape.contains(lon, lat)) {
                      widget.onSelectState(shape.id);
                      break;
                    }
                  }
                },
                child: Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(
                          painter: _BrazilMapPainter(
                              Theme.of(context).colorScheme,
                              snapshot.data!,
                              widget.selectedState,
                              _municipalityShapes))),
                  ...widget.regions
                      .where((item) =>
                          item['center_lat'] is num &&
                          item['center_lon'] is num)
                      .map((item) {
                    final lat = (item['center_lat'] as num).toDouble();
                    final lon = (item['center_lon'] as num).toDouble();
                    final x = selected == null
                        ? ((lon + 74.2) / 40.2).clamp(0.05, .95).toDouble()
                        : (8 +
                                (lon - minLon) /
                                    lonSpan *
                                    (constraints.maxWidth - 16)) /
                            constraints.maxWidth;
                    final y = selected == null
                        ? ((5.4 - lat) / 40.2).clamp(0.05, .95).toDouble()
                        : (8 +
                                (maxLat - lat) /
                                    latSpan *
                                    (constraints.maxHeight - 16)) /
                            constraints.maxHeight;
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
          });
        },
      );
}

class _BrazilMapPainter extends CustomPainter {
  const _BrazilMapPainter(
      this.scheme, this.shapes, this.selectedId, this.municipalityShapes);
  final ColorScheme scheme;
  final List<_IbgeShape> shapes;
  final String? selectedId;
  final List<_IbgeShape> municipalityShapes;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = selectedId == null
        ? null
        : shapes.where((shape) => shape.id == selectedId).firstOrNull;
    final sourcePoints =
        (selected?.rings ?? shapes.expand((shape) => shape.rings))
            .expand((ring) => ring)
            .toList();
    final minLon =
        sourcePoints.map((p) => p.$1).reduce((a, b) => a < b ? a : b);
    final maxLon =
        sourcePoints.map((p) => p.$1).reduce((a, b) => a > b ? a : b);
    final minLat =
        sourcePoints.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    final maxLat =
        sourcePoints.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    final lonSpan = (maxLon - minLon).abs().clamp(.1, double.infinity);
    final latSpan = (maxLat - minLat).abs().clamp(.1, double.infinity);
    final border = Paint()
      ..color = scheme.outline.withOpacity(.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final shape in shapes) {
      if (selected != null && shape.id != selected.id) continue;
      final fill = Paint()
        ..color = shape.id == selectedId
            ? scheme.primary.withOpacity(.42)
            : scheme.primaryContainer;
      final path = Path();
      for (final ring in shape.rings) {
        for (var i = 0; i < ring.length; i++) {
          final p = ring[i];
          final x = selected == null
              ? (p.$1 + 74.0) / 40.0 * size.width
              : 8 + (p.$1 - minLon) / lonSpan * (size.width - 16);
          final y = selected == null
              ? (5.0 - p.$2) / 40.0 * size.height
              : 8 + (maxLat - p.$2) / latSpan * (size.height - 16);
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
    if (municipalityShapes.isNotEmpty) {
      final municipalityBorder = Paint()
        ..color = scheme.tertiary.withOpacity(.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      final municipalityFill = Paint()
        ..color = scheme.tertiary.withOpacity(.12)
        ..style = PaintingStyle.fill;
      for (final shape in municipalityShapes) {
        final path = Path();
        for (final ring in shape.rings) {
          for (var i = 0; i < ring.length; i++) {
            final p = ring[i];
            final x = 8 + (p.$1 - minLon) / lonSpan * (size.width - 16);
            final y = 8 + (maxLat - p.$2) / latSpan * (size.height - 16);
            if (i == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          path.close();
        }
        canvas.drawPath(path, municipalityFill);
        canvas.drawPath(path, municipalityBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BrazilMapPainter oldDelegate) =>
      oldDelegate.scheme != scheme ||
      oldDelegate.shapes != shapes ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.municipalityShapes != municipalityShapes;
}

class _IbgeShape {
  const _IbgeShape(this.id, this.rings);
  final String id;
  final List<List<(double, double)>> rings;
  factory _IbgeShape.fromGeoJson(String id, Map json) {
    final geometry =
        ((json['features'] as List).first as Map)['geometry'] as Map;
    final raw = geometry['coordinates'] as List;
    final polygons = geometry['type'] == 'MultiPolygon'
        ? raw.expand((p) => p as List).toList()
        : raw;
    return _IbgeShape(
        id,
        polygons
            .map<List<(double, double)>>(
                (ring) => (ring as List).map<(double, double)>((point) {
                      final p = point as List;
                      return (
                        (p[0] as num).toDouble(),
                        (p[1] as num).toDouble()
                      );
                    }).toList())
            .toList());
  }

  bool contains(double lon, double lat) {
    for (final ring in rings) {
      var inside = false;
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final xi = ring[i].$1;
        final yi = ring[i].$2;
        final xj = ring[j].$1;
        final yj = ring[j].$2;
        final crosses = (yi > lat) != (yj > lat);
        if (crosses && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return false;
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
