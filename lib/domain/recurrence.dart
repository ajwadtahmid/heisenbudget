// PURE DART: no Flutter imports. All "repeats every..." date maths lives here.
import 'date_range.dart';
import 'iso_date.dart';

/// What a repeat interval counts in.
enum RecurrenceUnit { day, week, month, year }

/// Longest "every N units" a rule may use.
const maxRecurrenceInterval = 365;

/// Whether occurrence number [index] of a rule that repeats every [interval]
/// [unit]s still lands on a date a [DateTime] can hold (a hand-edited backup
/// could otherwise name a position thousands of years away).
bool scheduleIndexInRange(RecurrenceUnit unit, int interval, int index) {
  if (index < 0 || interval < 1) return false;
  final steps = index * interval;
  return switch (unit) {
    RecurrenceUnit.day => steps <= 3000000,
    RecurrenceUnit.week => steps * 7 <= 3000000,
    RecurrenceUnit.month => steps <= 96000,
    RecurrenceUnit.year => steps <= 8000,
  };
}

/// Most occurrences one catch-up adds for a single rule, so a rule that
/// starts years ago cannot flood the ledger in one go.
const maxCatchUpPerRule = 500;

/// When a repeating transaction happens: every [interval] [unit]s starting on
/// [start], up to and including [end] (null = forever).
///
/// Occurrence number `k` is always worked out from [start], never from the
/// previous occurrence. A monthly rule on the 31st therefore goes Jan 31,
/// Feb 28 (or 29), Mar 31, and does not slip to the 28th for good.
class Recurrence {
  Recurrence({
    required this.unit,
    required this.interval,
    required DateTime start,
    DateTime? end,
  }) : start = dateOnly(start),
       end = end == null ? null : dateOnly(end) {
    RangeError.checkValueInInterval(
      interval,
      1,
      maxRecurrenceInterval,
      'interval',
    );
  }

  final RecurrenceUnit unit;
  final int interval;
  final DateTime start;
  final DateTime? end;

  /// The date of occurrence [k] (0 = the start date), ignoring [end].
  DateTime rawOccurrence(int k) {
    final steps = k * interval;
    switch (unit) {
      case RecurrenceUnit.day:
        // DateTime(y, m, d + n) counts calendar days, so a daylight-saving
        // change cannot move the result by an hour or a day.
        return DateTime(start.year, start.month, start.day + steps);
      case RecurrenceUnit.week:
        return DateTime(start.year, start.month, start.day + 7 * steps);
      case RecurrenceUnit.month:
        final index = start.year * 12 + (start.month - 1) + steps;
        return _clamped(index ~/ 12, index % 12 + 1);
      case RecurrenceUnit.year:
        return _clamped(start.year + steps, start.month);
    }
  }

  /// [start]'s day of the month, or the month's last day when it is shorter
  /// (the 31st in April, Feb 29 in a common year).
  DateTime _clamped(int year, int month) {
    final last = daysInMonth(year, month);
    return DateTime(year, month, start.day > last ? last : start.day);
  }

  /// The date of occurrence [k], or null when it falls after [end].
  DateTime? occurrence(int k) {
    final date = rawOccurrence(k);
    final stop = end;
    return stop != null && date.isAfter(stop) ? null : date;
  }

  /// The occurrences from number [fromIndex] up to and including [today],
  /// at most [limit] of them. `(index, date)` pairs, oldest first.
  List<(int, DateTime)> dueThrough(
    DateTime today, {
    int fromIndex = 0,
    int limit = maxCatchUpPerRule,
  }) {
    final day = dateOnly(today);
    final due = <(int, DateTime)>[];
    for (var k = fromIndex; due.length < limit; k++) {
      final date = occurrence(k);
      if (date == null || date.isAfter(day)) break;
      due.add((k, date));
    }
    return due;
  }

  /// A short, human description: "Monthly on the 1st".
  String get scheduleText {
    final every = interval == 1;
    switch (unit) {
      case RecurrenceUnit.day:
        return every ? 'Daily' : 'Every $interval days';
      case RecurrenceUnit.week:
        final day = _weekdays[start.weekday - 1];
        return every ? 'Weekly on $day' : 'Every $interval weeks on $day';
      case RecurrenceUnit.month:
        final day = _ordinal(start.day);
        final tail = start.day > 28 ? ' (or the last day)' : '';
        return every
            ? 'Monthly on the $day$tail'
            : 'Every $interval months on the $day$tail';
      case RecurrenceUnit.year:
        final on = '${_months[start.month - 1]} ${start.day}';
        final tail = start.month == 2 && start.day == 29
            ? ' (Feb 28 in other years)'
            : '';
        return every
            ? 'Yearly on $on$tail'
            : 'Every $interval years on $on$tail';
    }
  }
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 1 -> "1st", 2 -> "2nd", 11 -> "11th", 22 -> "22nd".
String _ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}
