import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/recurrence.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
BudgetMonth bm(int y, int m) => BudgetMonth(y, m);

void main() {
  group('BudgetMonth', () {
    test('keys sort in time order and parse back', () {
      expect(bm(2026, 10).key, '2026-10');
      expect(bm(2026, 1).key, '2026-01');
      expect(BudgetMonth.parse('2026-10'), bm(2026, 10));
      expect(bm(2026, 9) < bm(2026, 10), isTrue);
      expect(bm(2025, 12) < bm(2026, 1), isTrue);
      expect(bm(2026, 10) > bm(2026, 9), isTrue);
      expect(bm(2026, 10) <= bm(2026, 10), isTrue);
    });

    test('rejects text that is not a budget month', () {
      for (final bad in [
        '',
        '2026-13',
        '2026-00',
        '26-10',
        '2026-1',
        '2026/10',
        'x',
      ]) {
        expect(
          () => BudgetMonth.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('shifts across year ends', () {
      expect(bm(2026, 10).shift(1), bm(2026, 11));
      expect(bm(2026, 12).shift(1), bm(2027, 1));
      expect(bm(2026, 1).shift(-1), bm(2025, 12));
      expect(bm(2026, 3).shift(-15), bm(2024, 12));
      expect(bm(2026, 3).shift(0), bm(2026, 3));
    });

    test('with start day 1 it is the calendar month', () {
      expect(bm(2026, 10).range(1), DateRange(d(2026, 10, 1), d(2026, 10, 31)));
      expect(bm(2026, 2).range(1), DateRange(d(2026, 2, 1), d(2026, 2, 28)));
      expect(bm(2028, 2).range(1), DateRange(d(2028, 2, 1), d(2028, 2, 29)));
    });

    test('with start day 25 it runs to the 24th of the next month', () {
      expect(
        bm(2026, 10).range(25),
        DateRange(d(2026, 10, 25), d(2026, 11, 24)),
      );
      expect(
        bm(2026, 12).range(25),
        DateRange(d(2026, 12, 25), d(2027, 1, 24)),
      );
      expect(bm(2026, 1).range(28), DateRange(d(2026, 1, 28), d(2026, 2, 27)));
    });

    test('consecutive months tile the calendar with no gap or overlap', () {
      for (final startDay in [1, 2, 15, 25, 28]) {
        var month = bm(2026, 1);
        var previousEnd = month.range(startDay).end;
        for (var i = 0; i < 36; i++) {
          month = month.shift(1);
          final r = month.range(startDay);
          expect(
            r.start,
            DateTime(previousEnd.year, previousEnd.month, previousEnd.day + 1),
            reason: 'start day $startDay, $month',
          );
          previousEnd = r.end;
        }
      }
    });

    test('the month containing a date, start day 1', () {
      expect(BudgetMonth.containing(d(2026, 10, 15), 1), bm(2026, 10));
      expect(BudgetMonth.containing(d(2026, 10, 1), 1), bm(2026, 10));
      expect(BudgetMonth.containing(d(2026, 10, 31), 1), bm(2026, 10));
    });

    test('the month containing a date, start day 25', () {
      expect(BudgetMonth.containing(d(2026, 10, 25), 25), bm(2026, 10));
      expect(BudgetMonth.containing(d(2026, 10, 24), 25), bm(2026, 9));
      expect(BudgetMonth.containing(d(2026, 10, 10), 25), bm(2026, 9));
      expect(BudgetMonth.containing(d(2026, 11, 24), 25), bm(2026, 10));
      expect(BudgetMonth.containing(d(2026, 11, 25), 25), bm(2026, 11));
      expect(BudgetMonth.containing(d(2027, 1, 3), 25), bm(2026, 12));
    });

    test('every date lands inside the range of the month it is assigned', () {
      for (final startDay in [1, 7, 25, 28]) {
        for (var i = 0; i < 800; i += 3) {
          final date = DateTime(2026, 1, 1 + i);
          final month = BudgetMonth.containing(date, startDay);
          expect(
            month.range(startDay).contains(date),
            isTrue,
            reason: '$date / $startDay',
          );
        }
      }
    });

    test('a start day outside 1 to 28 is refused', () {
      for (final bad in [0, -1, 29, 31]) {
        expect(() => bm(2026, 10).range(bad), throwsRangeError, reason: '$bad');
        expect(
          () => BudgetMonth.containing(d(2026, 10, 1), bad),
          throwsRangeError,
        );
      }
    });
  });

  group('BudgetUnit', () {
    test('names the length for people', () {
      expect(BudgetUnit.month.label, 'Monthly');
      expect(BudgetUnit.week.label, 'Weekly');
      expect(BudgetUnit.fortnight.label, 'Every 2 weeks');
      expect(const BudgetUnit.days(21).label, 'Every 3 weeks');
      expect(const BudgetUnit.days(10).label, 'Every 10 days');
      expect(const BudgetUnit.days(10).noun, '10 days');
      expect(const BudgetUnit.days(10).plural, '10-day periods');
      expect(const BudgetUnit.days(1).label, 'Daily');
      expect(const BudgetUnit.days(1).noun, 'day');
    });

    test('a run of days without an anchor starts today unless whole weeks', () {
      final today = d(2026, 10, 15); // a Thursday
      DateRange of(int days) => currentRangeFor(
        BudgetUnit.days(days),
        today,
        monthStartDay: 1,
        weekStartDay: 1,
      );
      expect(of(10), DateRange(d(2026, 10, 15), d(2026, 10, 24)));
      expect(of(7), DateRange(d(2026, 10, 12), d(2026, 10, 18)));
      expect(of(21), DateRange(d(2026, 10, 12), d(2026, 11, 1)));
    });

    test('names month lengths for people', () {
      expect(BudgetUnit.quarter.label, 'Quarterly');
      expect(BudgetUnit.year.label, 'Yearly');
      expect(const BudgetUnit.months(4).label, 'Every 4 months');
      expect(const BudgetUnit.months(24).label, 'Every 2 years');
      expect(BudgetUnit.year.noun, 'year');
      expect(const BudgetUnit.months(4).noun, '4 months');
      expect(const BudgetUnit.months(4).plural, '4-month periods');
      expect(BudgetUnit.month.plural, 'months');
      expect(BudgetUnit.month.isMonth, isTrue);
      expect(BudgetUnit.quarter.isMonth, isFalse);
      expect(BudgetUnit.quarter.inMonths, isTrue);
    });

    test('a quarter starts with the budget month that holds the date', () {
      DateRange of(int startDay) => currentRangeFor(
        BudgetUnit.quarter,
        d(2026, 10, 15),
        monthStartDay: startDay,
        weekStartDay: 1,
      );
      expect(of(1), DateRange(d(2026, 10, 1), d(2026, 12, 31)));
      // Oct 15 is still in the budget month that began Sep 25.
      expect(of(25), DateRange(d(2026, 9, 25), d(2026, 12, 24)));
    });

    test('month blocks count from the entry start and stay adjacent', () {
      final entry = LimitEntry(
        categoryId: 1,
        unit: BudgetUnit.quarter,
        repeats: true,
        start: d(2026, 10, 1),
        amountCents: 100,
      );
      expect(
        entry.rangeAt(d(2026, 12, 31), 1),
        DateRange(d(2026, 10, 1), d(2026, 12, 31)),
      );
      expect(
        entry.rangeAt(d(2027, 1, 5), 1),
        DateRange(d(2027, 1, 1), d(2027, 3, 31)),
      );
      expect(
        entry.rangeAt(d(2026, 9, 30), 1),
        DateRange(d(2026, 7, 1), d(2026, 9, 30)),
      );
      final first = entry.firstRange(1);
      expect(
        nextRange(first, BudgetUnit.quarter, 1),
        DateRange(d(2027, 1, 1), d(2027, 3, 31)),
      );
      expect(
        previousRange(first, BudgetUnit.quarter, 1),
        DateRange(d(2026, 7, 1), d(2026, 9, 30)),
      );
      final year = LimitEntry(
        categoryId: null,
        unit: BudgetUnit.year,
        repeats: true,
        start: d(2026, 10, 1),
        amountCents: 100,
      );
      expect(
        year.rangeAt(d(2027, 10, 1), 1),
        DateRange(d(2027, 10, 1), d(2028, 9, 30)),
      );
    });

    test('finished quarters are listed once each', () {
      final entry = LimitEntry(
        categoryId: 1,
        unit: BudgetUnit.quarter,
        repeats: true,
        start: d(2026, 1, 1),
        amountCents: 100,
      );
      final past = pastPeriods([entry], d(2026, 10, 15), monthStartDay: 1);
      expect(past.map((p) => p.range.start), [
        d(2026, 7, 1),
        d(2026, 4, 1),
        d(2026, 1, 1),
      ]);
    });

    test('periods of an entry count from its first day', () {
      final entry = LimitEntry(
        categoryId: 1,
        unit: const BudgetUnit.days(10),
        repeats: true,
        start: d(2026, 10, 1),
        amountCents: 100,
      );
      expect(
        entry.rangeAt(d(2026, 10, 25), 1),
        DateRange(d(2026, 10, 21), d(2026, 10, 30)),
      );
      expect(
        entry.rangeAt(d(2026, 10, 10), 1),
        DateRange(d(2026, 10, 1), d(2026, 10, 10)),
      );
    });
  });

  group('weekStartOf', () {
    test('Monday weeks', () {
      expect(weekStartOf(d(2026, 10, 15), 1), d(2026, 10, 12)); // Thursday
      expect(weekStartOf(d(2026, 10, 12), 1), d(2026, 10, 12));
      expect(weekStartOf(d(2026, 10, 18), 1), d(2026, 10, 12)); // Sunday
      expect(weekStartOf(d(2026, 10, 19), 1), d(2026, 10, 19));
    });

    test('Sunday and Saturday weeks, across month ends', () {
      expect(weekStartOf(d(2026, 10, 15), 7), d(2026, 10, 11));
      expect(weekStartOf(d(2026, 10, 15), 6), d(2026, 10, 10));
      expect(weekStartOf(d(2026, 11, 1), 1), d(2026, 10, 26));
    });
  });

  group('currentRangeFor', () {
    DateRange range(
      BudgetUnit u,
      DateTime date, {
      int month = 1,
      int week = 1,
      DateTime? anchor,
    }) => currentRangeFor(
      u,
      date,
      monthStartDay: month,
      weekStartDay: week,
      anchor: anchor,
    );

    test('a week starts on the chosen weekday', () {
      expect(
        range(BudgetUnit.week, d(2026, 10, 15)),
        DateRange(d(2026, 10, 12), d(2026, 10, 18)),
      );
      expect(
        range(BudgetUnit.week, d(2026, 10, 15), week: 7),
        DateRange(d(2026, 10, 11), d(2026, 10, 17)),
      );
    });

    test('a fortnight without an anchor is this week and the next', () {
      expect(
        range(BudgetUnit.fortnight, d(2026, 10, 15)),
        DateRange(d(2026, 10, 12), d(2026, 10, 25)),
      );
    });

    test('a fortnight with an anchor counts 14-day blocks from it', () {
      final anchor = d(2026, 10, 2);
      expect(
        range(BudgetUnit.fortnight, d(2026, 10, 15), anchor: anchor),
        DateRange(d(2026, 10, 2), d(2026, 10, 15)),
      );
      expect(
        range(BudgetUnit.fortnight, d(2026, 10, 16), anchor: anchor),
        DateRange(d(2026, 10, 16), d(2026, 10, 29)),
      );
      expect(
        range(BudgetUnit.fortnight, d(2026, 10, 1), anchor: anchor),
        DateRange(d(2026, 9, 18), d(2026, 10, 1)),
      );
    });

    test('a month follows the budget-month start day', () {
      expect(
        range(BudgetUnit.month, d(2026, 10, 15)),
        DateRange(d(2026, 10, 1), d(2026, 10, 31)),
      );
      expect(
        range(BudgetUnit.month, d(2026, 10, 15), month: 25),
        DateRange(d(2026, 9, 25), d(2026, 10, 24)),
      );
    });

    test('neighbouring periods are exactly adjacent', () {
      for (final unit in const [
        BudgetUnit.week,
        BudgetUnit.fortnight,
        BudgetUnit.month,
        BudgetUnit.days(10),
      ]) {
        var r = range(unit, d(2026, 10, 15), month: 25);
        for (var i = 0; i < 30; i++) {
          final next = nextRange(r, unit, 25);
          expect(
            next.start,
            DateTime(r.end.year, r.end.month, r.end.day + 1),
            reason: '$unit $i',
          );
          expect(previousRange(next, unit, 25), r, reason: '$unit back $i');
          r = next;
        }
      }
    });

    test('a daylight-saving change never shifts a week or fortnight', () {
      var r = range(BudgetUnit.week, d(2026, 3, 1));
      for (var i = 0; i < 20; i++) {
        expect(r.lengthInDays, 7);
        r = nextRange(r, BudgetUnit.week, 1);
      }
      var f = range(BudgetUnit.fortnight, d(2026, 10, 15));
      for (var i = 0; i < 20; i++) {
        expect(f.lengthInDays, 14);
        f = nextRange(f, BudgetUnit.fortnight, 1);
      }
    });
  });

  group('resolveBudget', () {
    LimitEntry e(
      int? cat,
      DateTime start,
      int? cents, {
      BudgetUnit unit = BudgetUnit.month,
      bool repeats = true,
    }) => LimitEntry(
      categoryId: cat,
      unit: unit,
      repeats: repeats,
      start: start,
      amountCents: cents,
    );

    ResolvedBudget? at(
      List<LimitEntry> entries,
      int? cat,
      DateTime date, {
      int month = 1,
    }) => resolveBudget(entries, cat, date, monthStartDay: month);

    test('no entries means no budget', () {
      expect(at(const [], 1, d(2026, 10, 15)), isNull);
    });

    test('a repeating monthly limit applies from its start onward', () {
      final entries = [e(1, d(2026, 9, 1), 20000)];
      expect(at(entries, 1, d(2026, 8, 31)), isNull);
      final sep = at(entries, 1, d(2026, 9, 10))!;
      expect(sep.limit, 20000);
      expect(sep.range, DateRange(d(2026, 9, 1), d(2026, 9, 30)));
      expect(
        at(entries, 1, d(2026, 10, 15))!.range,
        DateRange(d(2026, 10, 1), d(2026, 10, 31)),
      );
      expect(at(entries, 1, d(2030, 1, 5))!.limit, 20000);
    });

    test('a weekly limit repeats in 7-day blocks from its first day', () {
      final entries = [e(1, d(2026, 10, 12), 5000, unit: BudgetUnit.week)];
      expect(
        at(entries, 1, d(2026, 10, 15))!.range,
        DateRange(d(2026, 10, 12), d(2026, 10, 18)),
      );
      expect(
        at(entries, 1, d(2026, 10, 19))!.range,
        DateRange(d(2026, 10, 19), d(2026, 10, 25)),
      );
      expect(at(entries, 1, d(2026, 12, 25))!.range.lengthInDays, 7);
      expect(
        at(entries, 1, d(2026, 10, 11)),
        isNull,
        reason: 'before it starts',
      );
    });

    test('a fortnightly limit repeats in 14-day blocks', () {
      final entries = [e(1, d(2026, 10, 2), 9000, unit: BudgetUnit.fortnight)];
      expect(
        at(entries, 1, d(2026, 10, 15))!.range,
        DateRange(d(2026, 10, 2), d(2026, 10, 15)),
      );
      expect(
        at(entries, 1, d(2026, 10, 16))!.range,
        DateRange(d(2026, 10, 16), d(2026, 10, 29)),
      );
    });

    test('a one-time limit applies to its first period only', () {
      for (final unit in const [
        BudgetUnit.week,
        BudgetUnit.fortnight,
        BudgetUnit.month,
        BudgetUnit.days(10),
      ]) {
        final start = unit == BudgetUnit.month
            ? d(2026, 10, 1)
            : d(2026, 10, 12);
        final entries = [e(1, start, 5000, unit: unit, repeats: false)];
        final first = at(entries, 1, start)!.range;
        expect(
          at(entries, 1, first.end)!.limit,
          5000,
          reason: '$unit last day',
        );
        expect(
          at(
            entries,
            1,
            DateTime(first.end.year, first.end.month, first.end.day + 1),
          ),
          isNull,
          reason: '$unit after it ends',
        );
        expect(
          at(entries, 1, d(2027, 6, 1)),
          isNull,
          reason: '$unit much later',
        );
      }
    });

    test('a later entry replaces it from its own start and not before', () {
      final entries = [e(1, d(2026, 9, 1), 20000), e(1, d(2026, 11, 1), 30000)];
      expect(at(entries, 1, d(2026, 10, 15))!.limit, 20000);
      expect(at(entries, 1, d(2026, 11, 1))!.limit, 30000);
      expect(at(entries, 1, d(2027, 5, 1))!.limit, 30000);
    });

    test('the order of the entries does not matter', () {
      final entries = [e(1, d(2026, 11, 1), 30000), e(1, d(2026, 9, 1), 20000)];
      expect(at(entries, 1, d(2026, 10, 15))!.limit, 20000);
    });

    test('"no budget" ends it from that day on', () {
      final entries = [e(1, d(2026, 9, 1), 20000), e(1, d(2026, 11, 1), null)];
      expect(at(entries, 1, d(2026, 10, 15))!.limit, 20000);
      expect(at(entries, 1, d(2026, 11, 1)), isNull);
      expect(at(entries, 1, d(2027, 3, 1)), isNull);
    });

    test('changing the period replaces the old one from the new start', () {
      final entries = [
        e(1, d(2026, 9, 1), 20000),
        e(1, d(2026, 10, 12), 6000, unit: BudgetUnit.week),
      ];
      expect(at(entries, 1, d(2026, 10, 5))!.entry.unit, BudgetUnit.month);
      final now = at(entries, 1, d(2026, 10, 15))!;
      expect(now.entry.unit, BudgetUnit.week);
      expect(now.limit, 6000);
    });

    test('a new budget after a one-time one ended replaces it', () {
      final entries = [
        e(1, d(2026, 9, 1), 20000, repeats: false),
        e(1, d(2026, 11, 1), 30000),
      ];
      expect(at(entries, 1, d(2026, 9, 20))!.limit, 20000);
      expect(at(entries, 1, d(2026, 10, 15)), isNull);
      expect(at(entries, 1, d(2026, 11, 20))!.limit, 30000);
    });

    test('categories and all spending are separate', () {
      final entries = [
        e(1, d(2026, 9, 1), 20000),
        e(2, d(2026, 9, 1), 5000),
        e(null, d(2026, 9, 1), 90000),
      ];
      expect(at(entries, 1, d(2026, 10, 1))!.limit, 20000);
      expect(at(entries, 2, d(2026, 10, 1))!.limit, 5000);
      expect(at(entries, null, d(2026, 10, 1))!.limit, 90000);
      expect(at(entries, 3, d(2026, 10, 1)), isNull);
    });

    test('a monthly limit follows the start day setting', () {
      final entries = [e(1, d(2026, 9, 25), 20000)];
      final r = at(entries, 1, d(2026, 10, 10), month: 25)!;
      expect(r.range, DateRange(d(2026, 9, 25), d(2026, 10, 24)));
    });
  });

  group('pastPeriods', () {
    LimitEntry e(
      DateTime start,
      int? cents, {
      BudgetUnit unit = BudgetUnit.month,
      bool repeats = true,
      int? cat = 1,
    }) => LimitEntry(
      categoryId: cat,
      unit: unit,
      repeats: repeats,
      start: start,
      amountCents: cents,
    );

    List<PastPeriod> past(
      List<LimitEntry> entries,
      DateTime today, {
      int limit = 12,
    }) => pastPeriods(entries, today, monthStartDay: 1, limit: limit);

    group('a period that a later change cut short', () {
      test('is listed up to the day before the change, marked ended early', () {
        final p = past([
          e(d(2026, 10, 1), 30000, unit: BudgetUnit.quarter),
          e(d(2026, 11, 1), 10000),
        ], d(2026, 11, 20));
        expect(p, hasLength(1));
        expect(p.single.range, DateRange(d(2026, 10, 1), d(2026, 10, 31)));
        expect((p.single.limit, p.single.endedEarly), (30000, true));
      });

      test('weekly then monthly: the straddling week is clipped', () {
        final p = past([
          e(d(2026, 9, 7), 5000, unit: BudgetUnit.week),
          e(d(2026, 9, 10), 20000),
        ], d(2026, 10, 15));
        // Sep 7 - 13 is cut at Sep 9 (newest start first); the month follows.
        expect(p.map((x) => (x.range, x.endedEarly)).toList(), [
          (DateRange(d(2026, 9, 7), d(2026, 9, 9)), true),
          (DateRange(d(2026, 9, 1), d(2026, 9, 30)), false),
        ]);
      });

      test('stopping mid-period lists the part that ran', () {
        final p = past([
          e(d(2026, 10, 5), 5000, unit: BudgetUnit.week),
          e(d(2026, 10, 14), null, unit: BudgetUnit.week), // stopped
        ], d(2026, 10, 20));
        expect(p.map((x) => (x.range, x.endedEarly)).toList(), [
          (DateRange(d(2026, 10, 12), d(2026, 10, 13)), true),
          (DateRange(d(2026, 10, 5), d(2026, 10, 11)), false),
        ]);
      });

      test('a one-time budget cut short is listed once', () {
        final p = past([
          e(d(2026, 10, 1), 30000, unit: BudgetUnit.quarter, repeats: false),
          e(d(2026, 11, 15), 10000),
        ], d(2026, 11, 20));
        expect(p, hasLength(1));
        expect(p.single.range, DateRange(d(2026, 10, 1), d(2026, 11, 14)));
        expect(p.single.endedEarly, isTrue);
      });

      test('a change that has not happened yet cuts nothing', () {
        final p = past([
          e(d(2026, 9, 1), 30000),
          e(d(2026, 12, 1), 10000), // starts in the future
        ], d(2026, 10, 15));
        expect(p.map((x) => (x.range.start, x.endedEarly)).toList(), [
          (d(2026, 9, 1), false),
        ]);
      });
    });

    test(
      'lists finished monthly periods, newest first, not the current one',
      () {
        final p = past([e(d(2026, 7, 1), 20000)], d(2026, 10, 15));
        expect(p.map((x) => x.range.start), [
          d(2026, 9, 1),
          d(2026, 8, 1),
          d(2026, 7, 1),
        ]);
        expect(p.every((x) => x.limit == 20000), isTrue);
      },
    );

    test('nothing before the budget started', () {
      expect(past([e(d(2026, 10, 1), 20000)], d(2026, 10, 15)), isEmpty);
    });

    test('weekly periods are 7-day blocks', () {
      final p = past([
        e(d(2026, 10, 5), 5000, unit: BudgetUnit.week),
      ], d(2026, 10, 20));
      expect(p.map((x) => x.range.start), [d(2026, 10, 12), d(2026, 10, 5)]);
      expect(p.every((x) => x.range.lengthInDays == 7), isTrue);
    });

    test('a one-time budget gives one past period once it is over', () {
      final entries = [e(d(2026, 8, 1), 20000, repeats: false)];
      expect(past(entries, d(2026, 8, 20)), isEmpty, reason: 'still running');
      final p = past(entries, d(2026, 10, 15));
      expect(p, hasLength(1));
      expect(p.single.range, DateRange(d(2026, 8, 1), d(2026, 8, 31)));
    });

    test('each period shows the amount in force then', () {
      final p = past([
        e(d(2026, 6, 1), 20000),
        e(d(2026, 9, 1), 30000),
      ], d(2026, 10, 15));
      final byStart = {for (final x in p) x.range.start: x.limit};
      expect(byStart[d(2026, 6, 1)], 20000);
      expect(byStart[d(2026, 8, 1)], 20000);
      expect(byStart[d(2026, 9, 1)], 30000);
    });

    test('a stopped budget keeps its history up to the day it stopped', () {
      final p = past([
        e(d(2026, 6, 1), 20000),
        e(d(2026, 9, 1), null),
      ], d(2026, 10, 15));
      expect(p.map((x) => x.range.start), [
        d(2026, 8, 1),
        d(2026, 7, 1),
        d(2026, 6, 1),
      ]);
    });

    test(
      'changing the period: the old periods end where the new one begins',
      () {
        final p = past([
          e(d(2026, 7, 1), 20000),
          e(d(2026, 10, 1), 6000, unit: BudgetUnit.week),
        ], d(2026, 10, 20));
        final months = p
            .where((x) => x.entry.unit == BudgetUnit.month)
            .map((x) => x.range.start)
            .toList();
        expect(months, [d(2026, 9, 1), d(2026, 8, 1), d(2026, 7, 1)]);
        final weeks = p
            .where((x) => x.entry.unit == BudgetUnit.week)
            .map((x) => x.range.start)
            .toList();
        expect(weeks, [d(2026, 10, 8), d(2026, 10, 1)]);
      },
    );

    test('the limit caps how many are returned, newest kept', () {
      final p = past([e(d(2025, 1, 1), 100)], d(2026, 10, 15), limit: 5);
      expect(p, hasLength(5));
      expect(p.first.range.start, d(2026, 9, 1));
    });

    test('a period ending yesterday is finished; one ending today is not', () {
      final entries = [e(d(2026, 9, 1), 100)];
      expect(past(entries, d(2026, 10, 1)).map((x) => x.range.start), [
        d(2026, 9, 1),
      ]);
      expect(past(entries, d(2026, 9, 30)), isEmpty);
    });
  });

  group('buildBudgetStatus', () {
    final october = bm(2026, 10).range(1);

    BudgetStatus status(
      int limit,
      int spent,
      DateTime today, {
      int planned = 0,
    }) => buildBudgetStatus(
      limit: limit,
      spent: spent,
      planned: planned,
      range: october,
      today: today,
    );

    test('well within the limit', () {
      final s = status(20000, 5000, d(2026, 10, 10));
      expect(s.left, 15000);
      expect(s.level, BudgetLevel.ok);
      expect(s.isOver, isFalse);
      expect(s.overBy, 0);
      expect(s.permille, 250);
    });

    test('"almost" starts at 80 percent and stays until it is over', () {
      expect(status(20000, 15999, d(2026, 10, 10)).level, BudgetLevel.ok);
      expect(status(20000, 16000, d(2026, 10, 10)).level, BudgetLevel.almost);
      expect(status(20000, 20000, d(2026, 10, 10)).level, BudgetLevel.almost);
      expect(status(20000, 20001, d(2026, 10, 10)).level, BudgetLevel.over);
    });

    test('over by how much', () {
      final s = status(20000, 23500, d(2026, 10, 10));
      expect(s.isOver, isTrue);
      expect(s.overBy, 3500);
      expect(s.left, -3500);
      expect(s.permille, 1000, reason: 'the bar stops at full');
      expect(s.perDay, isNull);
    });

    test('exactly at the limit is not over, and nothing is left per day', () {
      final s = status(20000, 20000, d(2026, 10, 10));
      expect(s.isOver, isFalse);
      expect(s.left, 0);
      expect(s.perDay, isNull);
    });

    test('days left count today, and per day divides what is left', () {
      final s = status(31000, 0, d(2026, 10, 22));
      expect(s.daysLeft, 10, reason: 'Oct 22 to 31 inclusive');
      expect(s.perDay, 3100);
      expect(status(30000, 0, d(2026, 10, 31)).daysLeft, 1);
      expect(status(30000, 0, d(2026, 10, 31)).perDay, 30000);
    });

    test('per day rounds down to whole cents', () {
      final s = status(10000, 0, d(2026, 10, 22)); // 10 days
      expect(s.perDay, 1000);
      final t = status(10001, 0, d(2026, 10, 22));
      expect(t.perDay, 1000);
    });

    test(
      'a month that has not started: its whole length, nothing spent yet',
      () {
        final s = status(31000, 0, d(2026, 9, 20));
        expect(s.hasStarted, isFalse);
        expect(s.hasEnded, isFalse);
        expect(s.daysLeft, 31);
        expect(s.perDay, 1000);
      },
    );

    test('a month that has ended: no days left, no per day, no planned', () {
      final s = status(31000, 5000, d(2026, 11, 3), planned: 9000);
      expect(s.hasEnded, isTrue);
      expect(s.daysLeft, 0);
      expect(s.perDay, isNull);
      expect(s.planned, 0);
      expect(s.left, 26000);
    });

    test('the first and last day are inside the month', () {
      expect(status(100, 0, d(2026, 10, 1)).hasStarted, isTrue);
      expect(status(100, 0, d(2026, 10, 1)).daysLeft, 31);
      expect(status(100, 0, d(2026, 10, 31)).hasEnded, isFalse);
      expect(status(100, 0, d(2026, 11, 1)).hasEnded, isTrue);
    });

    test('planned expenses that would break the limit are flagged', () {
      final s = status(20000, 15000, d(2026, 10, 10), planned: 7000);
      expect(s.isOver, isFalse);
      expect(s.plannedWouldExceed, isTrue);
      expect(s.plannedOverBy, 2000);
      final ok = status(20000, 15000, d(2026, 10, 10), planned: 5000);
      expect(ok.plannedWouldExceed, isFalse);
      expect(ok.plannedOverBy, 0);
    });

    test('already over: the planned warning stays quiet', () {
      final s = status(20000, 25000, d(2026, 10, 10), planned: 3000);
      expect(s.plannedWouldExceed, isFalse);
    });

    test('a zero limit counts as fully used', () {
      final s = status(0, 0, d(2026, 10, 10));
      expect(s.permille, 1000);
    });

    test(
      'a budget month that starts on the 25th counts days across the month end',
      () {
        final range = bm(2026, 10).range(25);
        final s = buildBudgetStatus(
          limit: 30000,
          spent: 0,
          range: range,
          today: d(2026, 11, 20),
        );
        expect(s.daysLeft, 5); // Nov 20 to Nov 24
        expect(s.perDay, 6000);
      },
    );
  });

  group('plannedByCategory', () {
    PlannedRule monthly(int cat, int cents, DateTime start, {int next = 0}) =>
        PlannedRule(
          categoryId: cat,
          amountCents: cents,
          recurrence: Recurrence(
            unit: RecurrenceUnit.month,
            interval: 1,
            start: start,
          ),
          nextIndex: next,
        );

    test('counts what is still due later this month', () {
      final october = bm(2026, 10).range(1);
      // Rent on the 28th, due again Oct 28 (index 1 after Sep 28).
      final planned = plannedByCategory(
        [monthly(1, 120000, d(2026, 9, 28), next: 1)],
        october,
        d(2026, 10, 15),
      );
      expect(planned, {1: 120000});
    });

    test('does not count what is due today or earlier (already added)', () {
      final october = bm(2026, 10).range(1);
      expect(
        plannedByCategory(
          [monthly(1, 100, d(2026, 9, 15), next: 1)],
          october,
          d(2026, 10, 15),
        ),
        isEmpty,
      );
    });

    test('counts every occurrence in the rest of the month', () {
      final october = bm(2026, 10).range(1);
      final weekly = PlannedRule(
        categoryId: 2,
        amountCents: 1000,
        recurrence: Recurrence(
          unit: RecurrenceUnit.week,
          interval: 1,
          start: d(2026, 10, 1),
        ),
        nextIndex: 2, // Oct 15 was index 2 and is already added
      );
      // Oct 22 and Oct 29 remain.
      expect(plannedByCategory([weekly], october, d(2026, 10, 15)), {2: 2000});
    });

    test('adds up rules of the same category and keeps others apart', () {
      final october = bm(2026, 10).range(1);
      final planned = plannedByCategory(
        [
          monthly(1, 100, d(2026, 9, 20), next: 1),
          monthly(1, 250, d(2026, 9, 25), next: 1),
          monthly(2, 700, d(2026, 9, 30), next: 1),
        ],
        october,
        d(2026, 10, 15),
      );
      expect(planned, {1: 350, 2: 700});
    });

    test('nothing for a month that is over, and the future month gets its occurrences', () {
      final september = bm(2026, 9).range(1);
      expect(
        plannedByCategory(
          [monthly(1, 100, d(2026, 8, 20), next: 2)],
          september,
          d(2026, 10, 15),
        ),
        isEmpty,
      );
      final december = bm(2026, 12).range(1);
      expect(
        plannedByCategory(
          [monthly(1, 100, d(2026, 8, 20), next: 2)],
          december,
          d(2026, 10, 15),
        ),
        {1: 100},
      );
    });

    test('a rule that has ended counts nothing', () {
      final october = bm(2026, 10).range(1);
      final ended = PlannedRule(
        categoryId: 1,
        amountCents: 100,
        recurrence: Recurrence(
          unit: RecurrenceUnit.month,
          interval: 1,
          start: d(2026, 5, 20),
          end: d(2026, 9, 20),
        ),
        nextIndex: 5,
      );
      expect(plannedByCategory([ended], october, d(2026, 10, 15)), isEmpty);
    });

    test('a daily rule and a far-away month stay bounded and correct', () {
      final daily = PlannedRule(
        categoryId: 1,
        amountCents: 100,
        recurrence: Recurrence(
          unit: RecurrenceUnit.day,
          interval: 1,
          start: d(2026, 10, 1),
        ),
        nextIndex: 15,
      );
      final october = bm(2026, 10).range(1);
      expect(plannedByCategory([daily], october, d(2026, 10, 15)), {1: 1600});
    });

    test('works across a start-day-25 budget month', () {
      final range = bm(2026, 10).range(25); // Oct 25 - Nov 24
      final planned = plannedByCategory(
        [monthly(1, 500, d(2026, 9, 1), next: 2)], // Nov 1 is index 2
        range,
        d(2026, 10, 28),
      );
      expect(planned, {1: 500});
    });
  });

  group('suggestLimit', () {
    test('the average, rounded to a whole unit', () {
      expect(suggestLimit([10000, 20000, 30000]), 20000);
      expect(suggestLimit([10050, 10000, 10000]), 10000);
      expect(
        suggestLimit([10150, 10150, 10150]),
        10200,
        reason: 'to the nearest unit',
      );
    });

    test('months with nothing spent still count towards the average', () {
      expect(suggestLimit([30000, 0, 0]), 10000);
    });

    test('a tiny average is not rounded down to zero', () {
      expect(suggestLimit([10, 0, 0]), 100);
    });

    test('nothing spent, or no months, gives no suggestion', () {
      expect(suggestLimit([0, 0, 0]), isNull);
      expect(suggestLimit(const []), isNull);
    });
  });

  group('a multi-month period with an anchor', () {
    DateRange of(DateTime anchor, {int startDay = 1}) => currentRangeFor(
      BudgetUnit.quarter,
      d(2026, 11, 20),
      monthStartDay: startDay,
      weekStartDay: 1,
      anchor: anchor,
    );

    test('starts in the budget month that holds the anchor', () {
      expect(of(d(2026, 10, 1)), DateRange(d(2026, 10, 1), d(2026, 12, 31)));
      expect(of(d(2026, 9, 1)), DateRange(d(2026, 9, 1), d(2026, 11, 30)));
      expect(of(d(2026, 11, 7)), DateRange(d(2026, 11, 1), d(2027, 1, 31)));
    });

    test('follows the budget month start day', () {
      // Starting on the 25th, Sep 25 begins "September".
      expect(
        of(d(2026, 9, 25), startDay: 25),
        DateRange(d(2026, 9, 25), d(2026, 12, 24)),
      );
    });

    test('no anchor still means the month that holds today', () {
      expect(
        currentRangeFor(
          BudgetUnit.quarter,
          d(2026, 11, 20),
          monthStartDay: 1,
          weekStartDay: 1,
        ),
        DateRange(d(2026, 11, 1), d(2027, 1, 31)),
      );
    });
  });

  group('overrunHint', () {
    // Newest first, as pastPeriods gives them.
    OverrunHint? hint(
      List<(int limit, int spent)> periods, {
      int lookBack = 6,
    }) => overrunHint([
      for (final (limit, spent) in periods) (limit: limit, spent: spent),
    ], lookBack: lookBack);

    test('says nothing with fewer than three finished periods', () {
      expect(hint(const []), isNull);
      expect(hint(const [(100, 200), (100, 200)]), isNull);
    });

    test('says nothing when it ran over only once', () {
      expect(hint(const [(100, 150), (100, 90), (100, 80), (100, 95)]), isNull);
    });

    test('says nothing when it ran over in fewer than half the periods', () {
      // 2 of 5 is under half.
      expect(
        hint(const [(100, 150), (100, 90), (100, 160), (100, 80), (100, 70)]),
        isNull,
      );
    });

    test(
      'speaks up when it ran over in at least half, and says by how much',
      () {
        final h = hint(const [
          (100, 150), // over by 50
          (100, 90),
          (100, 130), // over by 30
          (100, 80),
        ])!;
        expect((h.over, h.of), (2, 4));
        expect(h.averageOverCents, 40);
      },
    );

    test('a spend exactly at the limit is not over', () {
      expect(
        hint(const [(100, 100), (100, 100), (100, 100), (100, 101)]),
        isNull,
      );
      expect(
        hint(const [(100, 101), (100, 101), (100, 100)])!.averageOverCents,
        1,
      );
    });

    test('looks only at the most recent periods', () {
      // Six recent ones within the limit, older ones all over: not "usually".
      final periods = [
        for (var i = 0; i < 6; i++) (100, 50),
        for (var i = 0; i < 6; i++) (100, 500),
      ];
      expect(hint(periods), isNull);
      // But a window wide enough to reach them would say so.
      expect(hint(periods, lookBack: 12), isNotNull);
    });

    test('the average is rounded to the nearest cent', () {
      // Over by 1 and 2: average 1.5 rounds up to 2.
      final h = hint(const [(100, 101), (100, 102), (100, 50)])!;
      expect(h.averageOverCents, 2);
    });
  });
}
