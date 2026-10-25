// PURE DART: no Flutter imports. ALL week/month boundary math lives here.
import 'iso_date.dart';
import 'week_mode.dart';

/// A span of whole days. [start] and [end] are both inclusive, date-only.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Counted in UTC so a daylight-saving change inside the range can't
  /// shave a day off (local `difference` would be 23 hours short).
  int get lengthInDays =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange(${toIsoDate(start)} .. ${toIsoDate(end)})';
}

/// Number of days in the given month (handles leap years).
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The first to the last day of a month.
DateRange monthOf(int year, int month) {
  // DateTime normalises overflow, so month 13 is January of next year.
  final first = DateTime(year, month, 1);
  return DateRange(first, DateTime(first.year, first.month + 1, 0));
}

/// The month that contains [today].
DateRange thisMonth(DateTime today) => monthOf(today.year, today.month);

/// The week that contains [today].
///
/// Calendar mode: the full 7-day week starting on [weekStartDay]. It is NOT
/// clipped to the month, so it can cross a month boundary.
/// Fixed mode: the 7-day block (within today's month) that contains today.
DateRange thisWeek(DateTime today, WeekMode mode, int weekStartDay) {
  final day = dateOnly(today);
  if (mode == WeekMode.fixed) {
    final n = (day.day - 1) ~/ 7 + 1;
    return weekOfMonth(day.year, day.month, n, mode, weekStartDay);
  }
  final daysSinceStart = (day.weekday - weekStartDay + 7) % 7;
  final start = DateTime(day.year, day.month, day.day - daysSinceStart);
  return DateRange(start, DateTime(start.year, start.month, start.day + 6));
}

/// Length of Week 1 in calendar mode: from the 1st up to the day before
/// [weekStartDay]. Always 1 to 7 days.
int _calendarFirstWeekLength(int year, int month, int weekStartDay) {
  final firstWeekday = DateTime(year, month, 1).weekday;
  final dayBeforeStart = weekStartDay == 1 ? 7 : weekStartDay - 1;
  return (dayBeforeStart - firstWeekday + 7) % 7 + 1;
}

/// How many week chips the month has: 4-5 in fixed mode, 4-6 in calendar mode.
int weeksInMonth(int year, int month, WeekMode mode, int weekStartDay) {
  final days = daysInMonth(year, month);
  if (mode == WeekMode.fixed) return (days + 6) ~/ 7;
  final firstLength = _calendarFirstWeekLength(year, month, weekStartDay);
  final remaining = days - firstLength;
  return 1 + (remaining + 6) ~/ 7;
}

/// Week [n] (1-based) of a month, always clipped to that month.
/// Throws [RangeError] if [n] is outside 1..weeksInMonth.
DateRange weekOfMonth(
  int year,
  int month,
  int n,
  WeekMode mode,
  int weekStartDay,
) {
  final weeks = weeksInMonth(year, month, mode, weekStartDay);
  if (n < 1 || n > weeks) {
    throw RangeError.range(n, 1, weeks, 'n', 'Week out of range for month');
  }
  final days = daysInMonth(year, month);

  final int startDay;
  final int endDay;
  if (mode == WeekMode.fixed) {
    startDay = 1 + (n - 1) * 7;
    endDay = startDay + 6;
  } else if (n == 1) {
    startDay = 1;
    endDay = _calendarFirstWeekLength(year, month, weekStartDay);
  } else {
    final firstLength = _calendarFirstWeekLength(year, month, weekStartDay);
    startDay = firstLength + 1 + (n - 2) * 7;
    endDay = startDay + 6;
  }

  return DateRange(
    DateTime(year, month, startDay),
    DateTime(year, month, endDay > days ? days : endDay),
  );
}

/// A user-picked range. Swaps the ends if they are the wrong way round.
DateRange custom(DateTime start, DateTime end) {
  final a = dateOnly(start);
  final b = dateOnly(end);
  return a.isAfter(b) ? DateRange(b, a) : DateRange(a, b);
}

/// A date inside the week before/after the one containing [anchor].
/// [delta] is -1 (previous) or +1 (next).
DateTime shiftWeek(
  DateTime anchor,
  int delta,
  WeekMode mode,
  int weekStartDay,
) {
  final week = thisWeek(anchor, mode, weekStartDay);
  final edge = delta < 0 ? week.start : week.end;
  return DateTime(edge.year, edge.month, edge.day + (delta < 0 ? -1 : 1));
}

/// The 1st of the month that is [delta] months away from [anchor].
DateTime shiftMonth(DateTime anchor, int delta) =>
    DateTime(anchor.year, anchor.month + delta, 1);
