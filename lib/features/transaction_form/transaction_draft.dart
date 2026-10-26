import '../../data/database/app_database.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/transaction_type.dart';

/// Values to start the Add sheet with, for Duplicate, favorites and
/// shortcuts. It is only a starting point: nothing is saved until the person
/// taps Save, and the date is always today.
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    this.amountCents,
    this.categoryId,
    this.note,
  });

  final TransactionType type;

  /// Null leaves the amount empty and focused.
  final int? amountCents;

  /// Null picks the usual default (last used, else "Other").
  final int? categoryId;
  final String? note;

  /// A copy of an existing transaction. An archived category is not carried
  /// over: it can no longer be picked for new transactions.
  factory TransactionDraft.fromTransaction(TransactionWithCategory item) {
    final tx = item.transaction;
    return TransactionDraft(
      type: tx.type,
      amountCents: tx.amountCents,
      categoryId: item.category.isArchived ? null : tx.categoryId,
      note: tx.note,
    );
  }

  /// A favorite's values, for opening it in the sheet instead of logging it.
  factory TransactionDraft.fromFavorite(
    FavoriteRow favorite, {
    required bool categoryArchived,
  }) {
    return TransactionDraft(
      type: favorite.type,
      amountCents: favorite.amountCents,
      categoryId: categoryArchived ? null : favorite.categoryId,
      note: favorite.note,
    );
  }
}
