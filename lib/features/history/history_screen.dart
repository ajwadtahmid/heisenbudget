import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/iso_date.dart';
import '../../domain/search.dart';
import '../../domain/sort_option.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/add_key.dart';
import '../shared/empty_state.dart';
import '../shared/transaction_menu.dart';
import '../shared/transaction_tile.dart';
import '../transaction_form/transaction_form_screen.dart';
import 'filter_sheet.dart';
import '../../providers/budget_history_providers.dart';
import 'budget_history_view.dart';
import 'history_mode_pill.dart';
import 'history_widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Swiped-away rows. A Dismissible must leave the tree in the same frame,
  /// but the database stream only updates a moment later, so hide them here.
  final _dismissed = <int>{};

  /// The search box. It is shown while it is open or holds a query, and the
  /// text reaches the filter a moment after typing stops.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    final query = ref.read(historyFilterProvider).query;
    _searchController.text = query;
    _searchOpen = query.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(historyFilterProvider.notifier).setQuery(text);
    });
  }

  /// Opens the search box, or closes it and drops the query.
  void _toggleSearch(bool isOpen) {
    if (isOpen) {
      _clearSearch();
      setState(() => _searchOpen = false);
      return;
    }
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    ref.read(historyFilterProvider.notifier).setQuery('');
  }

  Future<void> _delete(TransactionWithCategory item) async {
    final row = item.transaction;
    setState(() => _dismissed.add(row.id));
    final repo = ref.read(transactionRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final backup = TransactionInput.fromRow(row);
    await repo.delete(row.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.add(backup),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final items = (ref.watch(historyResultsProvider).value ?? const [])
        .where((i) => !_dismissed.contains(i.transaction.id))
        .toList();
    final searchShown = _searchOpen || filter.isSearching;
    final isBudgets = ref.watch(historyModeProvider) == HistoryMode.budgets;

    // The query can also be cleared from the chip: keep the box in step.
    ref.listen(historyFilterProvider.select((f) => f.query), (_, query) {
      if (_searchController.text != query && !_searchFocus.hasFocus) {
        _searchController.text = query;
      }
    });

    return Scaffold(
      floatingActionButton: isBudgets ? null : const AddKey(),
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (!isBudgets)
            IconButton(
              key: const ValueKey('search-button'),
              tooltip: searchShown ? 'Close search' : 'Search',
              icon: Icon(searchShown ? Icons.search_off : Icons.search),
              onPressed: () => _toggleSearch(searchShown),
            ),
        ],
      ),
      body: Column(
        children: [
          const HistoryModePill(),
          Expanded(
            child: isBudgets
                ? const BudgetHistoryView()
                : LayoutBuilder(
                    builder: (context, box) => Column(
                      children: [
                        // The controls scroll if they ever need more than half the screen
                        // (large text, search open), so the list always keeps room.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: box.maxHeight * 0.5,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (searchShown) _searchField(),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      4,
                                      20,
                                      8,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ControlFace(
                                          key: const ValueKey('filter-button'),
                                          tooltip: 'Filter',
                                          icon: Icons.filter_list,
                                          label: filter.activeCount > 0
                                              ? 'Filter · ${filter.activeCount}'
                                              : 'Filter',
                                          highlighted: filter.hasFilters,
                                          onTap: () => showFilterSheet(context),
                                        ),
                                        PopupMenuButton<SortOption>(
                                          key: const ValueKey('sort-button'),
                                          tooltip: 'Sort',
                                          initialValue: filter.sort,
                                          onSelected: ref
                                              .read(
                                                historyFilterProvider.notifier,
                                              )
                                              .setSort,
                                          itemBuilder: (_) => [
                                            for (final option
                                                in SortOption.values)
                                              CheckedPopupMenuItem(
                                                value: option,
                                                checked: option == filter.sort,
                                                child: Text(option.label),
                                              ),
                                          ],
                                          // Shows how the list is sorted right now.
                                          child: ControlFace(
                                            icon: Icons.swap_vert,
                                            label: filter.sort.label,
                                            trailing: Icons.arrow_drop_down,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (filter.hasFilters || filter.isSearching)
                                  _ActiveFilterChips(
                                    onClearSearch: _clearSearch,
                                  ),
                                if (filter.isSearching && items.isNotEmpty)
                                  _searchSummary(items, symbol),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: items.isEmpty
                              ? _emptyState(filter)
                              : _list(
                                  items,
                                  symbol,
                                  groupByDay: _isDateSort(filter.sort),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _isDateSort(SortOption sort) =>
      sort == SortOption.newestFirst || sort == SortOption.oldestFirst;

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: TextField(
        key: const ValueKey('search-field'),
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        inputFormatters: [LengthLimitingTextInputFormatter(maxSearchLength)],
        decoration: InputDecoration(
          hintText: 'Search notes, categories, amounts',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    key: const ValueKey('search-clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _clearSearch();
                      _searchFocus.requestFocus();
                    },
                  ),
          ),
        ),
        onChanged: _onSearchChanged,
        onSubmitted: (text) {
          _debounce?.cancel();
          ref.read(historyFilterProvider.notifier).setQuery(text);
        },
      ),
    );
  }

  /// "12 results · net -$84.20" under the controls while searching.
  Widget _searchSummary(List<TransactionWithCategory> items, String symbol) {
    final net = items.fold<int>(0, (sum, i) => sum + _signed(i));
    final n = items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$n result${n == 1 ? '' : 's'} · net '
          '${formatMoney(net, symbol, showPlus: true)}',
          key: const ValueKey('search-summary'),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.appColors.dim),
        ),
      ),
    );
  }

  Widget _emptyState(HistoryFilter filter) {
    if (filter.isSearching) {
      return EmptyState(
        icon: Icons.search_off,
        message: ref.watch(copyProvider).noMatches(filter.query.trim()),
        actionLabel: 'Clear search',
        onAction: _clearSearch,
      );
    }
    if (filter.hasFilters) {
      return EmptyState(
        icon: Icons.search_off,
        message: 'No results for these filters.',
        actionLabel: 'Clear filters',
        onAction: ref.read(historyFilterProvider.notifier).clear,
      );
    }
    return EmptyState(
      icon: Icons.show_chart,
      message: ref.watch(copyProvider).emptyHistory,
    );
  }

  /// Rows grouped under sticky day headers. When sorting by amount, days
  /// would repeat, so those sorts show one plain list.
  Widget _list(
    List<TransactionWithCategory> items,
    String symbol, {
    required bool groupByDay,
  }) {
    final c = context.appColors;
    final theme = Theme.of(context);

    Widget row(TransactionWithCategory item) => Dismissible(
      key: ValueKey('tx-${item.transaction.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: c.error.withValues(alpha: 0.16),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: c.error,
          semanticLabel: 'Delete',
        ),
      ),
      onDismissed: (_) => _delete(item),
      child: TransactionTile(
        item: item,
        currencySymbol: symbol,
        highlight: ref.watch(searchQueryProvider),
        onTap: () => showTransactionForm(context, editId: item.transaction.id),
        onLongPress: () => showTransactionMenu(context, ref, item),
      ),
    );

    final slivers = <Widget>[];
    if (!groupByDay) {
      slivers.add(
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => row(items[i]),
        ),
      );
    } else {
      // One pass: consecutive rows with the same date make up a day, and the
      // day's net is summed on the way.
      var start = 0;
      while (start < items.length) {
        final date = items[start].transaction.date;
        var end = start;
        var net = 0;
        while (end < items.length && items[end].transaction.date == date) {
          net += _signed(items[end]);
          end++;
        }
        final count = end - start;
        final day = items.sublist(start, end);
        slivers.add(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: DayHeaderDelegate(
                  label: formatDayHeader(fromIsoDate(date)),
                  // A one-entry day's total would just repeat its row.
                  net: count > 1
                      ? formatMoney(net, symbol, showPlus: true)
                      : null,
                  colors: c,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: c.dim,
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: day.length,
                itemBuilder: (_, i) => row(day[i]),
              ),
            ],
          ),
        );
        start = end;
      }
    }
    // Room to scroll the last row clear of the add key.
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));
    return CustomScrollView(slivers: slivers);
  }

  int _signed(TransactionWithCategory i) =>
      i.transaction.type == TransactionType.income
      ? i.transaction.amountCents
      : -i.transaction.amountCents;
}

/// Removable chips for each active filter.
class _ActiveFilterChips extends ConsumerWidget {
  const _ActiveFilterChips({required this.onClearSearch});

  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final categories = ref.watch(allCategoriesProvider).value ?? const [];
    final period = filter.period;

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (filter.isSearching)
            _chip(
              'search',
              'Search: ${filter.query.trim()}',
              onClearSearch,
              tooltip: 'Remove search',
            ),
          if (filter.type != null)
            _chip(
              'type',
              filter.type == TransactionType.income ? 'Income' : 'Expense',
              () => notifier.setType(null),
            ),
          for (final id in filter.categoryIds)
            _chip(
              'category-$id',
              categories
                      .where((c) => c.id == id)
                      .map((c) => c.name)
                      .firstOrNull ??
                  'Category',
              () => notifier.setCategories({...filter.categoryIds}..remove(id)),
            ),
          if (period != null)
            _chip(
              'period',
              formatRange(rangeOf(period, settings)),
              () => notifier.setPeriod(null),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    String key,
    String label,
    VoidCallback onDeleted, {
    String tooltip = 'Remove filter',
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        key: ValueKey('active-$key'),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: onDeleted,
        deleteButtonTooltipMessage: tooltip,
      ),
    );
  }
}
