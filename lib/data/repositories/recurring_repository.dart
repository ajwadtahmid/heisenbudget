import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/iso_date.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import '../database/app_database.dart';
import 'transaction_repository.dart';

/// The values a repeating rule is made from.
class RecurringInput {
  const RecurringInput({
    required this.amountCents,
    required this.type,
    required this.categoryId,
    required this.unit,
    required this.interval,
    required this.start,
    this.end,
    this.note,
    this.title,
  });

  final int amountCents;
  final TransactionType type;
  final int categoryId;
  final String? note;
  final String? title;
  final RecurrenceUnit unit;
  final int interval;
  final DateTime start;
  final DateTime? end;

  void validate() {
    if (amountCents < 1 || amountCents > maxAmountCents) {
      throw RangeError.range(amountCents, 1, maxAmountCents, 'amountCents');
    }
    if ((title?.length ?? 0) > maxTitleLength) {
      throw ArgumentError.value(title, 'title', 'longer than $maxTitleLength');
    }
    if ((note?.length ?? 0) > maxNoteLength) {
      throw ArgumentError.value(note, 'note', 'longer than $maxNoteLength');
    }
    RangeError.checkValueInInterval(
      interval,
      1,
      maxRecurrenceInterval,
      'interval',
    );
    final stop = end;
    if (stop != null && dateOnly(stop).isBefore(dateOnly(start))) {
      throw ArgumentError.value(stop, 'end', 'is before the start date');
    }
  }
}

/// Reads a stored rule as dates and schedule.
extension RecurringRuleDates on RecurringRuleRow {
  Recurrence get recurrence => Recurrence(
    unit: unit,
    interval: interval,
    start: fromIsoDate(startDate),
    end: endDate == null ? null : fromIsoDate(endDate!),
  );

  /// The next date this rule will add a transaction on, or null once it has
  /// run past its end date.
  DateTime? get nextDate => recurrence.occurrence(nextIndex);

  /// True when no occurrences are left.
  bool get hasEnded => nextDate == null;
}

class RecurringRepository {
  RecurringRepository(this._db);

  final AppDatabase _db;

  $RecurringRulesTable get _r => _db.recurringRules;
  $TransactionsTable get _t => _db.transactions;

  Stream<List<RecurringRuleRow>> watchAll() {
    return (_db.select(_r)..orderBy([(r) => OrderingTerm.asc(r.id)])).watch();
  }

  Future<RecurringRuleRow?> getById(int id) {
    return (_db.select(_r)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Saves a new transaction together with a rule that repeats it. The
  /// transaction is occurrence 0, so the rule carries on from occurrence 1.
  /// Both are saved or neither is. Returns the new transaction's id.
  Future<int> addWithRule(TransactionInput tx, RecurringInput rule) {
    tx.validate();
    rule.validate();
    return _db.transaction(() async {
      final ruleId = await _insertRule(rule, nextIndex: 1);
      final now = DateTime.now();
      return _db
          .into(_t)
          .insert(
            TransactionsCompanion.insert(
              amountCents: tx.amountCents,
              type: tx.type,
              date: toIsoDate(tx.date),
              categoryId: tx.categoryId,
              note: Value(_cleanNote(tx.note)),
              title: Value(_cleanNote(tx.title)),
              createdAt: now,
              updatedAt: now,
              recurringRuleId: Value(ruleId),
            ),
          );
    });
  }

  /// Turns an existing transaction into occurrence 0 of a new rule.
  Future<int?> makeRecurring(
    int transactionId, {
    required RecurrenceUnit unit,
    required int interval,
    DateTime? end,
  }) {
    return _db.transaction(() async {
      final tx = await (_db.select(
        _t,
      )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
      if (tx == null || tx.recurringRuleId != null) return null;
      final input = RecurringInput(
        amountCents: tx.amountCents,
        type: tx.type,
        categoryId: tx.categoryId,
        note: tx.note,
        title: tx.title,
        unit: unit,
        interval: interval,
        start: fromIsoDate(tx.date),
        end: end,
      )..validate();
      final ruleId = await _insertRule(input, nextIndex: 1);
      await (_db.update(_t)..where((t) => t.id.equals(transactionId))).write(
        TransactionsCompanion(recurringRuleId: Value(ruleId)),
      );
      return ruleId;
    });
  }

  /// Saves edits to a rule. These only change transactions added from now on.
  ///
  /// The schedule (unit, interval, start date) is only rewritten when
  /// [reanchor] is true; the rule then counts from [RecurringInput.start]
  /// again, so its next transaction is on that date.
  Future<void> update(
    int id,
    RecurringInput input, {
    required bool reanchor,
  }) async {
    input.validate();
    await _db.transaction(() async {
      final rule = await getById(id);
      if (rule == null) return;
      final category = await (_db.select(
        _db.categories,
      )..where((c) => c.id.equals(input.categoryId))).getSingleOrNull();
      if (category == null || category.type != rule.type) {
        throw ArgumentError.value(
          input.categoryId,
          'categoryId',
          'must be a ${rule.type.name} category',
        );
      }
      await (_db.update(_r)..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(
          amountCents: Value(input.amountCents),
          categoryId: Value(input.categoryId),
          note: Value(_cleanNote(input.note)),
          title: Value(_cleanNote(input.title)),
          endDate: Value(input.end == null ? null : toIsoDate(input.end!)),
          unit: reanchor ? Value(input.unit) : const Value.absent(),
          interval: reanchor ? Value(input.interval) : const Value.absent(),
          startDate: reanchor
              ? Value(toIsoDate(input.start))
              : const Value.absent(),
          nextIndex: reanchor ? const Value(0) : const Value.absent(),
        ),
      );
    });
  }

  Future<void> setActive(int id, bool active) {
    return (_db.update(_r)..where((r) => r.id.equals(id))).write(
      RecurringRulesCompanion(isActive: Value(active)),
    );
  }

  /// Skips the next occurrence. Returns false when there is none left.
  Future<bool> skipNext(int id) {
    return _db.transaction(() async {
      final rule = await getById(id);
      if (rule == null || rule.hasEnded) return false;
      await (_db.update(_r)..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(nextIndex: Value(rule.nextIndex + 1)),
      );
      return true;
    });
  }

  /// Deletes the rule. Transactions it already made stay (their link is
  /// cleared by the database).
  Future<void> delete(int id) async {
    await (_db.delete(_r)..where((r) => r.id.equals(id))).go();
  }

  Future<int> _insertRule(RecurringInput input, {required int nextIndex}) {
    return _db
        .into(_r)
        .insert(
          RecurringRulesCompanion.insert(
            amountCents: input.amountCents,
            type: input.type,
            categoryId: input.categoryId,
            note: Value(_cleanNote(input.note)),
            title: Value(_cleanNote(input.title)),
            unit: input.unit,
            interval: Value(input.interval),
            startDate: toIsoDate(input.start),
            endDate: Value(input.end == null ? null : toIsoDate(input.end!)),
            nextIndex: Value(nextIndex),
            createdAt: DateTime.now(),
          ),
        );
  }

  String? _cleanNote(String? note) {
    final clean = note?.trim();
    return (clean == null || clean.isEmpty) ? null : clean;
  }
}
