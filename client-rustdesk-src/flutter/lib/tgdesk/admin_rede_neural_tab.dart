import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

/// A aba do admin sobre a rede neural (§10.5.3, §14).
///
/// Existe porque a arquitetura inteira se apoia em CALIBRAÇÃO VISÍVEL — "quando
/// dizemos 70–80%, acertamos 74% em 112 casos". Sem uma tela que mostre isso, o
/// número na frente do técnico volta a ser oráculo, e o produto perde a única
/// defesa que tem contra um modelo que começou a mentir.
///
/// O que esta tela recusa a fazer: inventar. Faixa sem histórico suficiente
/// aparece como "sem histórico", nunca como um número; e o motor vigente é
/// mostrado como ele é, não como a gente gostaria que fosse — existir um modelo
/// treinado no banco NÃO significa que ele está decidindo.
///
/// Esta é a única tela do produto que busca ao montar, e a exceção é
/// deliberada: §10.4 fala do fluxo do técnico, que precisa estar pronto antes
/// do clique. Aqui é auditoria sob demanda, de um humano que abriu a tela para
/// investigar — empurrar isto pelo canal para todo mundo seria carregar dado
/// que ninguém está olhando.
class AdminRedeNeuralTab extends StatefulWidget {
  const AdminRedeNeuralTab({super.key});

  @override
  State<AdminRedeNeuralTab> createState() => _AdminRedeNeuralTabState();
}

class _AdminRedeNeuralTabState extends State<AdminRedeNeuralTab> {
  Map<String, dynamic>? _painel;
  Object? _erro;
  bool _carregando = true;
  bool _treinando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await TgdeskApi.painelRedeNeural();
      if (mounted) setState(() => _painel = r);
    } catch (e) {
      if (mounted) setState(() => _erro = e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _treinar() async {
    setState(() => _treinando = true);
    try {
      final r = await TgdeskApi.treinarRedeNeural();
      final treinados = (r['treinados'] as List? ?? const []).length;
      final recusados = (r['recusados'] as List? ?? const []).length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Treino concluído: $treinados cabeçote(s), '
              '$recusados status recusado(s) por volume.'),
        ));
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falha no treino: $e')));
      }
    } finally {
      if (mounted) setState(() => _treinando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando && _painel == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null && _painel == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Não foi possível ler o painel: $_erro'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _carregar, child: const Text('Tentar novamente')),
        ]),
      );
    }

    final p = _painel!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _QuemResponde(painel: p),
      const SizedBox(height: 16),
      _Modelos(modelos: (p['modelos'] as List? ?? const [])),
      const SizedBox(height: 16),
      _Conjunto(
        conjunto: Map<String, dynamic>.from(p['conjunto_de_treino'] as Map? ?? {}),
        treinando: _treinando,
        aoTreinar: _treinar,
      ),
      const SizedBox(height: 16),
      _Laco(laco: Map<String, dynamic>.from(p['laco_rat'] as Map? ?? {})),
      const SizedBox(height: 16),
      _Calibracao(faixas: (p['calibracao_de_campo'] as List? ?? const [])),
      const SizedBox(height: 16),
      _Ontologia(statuses: (p['ontologia'] as List? ?? const [])),
    ]);
  }
}

/// O bloco mais importante da tela: QUEM responde hoje.
///
/// Fica no topo porque é o mal-entendido mais provável — ver um modelo treinado
/// na lista abaixo e concluir que ele está decidindo.
class _QuemResponde extends StatelessWidget {
  const _QuemResponde({required this.painel});
  final Map<String, dynamic> painel;

  @override
  Widget build(BuildContext context) {
    final motor = (painel['motor_vigente'] ?? '') as String;
    final ehModelo = motor == 'modelo';
    return Card(
      child: ListTile(
        leading: Icon(
          ehModelo ? Icons.hub : Icons.rule,
          color: ehModelo ? TgdeskColors.primary : TgdeskSeverityColors.warning,
          size: 32,
        ),
        title: Text(
          ehModelo ? 'A rede está decidindo' : 'A camada de regra está decidindo',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text((painel['motivo_do_motor'] ?? '') as String),
      ),
    );
  }
}

class _Modelos extends StatelessWidget {
  const _Modelos({required this.modelos});
  final List<dynamic> modelos;

  @override
  Widget build(BuildContext context) {
    if (modelos.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.hub_outlined),
          title: Text('Nenhum modelo treinado'),
          subtitle: Text(
            'Nenhum status atingiu o volume mínimo de exemplos. '
            'Isso não é falha: a camada de regra responde sozinha, e o produto '
            'funciona sem rede nenhuma.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Modelos', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...modelos.map((m) => _UmModelo(m: Map<String, dynamic>.from(m as Map))),
        ]),
      ),
    );
  }
}

class _UmModelo extends StatelessWidget {
  const _UmModelo({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final estado = (m['estado'] ?? '') as String;
    final bloqueios = (m['bloqueios_para_promover'] as List? ?? const []);
    final causas = (m['causas'] as List? ?? const []).join(', ');

    return ExpansionTile(
      leading: _ChipDeEstado(estado: estado),
      title: Text((m['status_codigo'] ?? '') as String),
      subtitle: Text('${m['n_treino']} treino · ${m['n_validacao']} validação · '
          '${m['n_simulado']} simulados'),
      children: [
        _linha('Causas que ele distingue', causas),
        _linha('Acurácia', _num(m['acuracia'])),
        // As duas linhas que mais importam, e a ordem não é acidental: ECE
        // primeiro porque o requisito do projeto é calibração, não acurácia.
        _linha('Erro de calibração (ECE)', _num(m['ece'], casas: 4),
            nota: 'o quanto a probabilidade que ele diz corresponde ao acerto real'),
        _linha('Log-loss do modelo', _num(m['log_loss'], casas: 3)),
        _linha('Log-loss da regra', _num(m['log_loss_regra'], casas: 3),
            nota: 'o baseline que ele precisa bater para valer a pena'),
        _linha('Temperatura de calibração', _num(m['temperatura'], casas: 2)),
        _linha('Versão', (m['codigo'] ?? '') as String),
        if (bloqueios.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Por que ainda não decide',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...bloqueios.map((b) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('· $b'),
                  )),
            ]),
          ),
        ],
      ],
    );
  }

  static Widget _linha(String rotulo, String valor, {String nota = ''}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 210, child: Text(rotulo)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(valor, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (nota.isNotEmpty)
                Text(nota, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        ]),
      );

  static String _num(dynamic v, {int casas = 3}) =>
      v == null ? '—' : (v as num).toDouble().toStringAsFixed(casas);
}

class _ChipDeEstado extends StatelessWidget {
  const _ChipDeEstado({required this.estado});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final (cor, rotulo) = switch (estado) {
      'promovido' => (TgdeskSeverityColors.ok, 'decide'),
      'rebaixado' => (TgdeskSeverityColors.critical, 'rebaixado'),
      _ => (TgdeskSeverityColors.warning, 'sombra'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(rotulo, style: TextStyle(color: cor, fontSize: 11)),
    );
  }
}

class _Conjunto extends StatelessWidget {
  const _Conjunto({
    required this.conjunto,
    required this.treinando,
    required this.aoTreinar,
  });

  final Map<String, dynamic> conjunto;
  final bool treinando;
  final Future<void> Function() aoTreinar;

  @override
  Widget build(BuildContext context) {
    final total = (conjunto['total'] ?? 0) as int;
    final reais = (conjunto['reais'] ?? 0) as int;
    final porOrigem = Map<String, dynamic>.from(conjunto['por_origem'] as Map? ?? {});

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Com que dado ele aprendeu',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('$total exemplos, dos quais $reais vieram da realidade'),
          const SizedBox(height: 4),
          ...porOrigem.entries.map((e) => Text('· ${_origem(e.key)}: ${e.value}')),
          const SizedBox(height: 8),
          // A frase que impede a leitura errada do número acima.
          const Text(
            'Exemplo simulado TREINA, mas nunca promove nem calibra: métrica '
            'calculada sobre simulação é métrica do simulador. Quem destrava a '
            'promoção é o caso real, que nasce do fechamento de atendimento.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: treinando ? null : () => aoTreinar(),
            icon: treinando
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.model_training),
            label: Text(treinando ? 'Treinando…' : 'Treinar agora'),
          ),
          const SizedBox(height: 4),
          const Text(
            'O treino sempre grava em sombra. Não existe caminho, nesta tela ou '
            'em qualquer outra, que promova um modelo sem o gate de calibração.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ]),
      ),
    );
  }

  static String _origem(String k) => switch (k) {
        'simulado_corpus' => 'simulados do corpus de fórum',
        'interno_rat' => 'reais, do laço RAT',
        'interno_escada' => 'reais, do teste completo',
        _ => k,
      };
}

class _Laco extends StatelessWidget {
  const _Laco({required this.laco});
  final Map<String, dynamic> laco;

  @override
  Widget build(BuildContext context) {
    final total = (laco['total'] ?? 0) as int;
    final obs = (laco['observacao'] ?? '') as String;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Suposição da rede × o que o técnico encontrou',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'É daqui que sai o melhor rótulo de treino que o produto consegue: '
            'não "resolvido/não resolvido", e sim a causa que a rede apontou '
            'contra a causa encontrada com a máquina na mão.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text(obs.isEmpty ? 'Sem comparações ainda.' : obs)
          else ...[
            Wrap(spacing: 16, runSpacing: 8, children: [
              _Placar(rotulo: 'acertou', n: laco['acertos'], cor: TgdeskSeverityColors.ok),
              _Placar(rotulo: 'errou', n: laco['erros'], cor: TgdeskSeverityColors.critical),
              _Placar(rotulo: 'absteve certo', n: laco['abstencoes_corretas'], cor: TgdeskColors.primary),
              _Placar(rotulo: 'absteve à toa', n: laco['abstencoes_indevidas'], cor: TgdeskSeverityColors.warning),
            ]),
            const SizedBox(height: 12),
            const Text('Utilidade, na avaliação do supervisor',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _Placar(rotulo: 'ajudou', n: laco['ajudou'], cor: TgdeskSeverityColors.ok),
              _Placar(rotulo: 'atrapalhou', n: laco['atrapalhou'], cor: TgdeskSeverityColors.critical),
              _Placar(rotulo: 'indiferente', n: laco['indiferente'], cor: Colors.grey),
            ]),
            const SizedBox(height: 8),
            // A regra que impede o laço de virar cobrança do técnico.
            const Text(
              'Divergência não é erro do técnico: o que se ajusta é a rede, e o '
              'caso entra no treino com peso maior — é justamente onde ela errava.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if ((laco['pendentes_avaliar'] ?? 0) as int > 0) ...[
              const SizedBox(height: 8),
              Text('${laco['pendentes_avaliar']} aguardando avaliação do supervisor',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ],
        ]),
      ),
    );
  }
}

class _Placar extends StatelessWidget {
  const _Placar({required this.rotulo, required this.n, required this.cor});
  final String rotulo;
  final dynamic n;
  final Color cor;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${n ?? 0}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cor)),
          Text(rotulo, style: const TextStyle(fontSize: 11)),
        ],
      );
}

/// "Quando dizemos 70–80%, acertamos 74% em 112 casos" (§10.5.3).
class _Calibracao extends StatelessWidget {
  const _Calibracao({required this.faixas});
  final List<dynamic> faixas;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Calibração medida em campo',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'É o que transforma a probabilidade em argumento em vez de oráculo — '
            'e é calculada SÓ sobre atendimento real avaliado. Caso simulado '
            'nunca entra aqui.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          if (faixas.isEmpty)
            const Text(
              'Sem histórico de campo ainda. Cada atendimento fechado com a '
              'causa marcada acrescenta uma linha aqui.',
            )
          else
            ...faixas.map((f) {
              final m = Map<String, dynamic>.from(f as Map);
              final de = ((m['de'] as num) * 100).round();
              final ate = ((m['ate'] as num) * 100).round();
              final acerto = m['acerto_real'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(acerto == null
                    ? 'Quando dizemos $de–$ate%: ${m['n']} casos — ${m['motivo']}'
                    : 'Quando dizemos $de–$ate%, acertamos '
                        '${((acerto as num) * 100).round()}% em ${m['n']} casos'),
              );
            }),
        ]),
      ),
    );
  }
}

class _Ontologia extends StatelessWidget {
  const _Ontologia({required this.statuses});
  final List<dynamic> statuses;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('O que ele sabe distinguir',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Cada status negativo tem um conjunto FECHADO de causas. O softmax '
            'da rede distribui probabilidade dentro dele, e o fechamento de '
            'chamado escolhe dali — nunca texto livre.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ...statuses.map((s) {
            final m = Map<String, dynamic>.from(s as Map);
            final causas = (m['causas'] as List? ?? const []);
            final limitacoes = (m['limitacoes'] as List? ?? const []);
            return ExpansionTile(
              title: Text((m['codigo'] ?? '') as String),
              subtitle: Text((m['descricao'] ?? '') as String),
              children: [
                ...causas.map((c) {
                  final cm = Map<String, dynamic>.from(c as Map);
                  final prior = ((cm['prior'] as num? ?? 0) * 100).toStringAsFixed(1);
                  final peso = ((cm['peso_externo'] as num? ?? 0) * 100).round();
                  return ListTile(
                    dense: true,
                    title: Text((cm['codigo'] ?? '') as String),
                    subtitle: Text('prior $prior% · ${cm['n_corpus']} casos de fórum · '
                        '${cm['n_interno']} internos · $peso% do peso ainda vem do fórum'),
                  );
                }),
                // A lacuna declarada. Aparece porque causa que o produto NÃO
                // consegue separar à distância precisa estar na tela, não sumir.
                if (limitacoes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      'Não separável à distância: ${limitacoes.join(', ')}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            );
          }),
        ]),
      ),
    );
  }
}
