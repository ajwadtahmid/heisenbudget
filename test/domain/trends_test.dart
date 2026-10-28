import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/summary.dart';
import 'package:heisenbudget/domain/trends.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Summary sum(int received, int spent) =>
    Summary(receivedCents: received, spentCents: spent);

/// Months 2026-01 onwards with the given spending, all of them finished.
List<MonthTotals> finished(List<int> spent, {List<int>? received}) {
  final months = [
    for (var i = 0; i < spent.length; i++) BudgetMonth(2026, 1 + i),
  ];
  return monthTotalsOf(
    months,
    [for (var i = 0; i < spent.length; i++) sum(received?[i] ?? 0, spent[i])],
    d(2027, 6, 1),
    1,
  );
}

void main() {
  group('trendMonths', () {
    test('ends with the month holding today, oldest first', () {
      final months = trendMonths(d(2026, 10, 15), 6, 1);
      expect(months.map((m) => m.key), [
        '2026-05',
        '2026-06',
        '2026-07',
        '2026-08',
        '2026-09',
        '2026-10',
      ]);
    });

    test('crosses the year', () {
      final months = trendMonths(d(2026, 2, 3), 4, 1);
      expect(months.map((m) => m.key), [
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
      ]);
    });

    test('follows the month start day', () {
      // With months starting on the 15th, Oct 10 is still in the Sep month.
      final months = trendMonths(d(2026, 10, 10), 3, 15);
      expect(months.last.key, '2026-09');
      expect(months.first.key, '2026-07');
      expect(months.last.range(15), DateRange(d(2026, 9, 15), d(2026, 10, 14)));
    });

    test('twelve months is twelve distinct months', () {
      final months = trendMonths(d(2026, 10, 15), 12, 1);
      expect(months, hasLength(12));
      expect(months.map((m) => m.key).toSet(), hasLength(12));
    });
  });

  group('monthTotalsOf', () {
    test('marks only the month that is still going', () {
      final months = trendMonths(d(2026, 10, 15), 3, 1);
      final totals = monthTotalsOf(
        months,
        [sum(100, 50), sum(200, 80), sum(300, 90)],
        d(2026, 10, 15),
        1,
      );
      expect(totals.map((t) => t.inProgress), [false, false, true]);
      expect(totals.last.range, DateRange(d(2026, 10, 1), d(2026, 10, 31)));
    });

    test('the last day of a month is still in progress; the next is not', () {
      final months = [const BudgetMonth(2026, 10)];
      expect(
        monthTotalsOf(
          months,
          [sum(0, 0)],
          d(2026, 10, 31),
          1,
        ).single.inProgress,
        isTrue,
      );
      expect(
        monthTotalsOf(months, [sum(0, 0)], d(2026, 11, 1), 1).single.inProgress,
        isFalse,
      );
    });

    test('purity, net and emptiness come from the sums', () {
      final t = finished([25000], received: [100000]).single;
      expect(t.netCents, 75000);
      expect(t.purity, 750);
      expect(t.isEmpty, isFalse);
      expect(finished([0]).single.isEmpty, isTrue);
      expect(finished([5000]).single.purity, isNull, reason: 'nothing came in');
    });
  });

  group('compareLastMonth', () {
    test('against the average of the months before it', () {
      // Spent 100.00 five times, then 88.00.
      final c = compareLastMonth(
        finished([10000, 10000, 10000, 10000, 10000, 8800]),
      )!;
      expect(c.month.month.key, '2026-06');
      expect(c.averageCents, 10000);
      expect(c.percent, -12);
      expect(c.monthsAveraged, 5);
    });

    test('above the average is positive', () {
      final c = compareLastMonth(finished([10000, 10000, 15000]))!;
      expect(c.percent, 50);
      expect(c.monthsAveraged, 2);
    });

    test('looks back at most five months', () {
      final c = compareLastMonth(
        finished([90000, 10000, 10000, 10000, 10000, 10000, 10000]),
      )!;
      expect(c.monthsAveraged, 5);
      expect(c.averageCents, 10000, reason: 'the old 900.00 month is too far');
    });

    test('a month still going is not the last month', () {
      final months = trendMonths(d(2026, 10, 15), 3, 1);
      final totals = monthTotalsOf(
        months,
        [sum(0, 10000), sum(0, 12000), sum(0, 99999)],
        d(2026, 10, 15),
        1,
      );
      final c = compareLastMonth(totals)!;
      expect(c.month.month.key, '2026-09');
      expect(c.averageCents, 10000);
      expect(c.percent, 20);
    });

    test('months before anything was logged do not pull the average down', () {
      // Nothing for three months, then 100.00, then 120.00.
      final c = compareLastMonth(finished([0, 0, 0, 10000, 12000]))!;
      expect(c.averageCents, 10000);
      expect(c.monthsAveraged, 1);
      expect(c.percent, 20);
    });

    test('a quiet month in the middle still counts', () {
      final c = compareLastMonth(finished([10000, 0, 10000, 5000]))!;
      expect(c.averageCents, 6667);
      expect(c.monthsAveraged, 3);
    });

    test('says nothing without a second finished month or any history', () {
      expect(compareLastMonth(const []), isNull);
      expect(compareLastMonth(finished([10000])), isNull);
      expect(
        compareLastMonth(finished([0, 0, 5000])),
        isNull,
        reason: 'only empty months before it',
      );
      expect(compareLastMonth(finished([0, 5000])), isNull);
    });

    test('rounds to the nearest percent, away from zero on a tie', () {
      // average 200, last 201: +0.5% rounds to +1.
      expect(compareLastMonth(finished([200, 201]))!.percent, 1);
      // average 200, last 199: -0.5% rounds to -1.
      expect(compareLastMonth(finished([200, 199]))!.percent, -1);
      // average 300, last 301: +0.33% rounds to 0.
      expect(compareLastMonth(finished([300, 301]))!.percent, 0);
    });
  });

  group('topMovers', () {
    CategoryHistory h(String name, List<int> spent, {int id = 0}) =>
        CategoryHistory(
          categoryId: id == 0 ? name.hashCode : id,
          name: name,
          icon: 'category',
          spent: spent,
        );

    test('the biggest rises and falls against the earlier average', () {
      final m = topMovers([
        h('Food', [30000, 20000, 20000, 20000]), // +100.00
        h('Rent', [100000, 100000, 100000, 100000]), // unchanged
        h('Fun', [1000, 5000, 5000, 5000]), // -40.00
        h('Travel', [0, 9000, 9000, 9000]), // -90.00
        h('Bills', [9500, 9000, 9000, 9000]), // +5.00
      ]);
      expect(m.up.map((c) => c.name), ['Food', 'Bills']);
      expect(m.down.map((c) => c.name), ['Travel', 'Fun']);
      expect(m.up.first.deltaCents, 10000);
      expect(m.up.first.averageCents, 20000);
      expect(m.down.first.deltaCents, -9000);
    });

    test('keeps at most the asked number on each side', () {
      final m = topMovers([
        for (var i = 1; i <= 6; i++) h('Up$i', [i * 1000, 0, 0], id: i),
        for (var i = 1; i <= 6; i++)
          h('Down$i', [0, i * 1000, i * 1000], id: 10 + i),
      ], count: 2);
      expect(m.up.map((c) => c.name), ['Up6', 'Up5']);
      expect(m.down.map((c) => c.name), ['Down6', 'Down5']);
    });

    test('a category with only one month cannot move', () {
      expect(
        topMovers([
          h('New', [5000]),
        ]).up,
        isEmpty,
      );
      expect(topMovers(const []).up, isEmpty);
    });

    test('the average of the earlier months is rounded', () {
      final m = topMovers([
        h('A', [1000, 100, 101]),
      ]);
      // (100 + 101) / 2 = 100.5 rounds to 101.
      expect(m.up.single.averageCents, 101);
    });
  });

  group('rhythmOf', () {
    final october = DateRange(d(2026, 10, 1), d(2026, 10, 31));

    test('counts the days so far in the month, not the whole month', () {
      final r = rhythmOf({d(2026, 10, 2): 1000}, october, d(2026, 10, 10))!;
      expect(r.days, 10);
      expect(r.totalCents, 1000);
      expect(r.noSpendDays, 9);
    });

    test('a finished month is counted whole', () {
      final r = rhythmOf({}, october, d(2026, 12, 25))!;
      expect(r.days, 31);
      expect(r.noSpendDays, 31);
      expect(r.longestNoSpendStreak, 31);
      expect(r.busiestDay, isNull);
      expect(r.averagePerDayCents, 0);
    });

    test('before the month starts there is nothing to say', () {
      expect(rhythmOf({}, october, d(2026, 9, 30)), isNull);
    });

    test('the busiest day, the average and the longest quiet run', () {
      final r = rhythmOf(
        {
          d(2026, 10, 1): 500,
          d(2026, 10, 4): 2500, // busiest
          d(2026, 10, 5): 1000,
          d(2026, 10, 9): 100,
        },
        october,
        d(2026, 10, 10),
      )!;
      expect(r.busiestDay, d(2026, 10, 4));
      expect(r.busiestDayCents, 2500);
      expect(r.totalCents, 4100);
      expect(r.averagePerDayCents, 410);
      // Spent on 1, 4, 5, 9: quiet days are 2-3, 6-8 and 10.
      expect(r.noSpendDays, 6);
      expect(r.longestNoSpendStreak, 3);
    });

    test('a tie for busiest keeps the earlier day', () {
      final r = rhythmOf(
        {d(2026, 10, 3): 700, d(2026, 10, 8): 700},
        october,
        d(2026, 10, 10),
      )!;
      expect(r.busiestDay, d(2026, 10, 3));
    });

    test('the average per day is rounded', () {
      // 100 over 3 days is 33.33 (33); 101 over 3 days is 33.67 (34).
      final range = DateRange(d(2026, 10, 1), d(2026, 10, 3));
      expect(
        rhythmOf(
          {d(2026, 10, 1): 100},
          range,
          d(2026, 10, 3),
        )!.averagePerDayCents,
        33,
      );
      expect(
        rhythmOf(
          {d(2026, 10, 1): 101},
          range,
          d(2026, 10, 3),
        )!.averagePerDayCents,
        34,
      );
    });

    test('works for a month that starts mid-month and a leap February', () {
      final fifteenth = DateRange(d(2026, 9, 15), d(2026, 10, 14));
      expect(rhythmOf({}, fifteenth, d(2026, 10, 14))!.days, 30);
      final leap = DateRange(d(2028, 2, 1), d(2028, 2, 29));
      expect(rhythmOf({}, leap, d(2028, 3, 5))!.days, 29);
    });
  });
}
