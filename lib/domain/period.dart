// PURE DART: no Flutter imports.
import 'date_range.dart';
import 'iso_date.dart';
import 'week_mode.dart';

/// What the user picked on the period selector.
sealed class Period {
  const Period();
}

/// The week containing [anchor] (the anchor moves when the user steps ‹ ›).
final class ThisWeek extends Period {
  ThisWeek(DateTime anchor) : anchor = dateOnly(anchor);
  final DateTime anchor;
}

/// The month containing [anchor].
final class ThisMonth extends Period {
  ThisMonth(DateTime anchor) : anchor = dateOnly(anchor);
  final DateTime anchor;
}

/// Week [n] (1-based) of a given month.
final class WeekOfMonth extends Period {
  const WeekOfMonth(this.year, this.month, this.n);
  final int year;
  final int month;
  final int n;
}

/// A custom range picked with the date range picker.
final class Custom extends Period {
  Custom(DateTime start, DateTime end) : range = custom(start, end);
  final DateRange range;
}

/// Turns a [Period] into concrete dates using the week settings.
DateRange resolvePeriod(Period period, WeekMode mode, int weekStartDay) {
  return switch (period) {
    ThisWeek(:final anchor) => thisWeek(anchor, mode, weekStartDay),
    ThisMonth(:final anchor) => thisMonth(anchor),
    WeekOfMonth(:final year, :final month, :final n) => weekOfMonth(
      year,
      month,
      n,
      mode,
      weekStartDay,
    ),
    Custom(:final range) => range,
  };
}

/// Moves a period one step back (-1) or forward (+1).
/// Custom ranges cannot be stepped and are returned unchanged.
Period stepPeriod(Period period, int delta, WeekMode mode, int weekStartDay) {
  switch (period) {
    case ThisWeek(:final anchor):
      return ThisWeek(shiftWeek(anchor, delta, mode, weekStartDay));
    case ThisMonth(:final anchor):
      return ThisMonth(shiftMonth(anchor, delta));
    case WeekOfMonth(:final year, :final month, :final n):
      final target = shiftMonth(DateTime(year, month, 1), delta);
      return clampPeriod(
        WeekOfMonth(target.year, target.month, n),
        mode,
        weekStartDay,
      );
    case Custom():
      return period;
  }
}

/// Keeps a [WeekOfMonth] valid after the month or the week settings change
/// (e.g. Week 6 becomes Week 5 in a month that only has 5 weeks).
Period clampPeriod(Period period, WeekMode mode, int weekStartDay) {
  if (period is! WeekOfMonth) return period;
  final weeks = weeksInMonth(period.year, period.month, mode, weekStartDay);
  final n = period.n.clamp(1, weeks);
  return n == period.n ? period : WeekOfMonth(period.year, period.month, n);
}
