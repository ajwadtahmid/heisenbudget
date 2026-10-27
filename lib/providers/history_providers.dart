import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../domain/date_range.dart';
import '../domain/iso_date.dart';
import '../domain/period.dart';
import '../domain/saved_filter.dart';
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
    this.minCents,
    this.maxCents,
    this.jumpTo,
    this.sort = SortOption.newestFirst,
    this.query = '',
  });

  /// null = both income and expense.
  final TransactionType? type;

  /// Empty = all categories.
  final Set<int> categoryIds;

  /// null = all time.
  final Period? period;

  /// Amount bounds in cents, both ends inclusive; null = no bound.
  final int? minCents;
  final int? maxCents;

  /// A date to start the list from: the newest rows shown are those of this
  /// day (newest first), or the oldest are (oldest first). Only used while
  /// the list is sorted by date.
  final DateTime? jumpTo;
  final SortOption sort;

  /// What the search box holds. Searching is separate from filtering: it is
  /// not counted by [hasFilters] or [activeCount], and clearing the filters
  /// leaves it alone.
  final String query;

  bool get isSearching => query.trim().isNotEmpty;

  /// True when anything narrows the list (sorting does not count).
  bool get hasFilters =>
      type != null ||
      categoryIds.isNotEmpty ||
      period != null ||
      hasAmountRange ||
      jumpTo != null;

  bool get hasAmountRange => minCents != null || maxCents != null;

  /// How many things narrow the list: the type, each chosen category, the
  /// date range, the amount range and a date jump. Shown on the Filter button.
  int get activeCount =>
      (type != null ? 1 : 0) +
      categoryIds.length +
      (period != null ? 1 : 0) +
      (hasAmountRange ? 1 : 0) +
      (jumpTo != null ? 1 : 0);

  HistoryFilter _copy({
    Object? type = _keep,
    Set<int>? categoryIds,
    Object? period = _keep,
    Object? minCents = _keep,
    Object? maxCents = _keep,
    Object? jumpTo = _keep,
    SortOption? sort,
    String? query,
  }) => HistoryFilter(
    type: identical(type, _keep) ? this.type : type as TransactionType?,
    categoryIds: categoryIds ?? this.categoryIds,
    period: identical(period, _keep) ? this.period : period as Period?,
    minCents: identical(minCents, _keep) ? this.minCents : minCents as int?,
    maxCents: identical(maxCents, _keep) ? this.maxCents : maxCents as int?,
    jumpTo: identical(jumpTo, _keep) ? this.jumpTo : jumpTo as DateTime?,
    sort: sort ?? this.sort,
    query: query ?? this.query,
  );

  HistoryFilter withType(TransactionType? type) => _copy(type: type);

  HistoryFilter withCategories(Set<int> ids) => _copy(categoryIds: ids);

  /// A new period starts the list afresh, so a date jump inside the old one
  /// is dropped.
  HistoryFilter withPeriod(Period? period) =>
      _copy(period: period, jumpTo: null);

  HistoryFilter withAmountRange(int? minCents, int? maxCents) =>
      _copy(minCents: minCents, maxCents: maxCents);

  HistoryFilter withJump(DateTime? day) =>
      _copy(jumpTo: day == null ? null : dateOnly(day));

  /// Sorting by amount has no dates to jump along, so the jump is dropped.
  HistoryFilter withSort(SortOption sort) =>
      _copy(sort: sort, jumpTo: sort.isByDate ? jumpTo : null);

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

  void setAmountRange(int? minCents, int? maxCents) =>
      state = state.withAmountRange(minCents, maxCents);

  void setJump(DateTime? day) => state = state.withJump(day);

  /// Shows [filter] instead (a saved filter, or "see these transactions"),
  /// keeping what is typed in the search box.
  void replace(HistoryFilter filter) => state = filter.withQuery(state.query);

  void setSort(SortOption sort) => state = state.withSort(sort);

  void setQuery(String query) => state = state.withQuery(query);

  void clear() => state = state.cleared();
}

/// The dates History reads: the chosen period, narrowed by a date jump.
DateRange? historyRangeOf(HistoryFilter filter, AppSettings settings) {
  final period = filter.period;
  final base = period == null ? null : rangeOf(period, settings);
  final jump = filter.jumpTo;
  if (jump == null || !filter.sort.isByDate) return base;
  final day = dateOnly(jump);
  final oldestFirst = filter.sort == SortOption.oldestFirst;
  final start = oldestFirst ? day : (base?.start ?? earliestDate);
  final end = oldestFirst ? (base?.end ?? latestDate) : day;
  // A jump outside the period cannot be followed: show the period.
  return start.isAfter(end) ? base : DateRange(start, end);
}

/// [filter] kept under [name], with its period saved the way it reads today.
SavedFilter savedFilterOf(
  HistoryFilter filter,
  String name,
  AppSettings settings,
  DateTime today,
) {
  final period = filter.period;
  final kind = SavedFilter.kindOf(
    period,
    today,
    settings.weekMode,
    settings.weekStartDay,
  );
  final range = kind == SavedPeriod.custom ? rangeOf(period!, settings) : null;
  return SavedFilter(
    name: name.trim(),
    type: filter.type,
    categoryIds: filter.categoryIds,
    period: kind,
    customStart: range?.start,
    customEnd: range?.end,
    minCents: filter.minCents,
    maxCents: filter.maxCents,
    sort: filter.sort,
  );
}

/// The History filter a saved one means on [today].
HistoryFilter historyFilterOf(SavedFilter saved, DateTime today) =>
    HistoryFilter(
      type: saved.type,
      categoryIds: saved.categoryIds,
      period: saved.periodFor(today),
      minCents: saved.minCents,
      maxCents: saved.maxCents,
      sort: saved.sort,
    );

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
  return repo
      .watchFiltered(
        type: filter.type,
        categoryIds: filter.categoryIds,
        range: historyRangeOf(filter, settings),
        minCents: filter.minCents,
        maxCents: filter.maxCents,
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
  return repo.watchFilteredTotals(
    type: filter.type,
    categoryIds: filter.categoryIds,
    range: historyRangeOf(filter, settings),
    minCents: filter.minCents,
    maxCents: filter.maxCents,
    search: filter.query.trim(),
  );
});

/// The words in the search box, parsed once for highlighting.
final searchQueryProvider = Provider<SearchQuery>(
  (ref) => SearchQuery.parse(
    ref.watch(historyFilterProvider.select((f) => f.query)),
  ),
);
