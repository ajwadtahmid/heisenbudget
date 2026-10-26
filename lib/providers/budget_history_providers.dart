import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/budget.dart';
import 'budget_providers.dart';

/// Which side of History is showing.
enum HistoryMode { transactions, budgets }

final historyModeProvider = NotifierProvider<HistoryModeNotifier, HistoryMode>(
  HistoryModeNotifier.new,
);

class HistoryModeNotifier extends Notifier<HistoryMode> {
  @override
  HistoryMode build() => HistoryMode.transactions;

  void set(HistoryMode mode) => state = mode;
}

/// Which budget periods to list.
enum PeriodFilter {
  all('All'),
  month('Monthly'),
  fortnight('Every 2 weeks'),
  week('Weekly'),
  oneTime('One-time');

  const PeriodFilter(this.label);
  final String label;
}

enum ResultFilter {
  all('All'),
  over('Went over'),
  within('Stayed within');

  const ResultFilter(this.label);
  final String label;
}

enum BudgetSort {
  newest('Date: newest first'),
  oldest('Date: oldest first'),
  mostOver('Most over budget first'),
  mostSpent('Most spent first');

  const BudgetSort(this.label);
  final String label;
}

/// The id used for "All spending" in a budget filter (categories start at 1).
const overallTargetId = 0;

/// What the Budgets side of History is filtered and sorted by.
class BudgetHistoryFilter {
  const BudgetHistoryFilter({
    this.period = PeriodFilter.all,
    this.result = ResultFilter.all,
    this.targets = const {},
    this.sort = BudgetSort.newest,
  });

  final PeriodFilter period;
  final ResultFilter result;

  /// Category ids, plus [overallTargetId] for all spending. Empty = every budget.
  final Set<int> targets;
  final BudgetSort sort;

  bool get hasFilters =>
      period != PeriodFilter.all ||
      result != ResultFilter.all ||
      targets.isNotEmpty;

  int get activeCount =>
      (period != PeriodFilter.all ? 1 : 0) +
      (result != ResultFilter.all ? 1 : 0) +
      targets.length;

  BudgetHistoryFilter copyWith({
    PeriodFilter? period,
    ResultFilter? result,
    Set<int>? targets,
    BudgetSort? sort,
  }) => BudgetHistoryFilter(
    period: period ?? this.period,
    result: result ?? this.result,
    targets: targets ?? this.targets,
    sort: sort ?? this.sort,
  );

  /// Removes every filter but keeps the sort order.
  BudgetHistoryFilter cleared() => BudgetHistoryFilter(sort: sort);

  bool accepts(PastBudget b) {
    final okPeriod = switch (period) {
      PeriodFilter.all => true,
      PeriodFilter.month => b.unit == BudgetUnit.month,
      PeriodFilter.fortnight => b.unit == BudgetUnit.fortnight,
      PeriodFilter.week => b.unit == BudgetUnit.week,
      PeriodFilter.oneTime => b.isOneTime,
    };
    final okResult = switch (result) {
      ResultFilter.all => true,
      ResultFilter.over => b.result == BudgetResult.over,
      ResultFilter.within => b.result != BudgetResult.over,
    };
    final okTarget =
        targets.isEmpty || targets.contains(b.categoryId ?? overallTargetId);
    return okPeriod && okResult && okTarget;
  }
}

final budgetHistoryFilterProvider =
    NotifierProvider<BudgetHistoryFilterNotifier, BudgetHistoryFilter>(
      BudgetHistoryFilterNotifier.new,
    );

class BudgetHistoryFilterNotifier extends Notifier<BudgetHistoryFilter> {
  @override
  BudgetHistoryFilter build() => const BudgetHistoryFilter();

  void setPeriod(PeriodFilter p) => state = state.copyWith(period: p);
  void setResult(ResultFilter r) => state = state.copyWith(result: r);
  void setTargets(Set<int> t) => state = state.copyWith(targets: t);
  void setSort(BudgetSort s) => state = state.copyWith(sort: s);
  void clear() => state = state.cleared();
}

/// How many periods of each budget are loaded; "Show more" adds a page.
const budgetHistoryPage = 12;

final budgetHistoryCountProvider = NotifierProvider<BudgetHistoryCount, int>(
  BudgetHistoryCount.new,
);

class BudgetHistoryCount extends Notifier<int> {
  @override
  int build() => budgetHistoryPage;

  void more() => state = state + budgetHistoryPage;
}

/// The finished budget periods, filtered and sorted.
final budgetHistoryProvider = Provider<AsyncValue<List<PastBudget>>>((ref) {
  final filter = ref.watch(budgetHistoryFilterProvider);
  final all = ref.watch(
    pastBudgetsProvider(ref.watch(budgetHistoryCountProvider)),
  );
  return all.whenData((rows) {
    final kept = rows.where(filter.accepts).toList();
    int byName(PastBudget a, PastBudget b) =>
        (a.category?.name ?? '').compareTo(b.category?.name ?? '');
    kept.sort((a, b) {
      final c = switch (filter.sort) {
        BudgetSort.newest => b.range.end.compareTo(a.range.end),
        BudgetSort.oldest => a.range.end.compareTo(b.range.end),
        BudgetSort.mostOver => (b.spent - b.limit).compareTo(a.spent - a.limit),
        BudgetSort.mostSpent => b.spent.compareTo(a.spent),
      };
      return c != 0 ? c : byName(a, b);
    });
    return kept;
  });
});
