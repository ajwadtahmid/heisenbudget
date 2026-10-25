import 'package:flutter/material.dart';

import '../transaction_form/transaction_form_screen.dart';

/// The one add button: a quiet tonal "+" key (accent outline, no loud fill).
/// Shown on Home and History; opens the Add transaction sheet.
class AddKey extends StatelessWidget {
  const AddKey({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      // No hero animation: Home and History each hold one of these in the
      // same tab stack, and a shared hero tag would clash on every page push.
      heroTag: null,
      tooltip: 'Add transaction',
      onPressed: () => showTransactionForm(context),
      child: const Icon(Icons.add),
    );
  }
}
