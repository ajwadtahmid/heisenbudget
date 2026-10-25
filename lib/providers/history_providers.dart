import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
import '../domain/period.dart';
import '../domain/sort_option.dart';
import '../domain/transaction_type.dart';
import 'database_providers.dart';
import 'period_providers.dart';
import 'settings_providers.dart';

/// What the History screen is filtered and sorted by. Immutable: use the
/// `with...` methods to get a changed copy.
class HistoryFilter {
  const HistoryFilter({
    this.type,
    this.categoryIds = const {},
    this.period,
    this.sort = SortOption.newestFirst,
  });

  /// null = both income and expense.
  final TransactionType? type;

  /// Empty = all categories.
  final Set<int> categoryIds;

  /// null = all time.
  final Period? period;
  final SortOption sort;

  /// True when anything narrows the list (sorting does not count).
  bool get hasFilters =>
      type != null || categoryIds.isNotEmpty || period != null;

  /// How many things narrow the list: the type, each chosen category and the
  /// date range. Shown on the Filter button.
  int get activeCount =>
      (type != null ? 1 : 0) + categoryIds.length + (period != null ? 1 : 0);

  HistoryFilter withType(TransactionType? type) => HistoryFilter(
    type: type,
    categoryIds: categoryIds,
    period: period,
    sort: sort,
  );

  HistoryFilter withCategories(Set<int> ids) =>
      HistoryFilter(type: type, categoryIds: ids, period: period, sort: sort);

  HistoryFilter withPeriod(Period? period) => HistoryFilter(
    type: type,
    categoryIds: categoryIds,
    period: period,
    sort: sort,
  );

  HistoryFilter withSort(SortOption sort) => HistoryFilter(
    type: type,
    categoryIds: categoryIds,
    period: period,
    sort: sort,
  );

  /// Removes every filter but keeps the sort order.
  HistoryFilter cleared() => HistoryFilter(sort: sort);
}

final historyFilterProvider =
    NotifierProvider<HistoryFilterNotifier, HistoryFilter>(
      HistoryFilterNotifier.new,
    );

class HistoryFilterNotifier extends Notifier<HistoryFilter> {
  @override
  HistoryFilter build() => const HistoryFilter();

  void setType(TransactionType? type) => state = state.withType(type);

  void setCategories(Set<int> ids) => state = state.withCategories(ids);

  void setPeriod(Period? period) => state = state.withPeriod(period);

  void setSort(SortOption sort) => state = state.withSort(sort);

  void clear() => state = state.cleared();
}

/// The filtered, sorted History list.
final historyListProvider = StreamProvider<List<TransactionWithCategory>>((
  ref,
) {
  final repo = ref.watch(transactionRepositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final settings = ref.watch(settingsProvider);
  final period = filter.period;
  return repo.watchFiltered(
    type: filter.type,
    categoryIds: filter.categoryIds,
    range: period == null ? null : rangeOf(period, settings),
    sort: filter.sort,
  );
});
