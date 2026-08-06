import 'package:flutter/material.dart';

import 'api_client.dart';
import 'control_channel.dart';
import 'theme.dart';

/// Formata centavos como moeda. Fica aqui, e não numa dependência de
/// internacionalização, porque é o único formato que o produto usa e trazer um
/// pacote inteiro para uma linha custaria mais do que a linha.
String moeda(int cents) {
  final negativo = cents < 0;
  final valor = cents.abs();
  final reais = (valor ~/ 100).toString();
  final centavos = (valor % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buffer.write('.');
    buffer.write(reais[i]);
  }
  return '${negativo ? '-' : ''}R\$ $buffer,$centavos';
}

int? centavosDe(String texto) {
  final limpo = texto.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll('.', '');
  if (limpo.isEmpty) return null;
  final valor = double.tryParse(limpo.replaceAll(',', '.'));
  if (valor == null) return null;
  return (valor * 100).round();
}

/// O construtor de OS: o orçamento montado a partir do catálogo.
///
/// O técnico não digita preço. Ele escolhe peças e serviços que o admin
/// cadastrou, e o valor sai da precificação do servidor — percentual por
/// classe, taxa, promoção, limites e o ajuste por demanda — resolvido lá e só
/// exibido aqui. Linha avulsa existe para o item que não estava no catálogo na
/// hora, e é a única em que rótulo e valor vêm digitados.
///
/// A tela se monta do canal: peças, serviços e as linhas já lançadas chegam no
/// snapshot. O único pedido que ela faz é o do orçamento, e por ação do
/// técnico — nunca ao montar.
class OsBuilderPage extends StatefulWidget {
  const OsBuilderPage({
    super.key,
    required this.ticketId,
    required this.typeKey,
    required this.osType,
  });

  final String ticketId;
  final String? typeKey;
  final String osType;

  @override
  State<OsBuilderPage> createState() => _OsBuilderPageState();
}

class _OsBuilderPageState extends State<OsBuilderPage> {
  final _control = TgdeskControlChannel.instance;
  Map<String, dynamic>? _quote;
  String? _erro;
  bool _ocupado = false;

  Future<void> _comAviso(Future<void> Function() acao) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await acao();
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _recalcular() => _comAviso(() async {
        final quote = await TgdeskApi.osQuote(widget.ticketId);
        if (mounted) setState(() => _quote = quote);
      });

  Future<void> _incluir(Map<String, dynamic> item) => _comAviso(() async {
        await TgdeskApi.addOsItem(widget.ticketId, item);
        final quote = await TgdeskApi.osQuote(widget.ticketId);
        if (mounted) setState(() => _quote = quote);
      });

  Future<void> _remover(String itemId) => _comAviso(() async {
        await TgdeskApi.removeOsItem(widget.ticketId, itemId);
        final quote = await TgdeskApi.osQuote(widget.ticketId);
        if (mounted) setState(() => _quote = quote);
      });

  Future<void> _fechar() => _comAviso(() async {
        final quote = await TgdeskApi.closeOsQuote(widget.ticketId);
        if (mounted) setState(() => _quote = quote);
      });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _control,
      builder: (context, _) {
        final os = _control.serviceOrderOf(widget.ticketId);
        if (os == null) {
          return const Padding(
            padding: EdgeInsets.all(TgdeskSpacing.md),
            child: Text('Este chamado ainda não virou OS.'),
          );
        }
        final linhas = (os['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _barraDeInclusao(),
            const SizedBox(height: TgdeskSpacing.sm),
            if (linhas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.md),
                child: Text('Nenhuma linha no orçamento ainda.'),
              )
            else
              ...linhas.map(_linha),
            const Divider(height: TgdeskSpacing.lg),
            _resumo(os),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: TgdeskSpacing.sm),
                child: Text(_erro!,
                    style: const TextStyle(color: TgdeskColors.suspended)),
              ),
          ],
        );
      },
    );
  }

  Widget _barraDeInclusao() {
    final pecas = _control.partsFor(widget.typeKey);
    final servicos = _control.servicesFor(widget.typeKey, widget.osType);
    return Wrap(
      spacing: TgdeskSpacing.sm,
      runSpacing: TgdeskSpacing.sm,
      children: [
        _seletor(
          rotulo: 'Serviço',
          icone: Icons.build_outlined,
          itens: servicos,
          aoEscolher: (item) => _incluir({'service_id': item['id']}),
        ),
        _seletor(
          rotulo: 'Peça',
          icone: Icons.memory_outlined,
          itens: pecas,
          aoEscolher: (item) => _incluir({'part_id': item['id']}),
        ),
        OutlinedButton.icon(
          onPressed: _ocupado ? null : _linhaAvulsa,
          icon: const Icon(Icons.edit_note_outlined, size: 18),
          label: const Text('Linha avulsa'),
        ),
      ],
    );
  }

  Widget _seletor({
    required String rotulo,
    required IconData icone,
    required List<Map<String, dynamic>> itens,
    required void Function(Map<String, dynamic>) aoEscolher,
  }) {
    if (itens.isEmpty) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icone, size: 18),
        label: Text('$rotulo — catálogo vazio'),
      );
    }
    return PopupMenuButton<Map<String, dynamic>>(
      enabled: !_ocupado,
      onSelected: aoEscolher,
      itemBuilder: (_) => [
        for (final item in itens)
          PopupMenuItem(
            value: item,
            child: Row(children: [
              Expanded(child: Text(item['label']?.toString() ?? '')),
              const SizedBox(width: TgdeskSpacing.md),
              Text(moeda((item['price_cents'] as num?)?.toInt() ?? 0),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
      ],
      child: OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icone, size: 18),
        label: Text('Incluir $rotulo'),
      ),
    );
  }

  Future<void> _linhaAvulsa() async {
    final rotulo = TextEditingController();
    final valor = TextEditingController();
    final quantidade = TextEditingController(text: '1');
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Linha avulsa'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: rotulo,
              decoration: const InputDecoration(labelText: 'O que foi')),
          TextField(
              controller: valor,
              decoration: const InputDecoration(labelText: 'Valor unitário'),
              keyboardType: TextInputType.number),
          TextField(
              controller: quantidade,
              decoration: const InputDecoration(labelText: 'Quantidade'),
              keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Incluir')),
        ],
      ),
    );
    if (confirmado != true) return;
    final cents = centavosDe(valor.text);
    if (rotulo.text.trim().isEmpty || cents == null) {
      setState(() => _erro = 'Linha avulsa precisa de rótulo e valor.');
      return;
    }
    await _incluir({
      'label': rotulo.text.trim(),
      'unit_cents': cents,
      'quantity': double.tryParse(quantidade.text.replaceAll(',', '.')) ?? 1,
    });
  }

  Widget _linha(Map<String, dynamic> item) {
    final quantidade = (item['quantity'] as num?)?.toDouble() ?? 1;
    final total = (item['total_cents'] as num?)?.toInt() ?? 0;
    final origem = item['part_id'] != null
        ? 'peça'
        : item['service_id'] != null
            ? 'serviço'
            : 'avulso';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item['label']?.toString() ?? ''),
      subtitle: Text('$origem · ${quantidade.toStringAsFixed(
        quantidade == quantidade.roundToDouble() ? 0 : 2,
      )} × ${moeda((item['unit_cents'] as num?)?.toInt() ?? 0)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(moeda(total),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          tooltip: 'Remover',
          icon: const Icon(Icons.close, size: 18),
          onPressed:
              _ocupado ? null : () => _remover(item['id']?.toString() ?? ''),
        ),
      ]),
    );
  }

  Widget _resumo(Map<String, dynamic> os) {
    // O que está na tela é o orçamento recalculado agora, se o técnico pediu;
    // senão, o que ficou gravado na OS. Os dois podem diferir, e é essa
    // diferença que o botão de fechar resolve: gravar é o que transforma
    // número em compromisso.
    final quote = _quote ?? (os['quote'] as Map?)?.cast<String, dynamic>();
    final gravado = (os['total_cents'] as num?)?.toInt() ?? 0;
    if (quote == null || quote.isEmpty) {
      return Row(children: [
        Expanded(
            child: Text(gravado > 0
                ? 'Orçamento gravado: ${moeda(gravado)}'
                : 'Orçamento ainda não calculado.')),
        TextButton(
            onPressed: _ocupado ? null : _recalcular,
            child: const Text('Calcular')),
      ]);
    }
    final subtotal = (quote['subtotal_cents'] as num?)?.toInt() ?? 0;
    final multiplicador = (quote['demand_multiple'] as num?)?.toInt() ?? 100;
    final ajustado = (quote['adjusted_cents'] as num?)?.toInt() ?? subtotal;
    final promo = (quote['promo_cents'] as num?)?.toInt() ?? 0;
    final taxa = (quote['fee_cents'] as num?)?.toInt() ?? 0;
    final total = (quote['total_cents'] as num?)?.toInt() ?? 0;
    final divisao = (quote['distributed_cents'] as Map?) ?? const {};

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _linhaResumo('Soma das linhas', moeda(subtotal)),
      if (multiplicador != 100)
        _linhaResumo(
          'Ajuste por demanda (${(multiplicador / 100).toStringAsFixed(2)}×)',
          moeda(ajustado - subtotal),
          destaque: true,
        ),
      if (promo > 0) _linhaResumo('Promoção', '-${moeda(promo)}'),
      if (taxa > 0) _linhaResumo('Taxa retida', moeda(taxa)),
      const SizedBox(height: TgdeskSpacing.xs),
      _linhaResumo('Total ao cliente', moeda(total), forte: true),
      if (divisao.isNotEmpty) ...[
        const SizedBox(height: TgdeskSpacing.sm),
        Text('Divisão', style: Theme.of(context).textTheme.labelMedium),
        for (final entrada in divisao.entries)
          if (((entrada.value as num?)?.toInt() ?? 0) != 0)
            _linhaResumo(
                entrada.key.toString(), moeda((entrada.value as num).toInt())),
      ],
      const SizedBox(height: TgdeskSpacing.sm),
      Row(children: [
        TextButton(
            onPressed: _ocupado ? null : _recalcular,
            child: const Text('Recalcular')),
        const Spacer(),
        FilledButton(
          onPressed: _ocupado ? null : _fechar,
          child: Text(gravado > 0 ? 'Regravar orçamento' : 'Fechar orçamento'),
        ),
      ]),
    ]);
  }

  Widget _linhaResumo(String rotulo, String valor,
          {bool forte = false, bool destaque = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: TgdeskSpacing.xs / 2),
        child: Row(children: [
          Expanded(
              child: Text(rotulo,
                  style: TextStyle(
                      color: destaque ? TgdeskColors.warning : null))),
          Text(valor,
              style: TextStyle(
                  fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
                  color: destaque ? TgdeskColors.warning : null)),
        ]),
      );
}
