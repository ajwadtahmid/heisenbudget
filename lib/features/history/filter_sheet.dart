import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/saved_filter.dart';
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
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final _min = TextEditingController(
    text: _text(ref.read(historyFilterProvider).minCents),
  );
  late final _max = TextEditingController(
    text: _text(ref.read(historyFilterProvider).maxCents),
  );
  String? _minError;
  String? _maxError;

  static String _text(int? cents) =>
      cents == null ? '' : centsToInputText(cents);

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// The cents in [text]: null when empty, [_bad] when not an amount.
  static const _bad = -1;
  static int? _read(String text) {
    if (text.trim().isEmpty) return null;
    return parseMoney(text).cents ?? _bad;
  }

  /// Applies the two fields once both read as amounts and agree. An empty
  /// field is no bound.
  void _amountChanged() {
    final min = _read(_min.text);
    final max = _read(_max.text);
    String? minError;
    String? maxError;
    if (min == _bad) minError = 'Enter a valid amount';
    if (max == _bad) maxError = 'Enter a valid amount';
    if (minError == null &&
        maxError == null &&
        min != null &&
        max != null &&
        min > max) {
      maxError = 'The maximum is below the minimum';
    }
    setState(() {
      _minError = minError;
      _maxError = maxError;
    });
    if (minError == null && maxError == null) {
      ref.read(historyFilterProvider.notifier).setAmountRange(min, max);
    }
  }

  /// Keeps the fields in step when the filter changes elsewhere (Clear
  /// filters, a saved filter, or the chip on the History screen).
  void _syncFields(int? min, int? max) {
    if (_read(_min.text) != min) {
      _min.text = _text(min);
      _minError = null;
    }
    if (_read(_max.text) != max) {
      _max.text = _text(max);
      _maxError = null;
    }
  }

  Future<void> _saveCurrent() async {
    final settings = ref.read(settingsProvider);
    final saved = settings.savedFilters;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveFilterDialog(existing: saved),
    );
    if (name == null || !mounted) return;
    final filter = ref.read(historyFilterProvider);
    final made = savedFilterOf(filter, name, settings, ref.read(clockProvider));
    final updated = SavedFilter.upsert(saved, made);
    if (updated == null) return;
    await ref.read(settingsProvider.notifier).setSavedFilters(updated);
  }

  void _apply(SavedFilter saved) {
    ref
        .read(historyFilterProvider.notifier)
        .replace(historyFilterOf(saved, ref.read(clockProvider)));
    Navigator.of(context).pop();
  }

  Future<void> _delete(SavedFilter saved) {
    final kept = [
      for (final f in ref.read(settingsProvider).savedFilters)
        if (f.name != saved.name) f,
    ];
    return ref.read(settingsProvider.notifier).setSavedFilters(kept);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      historyFilterProvider.select((f) => (f.minCents, f.maxCents)),
      (_, range) => _syncFields(range.$1, range.$2),
    );
    final filter = ref.watch(historyFilterProvider);
    final notifier = ref.read(historyFilterProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final all = ref.watch(allCategoriesProvider).value ?? const [];
    final used = ref.watch(usedCategoryIdsProvider).value ?? const <int>{};
    final savedFilters = settings.savedFilters;

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
            const SizedBox(height: 16),
            Text('Amount', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _amountField('amount-min', 'At least', _min)),
                const SizedBox(width: 12),
                Expanded(child: _amountField('amount-max', 'At most', _max)),
              ],
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
            Text(
              'Saved filters',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (savedFilters.isEmpty)
              Text(
                'Keep a set of filters you use often, then bring it back in '
                'one tap.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.appColors.dim),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < savedFilters.length; i++)
                    InputChip(
                      key: ValueKey('saved-filter-$i'),
                      avatar: const Icon(Icons.bookmark_outline, size: 18),
                      label: Text(savedFilters[i].name),
                      onPressed: () => _apply(savedFilters[i]),
                      onDeleted: () => _delete(savedFilters[i]),
                      deleteButtonTooltipMessage:
                          'Delete "${savedFilters[i].name}"',
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('save-filter'),
                onPressed: filter.withJump(null).hasFilters
                    ? _saveCurrent
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save these filters'),
              ),
            ),
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

  Widget _amountField(String key, String label, TextEditingController c) {
    final error = key == 'amount-min' ? _minError : _maxError;
    return TextField(
      key: ValueKey(key),
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${ref.watch(settingsProvider).currencySymbol} ',
        errorText: error,
        errorMaxLines: 2,
      ),
      onChanged: (_) => _amountChanged(),
    );
  }
}

/// Asks for a name for the filters being saved. A name already in use
/// replaces that filter; a full list refuses a new name.
class _SaveFilterDialog extends StatefulWidget {
  const _SaveFilterDialog({required this.existing});

  final List<SavedFilter> existing;

  @override
  State<_SaveFilterDialog> createState() => _SaveFilterDialogState();
}

class _SaveFilterDialogState extends State<_SaveFilterDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final key = name.toLowerCase();
    final replaces = widget.existing.any((f) => f.name.toLowerCase() == key);
    if (!replaces && widget.existing.length >= maxSavedFilters) {
      setState(
        () => _error =
            'You can keep up to $maxSavedFilters saved filters. Delete one '
            'first.',
      );
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save these filters'),
      content: TextField(
        key: const ValueKey('saved-filter-name'),
        controller: _controller,
        autofocus: true,
        maxLength: maxSavedFilterNameLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          key: const ValueKey('saved-filter-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('saved-filter-save'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
