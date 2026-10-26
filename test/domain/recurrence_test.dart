import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/recurrence.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Recurrence monthly(DateTime start, {int every = 1, DateTime? end}) =>
    Recurrence(
      unit: RecurrenceUnit.month,
      interval: every,
      start: start,
      end: end,
    );

void main() {
  group('monthly', () {
    test('keeps the day of the month', () {
      final r = monthly(d(2026, 1, 15));
      expect(
        [for (var k = 0; k < 4; k++) r.occurrence(k)],
        [d(2026, 1, 15), d(2026, 2, 15), d(2026, 3, 15), d(2026, 4, 15)],
      );
    });

    test('the 31st clamps to the last day, then returns to the 31st', () {
      final r = monthly(d(2026, 1, 31));
      expect(
        [for (var k = 0; k < 5; k++) r.occurrence(k)],
        [
          d(2026, 1, 31),
          d(2026, 2, 28),
          d(2026, 3, 31),
          d(2026, 4, 30),
          d(2026, 5, 31),
        ],
      );
    });

    test('February in a leap year', () {
      final r = monthly(d(2028, 1, 30));
      expect(r.occurrence(1), d(2028, 2, 29));
      expect(r.occurrence(2), d(2028, 3, 30));
    });

    test('every 3 months crosses the year', () {
      final r = monthly(d(2026, 11, 10), every: 3);
      expect(r.occurrence(1), d(2027, 2, 10));
      expect(r.occurrence(2), d(2027, 5, 10));
    });

    test('a long way out stays correct (no drift)', () {
      final r = monthly(d(2026, 1, 31));
      expect(r.occurrence(120), d(2036, 1, 31));
      expect(r.occurrence(121), d(2036, 2, 29));
    });
  });

  group('yearly', () {
    test(
      'Feb 29 falls on Feb 28 in common years and returns in leap years',
      () {
        final r = Recurrence(
          unit: RecurrenceUnit.year,
          interval: 1,
          start: d(2024, 2, 29),
        );
        expect(r.occurrence(1), d(2025, 2, 28));
        expect(r.occurrence(3), d(2027, 2, 28));
        expect(r.occurrence(4), d(2028, 2, 29));
      },
    );

    test('every 2 years', () {
      final r = Recurrence(
        unit: RecurrenceUnit.year,
        interval: 2,
        start: d(2026, 10, 25),
      );
      expect(r.occurrence(1), d(2028, 10, 25));
    });
  });

  group('days and weeks', () {
    test('weekly stays on the same weekday', () {
      final r = Recurrence(
        unit: RecurrenceUnit.week,
        interval: 1,
        start: d(2026, 10, 23),
      );
      expect(r.occurrence(1), d(2026, 10, 30));
      expect(r.occurrence(2), d(2026, 11, 6));
      expect(r.occurrence(2)!.weekday, d(2026, 10, 23).weekday);
    });

    test('every 2 weeks and every 10 days', () {
      final w = Recurrence(
        unit: RecurrenceUnit.week,
        interval: 2,
        start: d(2026, 12, 25),
      );
      expect(w.occurrence(1), d(2027, 1, 8));
      final day = Recurrence(
        unit: RecurrenceUnit.day,
        interval: 10,
        start: d(2026, 2, 25),
      );
      expect(day.occurrence(1), d(2026, 3, 7));
    });

    test('stepping over daylight saving never moves the date', () {
      // US clocks change on 2026-03-08 and 2026-11-01.
      final r = Recurrence(
        unit: RecurrenceUnit.day,
        interval: 1,
        start: d(2026, 3, 6),
      );
      expect(
        [for (var k = 0; k < 4; k++) r.occurrence(k)],
        [d(2026, 3, 6), d(2026, 3, 7), d(2026, 3, 8), d(2026, 3, 9)],
      );
      for (var k = 0; k < 400; k++) {
        final date = r.occurrence(k)!;
        expect((date.hour, date.minute), (0, 0));
      }
    });
  });

  group('end date and due occurrences', () {
    test('the end date itself is included, later ones are not', () {
      final r = monthly(d(2026, 1, 1), end: d(2026, 3, 1));
      expect(r.occurrence(2), d(2026, 3, 1));
      expect(r.occurrence(3), isNull);
    });

    test('an end date between occurrences stops before the next one', () {
      final r = monthly(d(2026, 1, 1), end: d(2026, 3, 31));
      expect(r.occurrence(2), d(2026, 3, 1));
      expect(r.occurrence(3), isNull);
    });

    test('dueThrough returns everything up to and including today', () {
      final r = monthly(d(2026, 1, 1));
      final due = r.dueThrough(d(2026, 3, 1));
      expect(due.map((e) => e.$1), [0, 1, 2]);
      expect(due.last.$2, d(2026, 3, 1));
    });

    test('dueThrough starts from the given index', () {
      final r = monthly(d(2026, 1, 1));
      final due = r.dueThrough(d(2026, 5, 20), fromIndex: 3);
      expect(due.map((e) => e.$1), [3, 4]);
    });

    test('nothing is due before the start or after the end', () {
      final r = monthly(d(2026, 6, 1), end: d(2026, 7, 1));
      expect(r.dueThrough(d(2026, 5, 31)), isEmpty);
      expect(r.dueThrough(d(2030, 1, 1), fromIndex: 2), isEmpty);
    });

    test('a daily rule from long ago is cut off at the limit', () {
      final r = Recurrence(
        unit: RecurrenceUnit.day,
        interval: 1,
        start: d(2020, 1, 1),
      );
      final due = r.dueThrough(d(2026, 1, 1));
      expect(due, hasLength(maxCatchUpPerRule));
      expect(due.first.$1, 0);
      expect(due.last.$1, maxCatchUpPerRule - 1);
    });

    test('the time of day on today is ignored', () {
      final r = monthly(d(2026, 1, 1));
      expect(r.dueThrough(DateTime(2026, 2, 1, 23, 59)).length, 2);
    });
  });

  group('validation', () {
    test('rejects an interval outside 1 to 365', () {
      for (final bad in [0, -1, 366]) {
        expect(
          () => Recurrence(
            unit: RecurrenceUnit.day,
            interval: bad,
            start: d(2026, 1, 1),
          ),
          throwsRangeError,
        );
      }
      expect(
        Recurrence(
          unit: RecurrenceUnit.day,
          interval: 365,
          start: d(2026, 1, 1),
        ).occurrence(1),
        d(2027, 1, 1),
      );
    });
  });

  group('scheduleText', () {
    test('plain-language descriptions', () {
      expect(monthly(d(2026, 11, 1)).scheduleText, 'Monthly on the 1st');
      expect(monthly(d(2026, 11, 2)).scheduleText, 'Monthly on the 2nd');
      expect(monthly(d(2026, 11, 3)).scheduleText, 'Monthly on the 3rd');
      expect(monthly(d(2026, 11, 11)).scheduleText, 'Monthly on the 11th');
      expect(monthly(d(2026, 11, 22)).scheduleText, 'Monthly on the 22nd');
      expect(
        monthly(d(2026, 11, 3), every: 3).scheduleText,
        'Every 3 months on the 3rd',
      );
      expect(
        monthly(d(2026, 1, 31)).scheduleText,
        'Monthly on the 31st (or the last day)',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.week,
          interval: 1,
          start: d(2026, 10, 23),
        ).scheduleText,
        'Weekly on Friday',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.week,
          interval: 2,
          start: d(2026, 10, 23),
        ).scheduleText,
        'Every 2 weeks on Friday',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.day,
          interval: 1,
          start: d(2026, 1, 1),
        ).scheduleText,
        'Daily',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.day,
          interval: 10,
          start: d(2026, 1, 1),
        ).scheduleText,
        'Every 10 days',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.year,
          interval: 1,
          start: d(2026, 10, 25),
        ).scheduleText,
        'Yearly on Oct 25',
      );
      expect(
        Recurrence(
          unit: RecurrenceUnit.year,
          interval: 1,
          start: d(2024, 2, 29),
        ).scheduleText,
        'Yearly on Feb 29 (Feb 28 in other years)',
      );
    });
  });
}
