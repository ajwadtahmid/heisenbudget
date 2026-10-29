import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../domain/iso_date.dart';
import '../database/app_database.dart';

/// Thrown when adding a goal beyond [maxActiveGoals] that are not yet reached.
class GoalLimitException implements Exception {
  const GoalLimitException();

  @override
  String toString() => 'You can have up to $maxActiveGoals goals at a time';
}

/// Thrown when a change would leave a goal with less than nothing in it.
class GoalBelowZeroException implements Exception {
  const GoalBelowZeroException();

  @override
  String toString() => 'A goal cannot hold less than nothing';
}

/// The values a goal is made from.
class GoalInput {
  const GoalInput({
    required this.name,
    required this.targetCents,
    this.targetDate,
    this.icon = 'savings',
  });

  final String name;
  final int targetCents;
  final DateTime? targetDate;
  final String icon;

  void validate() {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxGoalNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'must be 1 to $maxGoalNameLength characters',
      );
    }
    if (targetCents < 1 || targetCents > maxAmountCents) {
      throw RangeError.range(targetCents, 1, maxAmountCents, 'targetCents');
    }
    final due = targetDate;
    if (due != null &&
        (due.isBefore(earliestDate) || due.isAfter(latestDate))) {
      throw ArgumentError.value(
        due,
        'targetDate',
        'outside the supported dates',
      );
    }
    if (icon.trim().isEmpty) {
      throw ArgumentError.value(icon, 'icon', 'must not be empty');
    }
  }
}

class GoalRepository {
  GoalRepository(this._db);

  final AppDatabase _db;

  $SavingsGoalsTable get _g => _db.savingsGoals;
  $GoalEntriesTable get _e => _db.goalEntries;

  /// Every goal in list order.
  Stream<List<SavingsGoalRow>> watchGoals() {
    return (_db.select(_g)..orderBy([
          (g) => OrderingTerm.asc(g.sortOrder),
          (g) => OrderingTerm.asc(g.id),
        ]))
        .watch();
  }

  /// Every entry of every goal, oldest first. A goal's entries are a handful
  /// to a few thousand rows, so the lists and the plans work from all of them.
  Stream<List<GoalEntryRow>> watchEntries() {
    return (_db.select(_e)..orderBy([
          (e) => OrderingTerm.asc(e.date),
          (e) => OrderingTerm.asc(e.id),
        ]))
        .watch();
  }

  Future<SavingsGoalRow?> getById(int id) {
    return (_db.select(_g)..where((g) => g.id.equals(id))).getSingleOrNull();
  }

  /// What is in the goal now.
  Future<int> savedIn(int goalId) async {
    final total = _e.amountCents.sum();
    final row =
        await (_db.selectOnly(_e)
              ..addColumns([total])
              ..where(_e.goalId.equals(goalId)))
            .getSingle();
    return row.read(total) ?? 0;
  }

  /// Adds a goal at the end of the list. Throws [GoalLimitException] when
  /// [maxActiveGoals] goals are not yet reached.
  Future<int> add(GoalInput input, {DateTime? now}) {
    input.validate();
    return _db.transaction(() async {
      if (await _activeCount() >= maxActiveGoals) {
        throw const GoalLimitException();
      }
      final last = await (_db.selectOnly(_g)..addColumns([_g.sortOrder.max()]))
          .map((r) => r.read(_g.sortOrder.max()))
          .getSingle();
      return _db
          .into(_g)
          .insert(
            SavingsGoalsCompanion.insert(
              name: input.name.trim(),
              targetCents: input.targetCents,
              targetDate: Value(_isoOrNull(input.targetDate)),
              icon: Value(input.icon.trim()),
              sortOrder: Value((last ?? -1) + 1),
              createdAt: now ?? DateTime.now(),
            ),
          );
    });
  }

  /// Saves edits to a goal. Raising or lowering the target does not touch the
  /// entries.
  Future<void> update(int id, GoalInput input) async {
    input.validate();
    await (_db.update(_g)..where((g) => g.id.equals(id))).write(
      SavingsGoalsCompanion(
        name: Value(input.name.trim()),
        targetCents: Value(input.targetCents),
        targetDate: Value(_isoOrNull(input.targetDate)),
        icon: Value(input.icon.trim()),
      ),
    );
  }

  /// Deletes a goal and all its entries.
  Future<void> delete(int id) {
    return _db.transaction(() async {
      await (_db.delete(_e)..where((e) => e.goalId.equals(id))).go();
      await (_db.delete(_g)..where((g) => g.id.equals(id))).go();
    });
  }

  /// Puts the goals in the order of [ids] (first = top). Ids that are not
  /// listed keep their place after the listed ones.
  Future<void> reorder(List<int> ids) {
    return _db.transaction(() async {
      for (var i = 0; i < ids.length; i++) {
        await (_db.update(_g)..where((g) => g.id.equals(ids[i]))).write(
          SavingsGoalsCompanion(sortOrder: Value(i)),
        );
      }
    });
  }

  /// Puts [cents] into the goal (negative: takes it out) on [date]. Throws
  /// [GoalBelowZeroException] when that would leave less than nothing.
  Future<int> addEntry(
    int goalId, {
    required int cents,
    required DateTime date,
    DateTime? now,
  }) {
    if (cents == 0 || cents.abs() > maxAmountCents) {
      throw RangeError.range(cents.abs(), 1, maxAmountCents, 'cents');
    }
    final day = dateOnly(date);
    if (day.isBefore(earliestDate) || day.isAfter(latestDate)) {
      throw ArgumentError.value(date, 'date', 'outside the supported dates');
    }
    return _db.transaction(() async {
      if (await getById(goalId) == null) {
        throw ArgumentError.value(goalId, 'goalId', 'no such goal');
      }
      if (await savedIn(goalId) + cents < 0) {
        throw const GoalBelowZeroException();
      }
      return _db
          .into(_e)
          .insert(
            GoalEntriesCompanion.insert(
              goalId: goalId,
              amountCents: cents,
              date: toIsoDate(day),
              createdAt: now ?? DateTime.now(),
            ),
          );
    });
  }

  /// Removes one entry. Throws [GoalBelowZeroException] when what is left
  /// would be less than nothing (for example removing a deposit that a later
  /// withdrawal drew on).
  Future<void> deleteEntry(int entryId) {
    return _db.transaction(() async {
      final entry = await (_db.select(
        _e,
      )..where((e) => e.id.equals(entryId))).getSingleOrNull();
      if (entry == null) return;
      if (await savedIn(entry.goalId) - entry.amountCents < 0) {
        throw const GoalBelowZeroException();
      }
      await (_db.delete(_e)..where((e) => e.id.equals(entryId))).go();
    });
  }

  /// How many goals are not yet reached.
  Future<int> _activeCount() async {
    final saved = _e.amountCents.sum();
    final rows =
        await (_db.select(_g).join([
                leftOuterJoin(_e, _e.goalId.equalsExp(_g.id)),
              ])
              ..addColumns([saved])
              ..groupBy([_g.id]))
            .get();
    return rows
        .where((r) => (r.read(saved) ?? 0) < r.readTable(_g).targetCents)
        .length;
  }

  String? _isoOrNull(DateTime? d) => d == null ? null : toIsoDate(dateOnly(d));
}
