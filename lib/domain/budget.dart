// PURE DART: no Flutter imports. Budget months, limits and how a budget is doing.
import 'date_range.dart';
import 'iso_date.dart';
import 'recurrence.dart';

/// Longest day of the month a budget month may start on (1 to this).
const maxBudgetStartDay = 28;

/// A budget month, named after the month it **begins** in: with a start day
/// of 25, "October" runs Oct 25 to Nov 24, so on Oct 10 you are still in
/// "September". With the default start day of 1 it is the calendar month.
class BudgetMonth implements Comparable<BudgetMonth> {
  const BudgetMonth(this.year, this.month);

  /// Reads `2026-10`.
  factory BudgetMonth.parse(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key);
    if (m == null) throw FormatException('Not a budget month', key);
    final month = int.parse(m[2]!);
    if (month < 1 || month > 12) {
      throw FormatException('Not a budget month', key);
    }
    return BudgetMonth(int.parse(m[1]!), month);
  }

  /// The budget month that [date] falls in.
  factory BudgetMonth.containing(DateTime date, int startDay) {
    _checkStartDay(startDay);
    final day = dateOnly(date);
    if (day.day >= startDay) return BudgetMonth(day.year, day.month);
    final previous = DateTime(day.year, day.month - 1);
    return BudgetMonth(previous.year, previous.month);
  }

  final int year;

  /// 1 to 12.
  final int month;

  /// `2026-10`: sorts in time order, and is what the database stores.
  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}';

  /// This month moved by [months] (negative for earlier).
  BudgetMonth shift(int months) {
    final moved = DateTime(year, month + months);
    return BudgetMonth(moved.year, moved.month);
  }

  /// The first and last day, inclusive. With start day 1 this is the
  /// calendar month; otherwise it runs to the day before the next start.
  DateRange range(int startDay) {
    _checkStartDay(startDay);
    final start = DateTime(year, month, startDay);
    final end = DateTime(year, month + 1, startDay - 1);
    return DateRange(start, end);
  }

  @override
  int compareTo(BudgetMonth other) => key.compareTo(other.key);

  bool operator <(BudgetMonth other) => compareTo(other) < 0;
  bool operator <=(BudgetMonth other) => compareTo(other) <= 0;
  bool operator >(BudgetMonth other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is BudgetMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'BudgetMonth($key)';
}

void _checkStartDay(int startDay) {
  RangeError.checkValueInInterval(startDay, 1, maxBudgetStartDay, 'startDay');
}

/// The longest custom budget period in days, and in months.
const maxBudgetDays = 365;
const maxBudgetMonths = 60;

/// How long one budget period is: a number of budget months (which follow
/// the budget-month start day), or a fixed number of days counted from the
/// entry's first day.
class BudgetUnit {
  /// A period of [days] days (1 to [maxBudgetDays]).
  const BudgetUnit.days(this.days) : months = 0;

  /// A period of [months] budget months (1 to [maxBudgetMonths]).
  const BudgetUnit.months(this.months) : days = 0;

  static const week = BudgetUnit.days(7);
  static const fortnight = BudgetUnit.days(14);
  static const month = BudgetUnit.months(1);
  static const quarter = BudgetUnit.months(3);
  static const year = BudgetUnit.months(12);

  /// Days in a period; 0 when the period is counted in months.
  final int days;

  /// Budget months in a period; 0 when the period is counted in days.
  final int months;

  /// A single budget month ("Monthly").
  bool get isMonth => months == 1;

  /// Counted in months (one or more) rather than days.
  bool get inMonths => months > 0;

  /// "Monthly", "Quarterly", "Yearly", "Weekly", "Every 2 weeks", "Every 10
  /// days", "Every 4 months".
  String get label {
    if (inMonths) {
      if (months == 1) return 'Monthly';
      if (months == 3) return 'Quarterly';
      if (months == 12) return 'Yearly';
      if (months % 12 == 0) return 'Every ${months ~/ 12} years';
      return 'Every $months months';
    }
    if (days == 1) return 'Daily';
    if (days == 7) return 'Weekly';
    if (days % 7 == 0) return 'Every ${days ~/ 7} weeks';
    return 'Every $days days';
  }

  /// "month", "year", "2 weeks", "10 days": for sentences like "every 2 weeks".
  String get noun {
    if (inMonths) {
      if (months == 1) return 'month';
      if (months == 12) return 'year';
      if (months % 12 == 0) return '${months ~/ 12} years';
      return '$months months';
    }
    if (days == 1) return 'day';
    if (days == 7) return 'week';
    if (days % 7 == 0) return '${days ~/ 7} weeks';
    return '$days days';
  }

  /// "months", "weeks", "10-day periods": for "the last 3 ...".
  String get plural {
    if (inMonths) return months == 1 ? 'months' : '$months-month periods';
    if (days == 1) return 'days';
    if (days == 7) return 'weeks';
    return '$days-day periods';
  }

  @override
  bool operator ==(Object other) =>
      other is BudgetUnit && other.days == days && other.months == months;

  @override
  int get hashCode => Object.hash(days, months);

  @override
  String toString() => 'BudgetUnit(days: $days, months: $months)';
}

/// The first day of the week (starting on [weekStartDay], 1 = Monday to 7 =
/// Sunday) that contains [date].
DateTime weekStartOf(DateTime date, int weekStartDay) {
  final day = dateOnly(date);
  final back = (day.weekday - weekStartDay + 7) % 7;
  return DateTime(day.year, day.month, day.day - back);
}

DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// [count] budget months from [first], as one range.
DateRange _monthsRange(BudgetMonth first, int count, int startDay) => DateRange(
  first.range(startDay).start,
  first.shift(count - 1).range(startDay).end,
);

/// The period of [unit] that contains [date], for a budget that has not
/// been created yet (or has no anchor). Months start with the budget month
/// for [monthStartDay] that holds [date], or the one that holds [anchor] (so a
/// quarter can start in a month already under way). A run of days counts from
/// [anchor];
/// without one it counts from the start of the week (starting on
/// [weekStartDay]) when the length is whole weeks, and from [date] itself
/// otherwise.
DateRange currentRangeFor(
  BudgetUnit unit,
  DateTime date, {
  required int monthStartDay,
  required int weekStartDay,
  DateTime? anchor,
}) {
  if (unit.inMonths) {
    return _monthsRange(
      BudgetMonth.containing(anchor ?? date, monthStartDay),
      unit.months,
      monthStartDay,
    );
  }
  final day = dateOnly(date);
  final from = anchor != null
      ? dateOnly(anchor)
      : unit.days % 7 == 0
      ? weekStartOf(day, weekStartDay)
      : day;
  final n = _floorDiv(_daysBetween(from, day), unit.days);
  final start = _addDays(from, n * unit.days);
  return DateRange(start, _addDays(start, unit.days - 1));
}

int _floorDiv(int a, int b) => (a / b).floor();

/// The period just before [range].
DateRange previousRange(DateRange range, BudgetUnit unit, int monthStartDay) {
  if (unit.inMonths) {
    return _monthsRange(
      BudgetMonth.containing(range.start, monthStartDay).shift(-unit.months),
      unit.months,
      monthStartDay,
    );
  }
  final start = _addDays(range.start, -unit.days);
  return DateRange(start, _addDays(start, unit.days - 1));
}

/// The period just after [range].
DateRange nextRange(DateRange range, BudgetUnit unit, int monthStartDay) {
  if (unit.inMonths) {
    return _monthsRange(
      BudgetMonth.containing(range.start, monthStartDay).shift(unit.months),
      unit.months,
      monthStartDay,
    );
  }
  final start = _addDays(range.start, unit.days);
  return DateRange(start, _addDays(start, unit.days - 1));
}

/// One stored limit. From [start] (the first day of its first period) the
/// limit for [categoryId] (null = all spending) is [amountCents], repeating
/// every [unit] or, when [repeats] is false, for that one period only. A
/// null amount means "no budget from here". A later entry replaces it.
class LimitEntry {
  const LimitEntry({
    required this.categoryId,
    required this.unit,
    required this.repeats,
    required this.start,
    required this.amountCents,
  });

  final int? categoryId;
  final BudgetUnit unit;
  final bool repeats;
  final DateTime start;
  final int? amountCents;

  /// The period of this entry that contains [date]. A run of days counts
  /// from [start]; months count budget months from the one that holds
  /// [start], in blocks of [BudgetUnit.months].
  DateRange rangeAt(DateTime date, int monthStartDay) {
    if (unit.inMonths) {
      final from = BudgetMonth.containing(start, monthStartDay);
      final at = BudgetMonth.containing(date, monthStartDay);
      final gap = (at.year - from.year) * 12 + (at.month - from.month);
      final first = from.shift(_floorDiv(gap, unit.months) * unit.months);
      return _monthsRange(first, unit.months, monthStartDay);
    }
    final n = _floorDiv(_daysBetween(start, dateOnly(date)), unit.days);
    final first = _addDays(start, n * unit.days);
    return DateRange(first, _addDays(first, unit.days - 1));
  }

  /// This entry's first period.
  DateRange firstRange(int monthStartDay) => rangeAt(start, monthStartDay);
}

/// A budget in force on some date: the entry, the period it is in, and the limit.
class ResolvedBudget {
  const ResolvedBudget({
    required this.entry,
    required this.range,
    required this.limit,
  });

  final LimitEntry entry;
  final DateRange range;
  final int limit;
}

/// The budget for [categoryId] (null = all spending) in force on [date]: the
/// latest entry that starts on or before it. Null when there is none, when
/// that entry says "no budget", or when it was one-time and its period is over.
ResolvedBudget? resolveBudget(
  Iterable<LimitEntry> entries,
  int? categoryId,
  DateTime date, {
  required int monthStartDay,
}) {
  final day = dateOnly(date);
  LimitEntry? best;
  for (final entry in entries) {
    if (entry.categoryId != categoryId || entry.start.isAfter(day)) continue;
    if (best == null || !entry.start.isBefore(best.start)) best = entry;
  }
  final amount = best?.amountCents;
  if (best == null || amount == null) return null;
  final range = best.rangeAt(day, monthStartDay);
  if (!best.repeats && range != best.firstRange(monthStartDay)) return null;
  return ResolvedBudget(entry: best, range: range, limit: amount);
}

/// A finished budget period.
class PastPeriod {
  const PastPeriod({
    required this.entry,
    required this.range,
    required this.limit,
    this.endedEarly = false,
  });

  final LimitEntry entry;

  /// Its days. Shorter than the period when [endedEarly].
  final DateRange range;
  final int limit;

  /// A later change (or stopping the budget) cut this period short, so
  /// [range] ends the day before that change.
  final bool endedEarly;
}

/// The finished periods of one budget's [entries] (all for the same
/// category, or all for all spending), newest first, at most [limit].
/// Each period shows the amount in force then: a later change never rewrites
/// it. A period that a later change cut short is listed up to that change.
List<PastPeriod> pastPeriods(
  Iterable<LimitEntry> entries,
  DateTime today, {
  required int monthStartDay,
  int limit = 12,
}) {
  final day = dateOnly(today);
  final rows = entries.toList()..sort((a, b) => a.start.compareTo(b.start));
  final out = <PastPeriod>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final amount = row.amountCents;
    if (amount == null) continue; // stopped
    final nextStart = i + 1 < rows.length ? rows[i + 1].start : null;
    var range = row.firstRange(monthStartDay);
    // A period belongs to this row if it starts before the next row does. One
    // that the next row cuts short is listed up to the day before it.
    while (nextStart == null || range.start.isBefore(nextStart)) {
      final cutShort = nextStart != null && !range.end.isBefore(nextStart);
      final end = cutShort ? _addDays(nextStart, -1) : range.end;
      if (!end.isBefore(day)) break; // not finished yet
      out.add(
        PastPeriod(
          entry: row,
          range: DateRange(range.start, end),
          limit: amount,
          endedEarly: cutShort,
        ),
      );
      if (!row.repeats) break;
      range = nextRange(range, row.unit, monthStartDay);
    }
  }
  out.sort((a, b) => b.range.start.compareTo(a.range.start));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// How often a budget has run over lately, and by how much when it did.
class OverrunHint {
  const OverrunHint({
    required this.over,
    required this.of,
    required this.averageOverCents,
  });

  /// Periods that ended over the limit, out of [of] looked at.
  final int over;
  final int of;

  /// The average overshoot in the periods that ran over, in cents.
  final int averageOverCents;
}

/// Says something only when a budget usually runs over: [periods] (newest
/// first, finished and full length) must number at least [minPeriods], and at
/// least two of the last [lookBack] must have ended over, and at least half.
/// A budget that went over once is not "usually" over.
OverrunHint? overrunHint(
  List<({int limit, int spent})> periods, {
  int lookBack = 6,
  int minPeriods = 3,
}) {
  final recent = periods.take(lookBack).toList();
  if (recent.length < minPeriods) return null;
  final overs = [
    for (final p in recent)
      if (p.spent > p.limit) p.spent - p.limit,
  ];
  if (overs.length < 2 || overs.length * 2 < recent.length) return null;
  final total = overs.fold<int>(0, (a, b) => a + b);
  return OverrunHint(
    over: overs.length,
    of: recent.length,
    averageOverCents: (total + overs.length ~/ 2) ~/ overs.length,
  );
}

enum BudgetLevel { ok, almost, over }

/// Spending at or above this share of the limit is "almost".
const almostPercent = 80;

/// How one budget is doing in one budget month.
class BudgetStatus {
  const BudgetStatus({
    required this.limit,
    required this.spent,
    required this.planned,
    required this.daysLeft,
    required this.hasStarted,
    required this.hasEnded,
  });

  final int limit;

  /// Expenses dated in the month, future-dated ones included (like the
  /// totals on Home).
  final int spent;

  /// Repeating expenses still due this month, not counted in [spent].
  final int planned;

  /// Days from today to the end of the month, today included; the whole
  /// month's length before it starts; 0 once it has ended.
  final int daysLeft;
  final bool hasStarted;
  final bool hasEnded;

  /// What is left; negative once over.
  int get left => limit - spent;

  bool get isOver => spent > limit;

  /// Over by this much (0 when not over).
  int get overBy => isOver ? spent - limit : 0;

  /// Share of the limit used, in tenths of a percent, never above 1000.
  int get permille =>
      limit <= 0 ? 1000 : (spent * 1000 ~/ limit).clamp(0, 1000);

  BudgetLevel get level {
    if (isOver) return BudgetLevel.over;
    if (spent * 100 >= limit * almostPercent) return BudgetLevel.almost;
    return BudgetLevel.ok;
  }

  /// Planned repeating expenses would take it over, though it is not over now.
  bool get plannedWouldExceed => !isOver && spent + planned > limit;

  /// How far over it would be once the planned expenses are added.
  int get plannedOverBy =>
      spent + planned > limit ? spent + planned - limit : 0;

  /// About how much can be spent per remaining day, or null when the month
  /// is over, nothing is left, or no day remains.
  int? get perDay {
    if (hasEnded || daysLeft <= 0 || left <= 0) return null;
    return left ~/ daysLeft;
  }
}

/// The status for a [limit] given what was [spent] and [planned] inside
/// [range], seen from [today].
BudgetStatus buildBudgetStatus({
  required int limit,
  required int spent,
  required DateRange range,
  required DateTime today,
  int planned = 0,
}) {
  final day = dateOnly(today);
  final started = !day.isBefore(range.start);
  final ended = day.isAfter(range.end);
  final daysLeft = ended
      ? 0
      : !started
      ? range.lengthInDays
      : DateRange(day, range.end).lengthInDays;
  return BudgetStatus(
    limit: limit,
    spent: spent,
    planned: ended ? 0 : planned,
    daysLeft: daysLeft,
    hasStarted: started,
    hasEnded: ended,
  );
}

/// A repeating expense, reduced to what the budget needs.
class PlannedRule {
  const PlannedRule({
    required this.categoryId,
    required this.amountCents,
    required this.recurrence,
    required this.nextIndex,
  });

  final int categoryId;
  final int amountCents;
  final Recurrence recurrence;
  final int nextIndex;
}

/// How much each category still has coming from repeating expenses inside
/// [range]: occurrences after [today] and no later than the range's end.
Map<int, int> plannedByCategory(
  Iterable<PlannedRule> rules,
  DateRange range,
  DateTime today,
) {
  final day = dateOnly(today);
  final totals = <int, int>{};
  for (final rule in rules) {
    // The schedule is checked from the next occurrence, with a cap so a daily
    // rule and a far-away month cannot loop for long.
    for (var k = rule.nextIndex, steps = 0; steps < 1000; k++, steps++) {
      final date = rule.recurrence.occurrence(k);
      if (date == null || date.isAfter(range.end)) break;
      if (date.isAfter(day) && !date.isBefore(range.start)) {
        totals[rule.categoryId] =
            (totals[rule.categoryId] ?? 0) + rule.amountCents;
      }
    }
  }
  return totals;
}

/// A suggested limit from the spending of previous months: their average,
/// rounded to a whole currency unit (never to zero when anything was
/// spent). Null when nothing was spent in any of them.
int? suggestLimit(List<int> monthlySpends) {
  if (monthlySpends.isEmpty) return null;
  final total = monthlySpends.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return null;
  final average = (total + monthlySpends.length ~/ 2) ~/ monthlySpends.length;
  final rounded = ((average + 50) ~/ 100) * 100;
  return rounded == 0 ? 100 : rounded;
}
