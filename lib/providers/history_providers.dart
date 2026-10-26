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

/// The words in the search box, parsed once for matching and highlighting.
final searchQueryProvider = Provider<SearchQuery>(
  (ref) => SearchQuery.parse(
    ref.watch(historyFilterProvider.select((f) => f.query)),
  ),
);

/// What History shows: the filtered list, narrowed by the search words.
/// Typing does not touch the database; it only narrows the list in memory.
final historyResultsProvider =
    Provider<AsyncValue<List<TransactionWithCategory>>>((ref) {
      final list = ref.watch(historyListProvider);
      final query = ref.watch(searchQueryProvider);
      if (query.isEmpty) return list;
      return list.whenData(
        (rows) => [
          for (final row in rows)
            if (query.matches(
              category: row.category.name,
              note: row.transaction.note,
              amountCents: row.transaction.amountCents,
            ))
              row,
        ],
      );
    });
