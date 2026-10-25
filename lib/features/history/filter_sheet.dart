import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../data/database/app_database.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/transaction_providers.dart';
import '../shared/period_selector.dart';

Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FilterSheet(),
  );
}

/// What the type selector can show; null in the filter means "All".
enum _TypeChoice { all, income, expense }

/// Filters apply as soon as they are changed, so there is no Apply button.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final all = ref.watch(allCategoriesProvider).value ?? const [];
    final used = ref.watch(usedCategoryIdsProvider).value ?? const <int>{};

    // Archived categories are only worth filtering by if they have history.
    bool offered(CategoryRow c) => !c.isArchived || used.contains(c.id);

    List<CategoryRow> forType(TransactionType type) =>
        all.where((c) => c.type == type && offered(c)).toList();

    void setType(TransactionType? type) {
      notifier.setType(type);
      if (type != null) {
        // Drop selected categories that belong to the other type.
        final keep = {for (final c in forType(type)) c.id};
        notifier.setCategories(filter.categoryIds.intersection(keep));
      }
    }

    void toggle(CategoryRow c) {
      final ids = {...filter.categoryIds};
      ids.contains(c.id) ? ids.remove(c.id) : ids.add(c.id);
      notifier.setCategories(ids);
    }

    final typeChoice = switch (filter.type) {
      null => _TypeChoice.all,
      TransactionType.income => _TypeChoice.income,
      TransactionType.expense => _TypeChoice.expense,
    };
    final sections = [
      if (filter.type != TransactionType.expense)
        ('Income categories', forType(TransactionType.income)),
      if (filter.type != TransactionType.income)
        ('Expense categories', forType(TransactionType.expense)),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<_TypeChoice>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _TypeChoice.all, label: Text('All')),
                ButtonSegment(value: _TypeChoice.income, label: Text('Income')),
                ButtonSegment(
                  value: _TypeChoice.expense,
                  label: Text('Expense'),
                ),
              ],
              selected: {typeChoice},
              onSelectionChanged: (s) => setType(switch (s.first) {
                _TypeChoice.all => null,
                _TypeChoice.income => TransactionType.income,
                _TypeChoice.expense => TransactionType.expense,
              }),
            ),
            const SizedBox(height: 16),
            Text('Date range', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            PeriodChips(
              period: filter.period,
              today: ref.watch(clockProvider),
              weekMode: settings.weekMode,
              weekStartDay: settings.weekStartDay,
              onChanged: notifier.setPeriod,
            ),
            for (final (title, categories) in sections) ...[
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    FilterChip(
                      key: ValueKey('filter-category-${c.id}'),
                      avatar: Icon(categoryIconFor(c.icon).icon, size: 18),
                      label: Text(
                        c.isArchived ? '${c.name} (archived)' : c.name,
                      ),
                      selected: filter.categoryIds.contains(c.id),
                      onSelected: (_) => toggle(c),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                // Expanded so long labels (large text) wrap instead of overflowing.
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
