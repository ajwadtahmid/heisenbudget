import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/backup_status.dart';
import '../domain/budget.dart';
import '../domain/goals.dart';
import '../domain/iso_date.dart';
import '../domain/lab_report.dart';
import '../domain/trends.dart';
import 'budget_providers.dart';
import 'category_providers.dart';
import 'database_providers.dart';
import 'goal_providers.dart';
import 'period_providers.dart';
import 'settings_providers.dart';
import 'trends_providers.dart';

/// Everything the report page says about one finished budget month.
class LabReport {
  const LabReport({
    required this.month,
    required this.totals,
    required this.previous,
    required this.budgets,
    required this.lastPeriods,
    required this.up,
    required this.down,
    required this.monthsAveraged,
    required this.biggest,
    required this.rhythm,
    required this.goals,
    required this.suggestions,
  });

  final BudgetMonth month;
  final MonthTotals totals;

  /// The month before, or null when nothing was logged in it.
  final MonthTotals? previous;

  /// Budgets that had a period end in the month.
  final List<ReportBudget> budgets;

  /// The last such period of each budget (null key: all spending), for
  /// "Copy forward".
  final Map<int?, PastBudget> lastPeriods;

  /// Categories that spent more and less than usual, against
  /// [monthsAveraged] earlier months.
  final List<CategoryMove> up;
  final List<CategoryMove> down;
  final int monthsAveraged;

  /// The five biggest expenses, biggest first.
  final List<TransactionWithCategory> biggest;

  /// Null when nothing was spent.
  final SpendingRhythm? rhythm;

  /// Goals that had money put in or taken out during the month.
  final List<ReportGoal> goals;
  final List<ReportSuggestion> suggestions;
}

/// The report for [month], worked out again when a transaction, a budget or
/// the backup date changes.
final labReportProvider = FutureProvider.family<LabReport, BudgetMonth>((
  ref,
  month,
) async {
  await ref.watch(transactionChangesProvider.future);
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);
  final limits = await ref.watch(budgetLimitsProvider.future);
  final categories = await ref.watch(allCategoriesProvider.future);
  final lastBackup = ref.watch(settingsProvider.select((s) => s.lastBackupAt));
  final goalRows = await ref.watch(goalsProvider.future);
  final goalEntries = await ref.watch(goalEntriesProvider.future);
  final inForce = {
    for (final line
        in ref.watch(budgetOverviewProvider).value?.all ?? const <BudgetLine>[])
      ?line.categoryId,
  };
  final repo = ref.read(transactionRepositoryProvider);

  final range = month.range(startDay);
  final months = [for (var back = 3; back >= 0; back--) month.shift(-back)];
  final totals = monthTotalsOf(
    months,
    await repo.summariesForRanges([for (final m in months) m.range(startDay)]),
    today,
    startDay,
  );
  final current = totals.last;
  final before = totals[2];

  // What moved: this month against up to three earlier ones.
  var up = const <CategoryMove>[];
  var down = const <CategoryMove>[];
  final earlier = moverBaseline(totals.sublist(0, 3).reversed.toList());
  if (earlier.isNotEmpty) {
    final movers = topMovers(
      await repo.categoryHistoryForRanges([
        range,
        for (final t in earlier) t.range,
      ]),
    );
    up = movers.up;
    down = movers.down;
  }

  // The budget periods that ended in the month, with what was spent in each.
  final byTarget = <int?, List<LimitEntry>>{};
  for (final row in limits) {
    byTarget.putIfAbsent(row.categoryId, () => []).add(row.entry);
  }
  final periods = <({int? categoryId, CategoryRow? category, PastPeriod p})>[];
  for (final MapEntry(key: id, value: entries) in byTarget.entries) {
    final category = id == null
        ? null
        : categories.where((c) => c.id == id).firstOrNull;
    for (final p in pastPeriods(
      entries,
      today,
      monthStartDay: startDay,
      limit: 1 << 30,
    )) {
      if (p.range.end.isBefore(range.start) || p.range.end.isAfter(range.end)) {
        continue;
      }
      periods.add((categoryId: id, category: category, p: p));
    }
  }
  final spent = await repo.spentForKeys([
    for (final x in periods) (x.p.range, x.categoryId),
  ]);
  final past = <PastBudget>[
    for (var i = 0; i < periods.length; i++)
      PastBudget(
        categoryId: periods[i].categoryId,
        category: periods[i].category,
        entry: periods[i].p.entry,
        range: periods[i].p.range,
        limit: periods[i].p.limit,
        spent: spent[i],
        endedEarly: periods[i].p.endedEarly,
      ),
  ];
  String nameOf(PastBudget b) => b.category == null
      ? 'All spending'
      : (b.category!.isArchived
            ? '${b.category!.name} (archived)'
            : b.category!.name);
  final lastPeriods = <int?, PastBudget>{};
  for (final b in past) {
    final seen = lastPeriods[b.categoryId];
    if (seen == null || b.range.end.isAfter(seen.range.end)) {
      lastPeriods[b.categoryId] = b;
    }
  }

  // What to do next.
  final byCategory = await repo.categoryHistoryForRanges([range]);
  final spending = [
    for (final h in byCategory)
      if (h.spent.first > 0)
        (id: h.categoryId, name: h.name, spentCents: h.spent.first),
  ]..sort((a, b) => b.spentCents.compareTo(a.spentCents));

  final byDay = await repo.expenseByDay(range);
  final rhythm = rhythmOf(byDay, range, today);

  // Goals: what went in during the month, and which were left alone.
  final movesByGoal = <int, List<GoalMove>>{};
  for (final e in goalEntries) {
    movesByGoal
        .putIfAbsent(e.goalId, () => [])
        .add(GoalMove(fromIsoDate(e.date), e.amountCents));
  }
  List<GoalMove> movesOf(SavingsGoalRow g) => movesByGoal[g.id] ?? const [];
  final reportGoals = reportGoalsOf([
    for (final g in goalRows)
      (id: g.id, name: g.name, targetCents: g.targetCents, moves: movesOf(g)),
  ], range);
  final touched = {for (final g in reportGoals) g.goalId};
  final idleGoals = [
    for (final g in goalRows)
      // Made by the end of the month, not reached now, and left alone in it.
      if (!dateOnly(g.createdAt).isAfter(range.end) &&
          savedOf(movesOf(g)) < g.targetCents &&
          !touched.contains(g.id))
        (id: g.id, name: g.name),
  ];

  return LabReport(
    month: month,
    totals: current,
    previous: before.isEmpty ? null : before,
    budgets: reportBudgetsOf([
      for (final b in past)
        BudgetPeriodResult(
          categoryId: b.categoryId,
          name: nameOf(b),
          limitCents: b.limit,
          spentCents: b.spent,
        ),
    ]),
    lastPeriods: lastPeriods,
    up: up,
    down: down,
    monthsAveraged: earlier.length,
    biggest: await repo.topExpenses(range, limit: 5),
    rhythm: rhythm == null || rhythm.totalCents == 0 ? null : rhythm,
    goals: reportGoals,
    suggestions: suggestionsOf(
      spending: spending,
      budgetedCategoryIds: inForce,
      backup: backupFreshness(lastBackup, today),
      idleGoals: idleGoals,
    ),
  );
});

/// The finished months with something logged in them, newest first, at most
/// [reportMonthsListed]: the Reports list under Trends.
final reportMonthsProvider = FutureProvider<List<MonthTotals>>((ref) async {
  final totals = await ref.watch(
    trendTotalsProvider(reportMonthsListed + 1).future,
  );
  return [
    for (final t in totals.reversed)
      if (!t.inProgress && !t.isEmpty) t,
  ];
});

/// The month whose report Home announces now, or null: it is within the first
/// days of a budget month, the report has not been opened, and the month has
/// something in it to report.
final reportNoticeProvider = Provider<BudgetMonth?>((ref) {
  final due = reportDue(
    today: ref.watch(clockProvider),
    startDay: ref.watch(monthStartDayProvider),
    seenMonth: ref.watch(settingsProvider.select((s) => s.reportSeenMonth)),
  );
  if (due == null) return null;
  final totals = ref.watch(trendTotalsProvider(6)).value;
  if (totals == null) return null;
  final month = totals.where((t) => t.month.key == due.key).firstOrNull;
  return month == null || month.isEmpty ? null : due;
});

/// Remembers that the report for [month] was opened (an older report never
/// brings back a newer one's card).
Future<void> markReportSeen(WidgetRef ref, BudgetMonth month) async {
  final seen = ref.read(settingsProvider).reportSeenMonth;
  if (seen != null && seen.compareTo(month.key) >= 0) return;
  await ref.read(settingsProvider.notifier).setReportSeenMonth(month.key);
}

/// Reads every report figure again (the page's "Try again").
void reloadReports(WidgetRef ref) {
  ref.invalidate(labReportProvider);
  ref.invalidate(reportMonthsProvider);
}
