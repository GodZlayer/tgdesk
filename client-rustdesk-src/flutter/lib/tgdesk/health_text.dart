/// Textos da análise de saúde, montados aqui.
///
/// O servidor manda código e números; a frase é desta camada. É o que permite
/// que outro cliente — Android, web — escreva a própria redação contra o mesmo
/// fluxo, e o que tira do fio bytes que não são informação.
///
/// Havia duas redações por problema saindo do servidor, uma técnica e uma para
/// o cliente. A escolha de quem lê qual é decisão de tela, e é aqui que ela
/// pertence.
library;

class TgdeskHealthText {
  const TgdeskHealthText._();

  static String _pct(Object? value) {
    final number = value is num ? value : num.tryParse('$value');
    if (number == null) return '';
    return '${number.round()}%';
  }

  static String _temp(Object? value) {
    final number = value is num ? value : num.tryParse('$value');
    if (number == null) return '';
    return '${number.round()} °C';
  }

  static String _janela(Map<String, dynamic> p) {
    final texto = p['window']?.toString() ?? '';
    if (texto.isNotEmpty) return texto;
    final minutos = p['window_minutes'];
    if (minutos is num) return '${minutos.round()} min';
    return '';
  }

  /// Frase técnica: o que aconteceu, com número. É o que o técnico precisa
  /// para decidir.
  static String technical(Map<String, dynamic> issue) {
    final params = issue['params'] is Map
        ? Map<String, dynamic>.from(issue['params'] as Map)
        : <String, dynamic>{};
    final janela = _janela(params);
    switch (issue['code']?.toString()) {
      case 'sustained_usage':
        final tempo = _pct(params['time_above_pct']);
        final limiar = _pct(params['threshold_pct']);
        final pico = _pct(params['peak_pct']);
        return '$tempo do tempo acima de $limiar'
            '${janela.isEmpty ? '' : ' nas últimas $janela'}'
            '${pico.isEmpty ? '' : ' (pico de $pico)'}';
      case 'storage_occupancy':
        return '${_pct(params['average_pct'])} de ocupação média'
            '${janela.isEmpty ? '' : ' nas últimas $janela'}';
      case 'cpu_sustained_usage':
        return 'Média de CPU acima de ${_pct(params['threshold_pct'])}'
            '${janela.isEmpty ? '' : ' nos últimos $janela'}';
      case 'memory_sustained_usage':
        return 'Média de memória acima de ${_pct(params['threshold_pct'])}'
            '${janela.isEmpty ? '' : ' nos últimos $janela'}';
      case 'storage_smart_failing':
        return 'Disco ${params['device'] ?? ''} reportou SMART '
            '${params['smart_status'] ?? ''}';
      case 'storage_space_low':
        return '${params['volume'] ?? 'Disco'} está com '
            '${_pct(params['used_pct'])} do espaço ocupado';
      case 'storage_life_low':
        return 'Disco ${params['device'] ?? ''} reportou '
            '${_pct(params['life_pct'])} de vida útil restante';
      case 'cpu_temperature_high':
        return 'Média da CPU acima de ${_temp(params['threshold_c'])}'
            '${janela.isEmpty ? '' : ' nos últimos $janela'}';
      case 'gpu_temperature_high':
        return 'Média da GPU acima de ${_temp(params['threshold_c'])}'
            '${janela.isEmpty ? '' : ' nos últimos $janela'}';
      case 'storage_temperature_high':
        return 'Média dos discos acima de ${_temp(params['threshold_c'])}'
            '${janela.isEmpty ? '' : ' nos últimos $janela'}';
    }
    return categoryLabel(issue['category']?.toString());
  }

  /// Frase para o cliente: o que isso significa para ele, sem número.
  static String forClient(Map<String, dynamic> issue) {
    switch (issue['code']?.toString()) {
      case 'sustained_usage':
      case 'cpu_sustained_usage':
        return 'O computador vem trabalhando no limite.';
      case 'memory_sustained_usage':
        return 'A memória vem sendo exigida acima do confortável.';
      case 'storage_occupancy':
      case 'storage_space_low':
        return 'O espaço de armazenamento está ficando reduzido.';
      case 'storage_smart_failing':
        return 'O armazenamento precisa de verificação imediata.';
      case 'storage_life_low':
        return 'O armazenamento está próximo do fim da vida útil.';
      case 'cpu_temperature_high':
      case 'gpu_temperature_high':
      case 'storage_temperature_high':
        return 'O computador está aquecendo mais do que o esperado.';
    }
    return 'Uma condição vem se mantendo neste computador.';
  }

  /// Há quanto tempo a condição dura, em linguagem corrente e sem precisão
  /// falsa. O servidor manda o instante; a frase é daqui.
  static String since(String? isoTimestamp) {
    final at = DateTime.tryParse(isoTimestamp ?? '');
    if (at == null) return '';
    final d = DateTime.now().toUtc().difference(at.toUtc());
    if (d.inMinutes < 60) return 'há menos de uma hora';
    if (d.inHours < 24) return 'há ${d.inHours}h';
    if (d.inDays == 1) return 'há um dia';
    if (d.inDays < 30) return 'há ${d.inDays} dias';
    final meses = d.inDays ~/ 30;
    return meses == 1 ? 'há um mês' : 'há $meses meses';
  }

  /// Narrativa do card do cliente. Era montada no servidor; os dados que ela
  /// precisa — categoria, nível, desde quando e tendência — continuam vindo
  /// de lá, porque quem tem o histórico é ele.
  static String cardNarrative(Map<String, dynamic> metric, String category) {
    final level = metric['level']?.toString();
    final tempo = since(metric['desde']?.toString());
    final trend = metric['tendencia']?.toString();
    if (level == null || level == 'normal') {
      switch (category) {
        case 'storage':
          return 'Há espaço livre suficiente neste computador.';
        case 'memory':
          return 'Há memória suficiente para as atividades atuais.';
      }
      return 'O computador está respondendo como esperado.';
    }
    final base = tempo.isEmpty
        ? 'Esta condição vem se mantendo.'
        : 'Esta condição se mantém $tempo.';
    final fim = trend == 'piorando'
        ? ' Vem piorando.'
        : trend == 'melhorando'
            ? ' Vem melhorando.'
            : '';
    if (category == 'storage') {
      return 'O disco está ficando cheio. $base'
          ' Liberar espaço costuma resolver.$fim';
    }
    return '$base Seu técnico consegue ver o histórico completo.$fim';
  }

  static String categoryLabel(String? category) {
    switch (category) {
      case 'processing':
        return 'Processamento';
      case 'memory':
        return 'Memória';
      case 'storage':
        return 'Armazenamento';
      case 'temperature':
        return 'Temperatura';
    }
    return 'Sistema';
  }

  /// Cabeçalho do técnico. Era montado no servidor em quatro versões, todas
  /// função apenas do nível — que a tela já recebe.
  static String technicalTitle(String? level) {
    switch (level) {
      case 'maximum':
      case 'critical':
        return 'Verificação técnica necessária';
      case 'warning':
        return 'Atenção recomendada';
    }
    return 'Sistema funcionando normalmente';
  }

  static String technicalSummary(String? level) {
    switch (level) {
      case 'maximum':
      case 'critical':
        return 'Foi identificada uma condição sustentada que pode afetar este computador.';
      case 'warning':
        return 'Foi identificada uma condição sustentada que deve ser acompanhada.';
    }
    return 'Nenhum problema importante foi identificado nesta análise.';
  }

  static String clientTitle(String? level) {
    switch (level) {
      case 'maximum':
      case 'critical':
        return 'Entre em contato com seu técnico';
      case 'warning':
        return 'Vale falar com seu técnico';
    }
    return 'Tudo certo por aqui';
  }

  static String clientSummary(String? level) {
    switch (level) {
      case 'maximum':
      case 'critical':
        return 'Foi identificada uma condição persistente neste computador.';
      case 'warning':
        return 'Uma condição vem se mantendo e merece atenção.';
    }
    return 'O TGDesk está acompanhando este computador.';
  }
}
