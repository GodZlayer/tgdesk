import 'package:flutter/material.dart';

import 'remote_session_page.dart';

class RemoteSessionsPane extends StatefulWidget {
  const RemoteSessionsPane({super.key});

  @override
  State<RemoteSessionsPane> createState() => _RemoteSessionsPaneState();
}

class _RemoteSessionsPaneState extends State<RemoteSessionsPane>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _manager = RemoteSessionsManager.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(vsync: this, length: _manager.entries.length);
    _manager.addListener(_onSessionsChanged);
  }

  @override
  void dispose() {
    _manager.removeListener(_onSessionsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onSessionsChanged() {
    if (!mounted) return;
    final newLength = _manager.entries.length;
    if (_tabController.length == newLength) {
      setState(() {});
      return;
    }
    final clampedIndex =
        newLength == 0 ? 0 : _tabController.index.clamp(0, newLength - 1);
    _tabController.dispose();
    _tabController = TabController(vsync: this, length: newLength)
      ..index = clampedIndex;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final entries = _manager.entries;
    if (entries.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.desktop_windows_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Nenhuma sessão de acesso remoto ativa.\n'
            'Conecte-se a um dispositivo a partir da aba Dispositivos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ]),
      );
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: entries.asMap().entries.map((e) => Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(e.value.hostname),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _manager.close(e.value.deviceId),
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ]),
                )).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: entries
                .map((e) => TgdeskRemoteSessionPage(
                      key: ValueKey(e.deviceId),
                      deviceId: e.deviceId,
                      remoteId: e.remoteId,
                      hostname: e.hostname,
                      credential: e.credential,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}
