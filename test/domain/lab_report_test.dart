import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/backup_status.dart';
import 'package:heisenbudget/domain/budget.dart';
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
}
