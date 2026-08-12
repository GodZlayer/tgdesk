import 'package:flutter/material.dart';

/// Tokens de cor do TGDesk Hub. Nunca use `Colors.red` etc. direto numa tela
/// nova — adicione (ou reaproveite) um token aqui, para que trocar uma cor
/// não vire uma busca-e-substitui em 4 arquivos.
class TgdeskColors {
  TgdeskColors._();

  static const seed = Colors.indigo;

  /// Dispositivo ativo e com heartbeat recente.
  static const online = Colors.green;

  /// Dispositivo ativo mas sem heartbeat (ou estado "offline" explícito).
  static const offline = Colors.grey;

  /// Dispositivo ainda não vinculado (estado guest).
  static const guest = Colors.blueGrey;

  /// Entidade suspensa administrativamente.
  static const suspended = Colors.red;

  /// Alerta ou ação administrativa de atenção.
  static const warning = Colors.orange;

  /// A cor da marca — o azul que pinta o que está selecionado, o ícone do
  /// aviso e o botão em foco.
  ///
  /// Estava escrita à mão em quatro pontos da tela de sessão, sempre a mesma.
  /// É a primeira candidata a virar editável quando a marca puder ter paleta:
  /// trocar só ela já muda a cara do produto.
  static const primary = Color(0xff35a7ff);
}

/// As cores dos domínios do painel administrativo.
///
/// Isto NÃO é paleta de marca, e a diferença importa: aqui o que vale é uma
/// cor ser distinguível da vizinha, não ser bonita ou combinar com o logo.
/// Deixar a marca pintar estas nove faria duas ficarem parecidas e o gráfico
/// deixaria de ser legível. Se um dia forem editáveis, é como conjunto.
class TgdeskDomainColors {
  TgdeskDomainColors._();

  static const Map<String, Color> byKey = {
    'connections': Color(0xff2563eb),
    'bindings': Color(0xff7c3aed),
    'financial': Color(0xff059669),
    'service_orders': Color(0xfff97316),
    'diagnostics': Color(0xffdc2626),
    'territory': Color(0xff0891b2),
    'catalog': Color(0xff4b5563),
    'security': Color(0xffb91c1c),
    'system': Color(0xff64748b),
  };

  static const fallback = Colors.blueGrey;

  static Color of(String key) => byKey[key] ?? fallback;
}

/// A tinta da anotação — as cores que o técnico escolhe para desenhar.
///
/// Também não é paleta de marca. São canetas: precisam saltar sobre a tela do
/// cliente, qualquer que seja ela. Se a marca as pintasse, um técnico com marca
/// azul ficaria sem caneta azul visível sobre um fundo azul.
class TgdeskAnnotationPalette {
  TgdeskAnnotationPalette._();

  static const colors = <Color>[
    Color(0xffff3b30),
    Color(0xffffcc00),
    Color(0xff34c759),
    Color(0xff32ade6),
    Color(0xffffffff),
  ];
}

/// Gravidade — o mesmo verde, amarelo e vermelho em toda tela.
///
/// Existe porque havia DOIS vermelhos para a mesma coisa: 0xffe5484d nas telas
/// de chamado e 0xffff5252 na do cliente e na de dispositivos. Não era escolha,
/// era deriva — cada tela nasceu com o vermelho que quem a escreveu digitou. O
/// valor que ficou é o menos saturado, que é o que se sustenta num fundo
/// escuro sem vibrar.
///
/// Não se confunde com TgdeskColors.online/suspended, que descrevem ESTADO de
/// uma entidade (ligada, suspensa). Aqui é o quanto uma leitura preocupa.
class TgdeskSeverityColors {
  TgdeskSeverityColors._();

  static const ok = Color(0xff45c95a);
  static const warning = Color(0xffffb020);
  static const critical = Color(0xffe5484d);

  /// A cor de um nível numérico, na escala que o servidor usa:
  /// 0 normal, 1 atenção, 2 crítico, 3 no limite.
  static Color of(int level) => level >= 2
      ? critical
      : level == 1
          ? warning
          : ok;
}

/// Superfícies do tema escuro — a tela do cliente e os painéis embutidos nela.
///
/// Esta parte do produto não segue o tema do sistema: é uma tela de quiosque,
/// vista de longe, e o fundo escuro é decisão de desenho, não preferência do
/// usuário. Por isso os valores são fixos aqui em vez de virem do ColorScheme.
class TgdeskSurfaces {
  TgdeskSurfaces._();

  /// Fundo da tela inteira.
  static const background = Color(0xff07101b);

  /// Cartão ou painel sobre o fundo.
  static const panel = Color(0xff111d29);

  /// Painel de segundo nível, um passo mais escuro.
  static const panelAlt = Color(0xff111c28);

  static const border = Color(0xff263444);
  static const borderStrong = Color(0xff25384b);
}

/// Hierarquia de texto sobre as superfícies escuras.
///
/// São quatro pesos e não uma escala aberta: título, apoio, corpo e o que só
/// precisa estar disponível sem chamar atenção. Quando uma tela precisou de um
/// quinto tom, quase sempre era um dos quatro escrito de novo com outro valor.
class TgdeskTextColors {
  TgdeskTextColors._();

  /// Subtítulo logo abaixo de um título.
  static const support = Color(0xffa9b5c6);

  /// Texto de apoio com algum destaque.
  static const strong = Color(0xffb7c2d1);

  /// Corpo secundário — a maior parte da prosa explicativa.
  static const body = Color(0xff9eacbf);

  /// Informação que só precisa estar lá: rodapé, carimbo de tempo.
  static const muted = Color(0xff75849a);

  /// Destaque frio, para ícones de acompanhamento.
  static const accent = Color(0xff8db8ee);
}

/// Escala de espaçamento de 4px. Prefira estes valores a números arbitrários.
class TgdeskSpacing {
  TgdeskSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Cor da bolinha de presença — único lugar que decide o mapeamento
/// estado→cor; use em qualquer tela que precise mostrar presença.
Color presenceColor(String presence) {
  switch (presence) {
    case 'online':
      return TgdeskColors.online;
    case 'offline':
      return TgdeskColors.offline;
    case 'guest':
      return TgdeskColors.guest;
    case 'suspenso':
      return TgdeskColors.suspended;
    default:
      return TgdeskColors.warning;
  }
}

/// Texto de erro padrão do Hub — substitui a repetição de
/// `Text(msg, style: TextStyle(color: Colors.red))` em cada tela.
class TgdeskErrorText extends StatelessWidget {
  final String message;
  const TgdeskErrorText(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(message, style: const TextStyle(color: TgdeskColors.suspended));
  }
}

Future<bool> showTgdeskConfirmSuspendDialog(
    BuildContext context, String targetLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar suspensão'),
      content: Text(
          'Suspender $targetLabel? O vínculo será preservado, mas a conexão privada e as verificações serão interrompidas.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: TgdeskColors.suspended),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Suspender'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> showTgdeskConfirmDeleteDialog(
    BuildContext context, String targetLabel) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apagar definitivamente?'),
      content: Text('Apagar $targetLabel? Essa ação não pode ser desfeita.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );
  return ok == true;
}
