import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/budget.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';

/// A stored limit as the pure budget logic reads it.
extension BudgetLimitEntry on BudgetLimitRow {
  LimitEntry get entry => LimitEntry(
    categoryId: categoryId,
    start: BudgetMonth.parse(startMonth),
    amountCents: amountCents,
  );
}

class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  $BudgetLimitsTable get _t => _db.budgetLimits;

  /// Every limit row, oldest start month first.
  Stream<List<BudgetLimitRow>> watchAll() {
    return (_db.select(_t)..orderBy([
          (l) => OrderingTerm.asc(l.startMonth),
          (l) => OrderingTerm.asc(l.id),
        ]))
        .watch();
  }

  /// Every limit row once, without watching for changes.
  Future<List<BudgetLimitRow>> getAll() {
    return (_db.select(_t)..orderBy([
          (l) => OrderingTerm.asc(l.startMonth),
          (l) => OrderingTerm.asc(l.id),
        ]))
        .get();
  }

  /// From [month] onward the limit for [categoryId] (null = all spending) is
  /// [amountCents]; a null amount means "no limit from this month on".
  ///
  /// This adds a row, or replaces the row that already starts in [month] for
  /// the same category. Rows for other months are left alone, so changing a
  /// limit never rewrites a month before [month].
  Future<void> setLimit({
    required BudgetMonth month,
    int? categoryId,
    int? amountCents,
  }) {
    if (amountCents != null &&
        (amountCents < 1 || amountCents > maxAmountCents)) {
      throw RangeError.range(amountCents, 1, maxAmountCents, 'amountCents');
    }
    return _db.transaction(() async {
      if (categoryId != null) {
        final category = await (_db.select(
          _db.categories,
        )..where((c) => c.id.equals(categoryId))).getSingleOrNull();
        if (category == null || category.type != TransactionType.expense) {
          throw ArgumentError.value(
            categoryId,
            'categoryId',
            'must be an expense category',
          );
        }
      }
      final existing =
          await (_db.select(_t)..where(
                (l) =>
                    l.startMonth.equals(month.key) &
                    (categoryId == null
                        ? l.categoryId.isNull()
                        : l.categoryId.equals(categoryId)),
              ))
              .getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_t)
            .insert(
              BudgetLimitsCompanion.insert(
                categoryId: Value(categoryId),
                startMonth: month.key,
                amountCents: Value(amountCents),
                createdAt: DateTime.now(),
              ),
            );
      } else {
        await (_db.update(_t)..where((l) => l.id.equals(existing.id))).write(
          BudgetLimitsCompanion(amountCents: Value(amountCents)),
        );
      }
    });
  }
}
