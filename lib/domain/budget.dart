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

/// One stored limit: from [start] onward the limit for [categoryId] (null =
/// all spending) is [amountCents]; a null amount means "no limit from here".
class LimitEntry {
  const LimitEntry({
    required this.categoryId,
    required this.start,
    required this.amountCents,
  });

  final int? categoryId;
  final BudgetMonth start;
  final int? amountCents;
}

/// The limit in force for [categoryId] (null = all spending) in [month]: the
/// latest entry that starts in or before it. Null when there is none, or when
/// the latest entry says "no limit".
int? resolveLimit(
  Iterable<LimitEntry> entries,
  int? categoryId,
  BudgetMonth month,
) {
  LimitEntry? best;
  for (final entry in entries) {
    if (entry.categoryId != categoryId || entry.start > month) continue;
    if (best == null || entry.start > best.start) best = entry;
  }
  return best?.amountCents;
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
