import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:heisenbudget/domain/iso_date.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/week_mode.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

DateRange r(DateTime a, DateTime b) => DateRange(a, b);

void main() {
  group('fixed mode', () {
    test('Feb non-leap has 4 weeks, last is 22-28', () {
      expect(weeksInMonth(2026, 2, WeekMode.fixed, 1), 4);
      expect(
        weekOfMonth(2026, 2, 4, WeekMode.fixed, 1),
        r(d(2026, 2, 22), d(2026, 2, 28)),
      );
    });

    test('Feb leap has 5 weeks, Week 5 is Feb 29 only', () {
      expect(weeksInMonth(2028, 2, WeekMode.fixed, 1), 5);
      expect(
        weekOfMonth(2028, 2, 5, WeekMode.fixed, 1),
        r(d(2028, 2, 29), d(2028, 2, 29)),
      );
    });

    test('30-day month: Week 5 is 29-30', () {
      expect(
        weekOfMonth(2026, 4, 5, WeekMode.fixed, 1),
        r(d(2026, 4, 29), d(2026, 4, 30)),
      );
    });

    test('31-day month: Week 5 is 29-31', () {
      expect(
        weekOfMonth(2026, 10, 5, WeekMode.fixed, 1),
        r(d(2026, 10, 29), d(2026, 10, 31)),
      );
    });

    test('thisWeek is the block containing today, inside the month', () {
      expect(
        thisWeek(d(2026, 10, 9), WeekMode.fixed, 1),
        r(d(2026, 10, 8), d(2026, 10, 14)),
      );
      expect(
        thisWeek(d(2026, 10, 31), WeekMode.fixed, 1),
        r(d(2026, 10, 29), d(2026, 10, 31)),
      );
    });

    test('week outside range throws', () {
      expect(
        () => weekOfMonth(2026, 2, 5, WeekMode.fixed, 1),
        throwsRangeError,
      );
      expect(
        () => weekOfMonth(2026, 2, 0, WeekMode.fixed, 1),
        throwsRangeError,
      );
    });
  });

  group('calendar mode', () {
    for (var weekStart = 1; weekStart <= 7; weekStart++) {
      test('weeks tile every month exactly (weekStart=$weekStart)', () {
        for (var year = 2023; year <= 2030; year++) {
          for (var month = 1; month <= 12; month++) {
            final total = daysInMonth(year, month);
            final weeks = weeksInMonth(
              year,
              month,
              WeekMode.calendar,
              weekStart,
            );
            expect(weeks, inInclusiveRange(4, 6));

            var expectedStart = d(year, month, 1);
            var sum = 0;
            for (var n = 1; n <= weeks; n++) {
              final w = weekOfMonth(
                year,
                month,
                n,
                WeekMode.calendar,
                weekStart,
              );
              expect(
                w.start,
                expectedStart,
                reason: '$year-$month week $n starts after previous ends',
              );
              expect(w.lengthInDays, inInclusiveRange(1, 7));
              if (n > 1) {
                expect(
                  w.start.weekday,
                  weekStart,
                  reason: 'later weeks start on the week start day',
                );
              }
              sum += w.lengthInDays;
              expectedStart = d(w.end.year, w.end.month, w.end.day + 1);
            }
            expect(sum, total, reason: '$year-$month has no gaps/overlaps');
            expect(
              weekOfMonth(year, month, weeks, WeekMode.calendar, weekStart).end,
              d(year, month, total),
            );
          }
        }
      });

      test('month starting on the week start day: Week 1 is 7 days '
          '(weekStart=$weekStart)', () {
        for (var year = 2026; year <= 2027; year++) {
          for (var month = 1; month <= 12; month++) {
            if (d(year, month, 1).weekday == weekStart) {
              final w = weekOfMonth(
                year,
                month,
                1,
                WeekMode.calendar,
                weekStart,
              );
              expect(w.lengthInDays, 7);
              return;
            }
          }
        }
        fail('no month found for weekStart=$weekStart');
      });

      test('month starting the day before week start: Week 1 is 1 day '
          '(weekStart=$weekStart)', () {
        final dayBefore = weekStart == 1 ? 7 : weekStart - 1;
        for (var year = 2026; year <= 2027; year++) {
          for (var month = 1; month <= 12; month++) {
            if (d(year, month, 1).weekday == dayBefore) {
              final w = weekOfMonth(
                year,
                month,
                1,
                WeekMode.calendar,
                weekStart,
              );
              expect(w.lengthInDays, 1);
              return;
            }
          }
        }
        fail('no month found for weekStart=$weekStart');
      });
    }

    test('Oct 2026 starts Thursday; Monday weeks', () {
      expect(
        weekOfMonth(2026, 10, 1, WeekMode.calendar, 1),
        r(d(2026, 10, 1), d(2026, 10, 4)),
      );
      expect(
        weekOfMonth(2026, 10, 2, WeekMode.calendar, 1),
        r(d(2026, 10, 5), d(2026, 10, 11)),
      );
      expect(weeksInMonth(2026, 10, WeekMode.calendar, 1), 5);
      expect(
        weekOfMonth(2026, 10, 5, WeekMode.calendar, 1),
        r(d(2026, 10, 26), d(2026, 10, 31)),
      );
    });

    test('thisWeek crosses the month boundary', () {
      // Oct 1 2026 is a Thursday; Monday start -> Sep 28 .. Oct 4.
      expect(
        thisWeek(d(2026, 10, 1), WeekMode.calendar, 1),
        r(d(2026, 9, 28), d(2026, 10, 4)),
      );
    });

    test('thisWeek respects a Sunday week start', () {
      expect(
        thisWeek(d(2026, 10, 1), WeekMode.calendar, 7),
        r(d(2026, 9, 27), d(2026, 10, 3)),
      );
    });

    test('thisWeek on the week start day itself', () {
      expect(
        thisWeek(d(2026, 10, 5), WeekMode.calendar, 1),
        r(d(2026, 10, 5), d(2026, 10, 11)),
      );
    });
  });

  group('months and years', () {
    test('thisMonth', () {
      expect(thisMonth(d(2026, 10, 17)), r(d(2026, 10, 1), d(2026, 10, 31)));
    });

    test('leap year February', () {
      expect(monthOf(2028, 2).end, d(2028, 2, 29));
      expect(monthOf(2026, 2).end, d(2026, 2, 28));
    });

    test('year boundary: Dec -> Jan', () {
      expect(monthOf(2026, 12), r(d(2026, 12, 1), d(2026, 12, 31)));
      expect(shiftMonth(d(2026, 12, 15), 1), d(2027, 1, 1));
      expect(shiftMonth(d(2026, 1, 15), -1), d(2025, 12, 1));
    });

    test('calendar thisWeek spans New Year', () {
      // Jan 1 2027 is a Friday.
      expect(
        thisWeek(d(2027, 1, 1), WeekMode.calendar, 1),
        r(d(2026, 12, 28), d(2027, 1, 3)),
      );
    });
  });

  group('custom and inclusive ends', () {
    test('swaps when start > end', () {
      expect(
        custom(d(2026, 10, 9), d(2026, 10, 2)),
        r(d(2026, 10, 2), d(2026, 10, 9)),
      );
    });

    test('single-day range', () {
      final range = custom(d(2026, 10, 2), d(2026, 10, 2));
      expect(range.lengthInDays, 1);
      expect(range.contains(d(2026, 10, 2)), isTrue);
    });

    test('strips time of day', () {
      final range = custom(
        DateTime(2026, 10, 2, 23, 59),
        DateTime(2026, 10, 3, 8),
      );
      expect(range, r(d(2026, 10, 2), d(2026, 10, 3)));
    });

    test('contains is inclusive on both ends', () {
      final range = r(d(2026, 10, 1), d(2026, 10, 7));
      expect(range.contains(d(2026, 10, 1)), isTrue);
      expect(range.contains(d(2026, 10, 7)), isTrue);
      expect(range.contains(d(2026, 9, 30)), isFalse);
      expect(range.contains(d(2026, 10, 8)), isFalse);
    });
  });

  group('period stepping', () {
    test('week anchor steps to adjacent calendar weeks', () {
      final next = shiftWeek(d(2026, 10, 7), 1, WeekMode.calendar, 1);
      expect(
        thisWeek(next, WeekMode.calendar, 1),
        r(d(2026, 10, 12), d(2026, 10, 18)),
      );
      final prev = shiftWeek(d(2026, 10, 7), -1, WeekMode.calendar, 1);
      expect(
        thisWeek(prev, WeekMode.calendar, 1),
        r(d(2026, 9, 28), d(2026, 10, 4)),
      );
    });

    test('fixed mode steps block by block, never skipping Week 5', () {
      final prev = shiftWeek(d(2026, 11, 3), -1, WeekMode.fixed, 1);
      expect(
        thisWeek(prev, WeekMode.fixed, 1),
        r(d(2026, 10, 29), d(2026, 10, 31)),
      );
      final next = shiftWeek(d(2026, 10, 30), 1, WeekMode.fixed, 1);
      expect(
        thisWeek(next, WeekMode.fixed, 1),
        r(d(2026, 11, 1), d(2026, 11, 7)),
      );
    });

    test('WeekOfMonth clamps n when stepping to a shorter month', () {
      // Aug 2026 starts on a Saturday, so Monday-start weeks give 6 weeks.
      expect(weeksInMonth(2026, 8, WeekMode.calendar, 1), 6);
      final stepped = stepPeriod(
        const WeekOfMonth(2026, 8, 6),
        1,
        WeekMode.calendar,
        1,
      );
      expect(stepped, isA<WeekOfMonth>());
      stepped as WeekOfMonth;
      expect(stepped.month, 9);
      expect(stepped.n, weeksInMonth(2026, 9, WeekMode.calendar, 1));
    });

    test('clampPeriod fixes n after a week mode change', () {
      final p = clampPeriod(
        const WeekOfMonth(2026, 8, 6),
        WeekMode.fixed,
        1,
      ) as WeekOfMonth;
      expect(p.n, 5);
    });

    test('stepping a custom range does nothing', () {
      final c = Custom(d(2026, 10, 1), d(2026, 10, 5));
      expect(stepPeriod(c, 1, WeekMode.calendar, 1), same(c));
    });

    test('resolvePeriod matches the underlying functions', () {
      expect(
        resolvePeriod(ThisMonth(d(2026, 10, 17)), WeekMode.calendar, 1),
        thisMonth(d(2026, 10, 17)),
      );
      expect(
        resolvePeriod(const WeekOfMonth(2026, 10, 2), WeekMode.calendar, 1),
        r(d(2026, 10, 5), d(2026, 10, 11)),
      );
    });
  });

  group('iso dates', () {
    test('round trip and padding', () {
      expect(toIsoDate(d(2026, 3, 5)), '2026-03-05');
      expect(fromIsoDate('2026-03-05'), d(2026, 3, 5));
    });

    test('strings sort like dates', () {
      expect(
        toIsoDate(d(2026, 9, 30)).compareTo(toIsoDate(d(2026, 10, 1))),
        lessThan(0),
      );
    });
  });
}
