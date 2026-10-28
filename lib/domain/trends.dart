// PURE DART: no Flutter imports. The numbers behind Trends.
import 'dart:math' as math;

import 'budget.dart';
import 'category_spend.dart' show purityPermille;
import 'date_range.dart';
import 'iso_date.dart';
import 'summary.dart';

/// How many months the trace can show.
const trendWindows = [6, 12];

/// The budget months ending with the one that holds [today], oldest first.
/// Budget months follow the "month starts on" setting, so Trends, budgets and
/// the month-end report always agree on what a month is.
List<BudgetMonth> trendMonths(DateTime today, int count, int startDay) {
  final now = BudgetMonth.containing(today, startDay);
  return [for (var back = count - 1; back >= 0; back--) now.shift(-back)];
}

/// What came in and went out in one budget month.
class MonthTotals {
  const MonthTotals({
    required this.month,
    required this.range,
    required this.summary,
    required this.inProgress,
  });

  final BudgetMonth month;
  final DateRange range;
  final Summary summary;

  /// The month is still going, so its totals are not final.
  final bool inProgress;

  int get receivedCents => summary.receivedCents;
  int get spentCents => summary.spentCents;
  int get netCents => summary.netCents;

  /// The share of what came in that was kept, in tenths of a percent; null
  /// when nothing came in.
  int? get purity => purityPermille(receivedCents, spentCents);

  /// Nothing was logged in it.
  bool get isEmpty => receivedCents == 0 && spentCents == 0;
}

/// Pairs each of [months] with its [summaries] (same order).
List<MonthTotals> monthTotalsOf(
  List<BudgetMonth> months,
  List<Summary> summaries,
  DateTime today,
  int startDay,
) {
  final day = dateOnly(today);
  return [
    for (var i = 0; i < months.length; i++)
      MonthTotals(
        month: months[i],
        range: months[i].range(startDay),
        summary: summaries[i],
        inProgress: !day.isAfter(months[i].range(startDay).end),
      ),
  ];
}

/// How the last finished month's spending sits against the months before it.
class SpendComparison {
  const SpendComparison({
    required this.month,
    required this.averageCents,
    required this.percent,
    required this.monthsAveraged,
  });

  /// The last finished month.
  final MonthTotals month;

  /// The average spent in the [monthsAveraged] months before it.
  final int averageCents;

  /// Above (positive) or below (negative) that average, in whole percent.
  final int percent;
  final int monthsAveraged;
}

/// The last finished month against the average of up to [lookBack] months
/// before it. Months before anything was logged are left out of the average
/// (a new user's empty past is not "saving"). Null when there is no finished
/// month with one earlier month to compare with, or the average is zero.
SpendComparison? compareLastMonth(
  List<MonthTotals> totals, {
  int lookBack = 5,
}) {
  final finished = [
    for (final t in totals)
      if (!t.inProgress) t,
  ];
  if (finished.length < 2) return null;
  final last = finished.last;
  final before = finished
      .sublist(math.max(0, finished.length - 1 - lookBack), finished.length - 1)
      .skipWhile((t) => t.isEmpty)
      .toList();
  if (before.isEmpty) return null;
  final total = before.fold<int>(0, (sum, t) => sum + t.spentCents);
  final average = (total + before.length ~/ 2) ~/ before.length;
  if (average == 0) return null;
  final delta = last.spentCents - average;
  // Rounded to the nearest whole percent, away from zero on a tie.
  final percent =
      (delta * 100 + (delta >= 0 ? average ~/ 2 : -(average ~/ 2))) ~/ average;
  return SpendComparison(
    month: last,
    averageCents: average,
    percent: percent,
    monthsAveraged: before.length,
  );
}

/// What was spent in one category in a run of months (newest first).
class CategoryHistory {
  const CategoryHistory({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.spent,
  });

  final int categoryId;
  final String name;
  final String icon;

  /// Spent in each month, the month being looked at first, then the months
  /// before it.
  final List<int> spent;
}

/// A category that spent more, or less, than it usually does.
class CategoryMove {
  const CategoryMove({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.currentCents,
    required this.averageCents,
  });

  final int categoryId;
  final String name;
  final String icon;
  final int currentCents;

  /// The average over the earlier months.
  final int averageCents;

  /// Positive: spent more than usual.
  int get deltaCents => currentCents - averageCents;
}

/// The [count] categories that moved up most and the [count] that moved down
/// most: each category's first month against the average of the rest.
/// Categories that did not change are left out.
({List<CategoryMove> up, List<CategoryMove> down}) topMovers(
  List<CategoryHistory> histories, {
  int count = 3,
}) {
  final moves = <CategoryMove>[];
  for (final h in histories) {
    if (h.spent.length < 2) continue;
    final earlier = h.spent.sublist(1);
    final total = earlier.fold<int>(0, (sum, c) => sum + c);
    moves.add(
      CategoryMove(
        categoryId: h.categoryId,
        name: h.name,
        icon: h.icon,
        currentCents: h.spent.first,
        averageCents: (total + earlier.length ~/ 2) ~/ earlier.length,
      ),
    );
  }
  final up = moves.where((m) => m.deltaCents > 0).toList()
    ..sort((a, b) => b.deltaCents.compareTo(a.deltaCents));
  final down = moves.where((m) => m.deltaCents < 0).toList()
    ..sort((a, b) => a.deltaCents.compareTo(b.deltaCents));
  return (up: up.take(count).toList(), down: down.take(count).toList());
}

/// How spending ran through the days of one month so far.
class SpendingRhythm {
  const SpendingRhythm({
    required this.days,
    required this.totalCents,
    required this.averagePerDayCents,
    required this.noSpendDays,
    required this.longestNoSpendStreak,
    this.busiestDay,
    this.busiestDayCents = 0,
  });

  /// Days counted: from the first day of the month up to today (or its end).
  final int days;
  final int totalCents;
  final int averagePerDayCents;

  /// Days with no expense, and the longest run of them in a row.
  final int noSpendDays;
  final int longestNoSpendStreak;

  /// The day with the most spent (null when nothing was spent).
  final DateTime? busiestDay;
  final int busiestDayCents;
}

/// The rhythm of [range] up to [today], from expenses [byDay] (date-only keys
/// with what was spent that day). Null before the range has begun.
SpendingRhythm? rhythmOf(
  Map<DateTime, int> byDay,
  DateRange range,
  DateTime today,
) {
  final now = dateOnly(today);
  final last = now.isBefore(range.end) ? now : range.end;
  if (last.isBefore(range.start)) return null;
  var days = 0;
  var total = 0;
  var noSpend = 0;
  var streak = 0;
  var longest = 0;
  DateTime? busiest;
  var busiestCents = 0;
  for (
    var day = range.start;
    !day.isAfter(last);
    day = DateTime(day.year, day.month, day.day + 1)
  ) {
    days++;
    final spent = byDay[day] ?? 0;
    total += spent;
    if (spent == 0) {
      noSpend++;
      streak++;
      if (streak > longest) longest = streak;
    } else {
      streak = 0;
      if (spent > busiestCents) {
        busiestCents = spent;
        busiest = day;
      }
    }
  }
  return SpendingRhythm(
    days: days,
    totalCents: total,
    averagePerDayCents: (total + days ~/ 2) ~/ days,
    noSpendDays: noSpend,
    longestNoSpendStreak: longest,
    busiestDay: busiest,
    busiestDayCents: busiestCents,
  );
}
