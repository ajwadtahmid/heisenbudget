import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/backup_status.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/goals.dart';
import 'package:heisenbudget/domain/lab_report.dart';
import 'package:heisenbudget/domain/summary.dart';
import 'package:heisenbudget/domain/trends.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

BudgetPeriodResult result(int? id, String name, int limit, int spent) =>
    BudgetPeriodResult(
      categoryId: id,
      name: name,
      limitCents: limit,
      spentCents: spent,
    );

({int id, String name, int spentCents}) cat(int id, String name, int spent) =>
    (id: id, name: name, spentCents: spent);

void main() {
  group('reportMonthFor', () {
    test('is the budget month before the one holding today', () {
      expect(reportMonthFor(d(2026, 10, 3), 1).key, '2026-09');
      expect(reportMonthFor(d(2026, 1, 20), 1).key, '2025-12');
    });

    test('follows the month start day', () {
      // With a 25th start, Oct 10 is still in "September".
      expect(reportMonthFor(d(2026, 10, 10), 25).key, '2026-08');
      expect(reportMonthFor(d(2026, 10, 25), 25).key, '2026-09');
    });
  });

  group('reportDue', () {
    BudgetMonth? due(DateTime today, {int startDay = 1, String? seen}) =>
        reportDue(today: today, startDay: startDay, seenMonth: seen);

    test('shows on the first seven days of a month', () {
      for (var day = 1; day <= 7; day++) {
        expect(due(d(2026, 10, day))?.key, '2026-09', reason: 'day $day');
      }
      expect(due(d(2026, 10, 8)), isNull);
      expect(due(d(2026, 10, 20)), isNull);
    });

    test('counts from the budget month start, not the calendar', () {
      expect(due(d(2026, 10, 25), startDay: 25)?.key, '2026-09');
      expect(due(d(2026, 10, 31), startDay: 25)?.key, '2026-09');
      expect(due(d(2026, 11, 1), startDay: 25), isNull);
      // Oct 24 is the end of the "September" month, nowhere near its start.
      expect(due(d(2026, 10, 24), startDay: 25), isNull);
      // Three days into "September" (Sep 28), the August report is due.
      expect(due(d(2026, 9, 28), startDay: 25)?.key, '2026-08');
    });

    test('is quiet once that report, or a later one, was opened', () {
      expect(due(d(2026, 10, 3), seen: '2026-09'), isNull);
      expect(due(d(2026, 10, 3), seen: '2026-10'), isNull);
      expect(due(d(2026, 10, 3), seen: '2026-08')?.key, '2026-09');
    });

    test('crosses the year', () {
      expect(due(d(2027, 1, 2))?.key, '2026-12');
    });
  });

  group('reportBudgetsOf', () {
    test('one period: over or under', () {
      final out = reportBudgetsOf([
        result(1, 'Food', 30000, 35000),
        result(2, 'Fun', 10000, 4000),
      ]);
      expect(out.map((b) => b.name), ['Food', 'Fun']);
      expect(out[0].wentOver, isTrue);
      expect(out[0].overCents, 5000);
      expect(out[0].leftCents, -5000);
      expect(out[1].wentOver, isFalse);
      expect(out[1].leftCents, 6000);
    });

    test('several periods are grouped and the overshoots add up', () {
      final out = reportBudgetsOf([
        result(1, 'Food', 10000, 12000),
        result(1, 'Food', 10000, 8000),
        result(1, 'Food', 10000, 10500),
        result(1, 'Food', 10000, 10000),
      ]);
      expect(out, hasLength(1));
      final b = out.single;
      expect(b.periods, 4);
      expect(b.overPeriods, 2);
      expect(b.limitCents, 40000);
      expect(b.spentCents, 40500);
      // 2000 + 500: the 2000 saved in the second period does not cancel it.
      expect(b.overCents, 2500);
    });

    test('over first, the biggest overshoot first, then by name', () {
      final out = reportBudgetsOf([
        result(3, 'Zoo', 100, 50),
        result(1, 'Rent', 100, 150),
        result(2, 'Food', 100, 400),
        result(4, 'Art', 100, 50),
      ]);
      expect(out.map((b) => b.name), ['Food', 'Rent', 'Art', 'Zoo']);
    });

    test('the budget on all spending has no category id', () {
      final out = reportBudgetsOf([result(null, 'All spending', 100, 120)]);
      expect(out.single.categoryId, isNull);
      expect(out.single.wentOver, isTrue);
    });

    test('nothing in, nothing out', () {
      expect(reportBudgetsOf(const []), isEmpty);
    });
  });

  group('suggestionsOf', () {
    List<ReportSuggestion> suggest(
      List<({int id, String name, int spentCents})> spending, {
      Set<int> budgeted = const {},
      BackupFreshness backup = BackupFreshness.recent,
    }) => suggestionsOf(
      spending: spending,
      budgetedCategoryIds: budgeted,
      backup: backup,
    );

    test('a budget for the biggest category that has none', () {
      final out = suggest([cat(1, 'Rent', 50000), cat(2, 'Food', 30000)]);
      expect(out.map((s) => (s as SetLimitSuggestion).name), ['Rent', 'Food']);
    });

    test('skips categories that already have a budget', () {
      final out = suggest(
        [cat(1, 'Rent', 50000), cat(2, 'Food', 30000)],
        budgeted: {1},
      );
      expect(out.single, isA<SetLimitSuggestion>());
      expect((out.single as SetLimitSuggestion).name, 'Food');
    });

    test('skips small categories (under 15% of the month)', () {
      // Total 100.00: Fun is 10%.
      final out = suggest([cat(1, 'Rent', 90000), cat(2, 'Fun', 10000)]);
      expect(out.map((s) => (s as SetLimitSuggestion).name), ['Rent']);
    });

    test('at most two budget suggestions', () {
      final out = suggest([
        cat(1, 'A', 30000),
        cat(2, 'B', 30000),
        cat(3, 'C', 30000),
      ]);
      expect(out.whereType<SetLimitSuggestion>(), hasLength(2));
    });

    test('a backup when there is none or it is old', () {
      expect(
        suggest(const [], backup: BackupFreshness.never).single,
        isA<BackUpSuggestion>(),
      );
      expect(
        suggest(const [], backup: BackupFreshness.stale).single,
        isA<BackUpSuggestion>(),
      );
      expect(suggest(const []), isEmpty);
    });

    test('budget suggestions come before the backup, three at most', () {
      final out = suggest([
        cat(1, 'A', 30000),
        cat(2, 'B', 30000),
      ], backup: BackupFreshness.never);
      expect(out, hasLength(3));
      expect(out.last, isA<BackUpSuggestion>());
    });

    test('nothing spent, nothing to suggest', () {
      expect(suggest(const []), isEmpty);
      expect(suggest([cat(1, 'A', 0)]), isEmpty);
    });
  });

  group('moverBaseline', () {
    List<MonthTotals> months(List<int> spent) => monthTotalsOf(
      [for (var i = 0; i < spent.length; i++) BudgetMonth(2026, 9 - i)],
      [for (final s in spent) Summary(receivedCents: 0, spentCents: s)],
      d(2026, 10, 15),
      1,
    );

    test('keeps the months as given when they all have something', () {
      expect(moverBaseline(months([100, 200, 300])), hasLength(3));
    });

    test('drops the empty ones before anything was logged', () {
      // Newest first: the last two are before the first transaction.
      expect(moverBaseline(months([100, 200, 0, 0])), hasLength(2));
    });

    test('keeps an empty month between two that have something', () {
      expect(moverBaseline(months([100, 0, 200])), hasLength(3));
    });

    test('is empty when fewer than two have something', () {
      expect(moverBaseline(months([100, 0, 0])), isEmpty);
      expect(moverBaseline(months([0, 0])), isEmpty);
      expect(moverBaseline(const []), isEmpty);
    });
  });

  group('reportGoalsOf', () {
    final september = DateRange(d(2026, 9, 1), d(2026, 9, 30));

    ({int id, String name, int targetCents, List<GoalMove> moves}) goal(
      int id,
      List<GoalMove> moves, {
      int target = 100000,
    }) => (id: id, name: 'Goal $id', targetCents: target, moves: moves);

    test('adds up what moved in the month and where it stood at the end', () {
      final out = reportGoalsOf([
        goal(1, [
          GoalMove(d(2026, 8, 20), 10000), // before: counts as saved only
          GoalMove(d(2026, 9, 1), 30000),
          GoalMove(d(2026, 9, 30), -5000),
          GoalMove(d(2026, 10, 1), 99999), // after: not counted at all
        ]),
      ], september);
      final g = out.single;
      expect(g.movedCents, 25000);
      expect(g.savedAtEndCents, 35000);
      expect(g.permilleAtEnd, 350);
      expect(g.reachedByEnd, isFalse);
    });

    test('leaves out goals with no entry in the month', () {
      final out = reportGoalsOf([
        goal(1, [GoalMove(d(2026, 8, 20), 10000)]),
        goal(2, const []),
        goal(3, [GoalMove(d(2026, 10, 2), 10000)]),
        goal(4, [GoalMove(d(2026, 9, 15), 100)]),
      ], september);
      expect(out.map((g) => g.goalId), [4]);
    });

    test('keeps the order given, and says when a goal was reached', () {
      final out = reportGoalsOf([
        goal(2, [GoalMove(d(2026, 9, 2), 5000)], target: 5000),
        goal(1, [GoalMove(d(2026, 9, 3), 100)]),
      ], september);
      expect(out.map((g) => g.goalId), [2, 1]);
      expect(out.first.reachedByEnd, isTrue);
      expect(out.first.permilleAtEnd, 1000);
    });

    test('a month where more came out than went in is negative', () {
      final out = reportGoalsOf([
        goal(1, [
          GoalMove(d(2026, 8, 1), 20000),
          GoalMove(d(2026, 9, 5), -7000),
        ]),
      ], september);
      expect(out.single.movedCents, -7000);
      expect(out.single.savedAtEndCents, 13000);
    });

    test('time of day on an entry does not move it across a month end', () {
      final out = reportGoalsOf([
        goal(1, [GoalMove(DateTime(2026, 9, 30, 23, 59), 100)]),
      ], september);
      expect(out.single.movedCents, 100);
    });
  });

  group('suggestionsOf with goals', () {
    List<ReportSuggestion> suggest({
      List<({int id, String name})> idle = const [],
      BackupFreshness backup = BackupFreshness.recent,
    }) => suggestionsOf(
      spending: [cat(1, 'A', 30000), cat(2, 'B', 30000)],
      budgetedCategoryIds: const {},
      backup: backup,
      idleGoals: idle,
    );

    test('a goal that was left alone comes after the budget suggestions', () {
      final out = suggest(idle: [(id: 7, name: 'Trip'), (id: 8, name: 'X')]);
      expect(out.map((s) => s.runtimeType), [
        SetLimitSuggestion,
        SetLimitSuggestion,
        AddToGoalSuggestion,
      ]);
      expect((out.last as AddToGoalSuggestion).goalId, 7);
    });

    test('only the first idle goal is suggested', () {
      final out = suggest(idle: [(id: 7, name: 'Trip'), (id: 8, name: 'X')]);
      expect(out.whereType<AddToGoalSuggestion>(), hasLength(1));
    });

    test('with a goal and a backup, one budget makes room for both', () {
      final out = suggest(
        idle: [(id: 7, name: 'Trip')],
        backup: BackupFreshness.never,
      );
      expect(out.map((s) => s.runtimeType), [
        SetLimitSuggestion,
        AddToGoalSuggestion,
        BackUpSuggestion,
      ]);
    });

    test('no idle goals leaves the earlier behaviour alone', () {
      final out = suggest(backup: BackupFreshness.never);
      expect(out.map((s) => s.runtimeType), [
        SetLimitSuggestion,
        SetLimitSuggestion,
        BackUpSuggestion,
      ]);
    });

    test('never more than three', () {
      final out = suggest(
        idle: [(id: 7, name: 'Trip')],
        backup: BackupFreshness.stale,
      );
      expect(out.length, lessThanOrEqualTo(3));
    });
  });
}
