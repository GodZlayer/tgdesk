import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'client_home_page.dart';
import 'control_channel.dart';
import 'hub_home_page.dart';
import 'api_client.dart';
import 'technician_identity.dart';
import 'technician_home_page.dart';

class TgdeskBootstrapPage extends StatefulWidget {
  const TgdeskBootstrapPage({super.key});

  @override
  State<TgdeskBootstrapPage> createState() => _TgdeskBootstrapPageState();
}

class _TgdeskBootstrapPageState extends State<TgdeskBootstrapPage> {
  bool _loading = true;
  bool _technician = false;
  String _stage = 'Iniciando o TGDesk...';

  @override
  void initState() {
    super.initState();
    // TgdeskControlChannel já é reativo (ChangeNotifier) e já reconecta
    // sozinho a cada 2s indefinidamente quando uma tentativa falha — não
    // precisa de um laço de retry manual aqui. O bug real era que esta tela
    // só olhava o resultado da PRIMEIRA tentativa e travava a decisão pra
    // sempre: se a rede ainda estivesse se acomodando logo após reiniciar o
    // serviço, caía pra Cliente e nunca mais reavaliava, mesmo a conexão
    // ficando boa segundos depois. Agora escuta o canal e promove pra
    // técnico assim que ele conectar de verdade, em tempo real.
    TgdeskControlChannel.instance.addListener(_onControlChannelChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    TgdeskControlChannel.instance.removeListener(_onControlChannelChanged);
    super.dispose();
  }

  void _onControlChannelChanged() {
    if (!mounted || _technician) return;
    if (TgdeskControlChannel.instance.connected) {
      setState(() => _technician = true);
    }
  }

  Future<void> _bootstrap() async {
    try {
      await Process.start(Platform.resolvedExecutable, const ['--tray'],
          mode: ProcessStartMode.detached,
          workingDirectory: File(Platform.resolvedExecutable).parent.path);
    } catch (_) {}
    _setStage('Lendo a identidade deste computador...');
    final installed = await importInstallerEnrollment();
    final credential = await loadTechnicianCredential();
    var authenticated = false;
    if (credential != null) {
      _setStage('Aguardando a rede privada administrativa...');
      final ready = await _waitForPrivateControl();
      if (ready) {
        _setStage('Autenticando pelo canal privado...');
        try {
          if (installed && AppState.isLoggedIn) {
            await TgdeskControlChannel.instance.start();
            authenticated = TgdeskControlChannel.instance.connected;
          } else {
            authenticated = await TgdeskControlChannel.instance
                .authenticateAndStart(credential.toJson());
          }
        } catch (_) {
          authenticated = false;
        }
      }
    }
    if (mounted) {
      setState(() {
        // _onControlChannelChanged pode já ter promovido pra técnico
        // enquanto isto rodava (o canal reconectou sozinho); nunca rebaixa.
        _technician = _technician || authenticated;
        _loading = false;
      });
    }
  }

  void _setStage(String value) {
    if (mounted) setState(() => _stage = value);
  }

  Future<bool> _waitForPrivateControl() async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect('10.70.0.1', 8080,
            timeout: const Duration(seconds: 2));
        socket.destroy();
        return true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  void _activated() {
    unawaited(TgdeskControlChannel.instance.start());
    setState(() => _technician = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_stage),
            ],
          ),
        ),
      );
    }
    if (_technician) {
      return AppState.isFreelancer
          ? const TgdeskTechnicianHomePage()
          : const HubHomePage();
    }
    return TgdeskClientHomePage(onTechnicianActivated: _activated);
  }
}
