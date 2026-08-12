import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/tgdesk/diagnostico_modelo.dart';
import 'package:flutter_hbb/tgdesk/diagnostico_telas.dart';

/// Testes das telas de diagnóstico (§10.6 e §10.7).
///
/// O que se protege: os cinco estados existem de verdade, a abstenção tem o
/// mesmo peso do resultado, e nenhuma tela quebra quando o dado ainda não
/// chegou pelo canal.

Widget _montar(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  group('estados obrigatórios', () {
    testWidgets('vazio: nunca rodou, e a tela diz isso sem quebrar',
        (tester) async {
      await tester.pumpWidget(_montar(TelaPreVoo(
        preVoo: null,
        aoConsentir: () {},
        aoExecutar: () {},
      )));
      expect(find.textContaining('nunca rodou'), findsOneWidget);
    });

    testWidgets('abstenção não é erro: aparece com veredito e direção',
        (tester) async {
      final r = ResultadoDoDiagnostico.doMapa({
        'abstain': true,
        'veredito': 'O dossiê não separa disco de memória.',
        'proximos_testes': ['escada_completa'],
      });
      expect(r.estado, EstadoDaTela.abstencao);

      await tester.pumpWidget(_montar(TelaResultado(resultado: r)));
      expect(find.text('Sem hipótese dominante'), findsOneWidget);
      // Abstenção sem direção é abstenção inútil.
      expect(find.textContaining('escada_completa'), findsOneWidget);
    });

    testWidgets('aborto por gate é resultado, não erro', (tester) async {
      final r = ResultadoDoDiagnostico.doMapa({
        'motivo_aborto': 'temperatura atingiu 95 °C no degrau 2',
        'proximos_testes': ['limpeza_e_reteste'],
      });
      expect(r.estado, EstadoDaTela.abortadoPorGate);

      await tester.pumpWidget(_montar(TelaResultado(resultado: r)));
      expect(find.text('Interrompido por proteção'), findsOneWidget);
      expect(find.textContaining('95 °C'), findsOneWidget);
    });

    testWidgets('resultado mostra veredito, top-3 e faixa', (tester) async {
      final r = ResultadoDoDiagnostico.doMapa({
        'veredito': 'Disco degradado',
        'causas': [
          {
            'codigo': 'disco_degradado',
            'titulo': 'Disco degradado',
            'prob': 0.88,
            'faixa': [0.8, 0.94],
            'evidencias': [
              {
                'metrica': 'latência p99',
                'valor_medido': '310ms',
                'limiar_esperado': '<40ms',
              }
            ],
          }
        ],
        'excluidas': ['memória instável (0 erros em 3 padrões)'],
      });
      await tester.pumpWidget(_montar(TelaResultado(resultado: r)));

      expect(find.text('Disco degradado'), findsWidgets);
      // Probabilidade E faixa: nunca número seco.
      expect(find.textContaining('88%'), findsOneWidget);
      expect(find.textContaining('80–94%'), findsOneWidget);
      // Medido × esperado, literal.
      expect(find.textContaining('310ms'), findsOneWidget);
      // O que foi excluído é tão importante quanto o que foi confirmado.
      expect(find.textContaining('memória instável'), findsOneWidget);
    });

    testWidgets('executando: degrau, curva e trava em aberto', (tester) async {
      final e = ExecucaoAoVivo.doMapa({
        'estagio': 'disco_sequencial',
        'degrau': 3,
        'total_degraus': 5,
        'pontos': [
          {'load_level': 20, 't_ms': 0, 'valor': 10.0},
          {'load_level': 40, 't_ms': 90, 'valor': 40.0},
        ],
        'marcas': [
          {'tipo': 'trava', 'load_level': 60, 'rotulo': 'travado há 3s…', 'em_aberto': true}
        ],
        'restante': {'min': 8, 'max': 12},
      });
      await tester.pumpWidget(_montar(TelaExecucao(
        execucao: e,
        aoPausar: () {},
        aoCancelar: () {},
      )));

      expect(find.textContaining('degrau 3 de 5'), findsOneWidget);
      expect(find.text('travado há 3s…'), findsOneWidget);
      expect(find.textContaining('8–12 min'), findsOneWidget);
    });
  });

  group('calibração visível (§10.5.3)', () {
    testWidgets('sem histórico mostra o rótulo honesto, não um número',
        (tester) async {
      final r = ResultadoDoDiagnostico.doMapa({
        'veredito': 'x',
        'causas': [
          {'codigo': 'c', 'titulo': 'C', 'prob': 0.7, 'faixa': [0.4, 0.9]}
        ],
      });
      await tester.pumpWidget(_montar(TelaResultado(resultado: r)));
      expect(find.textContaining('sem histórico suficiente'), findsOneWidget);
    });
  });

  group('pré-voo', () {
    testWidgets('gate aparece COM o motivo, e executar só sai com consentimento',
        (tester) async {
      final p = PreVoo.doMapa({
        'inventario': {'disco': 'SSD 480GB'},
        'repouso': {'SMART': '12 setores realocados'},
        'gates': [
          {'codigo': 'disco_somente_leitura', 'motivo': 'SMART já acusou realocação'}
        ],
        'duracao': {'min': 14, 'max': 20},
        'perfil': 'completa',
        'perfil_versao': 1,
        'consentimento': false,
      });
      await tester.pumpWidget(_montar(TelaPreVoo(
        preVoo: p,
        aoConsentir: () {},
        aoExecutar: () {},
      )));

      expect(find.textContaining('SMART já acusou realocação'), findsOneWidget);
      expect(find.textContaining('14–20 min'), findsOneWidget);

      // Sem consentimento, o botão não executa. É a única decisão humana entre
      // o chamado chegar e a escada começar.
      //
      // `find.byType` casa o tipo EXATO, e `FilledButton.icon` devolve uma
      // subclasse — por isso a busca é por predicado. Foi o que fez a primeira
      // versão deste teste falhar.
      final botao = tester.widget<ButtonStyleButton>(
        find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(botao.onPressed, isNull,
          reason: 'sem consentimento, executar tem que estar desabilitado');
    });
  });

  group('dossiê', () {
    testWidgets('compara limiar antes × depois, que é o que valida um reparo',
        (tester) async {
      final depois = ExecucaoAnterior.doMapa({
        'quando': '2026-08-10T10:00:00Z',
        'perfil': 'completa',
        'degrau_quebra': null,
        'causa': 'disco substituído',
        'recidiva_30d': false,
      });
      final antes = ExecucaoAnterior.doMapa({
        'quando': '2026-07-10T10:00:00Z',
        'perfil': 'completa',
        'degrau_quebra': 3,
        'causa': 'disco degradado',
        'recidiva_30d': true,
      });

      await tester.pumpWidget(_montar(TelaDossie(execucoes: [depois, antes])));
      expect(find.textContaining('quebrava no degrau 3'), findsOneWidget);
      expect(find.textContaining('atravessa a escada inteira'), findsWidgets);
    });

    testWidgets('janela de recidiva aberta não vira "sem recidiva"',
        (tester) async {
      final e = ExecucaoAnterior.doMapa({
        'quando': '2026-08-11T10:00:00Z',
        'perfil': 'completa',
        'degrau_quebra': 2,
        'causa': 'memória instável',
        // recidiva_30d ausente = janela ainda aberta
      });
      await tester.pumpWidget(_montar(TelaDossie(execucoes: [e])));
      expect(find.textContaining('janela de recidiva ainda aberta'), findsOneWidget);
    });
  });

  group('modelo', () {
    test('escala não divide por zero em curva plana', () {
      final escala = EscalaDaCurva.de([
        const PontoDaCurva(loadLevel: 20, tMs: 0, valor: 5),
        const PontoDaCurva(loadLevel: 40, tMs: 1, valor: 5),
      ]);
      final n = escala.normalizar(5);
      expect(n.isFinite, isTrue);
    });

    test('comparação recusa perfis diferentes em vez de comparar errado', () {
      final a = ExecucaoAnterior.doMapa(
          {'perfil': 'completa', 'degrau_quebra': 3, 'quando': '2026-07-01T00:00:00Z'});
      final b = ExecucaoAnterior.doMapa(
          {'perfil': 'rapida', 'degrau_quebra': 5, 'quando': '2026-08-01T00:00:00Z'});
      final c = ComparacaoDeLimiar(antes: a, depois: b);

      expect(c.comparavel, isFalse);
      expect(c.melhorou, isFalse);
      expect(c.texto, contains('não comparável'));
    });

    test('faixa grosseira se anuncia como tal', () {
      final f = FaixaDeDuracao.doMapa({'min': 5, 'max': 60, 'grosseira': true});
      expect(f.texto, contains('grosseira'));
    });
  });
}
