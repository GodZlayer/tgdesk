import 'package:flutter/material.dart';

import 'diagnostico_modelo.dart';
import 'theme.dart';

/// As quatro telas do técnico (§10.6) e os cinco estados (§10.7).
///
/// Todas se desenham a partir do que já chegou pelo canal. Nenhuma busca dado
/// ao montar — não há `initState` que consulte, não há `FutureBuilder` de
/// carregamento. Se o dado não chegou, a tela mostra o estado `vazio`.
///
/// Linguagem visual (§10.8): empresta-se a GRAMÁTICA DE LEITURA das ferramentas
/// que o técnico já conhece — eixo, unidade, escala, o que é vermelho e por quê
/// — e não o cromo. Refazer a forma cobraria dele um retreinamento gratuito.

/// A curva com o ponto de quebra marcado.
///
/// Isto é a EXPLICAÇÃO, não a ilustração (§10.6-C). Uma probabilidade sozinha
/// na tela é pedir ao técnico que confie no oráculo; a mesma probabilidade
/// ancorada na curva é argumento.
class CurvaDaEscada extends StatelessWidget {
  const CurvaDaEscada({
    super.key,
    required this.pontos,
    this.marcas = const [],
    this.altura = 180,
  });

  final List<PontoDaCurva> pontos;
  final List<MarcaNaCurva> marcas;
  final double altura;

  @override
  Widget build(BuildContext context) {
    if (pontos.length < 2) {
      return SizedBox(
        height: altura,
        child: Center(
          child: Text('sem amostras ainda',
              style: TextStyle(color: TgdeskTextColors.muted)),
        ),
      );
    }
    return SizedBox(
      height: altura,
      child: CustomPaint(
        painter: _CurvaPainter(pontos: pontos, marcas: marcas),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CurvaPainter extends CustomPainter {
  const _CurvaPainter({required this.pontos, required this.marcas});

  final List<PontoDaCurva> pontos;
  final List<MarcaNaCurva> marcas;

  @override
  void paint(Canvas canvas, Size size) {
    final escala = EscalaDaCurva.de(pontos);

    // Grade por DEGRAU, não por pixel: o eixo X é carga, e é essa leitura que
    // o técnico precisa fazer — "quebrou no degrau 3", não "quebrou aos 47%".
    final grade = Paint()
      ..color = TgdeskSurfaces.border
      ..strokeWidth = 1;
    for (var d = 1; d <= 5; d++) {
      final x = size.width * (d / 5);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grade);
    }

    final linha = Paint()
      ..color = TgdeskColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final caminho = Path();
    for (var i = 0; i < pontos.length; i++) {
      final x = size.width * (i / (pontos.length - 1));
      final y = size.height * (1 - escala.normalizar(pontos[i].valor));
      if (i == 0) {
        caminho.moveTo(x, y);
      } else {
        caminho.lineTo(x, y);
      }
    }
    canvas.drawPath(caminho, linha);

    for (final m in marcas) {
      final x = size.width * (m.loadLevel / 100).clamp(0.0, 1.0);
      final cor = switch (m.tipo) {
        'quebra' => TgdeskSeverityColors.critical,
        'trava' => TgdeskSeverityColors.critical,
        // Aborto por gate NÃO é vermelho de erro: é evento, e é resultado.
        'gate' => TgdeskSeverityColors.warning,
        _ => TgdeskTextColors.muted,
      };
      final marca = Paint()
        ..color = cor
        ..strokeWidth = m.emAberto ? 3 : 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), marca);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvaPainter old) =>
      old.pontos != pontos || old.marcas != marcas;
}

/// Tela A — Pré-voo. O que vai acontecer, por quê, e quanto vai custar.
class TelaPreVoo extends StatelessWidget {
  const TelaPreVoo({
    super.key,
    required this.preVoo,
    required this.aoConsentir,
    required this.aoExecutar,
  });

  final PreVoo? preVoo;
  final VoidCallback aoConsentir;
  final VoidCallback aoExecutar;

  @override
  Widget build(BuildContext context) {
    final p = preVoo;
    if (p == null) {
      return const _Vazio(mensagem: 'Este dispositivo nunca rodou a escada.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Secao(titulo: 'Inventário', linhas: p.inventario),
        _Secao(titulo: 'Estado em repouso', linhas: p.estadoDeRepouso),
        const SizedBox(height: 12),
        Text('Proteções que serão aplicadas',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        // O motivo vem junto SEMPRE. É o que permite ao técnico saber, antes de
        // começar, que o disco vai rodar só em leitura — e por quê.
        ...p.gates.map((g) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.shield_outlined,
                    size: 16, color: TgdeskSeverityColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text('${g.codigo} — ${g.motivo}')),
              ]),
            )),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.schedule, size: 16),
          const SizedBox(width: 8),
          Text(p.duracao.texto),
        ]),
        const SizedBox(height: 4),
        Text('perfil ${p.perfil} v${p.perfilVersao}',
            style: TextStyle(color: TgdeskTextColors.muted, fontSize: 12)),
        const SizedBox(height: 20),
        // Uma decisão humana entre o chamado chegar e a escada começar:
        // consentir e executar. Todo o resto o servidor propõe (§10.3).
        CheckboxListTile(
          value: p.consentimentoDado,
          onChanged: (_) => aoConsentir(),
          title: const Text('O teste força o equipamento e pode agravar falha '
              'existente. Autorizo a execução.'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: p.consentimentoDado ? aoExecutar : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Executar escada'),
        ),
      ],
    );
  }
}

/// Tela B — Execução ao vivo.
class TelaExecucao extends StatelessWidget {
  const TelaExecucao({
    super.key,
    required this.execucao,
    required this.aoPausar,
    required this.aoCancelar,
  });

  final ExecucaoAoVivo? execucao;
  final VoidCallback aoPausar;
  final VoidCallback aoCancelar;

  @override
  Widget build(BuildContext context) {
    final e = execucao;
    if (e == null) return const _Vazio(mensagem: 'Nada em execução.');

    final travaAberta = e.marcas.where((m) => m.emAberto).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${e.estagio} — degrau ${e.degrau} de ${e.totalDegraus}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: e.totalDegraus == 0 ? 0 : e.degrau / e.totalDegraus,
        ),
        const SizedBox(height: 16),
        CurvaDaEscada(pontos: e.pontos, marcas: e.marcas),
        const SizedBox(height: 12),
        // Trava aparece na hora, com duração ainda em aberto, e fecha quando o
        // heartbeat volta (§10.6-B).
        if (travaAberta.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TgdeskSeverityColors.critical.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber, color: TgdeskSeverityColors.critical),
              const SizedBox(width: 8),
              Expanded(child: Text(travaAberta.first.rotulo)),
            ]),
          ),
        const SizedBox(height: 12),
        Text('restante: ${e.restante.texto}',
            style: TextStyle(color: TgdeskTextColors.muted)),
        const SizedBox(height: 20),
        Row(children: [
          OutlinedButton.icon(
            onPressed: aoPausar,
            icon: Icon(e.pausada ? Icons.play_arrow : Icons.pause),
            label: Text(e.pausada ? 'Retomar' : 'Pausar'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: aoCancelar,
            icon: const Icon(Icons.stop),
            label: const Text('Cancelar'),
          ),
        ]),
      ],
    );
  }
}

/// Tela C — Resultado. A tela principal.
class TelaResultado extends StatelessWidget {
  const TelaResultado({super.key, required this.resultado});

  final ResultadoDoDiagnostico? resultado;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    if (r == null) {
      return const _Vazio(mensagem: 'Nenhum diagnóstico para este dispositivo.');
    }

    // Aborto por gate é resultado, não erro — e a tela diz o que foi medido
    // até ali em vez de jogar tudo fora.
    if (r.estado == EstadoDaTela.abortadoPorGate) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _Cabecalho(
          icone: Icons.shield,
          cor: TgdeskSeverityColors.warning,
          titulo: 'Interrompido por proteção',
          subtitulo: r.motivoAborto,
        ),
        const SizedBox(height: 16),
        CurvaDaEscada(pontos: r.pontos, marcas: r.marcas),
        const SizedBox(height: 16),
        _ProximosPassos(passos: r.proximosPassos),
      ]);
    }

    // Abstenção tem o MESMO peso visual do resultado (§10.7). Não é erro, não
    // é estado degradado: é uma resposta, e diz o que rodar em seguida.
    if (r.estado == EstadoDaTela.abstencao) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        _Cabecalho(
          icone: Icons.help_outline,
          cor: TgdeskColors.primary,
          titulo: 'Sem hipótese dominante',
          subtitulo: r.veredito.isEmpty
              ? 'O dossiê não decide entre as causas candidatas.'
              : r.veredito,
        ),
        const SizedBox(height: 16),
        if (r.pontos.isNotEmpty) CurvaDaEscada(pontos: r.pontos, marcas: r.marcas),
        const SizedBox(height: 16),
        _ProximosPassos(passos: r.proximosPassos),
      ]);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      // 1. Veredito curto — uma frase, gerada por template no servidor.
      Text(r.veredito, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      // 2. Top-3 com barra de probabilidade.
      ...r.causas.map((c) => _LinhaDeCausa(causa: c)),
      const SizedBox(height: 16),
      // 3. A curva com o ponto de quebra marcado.
      CurvaDaEscada(pontos: r.pontos, marcas: r.marcas),
      const SizedBox(height: 16),
      // 4. Evidências da causa nº 1, literais.
      if (r.causas.isNotEmpty) _Evidencias(causa: r.causas.first),
      // 5. O que foi excluído — impede refazer trabalho.
      if (r.excluidas.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Excluído', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        ...r.excluidas.map((e) => Text('· $e')),
      ],
      const SizedBox(height: 16),
      _ProximosPassos(passos: r.proximosPassos),
    ]);
  }
}

/// Tela D — Dossiê. É aqui que o técnico vê que a máquina está piorando.
class TelaDossie extends StatelessWidget {
  const TelaDossie({super.key, required this.execucoes});

  final List<ExecucaoAnterior> execucoes;

  @override
  Widget build(BuildContext context) {
    if (execucoes.isEmpty) {
      return const _Vazio(mensagem: 'Sem histórico para este dispositivo.');
    }
    final comparacao = execucoes.length >= 2
        ? ComparacaoDeLimiar(antes: execucoes[1], depois: execucoes[0])
        : null;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (comparacao != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: TgdeskSurfaces.panelAlt,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Icon(
              comparacao.melhorou ? Icons.trending_up : Icons.trending_down,
              color: comparacao.melhorou
                  ? TgdeskSeverityColors.ok
                  : TgdeskSeverityColors.critical,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(comparacao.texto)),
          ]),
        ),
        const SizedBox(height: 16),
      ],
      ...execucoes.map((e) => _LinhaDeHistorico(execucao: e)),
    ]);
  }
}

// --- peças internas --------------------------------------------------------

class _Vazio extends StatelessWidget {
  const _Vazio({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(mensagem,
              textAlign: TextAlign.center,
              style: TextStyle(color: TgdeskTextColors.muted)),
        ),
      );
}

/// Bloco de "rótulo: valor" — inventário e estado de repouso.
class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.linhas});

  final String titulo;
  final Map<String, String> linhas;

  @override
  Widget build(BuildContext context) {
    if (linhas.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      ...linhas.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              SizedBox(
                width: 150,
                child: Text(e.key,
                    style: TextStyle(color: TgdeskTextColors.muted)),
              ),
              Expanded(child: Text(e.value)),
            ]),
          )),
      const SizedBox(height: 10),
    ]);
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.subtitulo,
  });

  final IconData icone;
  final Color cor;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              if (subtitulo.isNotEmpty)
                Text(subtitulo,
                    style: TextStyle(color: TgdeskTextColors.muted)),
            ]),
          ),
        ],
      );
}

class _LinhaDeCausa extends StatelessWidget {
  const _LinhaDeCausa({required this.causa});

  final CausaNaTela causa;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(causa.titulo)),
            // Probabilidade E faixa. Nunca número seco (§10.5.1).
            Text('${causa.probTexto}  (${causa.faixaTexto})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: causa.prob),
          const SizedBox(height: 2),
          // Calibração visível: é o que transforma o número em argumento em vez
          // de oráculo (§10.5.3). Vazio vira o rótulo honesto.
          Text(
            causa.calibracao.isEmpty
                ? 'sem histórico suficiente para calibrar'
                : causa.calibracao,
            style: TextStyle(color: TgdeskTextColors.muted, fontSize: 11),
          ),
        ]),
      );
}

class _Evidencias extends StatelessWidget {
  const _Evidencias({required this.causa});

  final CausaNaTela causa;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Evidências', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ...causa.evidencias.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  e.esperado.isEmpty
                      ? '${e.metrica}: ${e.medido}'
                      // Medido × esperado, literal (§10.5.2, item 4).
                      : '${e.metrica}: ${e.medido}  ·  esperado ${e.esperado}',
                ),
              )),
        ],
      );
}

class _ProximosPassos extends StatelessWidget {
  const _ProximosPassos({required this.passos});

  final List<String> passos;

  @override
  Widget build(BuildContext context) {
    if (passos.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Próximos passos', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      ...passos.map((p) => Text('· $p')),
    ]);
  }
}

class _LinhaDeHistorico extends StatelessWidget {
  const _LinhaDeHistorico({required this.execucao});

  final ExecucaoAnterior execucao;

  @override
  Widget build(BuildContext context) {
    final e = execucao;
    // Recidiva nula = janela ainda aberta. A tela diz isso, em vez de fingir
    // que o reparo foi confirmado (§13.5).
    final recidiva = e.recidiva30d == null
        ? 'janela de recidiva ainda aberta'
        : (e.recidiva30d! ? 'sintoma voltou em 30 dias' : 'sem recidiva em 30 dias');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(e.causa.isEmpty ? 'sem causa registrada' : e.causa),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.degrauQuebra == null
              ? 'atravessou a escada inteira'
              : 'quebrou no degrau ${e.degrauQuebra}'),
          Text(recidiva,
              style: TextStyle(color: TgdeskTextColors.muted, fontSize: 11)),
        ]),
        trailing: Text('${e.quando.day}/${e.quando.month}',
            style: TextStyle(color: TgdeskTextColors.muted)),
      ),
    );
  }
}
