import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../providers/budget_history_providers.dart';
import '../../providers/budget_providers.dart';
import '../../providers/settings_providers.dart';
import '../budgets/budget_gauge.dart';
import '../shared/empty_state.dart';
import 'history_widgets.dart';

/// The Budgets side of History: every finished budget period, newest first,
/// with its own Filter and Sort under the pill. Read-only.
class BudgetHistoryView extends ConsumerWidget {
  const BudgetHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(budgetHistoryFilterProvider);
    final rows = ref.watch(budgetHistoryProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final startDay = ref.watch(monthStartDayProvider);
    final theme = Theme.of(context);
    final c = context.appColors;
    final notifier = ref.read(budgetHistoryFilterProvider.notifier);

    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          // Controls scroll if they ever need more than half the screen.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.5),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ControlFace(
                            key: const ValueKey('budget-filter-button'),
                            tooltip: 'Filter',
                            icon: Icons.filter_list,
                            label: filter.activeCount > 0
                                ? 'Filter · ${filter.activeCount}'
                                : 'Filter',
                            highlighted: filter.hasFilters,
                            onTap: () => showBudgetHistoryFilterSheet(context),
                          ),
                          PopupMenuButton<BudgetSort>(
                            key: const ValueKey('budget-sort-button'),
                            tooltip: 'Sort',
                            initialValue: filter.sort,
                            onSelected: notifier.setSort,
                            itemBuilder: (_) => [
                              for (final option in BudgetSort.values)
                                CheckedPopupMenuItem(
                                  value: option,
                                  checked: option == filter.sort,
                                  child: Text(option.label),
                                ),
                            ],
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
                  if (filter.hasFilters) const _ActiveChips(),
                ],
              ),
            ),
          ),
          Expanded(
            child: rows.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const EmptyState(
                icon: Icons.error_outline,
                message: 'Could not load past budgets.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return filter.hasFilters
                      ? EmptyState(
                          icon: Icons.search_off,
                          message: 'No results for these filters.',
                          actionLabel: 'Clear filters',
                          onAction: notifier.clear,
                        )
                      : const EmptyState(
                          icon: Icons.history,
                          message:
                              'No past budgets yet.\nFinished weeks, months '
                              'and one-time budgets appear here.',
                        );
                }
                return _List(
                  rows: list,
                  symbol: symbol,
                  startDay: startDay,
                  theme: theme,
                  colors: c,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({
    required this.rows,
    required this.symbol,
    required this.startDay,
    required this.theme,
    required this.colors,
  });

  final List<PastBudget> rows;
  final String symbol;
  final int startDay;
  final ThemeData theme;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group by the month each period ended in, for the headers; the order
    // within the list is the chosen sort.
    final slivers = <Widget>[];
    var start = 0;
    String monthOf(PastBudget b) => formatMonth(b.range.end);
    final grouped = ref.watch(
      budgetHistoryFilterProvider.select(
        (f) => f.sort == BudgetSort.newest || f.sort == BudgetSort.oldest,
      ),
    );

    Widget tile(PastBudget b) {
      final status = buildBudgetStatus(
        limit: b.limit,
        spent: b.spent,
        range: b.range,
        today: DateTime(
          b.range.end.year,
          b.range.end.month,
          b.range.end.day + 1,
        ),
      );
      return BudgetGauge(
        key: ValueKey(
          'past-${b.categoryId ?? 0}-${b.range.start.toIso8601String()}',
        ),
        name: b.category == null
            ? 'All spending'
            : (b.category!.isArchived
                  ? '${b.category!.name} (archived)'
                  : b.category!.name),
        iconKey: b.category == null
            ? null
            : categoryIconFor(b.category!.icon).key,
        periodLabel: budgetPeriodLabel(b.entry, b.range, startDay),
        status: status,
        range: b.range,
        symbol: symbol,
        finished: true,
      );
    }

    if (!grouped) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => tile(rows[i]),
          ),
        ),
      );
    } else {
      while (start < rows.length) {
        final month = monthOf(rows[start]);
        var end = start;
        while (end < rows.length && monthOf(rows[end]) == month) {
          end++;
        }
        final group = rows.sublist(start, end);
        slivers.add(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: DayHeaderDelegate(
                  label: month,
                  net: null,
                  colors: colors,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    color: colors.dim,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList.builder(
                  itemCount: group.length,
                  itemBuilder: (_, i) => tile(group[i]),
                ),
              ),
            ],
          ),
        );
        start = end;
      }
    }

    // "Show more" when any budget has as many periods loaded as were asked for.
    final perBudget = ref.watch(budgetHistoryCountProvider);
    final counts = <int?, int>{};
    for (final b
        in ref.watch(pastBudgetsProvider(perBudget)).value ??
            const <PastBudget>[]) {
      counts[b.categoryId] = (counts[b.categoryId] ?? 0) + 1;
    }
    final mayHaveMore = counts.values.any((n) => n >= perBudget);
    slivers.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: mayHaveMore
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const ValueKey('budget-history-more'),
                    onPressed: ref
                        .read(budgetHistoryCountProvider.notifier)
                        .more,
                    child: const Text('Show more'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    return CustomScrollView(slivers: slivers);
  }
}

/// Removable chips for each active budget filter.
class _ActiveChips extends ConsumerWidget {
  const _ActiveChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(budgetHistoryFilterProvider);
    final notifier = ref.read(budgetHistoryFilterProvider.notifier);
    final names = ref.watch(_budgetNamesProvider);

    Widget chip(String key, String label, VoidCallback onDeleted) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        key: ValueKey('budget-active-$key'),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: onDeleted,
        deleteButtonTooltipMessage: 'Remove filter',
      ),
    );

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (filter.period != PeriodFilter.all)
            chip(
              'period',
              filter.period.label,
              () => notifier.setPeriod(PeriodFilter.all),
            ),
          if (filter.result != ResultFilter.all)
            chip(
              'result',
              filter.result.label,
              () => notifier.setResult(ResultFilter.all),
            ),
          for (final id in filter.targets)
            chip(
              'target-$id',
              names[id] ?? 'Budget',
              () => notifier.setTargets({...filter.targets}..remove(id)),
            ),
        ],
      ),
    );
  }
}

/// Names for the budgets that have history, keyed by target id.
final _budgetNamesProvider = Provider<Map<int, String>>((ref) {
  final all =
      ref
          .watch(pastBudgetsProvider(ref.watch(budgetHistoryCountProvider)))
          .value ??
      const [];
  return {
    for (final b in all)
      b.categoryId ?? overallTargetId: b.category?.name ?? 'All spending',
  };
});

/// The filter sheet for past budgets: period, result and which budgets.
Future<void> showBudgetHistoryFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _BudgetFilterSheet(),
  );
}

class _BudgetFilterSheet extends ConsumerWidget {
  const _BudgetFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(budgetHistoryFilterProvider);
    final notifier = ref.read(budgetHistoryFilterProvider.notifier);
    final names = ref.watch(_budgetNamesProvider);
    final theme = Theme.of(context);

    // "All spending" first, then categories by name.
    final ids = names.keys.toList()
      ..sort((a, b) {
        if (a == overallTargetId) return -1;
        if (b == overallTargetId) return 1;
        return names[a]!.compareTo(names[b]!);
      });

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Period', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in PeriodFilter.values)
                  ChoiceChip(
                    key: ValueKey('budget-filter-period-${p.name}'),
                    showCheckmark: false,
                    label: Text(p.label),
                    selected: filter.period == p,
                    onSelected: (_) => notifier.setPeriod(p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Result', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in ResultFilter.values)
                  ChoiceChip(
                    key: ValueKey('budget-filter-result-${r.name}'),
                    showCheckmark: false,
                    label: Text(r.label),
                    selected: filter.result == r,
                    onSelected: (_) => notifier.setResult(r),
                  ),
              ],
            ),
            if (ids.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Budgets', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in ids)
                    FilterChip(
                      key: ValueKey('budget-filter-target-$id'),
                      label: Text(names[id]!),
                      selected: filter.targets.contains(id),
                      onSelected: (on) {
                        final next = {...filter.targets};
                        on ? next.add(id) : next.remove(id);
                        notifier.setTargets(next);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: filter.hasFilters ? notifier.clear : null,
                      child: const Text('Clear filters'),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
