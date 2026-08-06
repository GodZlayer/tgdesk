/// Dinheiro em texto, e de volta.
///
/// O produto guarda valor em centavos inteiros, sempre — ponto flutuante para
/// dinheiro acumula erro que aparece no total da OS. A conversão para texto e
/// de volta acontece só na borda, aqui.
///
/// Sem pacote de internacionalização: o TGDesk usa um formato só, e trazer uma
/// dependência inteira para duas funções custaria mais do que as duas funções.
library;

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

/// Lê o que o usuário digitou como centavos. Aceita o que ele naturalmente
/// escreve — "1.234,56", "R$ 90", "90.5" — e devolve nulo quando não há número
/// nenhum, para que quem chama distinga "vazio" de "zero".
int? centavosDe(String texto) {
  final limpo = texto.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll('.', '');
  if (limpo.isEmpty) return null;
  final valor = double.tryParse(limpo.replaceAll(',', '.'));
  if (valor == null) return null;
  return (valor * 100).round();
}
