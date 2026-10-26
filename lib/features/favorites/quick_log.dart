import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../transaction_form/transaction_draft.dart';
import '../transaction_form/transaction_form_screen.dart';

/// Whether [favorite] can be logged without asking anything: it has an amount
/// and its category can still be used.
bool canLogDirectly(FavoriteRow favorite, List<CategoryRow> categories) {
  if (favorite.amountCents == null) return false;
  final category = categories.where((c) => c.id == favorite.categoryId);
  return category.isNotEmpty && !category.first.isArchived;
}

/// Opens [favorite] in the Add sheet, filled in and dated today.
Future<void> openFavoriteInForm(
  BuildContext context,
  WidgetRef ref,
  FavoriteRow favorite,
) {
  final categories = ref.read(allCategoriesProvider).value ?? const [];
  final category = categories.where((c) => c.id == favorite.categoryId);
  final archived = category.isEmpty || category.first.isArchived;
  return showTransactionForm(
    context,
    draft: TransactionDraft.fromFavorite(favorite, categoryArchived: archived),
  );
}

/// Logs [favorite] dated today with a tick and an Undo. The caller has
/// checked that it can be logged directly ([canLogDirectly]).
Future<void> logFavoriteNow(WidgetRef ref, FavoriteRow favorite) async {
  final repo = ref.read(transactionRepositoryProvider);
  final messenger = ref.read(rootMessengerKeyProvider);
  final symbol = ref.read(settingsProvider).currencySymbol;
  final cents = favorite.amountCents!;
  final id = await repo.add(
    TransactionInput(
      amountCents: cents,
      type: favorite.type,
      date: ref.read(clockProvider),
      categoryId: favorite.categoryId,
      note: favorite.note,
      title: favorite.title,
    ),
  );
  HapticFeedback.selectionClick();
  final signed = favorite.type == TransactionType.income ? cents : -cents;
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Logged ${favorite.label} ${formatMoney(signed, symbol)}.',
        ),
        action: SnackBarAction(label: 'Undo', onPressed: () => repo.delete(id)),
      ),
    );
}
