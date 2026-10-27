import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/transaction_repository.dart';
import '../domain/period.dart';
import '../domain/search.dart';
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
    this.query = '',
  });

  /// null = both income and expense.
  final TransactionType? type;

  /// Empty = all categories.
  final Set<int> categoryIds;

  /// null = all time.
  final Period? period;
  final SortOption sort;

  /// What the search box holds. Searching is separate from filtering: it is
  /// not counted by [hasFilters] or [activeCount], and clearing the filters
  /// leaves it alone.
  final String query;

  bool get isSearching => query.trim().isNotEmpty;

  /// True when anything narrows the list (sorting does not count).
  bool get hasFilters =>
      type != null || categoryIds.isNotEmpty || period != null;

  /// How many things narrow the list: the type, each chosen category and the
  /// date range. Shown on the Filter button.
  int get activeCount =>
      (type != null ? 1 : 0) + categoryIds.length + (period != null ? 1 : 0);

  HistoryFilter _copy({
    Object? type = _keep,
    Set<int>? categoryIds,
    Object? period = _keep,
    SortOption? sort,
    String? query,
  }) => HistoryFilter(
    type: identical(type, _keep) ? this.type : type as TransactionType?,
    categoryIds: categoryIds ?? this.categoryIds,
    period: identical(period, _keep) ? this.period : period as Period?,
    sort: sort ?? this.sort,
    query: query ?? this.query,
  );

  HistoryFilter withType(TransactionType? type) => _copy(type: type);

  HistoryFilter withCategories(Set<int> ids) => _copy(categoryIds: ids);

  HistoryFilter withPeriod(Period? period) => _copy(period: period);

  HistoryFilter withSort(SortOption sort) => _copy(sort: sort);

  HistoryFilter withQuery(String query) => _copy(query: query);

  /// Removes every filter but keeps the sort order and the search.
  HistoryFilter cleared() => HistoryFilter(sort: sort, query: query);
}

const Object _keep = Object();

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

  void setQuery(String query) => state = state.withQuery(query);

  void clear() => state = state.cleared();
}

/// How many rows History reads at a time. Scrolling near the end reads
/// another page.
const historyPageSize = 100;

/// One page of History: the rows to show and whether more follow.
class HistoryPage {
  const HistoryPage(this.rows, {required this.hasMore});

  final List<TransactionWithCategory> rows;
  final bool hasMore;
}

/// How many rows are loaded. It starts again whenever the filter, the sort or
/// the search changes, because the list then starts again from the top.
final historyLimitProvider = NotifierProvider<HistoryLimit, int>(
  HistoryLimit.new,
);

class HistoryLimit extends Notifier<int> {
  @override
  int build() {
    ref.watch(historyFilterProvider);
    return historyPageSize;
  }

  void more() => state += historyPageSize;
}

/// The rows to show out of [rows], which holds up to one more than [limit] so
/// that "is there more?" is known without a second query. In a date-ordered
/// list a day is never cut in half: if the next page continues the last day,
/// that day waits for the next page, so its total on the day header is right.
HistoryPage historyPageOf(
  List<TransactionWithCategory> rows,
  int limit, {
  required bool byDate,
}) {
  if (rows.length <= limit) return HistoryPage(rows, hasMore: false);
  var shown = rows.sublist(0, limit);
  final lastDate = shown.last.transaction.date;
  if (byDate && rows[limit].transaction.date == lastDate) {
    final cut = shown.lastIndexWhere((r) => r.transaction.date != lastDate);
    // A single day longer than a whole page has to be shown cut.
    if (cut >= 0) shown = shown.sublist(0, cut + 1);
  }
  return HistoryPage(shown, hasMore: true);
}

/// The filtered, sorted, searched History list, one page at a time.
final historyListProvider = StreamProvider<HistoryPage>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final settings = ref.watch(settingsProvider);
  final limit = ref.watch(historyLimitProvider);
  final period = filter.period;
  return repo
      .watchFiltered(
        type: filter.type,
        categoryIds: filter.categoryIds,
        range: period == null ? null : rangeOf(period, settings),
        sort: filter.sort,
        search: filter.query.trim(),
        limit: limit + 1,
      )
      .map((rows) => historyPageOf(rows, limit, byDate: filter.sort.isByDate));
});

/// How many transactions the filter and search match in all, and their net:
/// the "12 results · net -$84.20" line. Only watched while searching.
final historyTotalsProvider = StreamProvider<FilteredTotals>((ref) {
  final repo = ref.watch(transactionRepositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final settings = ref.watch(settingsProvider);
  final period = filter.period;
  return repo.watchFilteredTotals(
    type: filter.type,
    categoryIds: filter.categoryIds,
    range: period == null ? null : rangeOf(period, settings),
    search: filter.query.trim(),
  );
});

/// The words in the search box, parsed once for highlighting.
final searchQueryProvider = Provider<SearchQuery>(
  (ref) => SearchQuery.parse(
    ref.watch(historyFilterProvider.select((f) => f.query)),
  ),
);
