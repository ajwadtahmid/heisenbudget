import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/budget.dart';
import '../../domain/iso_date.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';

/// A stored limit as the pure budget logic reads it.
extension BudgetLimitEntry on BudgetLimitRow {
  LimitEntry get entry => LimitEntry(
    categoryId: categoryId,
    unit: lengthMonths > 0
        ? BudgetUnit.months(lengthMonths)
        : BudgetUnit.days(lengthDays),
    repeats: repeats,
    start: fromIsoDate(start),
    amountCents: amountCents,
  );
}

class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  $BudgetLimitsTable get _t => _db.budgetLimits;

  /// Every limit row, oldest start first.
  Stream<List<BudgetLimitRow>> watchAll() {
    return (_db.select(_t)..orderBy([
          (l) => OrderingTerm.asc(l.start),
          (l) => OrderingTerm.asc(l.id),
        ]))
        .watch();
  }

  /// Every limit row once, without watching for changes.
  Future<List<BudgetLimitRow>> getAll() {
    return (_db.select(_t)..orderBy([
          (l) => OrderingTerm.asc(l.start),
          (l) => OrderingTerm.asc(l.id),
        ]))
        .get();
  }

  /// From [start] (the first day of a period) the budget for [categoryId]
  /// (null = all spending) is [amountCents], repeating every [unit] or, when
  /// [repeats] is false, for that one period only. A null amount means "no
  /// budget from this period on".
  ///
  /// This adds a row, or replaces the row that already starts on [start] for
  /// the same category. Rows for other days are left alone, so a change never
  /// rewrites an earlier period.
  Future<void> setLimit({
    required DateTime start,
    required BudgetUnit unit,
    bool repeats = true,
    int? categoryId,
    int? amountCents,
  }) {
    if (unit.inMonths) {
      RangeError.checkValueInInterval(
        unit.months,
        1,
        maxBudgetMonths,
        'unit.months',
      );
    } else {
      RangeError.checkValueInInterval(unit.days, 1, maxBudgetDays, 'unit.days');
    }
    if (amountCents != null &&
        (amountCents < 1 || amountCents > maxAmountCents)) {
      throw RangeError.range(amountCents, 1, maxAmountCents, 'amountCents');
    }
    final day = toIsoDate(dateOnly(start));
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
                    l.start.equals(day) &
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
                lengthDays: unit.days,
                lengthMonths: Value(unit.months),
                repeats: Value(repeats),
                start: day,
                amountCents: Value(amountCents),
                createdAt: DateTime.now(),
              ),
            );
      } else {
        await (_db.update(_t)..where((l) => l.id.equals(existing.id))).write(
          BudgetLimitsCompanion(
            lengthDays: Value(unit.days),
            lengthMonths: Value(unit.months),
            repeats: Value(repeats),
            amountCents: Value(amountCents),
          ),
        );
      }
    });
  }
}
