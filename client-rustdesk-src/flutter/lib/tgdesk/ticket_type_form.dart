import 'package:flutter/material.dart';

import 'control_channel.dart';
import 'theme.dart';

/// Formulário de um chamado, montado a partir do esquema do tipo.
///
/// Não há um widget por equipamento aqui. O que a tela sabe é ler
/// `ticket_type_fields` — rótulo, natureza, obrigatoriedade e condição — e
/// desenhar o controle correspondente. Um tipo novo cadastrado pelo admin
/// aparece nesta tela sem uma linha de código nova.
class TicketTypeForm extends StatelessWidget {
  const TicketTypeForm({
    super.key,
    required this.typeKey,
    required this.values,
    required this.onChanged,
    this.ambient = const {},
  });

  /// Qual tipo está sendo preenchido.
  final String? typeKey;

  /// Valores atuais dos campos, por `field_key`.
  final Map<String, dynamic> values;

  /// Chamado a cada digitação/escolha, com o mapa já atualizado.
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Atributos do próprio chamado que as condições podem consultar —
  /// modalidade, por exemplo. Não são campos do tipo, e por isso não entram
  /// em `values`: seriam uma segunda verdade sobre um dado que já é coluna.
  final Map<String, dynamic> ambient;

  void _set(String key, dynamic value) {
    onChanged(<String, dynamic>{...values, key: value});
  }

  @override
  Widget build(BuildContext context) {
    final channel = TgdeskControlChannel.instance;
    final visible = channel.visibleFieldsOf(typeKey, {...values, ...ambient});
    if (visible.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: TgdeskSpacing.sm),
        child: Text('Este tipo ainda não tem campos cadastrados.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in visible)
          Padding(
            padding: const EdgeInsets.only(top: TgdeskSpacing.sm),
            child: _fieldWidget(context, field),
          ),
      ],
    );
  }

  Widget _fieldWidget(BuildContext context, Map<String, dynamic> field) {
    final key = field['field_key']?.toString() ?? '';
    final label = field['label']?.toString() ?? key;
    final help = field['help']?.toString() ?? '';
    final required = field['required'] == true;
    final rotulo = required ? '$label *' : label;
    final atual = values[key];

    switch (field['kind']?.toString()) {
      case 'bool':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(rotulo),
          subtitle: help.isEmpty ? null : Text(help),
          value: atual == true,
          onChanged: (value) => _set(key, value),
        );

      case 'choice':
        final options = (field['options'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        return DropdownButtonFormField<String>(
          value: options.any((o) => o['value']?.toString() == atual?.toString())
              ? atual?.toString()
              : null,
          decoration: InputDecoration(
              labelText: rotulo, helperText: help.isEmpty ? null : help),
          items: options
              .map((option) => DropdownMenuItem(
                    value: option['value']?.toString(),
                    child: Text(option['label']?.toString() ??
                        option['value']?.toString() ??
                        ''),
                  ))
              .toList(),
          onChanged: (value) => _set(key, value),
        );

      case 'number':
        return TextFormField(
          initialValue: atual?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: rotulo, helperText: help.isEmpty ? null : help),
          onChanged: (value) => _set(key, num.tryParse(value) ?? value),
        );

      case 'multiline':
        return TextFormField(
          initialValue: atual?.toString() ?? '',
          maxLines: 3,
          decoration: InputDecoration(
              labelText: rotulo, helperText: help.isEmpty ? null : help),
          onChanged: (value) => _set(key, value),
        );

      // 'date' e 'attachment' ainda não têm controle próprio: até terem, o
      // campo aparece como texto em vez de sumir da tela sem explicação.
      default:
        return TextFormField(
          initialValue: atual?.toString() ?? '',
          decoration: InputDecoration(
              labelText: rotulo, helperText: help.isEmpty ? null : help),
          onChanged: (value) => _set(key, value),
        );
    }
  }
}

/// O que falta preencher, na mesma regra que o servidor aplica: obrigatório
/// escondido por condição não bloqueia. Existe para a tela avisar antes de
/// enviar, não para substituir a verificação do servidor — que continua sendo
/// a que vale.
String? ticketTypeFormPending(
    String? typeKey, Map<String, dynamic> values, Map<String, dynamic> ambient) {
  final visible = TgdeskControlChannel.instance
      .visibleFieldsOf(typeKey, {...values, ...ambient});
  for (final field in visible) {
    if (field['required'] != true) continue;
    final raw = values[field['field_key']?.toString()];
    if (raw == null || raw.toString().trim().isEmpty) {
      return 'Preencha "${field['label']}".';
    }
  }
  return null;
}
