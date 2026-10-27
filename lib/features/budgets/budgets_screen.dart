import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/budget_history_providers.dart';
import '../../providers/budget_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';
import '../shared/empty_state.dart';
import 'budget_editor.dart';
import 'budget_gauge.dart';

/// Every budget in force now: a gauge for the current period of each, the ones
/// in trouble first. Earlier periods are in History > Budgets.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  /// Opens History on its Budgets side.
  static void showPast(WidgetRef ref) {
    ref.read(historyModeProvider.notifier).set(HistoryMode.budgets);
    ref.read(shellTabProvider.notifier).select(historyTab);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(budgetOverviewProvider);
    final overview = loaded.value;
    final startDay = ref.watch(monthStartDayProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final theme = Theme.of(context);
    final c = context.appColors;

    void edit(BudgetLine line) {
      showBudgetEditor(
        context,
        categoryId: line.categoryId,
        name: line.category?.name ?? 'All spending',
        current: line,
      );
    }

    final Widget body;
    if (loaded.hasError) {
      body = EmptyState(
        key: const ValueKey('budgets-error'),
        icon: Icons.error_outline,
        message: 'Could not load your budgets.',
        actionLabel: 'Try again',
        onAction: () => reloadBudgets(ref),
      );
    } else if (overview == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!overview.hasAny) {
      body = EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        message:
            'No budgets right now.\nSet a limit for a category, or for all '
            'your spending, per month or for a length you choose.',
        actionLabel: 'Set a limit',
        onAction: () => _showAddLimit(context, overview),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (overview.overall != null)
            BudgetGauge(
              key: const ValueKey('gauge-overall'),
              name: 'All spending',
              periodLabel: budgetPeriodLabel(
                overview.overall!.entry,
                overview.overall!.range,
                startDay,
              ),
              status: overview.overall!.status,
              range: overview.overall!.range,
              symbol: symbol,
              onTap: () => edit(overview.overall!),
            ),
          if (overview.categoriesExceedOverall)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.m),
              child: Text(
                'The category limits add up to '
                '${formatMoney(overview.sameUnitCategoryTotal, symbol)}, more '
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
              periodLabel: budgetPeriodLabel(line.entry, line.range, startDay),
              iconKey: categoryIconFor(line.category!.icon).key,
              status: line.status,
              range: line.range,
              symbol: symbol,
              onTap: () => edit(line),
            ),
          Wrap(
            spacing: Gap.m,
            runSpacing: Gap.s,
            children: [
              if (overview.overall == null || overview.withoutLimit.isNotEmpty)
                OutlinedButton.icon(
                  key: const ValueKey('budget-add'),
                  onPressed: () => _showAddLimit(context, overview),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a limit'),
                ),
            ],
          ),
          const SizedBox(height: Gap.l),
          Text(
            'Every expense dated inside the period counts, including ones '
            'dated later in it.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
          const SizedBox(height: Gap.s),
          TextButton.icon(
            key: const ValueKey('budgets-past-link'),
            onPressed: () => showPast(ref),
            icon: const Icon(Icons.history),
            label: const Text('Past budgets'),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            key: const ValueKey('budgets-past'),
            tooltip: 'Past budgets',
            icon: const Icon(Icons.history),
            onPressed: () => showPast(ref),
          ),
        ],
      ),
      body: body,
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
