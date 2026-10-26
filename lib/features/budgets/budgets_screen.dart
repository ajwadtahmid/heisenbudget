import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../providers/budget_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';
import '../shared/empty_state.dart';
import 'budget_editor.dart';
import 'budget_gauge.dart';

/// "October 2026" for calendar months, otherwise the dates it runs between
/// ("Oct 25 – Nov 24, 2026").
String budgetMonthLabel(BudgetMonth month, int startDay) {
  final range = month.range(startDay);
  return startDay == 1 ? formatMonth(range.start) : formatRange(range);
}

/// Monthly limits and how each is doing.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(selectedBudgetOverviewProvider);
    final current = ref.watch(currentBudgetMonthProvider);
    final selected = ref.watch(selectedBudgetMonthProvider);
    final startDay = ref.watch(monthStartDayProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final offset = ref.watch(budgetMonthOffsetProvider);
    final notifier = ref.read(budgetMonthOffsetProvider.notifier);
    final theme = Theme.of(context);
    final c = context.appColors;
    final isPast = selected < current;

    void edit(BudgetLine line) {
      if (isPast) return;
      showBudgetEditor(
        context,
        categoryId: line.categoryId,
        name: line.category?.name ?? 'All spending',
        currentLimit: line.status.limit,
      );
    }

    Widget body;
    if (overview == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!overview.hasAny) {
      body = _Empty(
        isPast: isPast,
        onSet: () => _showAddLimit(context, overview),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (isPast)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.m),
              child: Text(
                'This month is over, so its limits cannot be changed.',
                key: const ValueKey('budget-past-note'),
                style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
              ),
            ),
          if (overview.overall != null)
            BudgetGauge(
              key: const ValueKey('gauge-overall'),
              name: 'All spending',
              status: overview.overall!.status,
              range: overview.range,
              symbol: symbol,
              onTap: isPast ? null : () => edit(overview.overall!),
            ),
          if (overview.categoriesExceedOverall)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.m),
              child: Text(
                'The category limits add up to '
                '${formatMoney(overview.categoryLimitTotal, symbol)}, more '
                'than the limit on all spending.',
                key: const ValueKey('budget-note'),
                style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
              ),
            ),
          for (final line in overview.lines)
            BudgetGauge(
              key: ValueKey('gauge-${line.categoryId}'),
              name: line.category!.isArchived
                  ? '${line.category!.name} (archived)'
                  : line.category!.name,
              iconKey: categoryIconFor(line.category!.icon).key,
              status: line.status,
              range: overview.range,
              symbol: symbol,
              onTap: isPast ? null : () => edit(line),
            ),
          if (!isPast &&
              (overview.overall == null || overview.withoutLimit.isNotEmpty))
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('budget-add'),
                onPressed: () => _showAddLimit(context, overview),
                icon: const Icon(Icons.add),
                label: const Text('Add a limit'),
              ),
            ),
          const SizedBox(height: Gap.l),
          Text(
            'Every expense dated in the budget month counts, including ones '
            'dated later in it.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Swipe sideways to move between months.
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 250) return;
          notifier.step(v < 0 ? 1 : -1);
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, Gap.m),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  customSemanticsActions: {
                    const CustomSemanticsAction(label: 'Previous month'): () =>
                        notifier.step(-1),
                    const CustomSemanticsAction(label: 'Next month'): () =>
                        notifier.step(1),
                  },
                  child: _MonthMenu(
                    label: budgetMonthLabel(selected, startDay),
                    offset: offset,
                    current: current,
                    startDay: startDay,
                    onSelected: notifier.set,
                  ),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// A sheet to pick what to put a limit on: all spending, or a category
  /// that has none yet.
  Future<void> _showAddLimit(BuildContext context, BudgetOverview overview) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.s),
              child: Text(
                'Put a limit on',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            if (overview.overall == null)
              ListTile(
                key: const ValueKey('budget-pick-overall'),
                leading: const Icon(Icons.functions),
                title: const Text('All spending'),
                subtitle: const Text('One limit for everything you spend'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showBudgetEditor(
                    context,
                    categoryId: null,
                    name: 'All spending',
                    currentLimit: null,
                  );
                },
              ),
            for (final category in overview.withoutLimit)
              ListTile(
                key: ValueKey('budget-pick-${category.id}'),
                leading: CategoryTile(iconKey: category.icon, size: 32),
                title: Text(category.name),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showBudgetEditor(
                    context,
                    categoryId: category.id,
                    name: category.name,
                    currentLimit: null,
                  );
                },
              ),
            const SizedBox(height: Gap.m),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isPast, required this.onSet});

  final bool isPast;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.account_balance_wallet_outlined,
      message: isPast
          ? 'No limits were set for this month.'
          : 'No budgets yet.\nSet a monthly limit for a category, or for all '
                'your spending.',
      actionLabel: isPast ? null : 'Set a limit',
      onAction: isPast ? null : onSet,
    );
  }
}

/// The month shown, as a button that opens a short list of months.
class _MonthMenu extends StatelessWidget {
  const _MonthMenu({
    required this.label,
    required this.offset,
    required this.current,
    required this.startDay,
    required this.onSelected,
  });

  final String label;
  final int offset;
  final BudgetMonth current;
  final int startDay;
  final ValueChanged<int> onSelected;

  static const _offsets = [1, 0, -1, -2, -3, -4, -5];

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    return PopupMenuButton<int>(
      key: const ValueKey('budget-month-menu'),
      tooltip: 'Choose a month',
      initialValue: offset,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final o in {..._offsets, offset})
          CheckedPopupMenuItem(
            key: ValueKey('budget-month-$o'),
            value: o,
            checked: o == offset,
            child: Text(budgetMonthLabel(current.shift(o), startDay)),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: Gap.l),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.input),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                key: const ValueKey('budget-month-label'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
