import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../data/recurring/recurring_service.dart';

/// Adds whatever repeating transactions have come due and, if any were added,
/// says so with an Undo. Safe to call from anywhere, any time.
Future<void> runRecurringCatchUp(WidgetRef ref) async {
  // Everything needed after the await is read first: the screen that called
  // this may be gone by then.
  final service = ref.read(recurringServiceProvider);
  final transactions = ref.read(transactionRepositoryProvider);
  final messenger = ref.read(rootMessengerKeyProvider);
  final today = ref.read(clockProvider);
  final failures = ref.read(recurringCatchUpFailuresProvider.notifier);

  final CatchUpResult result;
  try {
    result = await service.catchUp(today);
  } catch (_) {
    // A failed catch-up changed nothing (it is one database transaction) and
    // will be tried again next time the app opens. One failure stays quiet;
    // the Repeating transactions page shows a notice after any, and a second
    // in a row says so here too.
    if (failures.failed() == 2) {
      messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not add repeating transactions. Nothing was lost; check '
              'Settings > Repeating transactions.',
            ),
          ),
        );
    }
    return;
  }
  failures.worked();
  if (result.isEmpty) return;

  final n = result.count;
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          n == 1
              ? 'Added 1 recurring transaction.'
              : 'Added $n recurring transactions.',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => transactions.deleteMany(result.transactionIds),
        ),
      ),
    );
}
