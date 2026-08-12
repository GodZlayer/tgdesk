import 'dart:math' as math;

/// Modelo das telas de diagnóstico (§10 da arquitetura).
///
/// Regra que este arquivo existe para tornar possível: **nenhuma tela busca
/// dado ao montar**. Tudo aqui é construído a partir do que chega pelo canal de
/// controle — o cálculo é do servidor, o desenho é do cliente (§10.4).
///
/// Por isso todo tipo aqui é imutável e nasce de um mapa JSON: o widget recebe
/// o objeto pronto e desenha. Não existe método que consulte nada.

/// Os cinco estados obrigatórios de toda tela (§10.7).
///
/// `abstencao` NÃO é erro nem estado degradado: é resposta de primeira classe,
/// com o mesmo peso visual do resultado, dizendo o que rodar em seguida.
enum EstadoDaTela { vazio, executando, abortadoPorGate, abstencao, resultado }

/// Um gate de segurança que vai ser aplicado, com o motivo.
///
/// O motivo é obrigatório: o técnico precisa ver ANTES de começar que o disco
/// vai rodar só em leitura porque o SMART já acusou realocação (§10.6-A).
class GateDeSeguranca {
  const GateDeSeguranca({required this.codigo, required this.motivo});

  final String codigo;
  final String motivo;

  factory GateDeSeguranca.doMapa(Map<String, dynamic> m) => GateDeSeguranca(
        codigo: (m['codigo'] ?? '') as String,
        motivo: (m['motivo'] ?? '') as String,
      );
}

/// Faixa de duração. Nunca número seco — faixa honesta vale mais que ponto
/// falso (§10.2).
class FaixaDeDuracao {
  const FaixaDeDuracao({required this.minMin, required this.maxMin, this.grosseira = false});

  final int minMin;
  final int maxMin;

  /// Sem histórico para aquela classe de dispositivo. A tela diz isso em vez de
  /// esconder a incerteza.
  final bool grosseira;

  factory FaixaDeDuracao.doMapa(Map<String, dynamic> m) => FaixaDeDuracao(
        minMin: (m['min'] ?? 0) as int,
        maxMin: (m['max'] ?? 0) as int,
        grosseira: (m['grosseira'] ?? false) as bool,
      );

  String get texto => grosseira
      ? 'estimativa grosseira: $minMin–$maxMin min'
      : 'estimado $minMin–$maxMin min';
}

/// Tela A — o que o técnico vê antes de autorizar a escada.
class PreVoo {
  const PreVoo({
    required this.inventario,
    required this.estadoDeRepouso,
    required this.gates,
    required this.duracao,
    required this.perfil,
    required this.perfilVersao,
    this.consentimentoDado = false,
  });

  final Map<String, String> inventario;

  /// Térmico, SMART, memória livre — o estado ANTES de forçar nada.
  final Map<String, String> estadoDeRepouso;
  final List<GateDeSeguranca> gates;
  final FaixaDeDuracao duracao;
  final String perfil;
  final int perfilVersao;
  final bool consentimentoDado;

  factory PreVoo.doMapa(Map<String, dynamic> m) => PreVoo(
        inventario: Map<String, String>.from(m['inventario'] ?? const {}),
        estadoDeRepouso: Map<String, String>.from(m['repouso'] ?? const {}),
        gates: ((m['gates'] ?? const []) as List)
            .map((g) => GateDeSeguranca.doMapa(Map<String, dynamic>.from(g as Map)))
            .toList(),
        duracao: FaixaDeDuracao.doMapa(Map<String, dynamic>.from(m['duracao'] ?? const {})),
        perfil: (m['perfil'] ?? '') as String,
        perfilVersao: (m['perfil_versao'] ?? 1) as int,
        consentimentoDado: (m['consentimento'] ?? false) as bool,
      );
}

/// Um ponto da curva: carga no eixo X, métrica no Y (§5).
class PontoDaCurva {
  const PontoDaCurva({required this.loadLevel, required this.tMs, required this.valor});

  final int loadLevel;
  final int tMs;
  final double valor;

  factory PontoDaCurva.doMapa(Map<String, dynamic> m) => PontoDaCurva(
        loadLevel: (m['load_level'] ?? 0) as int,
        tMs: (m['t_ms'] ?? 0) as int,
        valor: ((m['valor'] ?? 0) as num).toDouble(),
      );
}

/// Marca na curva: trava, aborto por gate, ponto de quebra.
///
/// Aborto por gate aparece como EVENTO na curva, não como erro (§10.6-B):
/// é resultado, e uma máquina que não atravessa o degrau 2 sem atingir 95 °C
/// já respondeu à pergunta térmica.
class MarcaNaCurva {
  const MarcaNaCurva({
    required this.tipo,
    required this.loadLevel,
    required this.rotulo,
    this.emAberto = false,
  });

  final String tipo; // 'trava' | 'gate' | 'quebra'
  final int loadLevel;
  final String rotulo;

  /// Trava ainda sem fim: "travado há 3s…". Fecha quando o heartbeat volta.
  final bool emAberto;

  factory MarcaNaCurva.doMapa(Map<String, dynamic> m) => MarcaNaCurva(
        tipo: (m['tipo'] ?? '') as String,
        loadLevel: (m['load_level'] ?? 0) as int,
        rotulo: (m['rotulo'] ?? '') as String,
        emAberto: (m['em_aberto'] ?? false) as bool,
      );
}

/// Tela B — execução ao vivo.
class ExecucaoAoVivo {
  const ExecucaoAoVivo({
    required this.estagio,
    required this.degrau,
    required this.totalDegraus,
    required this.pontos,
    required this.marcas,
    required this.restante,
    this.pausada = false,
  });

  final String estagio;
  final int degrau;
  final int totalDegraus;
  final List<PontoDaCurva> pontos;
  final List<MarcaNaCurva> marcas;

  /// Recalculado durante a execução. Se o dispositivo for mais lento que o
  /// previsto, o número sobe na cara do supervisor em vez de estourar em
  /// silêncio (§10.2).
  final FaixaDeDuracao restante;
  final bool pausada;

  factory ExecucaoAoVivo.doMapa(Map<String, dynamic> m) => ExecucaoAoVivo(
        estagio: (m['estagio'] ?? '') as String,
        degrau: (m['degrau'] ?? 0) as int,
        totalDegraus: (m['total_degraus'] ?? 5) as int,
        pontos: ((m['pontos'] ?? const []) as List)
            .map((p) => PontoDaCurva.doMapa(Map<String, dynamic>.from(p as Map)))
            .toList(),
        marcas: ((m['marcas'] ?? const []) as List)
            .map((x) => MarcaNaCurva.doMapa(Map<String, dynamic>.from(x as Map)))
            .toList(),
        restante: FaixaDeDuracao.doMapa(Map<String, dynamic>.from(m['restante'] ?? const {})),
        pausada: (m['pausada'] ?? false) as bool,
      );
}

/// Uma evidência literal que sustenta a causa (§10.5.1, item 3).
///
/// Métrica, valor medido, limiar esperado. Nunca "indícios sugerem".
class EvidenciaLiteral {
  const EvidenciaLiteral({
    required this.metrica,
    required this.medido,
    this.esperado = '',
  });

  final String metrica;
  final String medido;
  final String esperado;

  factory EvidenciaLiteral.doMapa(Map<String, dynamic> m) => EvidenciaLiteral(
        metrica: (m['metrica'] ?? '') as String,
        medido: (m['valor_medido'] ?? '') as String,
        esperado: (m['limiar_esperado'] ?? '') as String,
      );
}

/// Uma causa provável com a faixa que a acompanha.
class CausaNaTela {
  const CausaNaTela({
    required this.codigo,
    required this.titulo,
    required this.prob,
    required this.faixaMin,
    required this.faixaMax,
    required this.evidencias,
    this.calibracao = '',
  });

  final String codigo;

  /// Já renderizado pelo `text_template` no servidor. O cliente NUNCA compõe
  /// frase de diagnóstico (§12.1).
  final String titulo;
  final double prob;
  final double faixaMin;
  final double faixaMax;
  final List<EvidenciaLiteral> evidencias;

  /// "quando dizemos 70–80%, acertamos 74% em 112 casos" (§10.5.3).
  /// Vazio significa "sem histórico suficiente" — nunca um número inventado.
  final String calibracao;

  factory CausaNaTela.doMapa(Map<String, dynamic> m) {
    final faixa = (m['faixa'] ?? const [0, 0]) as List;
    return CausaNaTela(
      codigo: (m['codigo'] ?? '') as String,
      titulo: (m['titulo'] ?? '') as String,
      prob: ((m['prob'] ?? 0) as num).toDouble(),
      faixaMin: ((faixa.isNotEmpty ? faixa[0] : 0) as num).toDouble(),
      faixaMax: ((faixa.length > 1 ? faixa[1] : 0) as num).toDouble(),
      evidencias: ((m['evidencias'] ?? const []) as List)
          .map((e) => EvidenciaLiteral.doMapa(Map<String, dynamic>.from(e as Map)))
          .toList(),
      calibracao: (m['calibracao'] ?? '') as String,
    );
  }

  String get probTexto => '${(prob * 100).round()}%';
  String get faixaTexto =>
      '${(faixaMin * 100).round()}–${(faixaMax * 100).round()}%';
}

/// Tela C — resultado, ou abstenção.
class ResultadoDoDiagnostico {
  const ResultadoDoDiagnostico({
    required this.estado,
    required this.veredito,
    required this.causas,
    required this.pontos,
    required this.marcas,
    required this.excluidas,
    required this.proximosPassos,
    this.motivoAborto = '',
  });

  final EstadoDaTela estado;

  /// Uma frase, gerada por template no servidor (§10.6-C).
  final String veredito;
  final List<CausaNaTela> causas;
  final List<PontoDaCurva> pontos;
  final List<MarcaNaCurva> marcas;

  /// O que o teste EXCLUIU. Tão importante quanto o que confirmou: é o que
  /// impede o supervisor de refazer trabalho (§10.5.2, item 5).
  final List<String> excluidas;
  final List<String> proximosPassos;
  final String motivoAborto;

  factory ResultadoDoDiagnostico.doMapa(Map<String, dynamic> m) {
    final abstain = (m['abstain'] ?? false) as bool;
    final aborto = (m['motivo_aborto'] ?? '') as String;
    final estado = aborto.isNotEmpty
        ? EstadoDaTela.abortadoPorGate
        : (abstain ? EstadoDaTela.abstencao : EstadoDaTela.resultado);
    return ResultadoDoDiagnostico(
      estado: estado,
      veredito: (m['veredito'] ?? '') as String,
      causas: ((m['causas'] ?? const []) as List)
          .map((c) => CausaNaTela.doMapa(Map<String, dynamic>.from(c as Map)))
          .toList(),
      pontos: ((m['pontos'] ?? const []) as List)
          .map((p) => PontoDaCurva.doMapa(Map<String, dynamic>.from(p as Map)))
          .toList(),
      marcas: ((m['marcas'] ?? const []) as List)
          .map((x) => MarcaNaCurva.doMapa(Map<String, dynamic>.from(x as Map)))
          .toList(),
      excluidas: List<String>.from(m['excluidas'] ?? const []),
      proximosPassos: List<String>.from(m['proximos_testes'] ?? const []),
      motivoAborto: aborto,
    );
  }
}

/// Tela D — histórico do dispositivo.
class ExecucaoAnterior {
  const ExecucaoAnterior({
    required this.quando,
    required this.perfil,
    required this.degrauQuebra,
    required this.causa,
    required this.pontos,
    this.recidiva7d,
    this.recidiva30d,
  });

  final DateTime quando;
  final String perfil;

  /// Nulo = atravessou a escada inteira sem quebrar.
  final int? degrauQuebra;
  final String causa;
  final List<PontoDaCurva> pontos;

  /// Nulo significa "janela ainda aberta", não "não houve" (§13.5).
  final bool? recidiva7d;
  final bool? recidiva30d;

  factory ExecucaoAnterior.doMapa(Map<String, dynamic> m) => ExecucaoAnterior(
        quando: DateTime.tryParse((m['quando'] ?? '') as String) ?? DateTime.now(),
        perfil: (m['perfil'] ?? '') as String,
        degrauQuebra: m['degrau_quebra'] as int?,
        causa: (m['causa'] ?? '') as String,
        pontos: ((m['pontos'] ?? const []) as List)
            .map((p) => PontoDaCurva.doMapa(Map<String, dynamic>.from(p as Map)))
            .toList(),
        recidiva7d: m['recidiva_7d'] as bool?,
        recidiva30d: m['recidiva_30d'] as bool?,
      );

  /// O limiar de uma execução é o degrau em que quebrou. É por ele que se
  /// compara antes × depois de um reparo (§11.6).
  int get limiar => degrauQuebra ?? 999;
}

/// Comparação entre duas execuções da MESMA escada. É o que valida um reparo:
/// "quebrava no degrau 3, agora atravessa inteira" — e não "trocado e testado".
class ComparacaoDeLimiar {
  const ComparacaoDeLimiar({required this.antes, required this.depois});

  final ExecucaoAnterior antes;
  final ExecucaoAnterior depois;

  bool get comparavel => antes.perfil == depois.perfil;
  bool get melhorou => comparavel && depois.limiar > antes.limiar;
  bool get piorou => comparavel && depois.limiar < antes.limiar;

  String get texto {
    if (!comparavel) return 'perfis diferentes — não comparável';
    if (melhorou) {
      final d = depois.degrauQuebra;
      return d == null
          ? 'quebrava no degrau ${antes.degrauQuebra}, agora atravessa a escada inteira'
          : 'quebrava no degrau ${antes.degrauQuebra}, agora no $d';
    }
    if (piorou) return 'piorou: quebra mais cedo que antes';
    return 'o limiar não se moveu';
  }
}

/// Escala de uma curva, usada pelo painter e pelos testes.
class EscalaDaCurva {
  const EscalaDaCurva({required this.min, required this.max});

  final double min;
  final double max;

  factory EscalaDaCurva.de(List<PontoDaCurva> pontos) {
    if (pontos.isEmpty) return const EscalaDaCurva(min: 0, max: 1);
    var menor = pontos.first.valor;
    var maior = pontos.first.valor;
    for (final p in pontos) {
      menor = math.min(menor, p.valor);
      maior = math.max(maior, p.valor);
    }
    // Curva plana não pode virar divisão por zero nem linha no topo do gráfico.
    if (maior == menor) return EscalaDaCurva(min: menor - 1, max: maior + 1);
    return EscalaDaCurva(min: menor, max: maior);
  }

  double normalizar(double valor) => (valor - min) / (max - min);
}
