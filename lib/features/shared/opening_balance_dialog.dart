import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';

/// Asks for the money you already had when you started. May be negative (you
/// started in debt) or zero. Returns the amount in cents, or null on cancel.
Future<int?> showOpeningBalanceDialog(
  BuildContext context, {
  required int initialCents,
  required String symbol,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) =>
        _OpeningBalanceDialog(initialCents: initialCents, symbol: symbol),
  );
}

class _OpeningBalanceDialog extends StatefulWidget {
  const _OpeningBalanceDialog({
    required this.initialCents,
    required this.symbol,
  });

  final int initialCents;
  final String symbol;

  @override
  State<_OpeningBalanceDialog> createState() => _OpeningBalanceDialogState();
}

class _OpeningBalanceDialogState extends State<_OpeningBalanceDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: centsToInputText(widget.initialCents),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final result = parseMoney(
      _controller.text,
      allowNegative: true,
      allowZero: true,
    );
    if (result.isValid) {
      Navigator.of(context).pop(result.cents);
    } else {
      setState(() => _error = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Opening balance'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What you had before your first entry. It counts toward your '
            'balance but not toward Received.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Gap.l),
          TextField(
            key: const ValueKey('opening-balance-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s-]')),
            ],
            style: monoText(size: 22, weight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Amount',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              prefixText: '${widget.symbol} ',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
