import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/comparison.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/week_mode.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
DateRange r(DateTime a, DateTime b) => DateRange(a, b);

Comparison? compare(
  Period period,
  DateTime today, {
  WeekMode mode = WeekMode.calendar,
  int startDay = 1,
}) => buildComparison(
  period: period,
  range: resolvePeriod(period, mode, startDay),
  today: today,
  mode: mode,
  weekStartDay: startDay,
);

void main() {
  group('months', () {
    test('in progress: the days so far against the same days last month', () {
      final c = compare(ThisMonth(d(2026, 10, 25)), d(2026, 10, 25))!;
      expect(c.current, r(d(2026, 10, 1), d(2026, 10, 25)));
      expect(c.previous, r(d(2026, 9, 1), d(2026, 9, 25)));
      expect(c.paceMatched, isTrue);
      expect(c.kind, ComparisonKind.month);
    });

    test('a finished month is compared whole against whole', () {
      final c = compare(ThisMonth(d(2026, 9, 10)), d(2026, 10, 25))!;
      expect(c.current, r(d(2026, 9, 1), d(2026, 9, 30)));
      expect(c.previous, r(d(2026, 8, 1), d(2026, 8, 31)));
      expect(c.paceMatched, isFalse);
    });

    test('the last day of the month counts as finished', () {
      final c = compare(ThisMonth(d(2026, 10, 31)), d(2026, 10, 31))!;
      expect(c.paceMatched, isFalse);
      expect(c.current, r(d(2026, 10, 1), d(2026, 10, 31)));
      expect(c.previous, r(d(2026, 9, 1), d(2026, 9, 30)));
    });

    test('the first day compares one day with one day', () {
      final c = compare(ThisMonth(d(2026, 10, 1)), d(2026, 10, 1))!;
      expect(c.current, r(d(2026, 10, 1), d(2026, 10, 1)));
      expect(c.previous, r(d(2026, 9, 1), d(2026, 9, 1)));
    });

    test('a shorter previous month is clipped to what exists', () {
      final c = compare(ThisMonth(d(2026, 3, 30)), d(2026, 3, 30))!;
      expect(c.current, r(d(2026, 3, 1), d(2026, 3, 30)));
      expect(c.previous, r(d(2026, 2, 1), d(2026, 2, 28)));
    });

    test('a leap February is 29 days', () {
      final c = compare(ThisMonth(d(2028, 3, 31)), d(2028, 3, 31))!;
      expect(c.previous, r(d(2028, 2, 1), d(2028, 2, 29)));
      final mid = compare(ThisMonth(d(2028, 3, 10)), d(2028, 3, 10))!;
      expect(mid.previous, r(d(2028, 2, 1), d(2028, 2, 10)));
    });

    test('January looks back into December of the year before', () {
      final c = compare(ThisMonth(d(2027, 1, 12)), d(2027, 1, 12))!;
      expect(c.previous, r(d(2026, 12, 1), d(2026, 12, 12)));
    });

    test('a longer previous month is cut to the same days', () {
      final c = compare(ThisMonth(d(2026, 4, 30)), d(2026, 4, 30))!;
      expect(c.paceMatched, isFalse);
      expect(c.previous, r(d(2026, 3, 1), d(2026, 3, 31)));
      final mid = compare(ThisMonth(d(2026, 4, 20)), d(2026, 4, 20))!;
      expect(mid.previous, r(d(2026, 3, 1), d(2026, 3, 20)));
    });

    test('a month that has not started has nothing to compare', () {
      expect(compare(ThisMonth(d(2026, 11, 5)), d(2026, 10, 25)), isNull);
    });

    test('the time of day does not matter', () {
      final c = compare(
        ThisMonth(d(2026, 10, 25)),
        DateTime(2026, 10, 25, 23, 59),
      )!;
      expect(c.current.end, d(2026, 10, 25));
    });
  });

  group('weeks', () {
    test(
      'a calendar week in progress against the same days of the week before',
      () {
        // Thursday Oct 15, weeks start on Monday: Oct 12 to 18.
        final c = compare(ThisWeek(d(2026, 10, 15)), d(2026, 10, 15))!;
        expect(c.current, r(d(2026, 10, 12), d(2026, 10, 15)));
        expect(c.previous, r(d(2026, 10, 5), d(2026, 10, 8)));
        expect(c.kind, ComparisonKind.week);
        expect(c.paceMatched, isTrue);
      },
    );

    test('a finished week is whole against whole', () {
      final c = compare(ThisWeek(d(2026, 10, 7)), d(2026, 10, 15))!;
      expect(c.current, r(d(2026, 10, 5), d(2026, 10, 11)));
      expect(c.previous, r(d(2026, 9, 28), d(2026, 10, 4)));
      expect(c.paceMatched, isFalse);
    });

    test('weeks that start on Sunday', () {
      final c = compare(
        ThisWeek(d(2026, 10, 15)),
        d(2026, 10, 15),
        startDay: 7,
      )!;
      expect(c.current, r(d(2026, 10, 11), d(2026, 10, 15)));
      expect(c.previous, r(d(2026, 10, 4), d(2026, 10, 8)));
    });

    test('fixed 7-day blocks', () {
      // Oct 15 is in the 15 to 21 block; the block before is 8 to 14.
      final c = compare(
        ThisWeek(d(2026, 10, 16)),
        d(2026, 10, 16),
        mode: WeekMode.fixed,
      )!;
      expect(c.current, r(d(2026, 10, 15), d(2026, 10, 16)));
      expect(c.previous, r(d(2026, 10, 8), d(2026, 10, 9)));
    });

    test('a week across a month end keeps its seven days', () {
      final c = compare(ThisWeek(d(2026, 11, 3)), d(2026, 11, 4))!;
      expect(c.current, r(d(2026, 11, 2), d(2026, 11, 4)));
      expect(c.previous, r(d(2026, 10, 26), d(2026, 10, 28)));
    });
  });

  group('week N of a month', () {
    test('compares with the same week number of the month before', () {
      final week = WeekOfMonth(2026, 10, 2);
      final range = resolvePeriod(week, WeekMode.calendar, 1);
      final c = compare(week, range.end.add(const Duration(days: 3)))!;
      expect(c.kind, ComparisonKind.weekOfMonth);
      expect(c.current, range);
      expect(
        c.previous,
        resolvePeriod(WeekOfMonth(2026, 9, 2), WeekMode.calendar, 1),
      );
      expect(c.paceMatched, isFalse);
    });

    test('a week 6 steps to the last week of a month that has only 5', () {
      // In calendar mode with Monday starts, find a month that has 6 weeks.
      final week6 = WeekOfMonth(2026, 8, 6);
      final range = resolvePeriod(week6, WeekMode.calendar, 1);
      final before = previousPeriodRange(week6, range, WeekMode.calendar, 1);
      expect(
        before,
        resolvePeriod(
          clampPeriod(WeekOfMonth(2026, 7, 6), WeekMode.calendar, 1),
          WeekMode.calendar,
          1,
        ),
      );
    });
  });

  group('custom ranges', () {
    test(
      'a finished range is compared with the equal window right before it',
      () {
        final period = Custom(d(2026, 10, 10), d(2026, 10, 19));
        final c = compare(period, d(2026, 10, 31))!;
        expect(c.kind, ComparisonKind.custom);
        expect(c.current, r(d(2026, 10, 10), d(2026, 10, 19)));
        expect(c.previous, r(d(2026, 9, 30), d(2026, 10, 9)));
        expect(c.previous.lengthInDays, c.current.lengthInDays);
      },
    );

    test('a range in progress is cut to the days so far', () {
      final period = Custom(d(2026, 10, 20), d(2026, 11, 5));
      final c = compare(period, d(2026, 10, 25))!;
      expect(c.paceMatched, isTrue);
      expect(c.current, r(d(2026, 10, 20), d(2026, 10, 25)));
      // 17 days long, so the window before is Oct 3 to Oct 19; first 6 days.
      expect(c.previous, r(d(2026, 10, 3), d(2026, 10, 8)));
    });

    test('a one-day range compares with the day before', () {
      final c = compare(
        Custom(d(2026, 10, 10), d(2026, 10, 10)),
        d(2026, 10, 20),
      )!;
      expect(c.previous, r(d(2026, 10, 9), d(2026, 10, 9)));
    });

    test('a range across a daylight-saving change keeps its length', () {
      final period = Custom(d(2026, 3, 1), d(2026, 3, 31));
      final c = compare(period, d(2026, 4, 5))!;
      expect(c.previous.lengthInDays, 31);
      expect(c.previous, r(d(2026, 1, 29), d(2026, 2, 28)));
    });

    test('a range that has not started has nothing to compare', () {
      expect(
        compare(Custom(d(2026, 11, 1), d(2026, 11, 9)), d(2026, 10, 25)),
        isNull,
      );
    });
  });

  group('compareTotals', () {
    Delta? c(int now, int before) =>
        compareTotals(current: now, previous: before);

    test('both zero says nothing', () => expect(c(0, 0), isNull));

    test('a fall', () {
      final delta = c(88000, 100000)!;
      expect(delta.direction, DeltaDirection.down);
      expect(delta.percent, 12);
      expect(delta.cents, 12000);
      expect(delta.fromNothing, isFalse);
    });

    test('a rise', () {
      final delta = c(125000, 100000)!;
      expect(delta.direction, DeltaDirection.up);
      expect(delta.percent, 25);
      expect(delta.cents, 25000);
    });

    test('rounds to the nearest whole percent', () {
      expect(c(10049, 10000)!.direction, DeltaDirection.same, reason: '0.49%');
      expect(c(10050, 10000)!.percent, 1, reason: '0.5% rounds up');
      expect(c(10149, 10000)!.percent, 1);
      expect(c(10150, 10000)!.percent, 2);
      expect(c(9950, 10000)!.percent, 1);
    });

    test('equal totals are the same', () {
      final delta = c(5000, 5000)!;
      expect(delta.direction, DeltaDirection.same);
      expect(delta.cents, 0);
    });

    test(
      'a change too small to round to 1% is "the same" but keeps its size',
      () {
        final delta = c(100001, 100000)!;
        expect(delta.direction, DeltaDirection.same);
        expect(delta.cents, 1);
      },
    );

    test('from nothing has no percentage, only the amount', () {
      final delta = c(25000, 0)!;
      expect(delta.direction, DeltaDirection.up);
      expect(delta.fromNothing, isTrue);
      expect(delta.percent, isNull);
      expect(delta.cents, 25000);
    });

    test('down to nothing is 100%', () {
      final delta = c(0, 25000)!;
      expect(delta.direction, DeltaDirection.down);
      expect(delta.percent, 100);
      expect(delta.cents, 25000);
    });

    test('huge rises are capped at 999%', () {
      final delta = c(100000000, 100)!;
      expect(delta.percent, Delta.maxPercent);
      expect(delta.capped, isTrue);
      final exact = c(1000 * 100, 100 * 100)!;
      expect(exact.percent, 900);
      expect(exact.capped, isFalse);
    });

    test('very large amounts do not overflow', () {
      final delta = c(99999999999, 49999999999)!;
      expect(delta.percent, 100);
    });
  });
}
