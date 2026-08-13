import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'diagnostico_modelo.dart';
import 'diagnostico_telas.dart';
import 'theme.dart';

/// A tela de diagnóstico do técnico (§10.6).
///
/// Hospeda as quatro telas — pré-voo, execução, resultado e dossiê — e não faz
/// mais nada. Em particular, **não busca dado ao montar** (§10.4): tudo vem do
/// `TgdeskControlChannel`, que recebeu o dossiê passivo já inferido no snapshot.
/// "O cálculo é do servidor, o desenho é do cliente."
///
/// Por isso a página é `AnimatedBuilder` sobre o canal em vez de `FutureBuilder`
/// sobre uma chamada: quando o servidor empurra um retrato novo, a tela se
/// redesenha sozinha. Não existe botão de atualizar, porque não existe consulta
/// para refazer.
class DiagnosticoPage extends StatelessWidget {
  const DiagnosticoPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final canal = TgdeskControlChannel.instance;

    return AnimatedBuilder(
      animation: canal,
      builder: (context, _) {
        final dossie = canal.diagnosticoDe(deviceId);
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text('Diagnóstico — $deviceName'),
              bottom: const TabBar(tabs: [
                Tab(text: 'Pré-voo'),
                Tab(text: 'Execução'),
                Tab(text: 'Resultado'),
                Tab(text: 'Dossiê'),
              ]),
            ),
            body: TabBarView(children: [
              _PreVooDoCanal(dossie: dossie, deviceId: deviceId),
              // Sem escada (B2) não há execução para pausar ou cancelar. As
              // ações existem no contrato da tela e ficam inertes até a escada
              // existir — melhor um botão que não faz nada visível do que uma
              // tela que promete controle que o servidor ainda não tem.
              TelaExecucao(
                execucao: null,
                aoPausar: () {},
                aoCancelar: () {},
              ),
              TelaResultado(resultado: _resultadoDoCanal(dossie)),
              const TelaDossie(execucoes: []),
            ]),
          ),
        );
      },
    );
  }
}

/// Traduz o dossiê passivo do canal para o modelo da tela de resultado.
///
/// O diagnóstico passivo é **hipótese**, não veredito (§10.5.1): não tem curva,
/// não tem limiar, e o teto de 0,85 já foi aplicado no servidor. Por isso os
/// pontos e as marcas vão vazios — desenhar uma curva aqui seria inventar a
/// intervenção que não aconteceu.
ResultadoDoDiagnostico? _resultadoDoCanal(Map<String, dynamic>? dossie) {
  if (dossie == null) return null;
  final status = (dossie['status'] ?? '') as String;
  if (status.isEmpty) return null;

  final causas = ((dossie['causas'] ?? const []) as List).map((c) {
    final m = Map<String, dynamic>.from(c as Map);
    // O título vem renderizado por `text_template` no servidor. O cliente
    // NUNCA compõe frase de diagnóstico (§12.1) — na falta dele, mostra o
    // código da causa, visivelmente cru em vez de silenciosamente errado.
    final slots = Map<String, dynamic>.from(m['slots'] as Map? ?? const {});
    m['titulo'] = slots['titulo'] ?? m['codigo'] ?? '';
    // As evidências do motor são literais; a tela espera metrica/valor.
    m['evidencias'] = ((m['evidencias'] ?? const []) as List)
        .map((e) => {'metrica': '', 'valor_medido': e.toString()})
        .toList();
    return m;
  }).toList();

  return ResultadoDoDiagnostico.doMapa({
    'abstain': dossie['abstain'] ?? false,
    'veredito': dossie['status_descricao'] ?? '',
    'causas': causas,
    'proximos_testes': dossie['proximos_testes'] ?? const [],
  });
}

/// Pré-voo montado do dossiê passivo.
///
/// Enquanto a escada (B2) não existir, o que se mostra aqui é o que o servidor
/// já sabe sem forçar nada: o estado observado e as evidências literais. A
/// ausência da estimativa de duração é DECLARADA, não escondida — §10.5.1 exige
/// um bloco explícito do que não se sabe, e é ele que impede a leitura de
/// veredito.
class _PreVooDoCanal extends StatefulWidget {
  const _PreVooDoCanal({required this.dossie, required this.deviceId});

  final Map<String, dynamic>? dossie;
  final String deviceId;

  @override
  State<_PreVooDoCanal> createState() => _PreVooDoCanalState();
}

class _PreVooDoCanalState extends State<_PreVooDoCanal> {
  bool _executando = false;

  /// A AÇÃO ÚNICA (§10.1).
  ///
  /// O supervisor não escolhe teste — escolhe *executar*. O menu de 32 itens
  /// não some do produto: ele vira a composição interna desta ação, na ordem
  /// fixa que o agente já implementa em `all_tests`. Escolher entre 32 caixas
  /// de seleção nunca foi decisão do técnico; era trabalho que o produto
  /// empurrava para ele.
  Future<void> _executarTesteCompleto() async {
    setState(() => _executando = true);
    try {
      await TgdeskApi.startDiagnostic(widget.deviceId, 'all_tests');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Teste completo iniciado — acompanhe na aba Execução.'),
        ));
        DefaultTabController.of(context).animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Não foi possível iniciar: $e')));
      }
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dossie;
    if (d == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Sem dossiê para este dispositivo.\n'
            'O servidor envia o retrato pelo canal quando há telemetria.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final evidencias = (d['evidencias'] ?? const []) as List;
    final medidaQueFalta = (d['medida_que_falta'] ?? '') as String;
    final status = (d['status'] ?? '') as String;
    final motor = (d['motor'] ?? '') as String;
    final sombra = d['sombra'] as Map?;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (status.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('Nada observado'),
            subtitle: Text(
              'Nenhum sinal da telemetria implica um status negativo. '
              'Isso não é "sem problema" — é "nada visível à distância".',
            ),
          ),
        )
      else
        Card(
          child: ListTile(
            leading: const Icon(Icons.troubleshoot, color: TgdeskColors.primary),
            title: Text((d['status_descricao'] ?? status) as String),
            subtitle: Text('Estado observado: $status'),
          ),
        ),
      const SizedBox(height: 16),
      Text('Evidências', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (evidencias.isEmpty)
        const Text('Nenhuma medida disponível.')
      else
        ...evidencias.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return ListTile(
            dense: true,
            leading: const Icon(Icons.fact_check_outlined, size: 18),
            title: Text((m['literal'] ?? '') as String),
            subtitle: Text((m['sinal'] ?? '') as String),
          );
        }),
      const SizedBox(height: 16),

      // O bloco do que NÃO se sabe. É o que impede a tela de ser lida como
      // veredito (§10.5.1, campo 4).
      Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('O que não se sabe',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Comportamento sob carga: nenhum teste foi executado. '
                'Sem teste não existe limiar, então nada aqui é veredito.'),
            // A lacuna NOMEADA. Quando o dossiê não consegue decidir, dizer
            // qual medida faltou vale mais que escolher a hipótese menos
            // improvável — e é o que separa "não sei" de "não meço".
            if (medidaQueFalta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.rule, size: 16, color: TgdeskColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Medida que falta para decidir: ${_medidaEmPortugues(medidaQueFalta)}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),

      const SizedBox(height: 16),

      // A AÇÃO ÚNICA. Um botão, não um menu (§10.1).
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _executando ? null : _executarTesteCompleto,
          icon: _executando
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: Text(_executando
              ? 'Iniciando…'
              : 'Executar teste completo'),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Roda a bateria inteira em ordem fixa — sistema, processamento, '
        'memória, rede, armazenamento, vídeo, energia e térmico. Você não '
        'escolhe testes: o resultado é comparável entre execuções porque a '
        'composição é sempre a mesma.',
        style: Theme.of(context).textTheme.bodySmall,
      ),

      // A calibração visível (§10.5.3) e a suposição da rede em sombra
      // (§14.1). Aparecem para o supervisor entender de onde veio o número —
      // é o que transforma probabilidade em argumento em vez de oráculo.
      if (motor.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Motor: $motor',
            style: Theme.of(context).textTheme.bodySmall),
      ],
      if (sombra != null) ...[
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rede em sombra — ${sombra['estado']}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'Treinada só com casos simulados do corpus. Roda no escuro e '
                'não decide nada: a resposta acima é da camada de regra.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text('${sombra['versao_modelo']}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// Traduz o código da medida que falta para linguagem de tela.
///
/// O código é estável e serve à auditoria; a frase serve a quem lê. Manter os
/// dois separados é a mesma regra do resto do produto — o cliente nunca compõe
/// diagnóstico, mas pode nomear uma lacuna, porque lacuna não é veredito.
String _medidaEmPortugues(String codigo) {
  switch (codigo) {
    case 'tempo_de_disco_ocupado_e_latencia_io':
      return 'tempo de disco ocupado e latência de leitura/escrita — '
          'hoje medimos só a OCUPAÇÃO do disco, que é quanto está cheio, '
          'não quanto ele demora para responder';
    case 'historico_de_episodios':
      return 'histórico de episódios de disco — a medida já está sendo '
          'coletada desde agora; ela precisa de alguns dias acumulados para '
          'mostrar se a lentidão vem em episódios';
    case 'historico_de_pressao':
      return 'histórico de pressão de recursos (ainda não há amostras suficientes)';
    case 'duracao_do_episodio':
      return 'quanto tempo cada episódio de lentidão dura';
    default:
      return codigo;
  }
}
