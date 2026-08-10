import 'package:flutter/material.dart';

import 'api_client.dart';

/// Onde o admin declara que uma máquina é um servidor de serviço.
///
/// Ser serviço não dá poder nenhum: o tier não vê nada a mais e não administra
/// ninguém. Ele diz que aquela máquina não tem operador humano e por isso é
/// legítimo qualquer dispositivo da VPN pedir para alcançá-la — e é isso que
/// torna a promoção uma decisão de infraestrutura, e não uma permissão.
///
/// Por isso a janela: só aparece aqui o que foi vinculado há pouco. Um avulso
/// antigo, já em operação e já esquecido, não pode virar destino de ingresso
/// aberto por engano. A janela é do servidor — esta tela apenas reflete o que
/// ele aceitaria — e vale só para promover; desfazer nunca tem prazo.
class AdminCrmServicesTab extends StatefulWidget {
  const AdminCrmServicesTab({super.key});

  @override
  State<AdminCrmServicesTab> createState() => _AdminCrmServicesTabState();
}

class _AdminCrmServicesTabState extends State<AdminCrmServicesTab> {
  List<Map<String, dynamic>> _devices = const [];
  String _window = '';
  bool _loading = true;
  String? _busyDeviceId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await TgdeskApi.crmDevices();
      final devices = (response['devices'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _window = response['promotion_window']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setTier(String deviceId, bool enabled) async {
    setState(() => _busyDeviceId = deviceId);
    try {
      await TgdeskApi.setCrmTier(deviceId, enabled);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final servers =
        _devices.where((d) => d['role'] == 'crm').toList(growable: false);
    final candidates =
        _devices.where((d) => d['role'] != 'crm').toList(growable: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) _ErrorBanner(message: _error!),
          _Section(
            title: 'Servidores de serviço',
            subtitle: servers.isEmpty
                ? 'Nenhum servidor promovido. Promova um dispositivo abaixo.'
                : 'O endereço é o que o instalador do produto precisa conhecer.',
          ),
          for (final device in servers)
            _DeviceTile(
              device: device,
              busy: _busyDeviceId == device['device_id'],
              actionLabel: 'Rebaixar',
              onAction: () => _setTier('${device['device_id']}', false),
            ),
          const SizedBox(height: 24),
          _Section(
            title: 'Candidatos',
            subtitle: candidates.isEmpty
                ? 'Nenhum dispositivo dentro da janela de $_window desde o vínculo.'
                : 'Vinculados há menos de $_window, do mais recente para o mais antigo.',
          ),
          for (final device in candidates)
            _DeviceTile(
              device: device,
              busy: _busyDeviceId == device['device_id'],
              actionLabel: 'Promover',
              onAction: () => _setTier('${device['device_id']}', true),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.busy,
    required this.actionLabel,
    required this.onAction,
  });

  final Map<String, dynamic> device;
  final bool busy;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ip = '${device['wg_virtual_ip'] ?? ''}';
    final org = '${device['organization'] ?? ''}';
    final network = '${device['network'] ?? ''}';
    final detalhe = [
      if (ip.isNotEmpty) ip,
      if (org.isNotEmpty) org,
      if (network.isNotEmpty) network,
    ].join('  ·  ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${device['hostname'] ?? device['device_id']}'),
        subtitle: Text(detalhe.isEmpty ? 'sem endereço na VPN' : detalhe),
        trailing: busy
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator())
            : TextButton(onPressed: onAction, child: Text(actionLabel)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
    );
  }
}
