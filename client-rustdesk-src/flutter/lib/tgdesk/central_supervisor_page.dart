import 'package:flutter/material.dart';

import 'control_channel.dart';
import 'diagnostico_page.dart';
import 'theme.dart';

/// A central do supervisor — controle, análise e acesso, por organização.
///
/// A separação de papéis que esta tela materializa:
///
///   * o **admin** administra o PRODUTO — taxas, precificação, catálogo,
///     regiões, funcionamento. É configuração, e muda raramente.
///   * o **supervisor** opera o PARQUE — as organizações de que ele participa,
///     as máquinas delas, o que está ruim e o que fazer. É operação, e muda o
///     tempo todo.
///
/// Antes, o supervisor tinha uma lista plana de dispositivos. Isso funciona com
/// um cliente e desmonta com dez: ele não pensa em "máquina 7", pensa em "a
/// padaria está com problema". A organização é a unidade de trabalho dele, e a
/// tela passa a ser organizada assim.
///
/// **Nada aqui busca ao montar** (§10.4). Organizações, redes, dispositivos,
/// chamados e diagnósticos já chegaram pelo canal; esta tela é uma VISTA sobre
/// o que o servidor empurrou. É por isso que ela também não tem botão de
/// atualizar — quando o servidor manda coisa nova, ela se redesenha.
class CentralSupervisorPage extends StatelessWidget {
  const CentralSupervisorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final canal = TgdeskControlChannel.instance;
    return AnimatedBuilder(
      animation: canal,
      builder: (context, _) {
        final orgs = _montarOrganizacoes(canal);
        if (orgs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nenhuma organização no seu escopo ainda.\n'
                'Elas aparecem aqui assim que houver rede e dispositivo vinculados.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ResumoDoParque(orgs: orgs),
            const SizedBox(height: 16),
            ...orgs.map((o) => _CartaoDaOrganizacao(org: o)),
          ],
        );
      },
    );
  }
}

/// Um dispositivo já resolvido com o que o canal sabe dele.
class _Maquina {
  _Maquina({
    required this.id,
    required this.nome,
    required this.online,
    required this.diagnostico,
  });

  final String id;
  final String nome;
  final bool online;
  final Map<String, dynamic>? diagnostico;

  String get status => (diagnostico?['status'] ?? '') as String;

  /// Uma máquina "precisa de atenção" quando o servidor concluiu ALGUMA COISA
  /// sobre ela. Sem status, não é "está tudo bem" — é "nada visível à
  /// distância", que é diferente e a tela não deve confundir.
  bool get precisaAtencao => status.isNotEmpty;
}

class _Organizacao {
  _Organizacao({required this.id, required this.nome, required this.maquinas});

  final String id;
  final String nome;
  final List<_Maquina> maquinas;

  int get online => maquinas.where((m) => m.online).length;
  int get comStatus => maquinas.where((m) => m.precisaAtencao).length;
}

/// Compõe a árvore org → rede → dispositivo a partir do que o canal entregou.
///
/// A ligação passa por REDE porque é assim que o escopo funciona no servidor:
/// dispositivo pertence a rede, rede pertence a organização. Atalhar isso aqui
/// criaria uma segunda regra de visibilidade no cliente — e duas regras de
/// visibilidade divergem no dia em que alguém mudar uma só.
List<_Organizacao> _montarOrganizacoes(TgdeskControlChannel canal) {
  final orgDaRede = <String, String>{};
  for (final n in canal.networks) {
    if (n is! Map) continue;
    final id = n['id']?.toString();
    final org = n['organization_id']?.toString();
    if (id != null && org != null) orgDaRede[id] = org;
  }

  final nomeDaOrg = <String, String>{};
  for (final o in canal.organizations) {
    if (o is! Map) continue;
    final id = o['id']?.toString();
    if (id != null) nomeDaOrg[id] = (o['name'] ?? 'Organização').toString();
  }

  final porOrg = <String, List<_Maquina>>{};
  for (final d in canal.devices) {
    if (d is! Map) continue;
    final id = d['id']?.toString();
    if (id == null) continue;

    // `network_ids` é a lista completa; `network_id` é o vínculo principal.
    // Uma máquina pode estar em mais de uma rede, e nesse caso ela aparece em
    // cada organização — que é o comportamento certo: o supervisor de cada
    // uma precisa vê-la.
    final redes = <String>{
      if (d['network_id'] != null) d['network_id'].toString(),
      ...((d['network_ids'] as List? ?? const []).map((e) => e.toString())),
    };

    final nome = (d['display_name']?.toString().trim().isNotEmpty ?? false)
        ? d['display_name'].toString()
        : (d['hostname']?.toString() ?? 'Dispositivo');

    final maquina = _Maquina(
      id: id,
      nome: nome,
      online: d['presence']?.toString() == 'online',
      diagnostico: canal.diagnosticoDe(id),
    );

    for (final rede in redes) {
      final org = orgDaRede[rede];
      if (org == null) continue;
      porOrg.putIfAbsent(org, () => []).add(maquina);
    }
  }

  final orgs = porOrg.entries
      .map((e) => _Organizacao(
            id: e.key,
            nome: nomeDaOrg[e.key] ?? 'Organização',
            maquinas: e.value,
          ))
      .toList();

  // Ordem por urgência, não alfabética: a organização com mais máquinas
  // precisando de atenção é a que o supervisor deve olhar primeiro. Ordenar
  // por nome faria a tela ignorar o que ela sabe.
  orgs.sort((a, b) {
    final porAtencao = b.comStatus.compareTo(a.comStatus);
    return porAtencao != 0 ? porAtencao : a.nome.compareTo(b.nome);
  });
  return orgs;
}

class _ResumoDoParque extends StatelessWidget {
  const _ResumoDoParque({required this.orgs});
  final List<_Organizacao> orgs;

  @override
  Widget build(BuildContext context) {
    final maquinas = orgs.fold<int>(0, (s, o) => s + o.maquinas.length);
    final online = orgs.fold<int>(0, (s, o) => s + o.online);
    final atencao = orgs.fold<int>(0, (s, o) => s + o.comStatus);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          _Numero(valor: '${orgs.length}', rotulo: 'organizações'),
          const SizedBox(width: 28),
          _Numero(valor: '$maquinas', rotulo: 'máquinas'),
          const SizedBox(width: 28),
          _Numero(
              valor: '$online',
              rotulo: 'online',
              cor: online > 0 ? TgdeskSeverityColors.ok : null),
          const SizedBox(width: 28),
          _Numero(
              valor: '$atencao',
              rotulo: 'com diagnóstico',
              cor: atencao > 0 ? TgdeskSeverityColors.warning : null),
        ]),
      ),
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({required this.valor, required this.rotulo, this.cor});
  final String valor;
  final String rotulo;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: cor)),
          Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
}

class _CartaoDaOrganizacao extends StatelessWidget {
  const _CartaoDaOrganizacao({required this.org});
  final _Organizacao org;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: org.comStatus > 0,
        leading: Icon(
          org.comStatus > 0 ? Icons.warning_amber : Icons.business_outlined,
          color: org.comStatus > 0 ? TgdeskSeverityColors.warning : null,
        ),
        title: Text(org.nome,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${org.maquinas.length} máquinas · ${org.online} online'
            '${org.comStatus > 0 ? ' · ${org.comStatus} com diagnóstico' : ''}'),
        children: [
          // Máquinas com diagnóstico primeiro: é o que o supervisor abriu a
          // organização para ver.
          ...(org.maquinas.toList()
                ..sort((a, b) {
                  final porStatus = (b.precisaAtencao ? 1 : 0)
                      .compareTo(a.precisaAtencao ? 1 : 0);
                  return porStatus != 0 ? porStatus : a.nome.compareTo(b.nome);
                }))
              .map((m) => _LinhaDaMaquina(maquina: m)),
        ],
      ),
    );
  }
}

class _LinhaDaMaquina extends StatelessWidget {
  const _LinhaDaMaquina({required this.maquina});
  final _Maquina maquina;

  @override
  Widget build(BuildContext context) {
    final d = maquina.diagnostico;
    final causas = (d?['causas'] as List? ?? const []);

    // A frase de uma linha: o que está errado e o que fazer. Vem renderizada do
    // servidor — o cliente nunca compõe diagnóstico (§12.1).
    String resumo;
    if (!maquina.precisaAtencao) {
      resumo = 'Nada visível à distância';
    } else if (causas.isEmpty) {
      resumo = (d?['status_descricao'] ?? maquina.status) as String;
    } else {
      final c = Map<String, dynamic>.from(causas.first as Map);
      final slots = Map<String, dynamic>.from(c['slots'] as Map? ?? const {});
      final acao = (slots['acao'] ?? '') as String;
      final titulo = (slots['titulo'] ?? c['codigo'] ?? '') as String;
      resumo = acao.isNotEmpty ? '$titulo — $acao' : titulo;
    }

    return ListTile(
      dense: true,
      leading: Icon(Icons.circle,
          size: 10,
          color: maquina.online
              ? TgdeskSeverityColors.ok
              : Theme.of(context).disabledColor),
      title: Text(maquina.nome),
      subtitle: Text(resumo, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.troubleshoot),
        tooltip: 'Diagnóstico',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DiagnosticoPage(
            deviceId: maquina.id,
            deviceName: maquina.nome,
          ),
        )),
      ),
    );
  }
}
