import 'package:drift/drift.dart';

import '../../domain/iso_date.dart';
import '../database/app_database.dart';
import '../repositories/recurring_repository.dart';

/// What one catch-up added.
class CatchUpResult {
  const CatchUpResult(this.transactionIds);

  static const none = CatchUpResult([]);

  final List<int> transactionIds;

  int get count => transactionIds.length;
  bool get isEmpty => transactionIds.isEmpty;
}

/// Adds the transactions that repeating rules have come due for.
///
/// The app cannot run in the background, so this is called whenever it opens,
/// comes back to the foreground, passes midnight, or restores a backup. It
/// only ever creates transactions dated today or earlier.
class RecurringService {
  RecurringService(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;
  Future<CatchUpResult>? _running;

  /// Creates every transaction that is due up to [today], for every active
  /// rule, in one database transaction. Safe to call at any time and as often
  /// as you like: a second call while one is running shares its result, and
  /// an occurrence that already exists is never added twice.
  Future<CatchUpResult> catchUp(DateTime today) {
    final running = _running;
    if (running != null) return running;
    final run = _catchUp(today).whenComplete(() => _running = null);
    _running = run;
    return run;
  }

  Future<CatchUpResult> _catchUp(DateTime today) {
    return _db.transaction(() async {
      final rules = await (_db.select(
        _db.recurringRules,
      )..where((r) => r.isActive.equals(true))).get();
      final created = <int>[];
      for (final rule in rules) {
        final due = rule.recurrence.dueThrough(
          today,
          fromIndex: rule.nextIndex,
        );
        if (due.isEmpty) continue;
        for (final (_, date) in due) {
          final id = await _insertIfMissing(rule, date);
          if (id != null) created.add(id);
        }
        await (_db.update(_db.recurringRules)
              ..where((r) => r.id.equals(rule.id)))
            .write(RecurringRulesCompanion(nextIndex: Value(due.last.$1 + 1)));
      }
      return created.isEmpty ? CatchUpResult.none : CatchUpResult(created);
    });
  }

  /// Records a rule's transaction today, ahead of schedule, and moves the
  /// schedule on so the same payment is not added again when it falls due.
  /// Returns the new transaction's id, or null when the rule is gone, has
  /// nothing left, or already made a transaction today.
  Future<int?> addNow(int ruleId, DateTime today) {
    return _db.transaction(() async {
      final rule = await (_db.select(
        _db.recurringRules,
      )..where((r) => r.id.equals(ruleId))).getSingleOrNull();
      if (rule == null || rule.hasEnded) return null;
      final id = await _insertIfMissing(rule, dateOnly(today));
      if (id == null) return null;
      await (_db.update(_db.recurringRules)..where((r) => r.id.equals(ruleId)))
          .write(RecurringRulesCompanion(nextIndex: Value(rule.nextIndex + 1)));
      return id;
    });
  }

  /// Inserts the rule's transaction for [date] unless it has one that day.
  Future<int?> _insertIfMissing(RecurringRuleRow rule, DateTime date) async {
    final iso = toIsoDate(date);
    final existing =
        await (_db.select(_db.transactions)..where(
              (t) => t.recurringRuleId.equals(rule.id) & t.date.equals(iso),
            ))
            .getSingleOrNull();
    if (existing != null) return null;
    final now = _now();
    return _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            amountCents: rule.amountCents,
            type: rule.type,
            date: iso,
            categoryId: rule.categoryId,
            note: Value(rule.note),
            createdAt: now,
            updatedAt: now,
            recurringRuleId: Value(rule.id),
          ),
        );
  }
}
