/// Nome e descrição de cada teste do catálogo, indexados pelo id.
///
/// O servidor manda id, categoria e impacto; o texto é desta camada. Um
/// cliente em outro idioma troca este arquivo e nada mais.
library;

class TgdeskDiagnosticText {
  const TgdeskDiagnosticText._();

  static const Map<String, String> _names = {
    'all_tests': 'Todos os testes',
    'system_overview': 'Visão geral do sistema',
    'cpu_stress': 'Carga do processador',
    'memory_integrity': 'Integridade da memória',
    'memory_extended': 'Memória multipadrão',
    'internet_quality': 'Qualidade da Internet',
    'network_latency_series': 'Estabilidade da conexão',
    'disk_performance': 'Desempenho do armazenamento',
    'disk_random_performance': 'Acesso aleatório do armazenamento',
    'smart_extended': 'Saúde física dos discos',
    'badblocks-read': 'Contadores de setores defeituosos',
    'storage_surface_read': 'Leitura integral da superfície',
    'filesystem_scan': 'Integridade do sistema de arquivos',
    'filesystem_deep_scan': 'Varredura profunda dos volumes',
    'gpu_stress': 'Diagnóstico gráfico',
    'battery_health': 'Saúde da bateria',
    'driver_errors': 'Falhas de drivers',
    'critical_events': 'Eventos críticos',
    'service_failures': 'Serviços com falha',
    'startup_inventory': 'Inicialização do Windows',
    'network_adapters': 'Adaptadores de rede',
    'dns_diagnostics': 'Diagnóstico DNS',
    'route_table': 'Rotas e gateways',
    'windows_integrity': 'Integridade do Windows',
    'update_status': 'Atualizações do Windows',
    'security_posture': 'Postura de segurança',
    'defender_quick_scan': 'Varredura antimalware',
    'temperature_sensors': 'Sensores térmicos',
    'storage_volumes': 'Volumes e espaço',
    'process_pressure': 'Pressão de processos',
  };

  static const Map<String, String> _descriptions = {
    'all_tests':
        'Executa sequencialmente todo o catálogo seguro do TGDesk, inclusive leitura integral da superfície dos discos. Pode levar horas ou dias e pode ser cancelado.',
    'system_overview':
        'Inventário, serviços, eventos críticos e estado geral.',
    'cpu_stress':
        'Mantém todos os núcleos ocupados e mede estabilidade e resposta.',
    'memory_integrity':
        'Reserva blocos de memória e verifica padrões de leitura e escrita.',
    'memory_extended':
        'Executa múltiplos padrões e passes em uma área ampla de RAM, registrando cada etapa e divergência.',
    'internet_quality':
        'Mede DNS, latência e acesso externo.',
    'network_latency_series':
        'Mede repetidamente latência, perda e variação para revelar falhas intermitentes em gráfico.',
    'disk_performance':
        'Executa leitura e escrita temporária e remove o arquivo ao terminar.',
    'disk_random_performance':
        'Mede operações e latência de leitura aleatória em arquivo temporário, sem alterar arquivos do usuário.',
    'smart_extended':
        'Consulta SMART, temperatura, desgaste e erros registrados.',
    'badblocks-read':
        'Consulta contadores de confiabilidade do disco sem escrever nem apagar dados.',
    'storage_surface_read':
        'Lê todos os bytes acessíveis de cada disco físico, sem escrever. Pode levar horas ou dias.',
    'filesystem_scan':
        'Verifica saúde dos volumes e eventos de corrupção sem reparar ou alterar dados.',
    'filesystem_deep_scan':
        'Solicita ao Windows uma varredura online real de cada volume compatível, sem executar reparos.',
    'gpu_stress':
        'Valida controladores e amostra os motores gráficos disponíveis na sessão do Windows.',
    'battery_health':
        'Consulta carga, tensão e estado da bateria.',
    'driver_errors':
        'Lista dispositivos PnP com erro ou driver ausente.',
    'critical_events':
        'Consolida eventos críticos e erros recentes do Windows.',
    'service_failures':
        'Detecta serviços automáticos parados e falhas de inicialização.',
    'startup_inventory':
        'Inventaria programas e tarefas iniciados com o Windows.',
    'network_adapters':
        'Verifica link, velocidade, erros e configuração IP.',
    'dns_diagnostics':
        'Testa servidores DNS configurados e resolução externa.',
    'route_table':
        'Analisa rotas, gateways e métricas de interface.',
    'windows_integrity':
        'Executa DISM ScanHealth sem reparar ou alterar arquivos.',
    'update_status':
        'Lista hotfixes e reinicializações pendentes.',
    'security_posture':
        'Consulta Defender, firewall, Secure Boot e criptografia.',
    'defender_quick_scan':
        'Executa uma verificação rápida real do Microsoft Defender e apresenta ameaças e estado final.',
    'temperature_sensors':
        'Lê sensores térmicos expostos pelo Windows e pelo hardware.',
    'storage_volumes':
        'Verifica capacidade, espaço livre e estado dos volumes.',
    'process_pressure':
        'Lista maiores consumidores de CPU, memória e I/O.',
  };

  static String name(String? id) => _names[id] ?? id ?? '';

  static String description(String? id) => _descriptions[id] ?? '';

  /// Rótulo do agrupamento. A categoria chega como dado; a palavra é daqui.
  static String category(String? id) {
    const rotulos = {
      'Completo': 'Completo',
      'Sistema': 'Sistema',
      'Processamento': 'Processamento',
      'Memória': 'Memória',
      'Rede': 'Rede',
      'Armazenamento': 'Armazenamento',
      'Vídeo': 'Vídeo',
      'Energia': 'Energia',
      'Segurança': 'Segurança',
      'Hardware': 'Hardware',
      'Desempenho': 'Desempenho',
    };
    return rotulos[id] ?? id ?? 'Outros';
  }
}
