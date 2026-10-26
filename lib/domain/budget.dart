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

/// How long one budget period is.
enum BudgetUnit {
  week('Weekly', 7),
  fortnight('Every 2 weeks', 14),
  month('Monthly', 0);

  const BudgetUnit(this.label, this.days);

  /// "Weekly", "Every 2 weeks", "Monthly".
  final String label;

  /// Days in a period; 0 for months (they vary).
  final int days;

  /// "week", "2 weeks", "month": for sentences like "just this month".
  String get noun => switch (this) {
    BudgetUnit.week => 'week',
    BudgetUnit.fortnight => '2 weeks',
    BudgetUnit.month => 'month',
  };
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

/// The period of [unit] that contains [date], for a budget that has not
/// been created yet (or has no anchor): weeks start on [weekStartDay], a
/// fortnight is the week plus the next one (or counts from [anchor]), and a
/// month is the budget month for [monthStartDay].
DateRange currentRangeFor(
  BudgetUnit unit,
  DateTime date, {
  required int monthStartDay,
  required int weekStartDay,
  DateTime? anchor,
}) {
  switch (unit) {
    case BudgetUnit.week:
      final start = weekStartOf(date, weekStartDay);
      return DateRange(start, _addDays(start, 6));
    case BudgetUnit.fortnight:
      final from = anchor == null
          ? weekStartOf(date, weekStartDay)
          : dateOnly(anchor);
      final n = _floorDiv(_daysBetween(from, dateOnly(date)), 14);
      final start = _addDays(from, n * 14);
      return DateRange(start, _addDays(start, 13));
    case BudgetUnit.month:
      return BudgetMonth.containing(date, monthStartDay).range(monthStartDay);
  }
}

int _floorDiv(int a, int b) => (a / b).floor();

/// The period just before [range].
DateRange previousRange(DateRange range, BudgetUnit unit, int monthStartDay) {
  if (unit == BudgetUnit.month) {
    return BudgetMonth.containing(
      range.start,
      monthStartDay,
    ).shift(-1).range(monthStartDay);
  }
  final start = _addDays(range.start, -unit.days);
  return DateRange(start, _addDays(start, unit.days - 1));
}

/// The period just after [range].
DateRange nextRange(DateRange range, BudgetUnit unit, int monthStartDay) {
  if (unit == BudgetUnit.month) {
    return BudgetMonth.containing(
      range.start,
      monthStartDay,
    ).shift(1).range(monthStartDay);
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

  /// The period of this entry that contains [date]. Weeks and fortnights
  /// count from [start]; months follow the budget-month start day.
  DateRange rangeAt(DateTime date, int monthStartDay) {
    switch (unit) {
      case BudgetUnit.week:
      case BudgetUnit.fortnight:
        final n = _floorDiv(_daysBetween(start, dateOnly(date)), unit.days);
        final first = _addDays(start, n * unit.days);
        return DateRange(first, _addDays(first, unit.days - 1));
      case BudgetUnit.month:
        return BudgetMonth.containing(date, monthStartDay).range(monthStartDay);
    }
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
  });

  final LimitEntry entry;
  final DateRange range;
  final int limit;
}

/// The finished periods of one budget's [entries] (all for the same
/// category, or all for all spending), newest first, at most [limit].
/// Each period shows the amount in force then: a later change never rewrites it.
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
    // A period belongs to this row if it starts before the next row does.
    while (range.end.isBefore(day) &&
        (nextStart == null || range.start.isBefore(nextStart))) {
      out.add(PastPeriod(entry: row, range: range, limit: amount));
      if (!row.repeats) break;
      range = nextRange(range, row.unit, monthStartDay);
    }
  }
  out.sort((a, b) => b.range.start.compareTo(a.range.start));
  return out.length > limit ? out.sublist(0, limit) : out;
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
