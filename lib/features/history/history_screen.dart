import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/iso_date.dart';
import '../../domain/sort_option.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/add_key.dart';
import '../shared/empty_state.dart';
import '../shared/transaction_tile.dart';
import '../transaction_form/transaction_form_screen.dart';
import 'filter_sheet.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Swiped-away rows. A Dismissible must leave the tree in the same frame,
  /// but the database stream only updates a moment later, so hide them here.
  final _dismissed = <int>{};

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
    final items = (ref.watch(historyListProvider).value ?? const [])
        .where((i) => !_dismissed.contains(i.transaction.id))
        .toList();

    return Scaffold(
      floatingActionButton: const AddKey(),
      appBar: AppBar(title: const Text('History')),
      body: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ControlFace(
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
                        .read(historyFilterProvider.notifier)
                        .setSort,
                    itemBuilder: (_) => [
                      for (final option in SortOption.values)
                        CheckedPopupMenuItem(
                          value: option,
                          checked: option == filter.sort,
                          child: Text(option.label),
                        ),
                    ],
                    // Shows how the list is sorted right now.
                    child: _ControlFace(
                      icon: Icons.swap_vert,
                      label: filter.sort.label,
                      trailing: Icons.arrow_drop_down,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (filter.hasFilters) const _ActiveFilterChips(),
          Expanded(
            child: items.isEmpty
                ? _emptyState(filter)
                : _list(items, symbol, groupByDay: _isDateSort(filter.sort)),
          ),
        ],
      ),
    );
  }

  bool _isDateSort(SortOption sort) =>
      sort == SortOption.newestFirst || sort == SortOption.oldestFirst;

  Widget _emptyState(HistoryFilter filter) {
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
        onTap: () => showTransactionForm(context, editId: item.transaction.id),
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
                delegate: _DayHeaderDelegate(
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

/// A day's date and net total. Pinned: it stays at the top while that day's
/// rows scroll under it, then the next day pushes it away.
class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DayHeaderDelegate({
    required this.label,
    required this.net,
    required this.colors,
    required this.labelStyle,
  });

  final String label;
  final String? net;
  final AppColors colors;
  final TextStyle? labelStyle;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          if (net != null) ...[
            const SizedBox(width: 12),
            Text(net!, style: monoText(size: 14, color: colors.dim)),
          ],
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate old) =>
      label != old.label ||
      net != old.net ||
      !identical(colors, old.colors) ||
      labelStyle != old.labelStyle;
}

/// Removable chips for each active filter.
class _ActiveFilterChips extends ConsumerWidget {
  const _ActiveFilterChips();

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

  Widget _chip(String key, String label, VoidCallback onDeleted) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        key: ValueKey('active-$key'),
        label: Text(label),
        onDeleted: onDeleted,
        deleteButtonTooltipMessage: 'Remove filter',
      ),
    );
  }
}

/// An outlined 48dp control: icon, a label, and an optional trailing icon.
/// Used for the Filter and Sort controls under the History title. Passing
/// [onTap] makes it a button; inside a PopupMenuButton the menu handles taps.
class _ControlFace extends StatelessWidget {
  const _ControlFace({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.trailing,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final IconData? trailing;
  final VoidCallback? onTap;

  /// Draws the border and icon in the accent (an active filter).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final face = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: 12, right: trailing == null ? 14 : 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.input),
        border: Border.all(
          color: highlighted ? c.accent : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: highlighted ? c.accent : c.dim),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: highlighted ? c.accent : c.text),
            ),
          ),
          if (trailing != null) Icon(trailing, color: c.dim),
        ],
      ),
    );
    if (onTap == null) return face;
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.input),
        onTap: onTap,
        child: face,
      ),
    );
  }
}
