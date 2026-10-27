import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/budget_repository.dart';
import '../domain/budget.dart';
import 'budget_providers.dart';
import 'category_providers.dart';
import 'database_providers.dart';
import 'period_providers.dart';

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
  custom('Custom'),
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

  /// Whether a period of [entry] (a budget on [categoryId], null for all
  /// spending) is the kind and the budget asked for. Needs no spending figure.
  bool acceptsKind(LimitEntry entry, int? categoryId) {
    final okPeriod = switch (period) {
      PeriodFilter.all => true,
      PeriodFilter.month => entry.unit.isMonth,
      PeriodFilter.custom => !entry.unit.isMonth,
      PeriodFilter.oneTime => !entry.repeats,
    };
    final okTarget =
        targets.isEmpty || targets.contains(categoryId ?? overallTargetId);
    return okPeriod && okTarget;
  }

  bool acceptsResult(BudgetResult r) => switch (result) {
    ResultFilter.all => true,
    ResultFilter.over => r == BudgetResult.over,
    ResultFilter.within => r != BudgetResult.over,
  };

  bool accepts(PastBudget b) =>
      acceptsKind(b.entry, b.categoryId) && acceptsResult(b.result);

  /// Whether the filter or the sort needs what was spent to decide, so every
  /// period has to be totalled, not only the ones on the page.
  bool get needsSpending =>
      result != ResultFilter.all ||
      sort == BudgetSort.mostOver ||
      sort == BudgetSort.mostSpent;
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

/// How many past-budget rows are read at a time. Scrolling near the end reads
/// another page.
const budgetHistoryPage = 30;

/// How many rows are loaded; it starts again when the filter or sort changes.
final budgetHistoryCountProvider = NotifierProvider<BudgetHistoryCount, int>(
  BudgetHistoryCount.new,
);

class BudgetHistoryCount extends Notifier<int> {
  @override
  int build() {
    ref.watch(budgetHistoryFilterProvider);
    return budgetHistoryPage;
  }

  void more() => state = state + budgetHistoryPage;
}

/// One page of past budgets: the rows to show and whether more follow.
class BudgetHistoryPage {
  const BudgetHistoryPage(this.rows, {required this.hasMore});

  final List<PastBudget> rows;
  final bool hasMore;
}

/// A finished period before what was spent is known.
class _Candidate {
  const _Candidate(this.categoryId, this.category, this.period);

  final int? categoryId;
  final CategoryRow? category;
  final PastPeriod period;

  String get name => category?.name ?? '';
}

/// Every finished period of every budget. Worked out from the limits alone
/// (no spending, no database query), so listing and filtering by period or by
/// budget is cheap however long the history is.
final _candidatesProvider = FutureProvider<List<_Candidate>>((ref) async {
  final limits = await ref.watch(budgetLimitsProvider.future);
  final categories = await ref.watch(allCategoriesProvider.future);
  final today = ref.watch(clockProvider);
  final startDay = ref.watch(monthStartDayProvider);

  final byTarget = <int?, List<LimitEntry>>{};
  for (final row in limits) {
    byTarget.putIfAbsent(row.categoryId, () => []).add(row.entry);
  }
  final out = <_Candidate>[];
  for (final MapEntry(key: categoryId, value: entries) in byTarget.entries) {
    final category = categoryId == null
        ? null
        : categories.where((c) => c.id == categoryId).firstOrNull;
    for (final period in pastPeriods(
      entries,
      today,
      monthStartDay: startDay,
      limit: 1 << 30,
    )) {
      out.add(_Candidate(categoryId, category, period));
    }
  }
  return out;
});

/// Names for the budgets that have history, keyed by target id (for the
/// filter and its chips).
final budgetHistoryTargetsProvider = Provider<Map<int, String>>((ref) {
  final all = ref.watch(_candidatesProvider).value ?? const [];
  return {
    for (final c in all)
      c.categoryId ?? overallTargetId: c.category?.name ?? 'All spending',
  };
});

/// A number that changes whenever a transaction does, so figures are recounted.
final _transactionChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchChangeCount(),
);

/// The finished budget periods, filtered and sorted, one page at a time.
///
/// Sorted by date, only the rows on the page are totalled. A filter or sort
/// that depends on what was spent ("Went over", "Most spent") needs every
/// period totalled, which is still a few queries however many there are.
final budgetHistoryProvider = FutureProvider<BudgetHistoryPage>((ref) async {
  final filter = ref.watch(budgetHistoryFilterProvider);
  final count = ref.watch(budgetHistoryCountProvider);
  final candidates = await ref.watch(_candidatesProvider.future);
  ref.watch(_transactionChangesProvider);
  final repo = ref.read(transactionRepositoryProvider);

  Future<List<PastBudget>> withSpending(List<_Candidate> some) async {
    final spent = await repo.spentForKeys([
      for (final c in some) (c.period.range, c.categoryId),
    ]);
    return [
      for (var i = 0; i < some.length; i++)
        PastBudget(
          categoryId: some[i].categoryId,
          category: some[i].category,
          entry: some[i].period.entry,
          range: some[i].period.range,
          limit: some[i].period.limit,
          endedEarly: some[i].period.endedEarly,
          spent: spent[i],
        ),
    ];
  }

  final kept = [
    for (final c in candidates)
      if (filter.acceptsKind(c.period.entry, c.categoryId)) c,
  ];

  if (!filter.needsSpending) {
    kept.sort((a, b) {
      final byDate = filter.sort == BudgetSort.oldest
          ? a.period.range.end.compareTo(b.period.range.end)
          : b.period.range.end.compareTo(a.period.range.end);
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
    return BudgetHistoryPage(
      await withSpending(kept.take(count).toList()),
      hasMore: kept.length > count,
    );
  }

  final all = [
    for (final b in await withSpending(kept))
      if (filter.acceptsResult(b.result)) b,
  ];
  all.sort((a, b) {
    final c = switch (filter.sort) {
      BudgetSort.newest => b.range.end.compareTo(a.range.end),
      BudgetSort.oldest => a.range.end.compareTo(b.range.end),
      BudgetSort.mostOver => (b.spent - b.limit).compareTo(a.spent - a.limit),
      BudgetSort.mostSpent => b.spent.compareTo(a.spent),
    };
    return c != 0
        ? c
        : (a.category?.name ?? '').compareTo(b.category?.name ?? '');
  });
  return BudgetHistoryPage(
    all.take(count).toList(),
    hasMore: all.length > count,
  );
});
