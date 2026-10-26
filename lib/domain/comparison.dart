// PURE DART: no Flutter imports. How "vs last month" picks what to compare.
import 'date_range.dart';
import 'iso_date.dart';
import 'period.dart';
import 'week_mode.dart';

/// What kind of period is being compared (decides how it is worded).
enum ComparisonKind { month, week, weekOfMonth, custom }

/// The two windows to compare: the selected period (up to today while it is
/// still going) and the matching window just before it.
class Comparison {
  const Comparison({
    required this.current,
    required this.previous,
    required this.paceMatched,
    required this.kind,
  });

  /// The current side. While the period is in progress this stops at today.
  final DateRange current;

  /// The earlier side: the same number of days from the start of the
  /// previous period (fewer if that period was shorter).
  final DateRange previous;

  /// True when the period is still going, so both sides were cut to the same
  /// elapsed days (Oct 1 to 25 against Sep 1 to 25, not all of September).
  final bool paceMatched;

  final ComparisonKind kind;
}

/// The whole period before [period]: the previous month or week, the same
/// week number of the previous month, or for a custom range the window of the
/// same length right before it.
DateRange previousPeriodRange(
  Period period,
  DateRange range,
  WeekMode mode,
  int weekStartDay,
) {
  if (period is Custom) {
    final days = range.lengthInDays;
    final end = DateTime(
      range.start.year,
      range.start.month,
      range.start.day - 1,
    );
    final start = DateTime(end.year, end.month, end.day - (days - 1));
    return DateRange(start, end);
  }
  final safe = clampPeriod(period, mode, weekStartDay);
  return resolvePeriod(
    stepPeriod(safe, -1, mode, weekStartDay),
    mode,
    weekStartDay,
  );
}

/// What to compare for [period] (whose dates are [range]) on [today], or null
/// when the period has not started yet.
Comparison? buildComparison({
  required Period period,
  required DateRange range,
  required DateTime today,
  required WeekMode mode,
  required int weekStartDay,
}) {
  final day = dateOnly(today);
  if (day.isBefore(range.start)) return null;

  final kind = switch (period) {
    ThisMonth() => ComparisonKind.month,
    ThisWeek() => ComparisonKind.week,
    WeekOfMonth() => ComparisonKind.weekOfMonth,
    Custom() => ComparisonKind.custom,
  };
  final before = previousPeriodRange(period, range, mode, weekStartDay);

  // A finished period (or its last day) compares whole against whole.
  if (!day.isBefore(range.end)) {
    return Comparison(
      current: range,
      previous: before,
      paceMatched: false,
      kind: kind,
    );
  }

  // Still going: only the days that have passed, against the same days.
  final elapsed = DateRange(range.start, day).lengthInDays;
  final sameDay = DateTime(
    before.start.year,
    before.start.month,
    before.start.day + elapsed - 1,
  );
  return Comparison(
    current: DateRange(range.start, day),
    previous: DateRange(
      before.start,
      sameDay.isAfter(before.end) ? before.end : sameDay,
    ),
    paceMatched: true,
    kind: kind,
  );
}

enum DeltaDirection { up, down, same }

/// How one total changed from the earlier window to the current one.
class Delta {
  const Delta({
    required this.direction,
    required this.cents,
    this.percent,
    this.capped = false,
  });

  final DeltaDirection direction;

  /// The size of the change in cents, never negative.
  final int cents;

  /// Whole percent of the earlier total; null when the earlier total was
  /// zero (a percentage of nothing means nothing).
  final int? percent;

  /// True when the real percentage is above [maxPercent].
  final bool capped;

  static const maxPercent = 999;

  /// A rise from nothing.
  bool get fromNothing => percent == null;
}

/// Compares two totals in cents. Null when both are zero (nothing to say).
Delta? compareTotals({required int current, required int previous}) {
  if (current == 0 && previous == 0) return null;
  final diff = current - previous;
  if (previous == 0) {
    return Delta(direction: DeltaDirection.up, cents: diff);
  }
  if (diff == 0) {
    return const Delta(direction: DeltaDirection.same, cents: 0, percent: 0);
  }
  // Rounded to the nearest whole percent, in integers.
  final raw = (diff.abs() * 100 + previous ~/ 2) ~/ previous;
  if (raw == 0) {
    return Delta(direction: DeltaDirection.same, cents: diff.abs(), percent: 0);
  }
  return Delta(
    direction: diff > 0 ? DeltaDirection.up : DeltaDirection.down,
    cents: diff.abs(),
    percent: raw > Delta.maxPercent ? Delta.maxPercent : raw,
    capped: raw > Delta.maxPercent,
  );
}
