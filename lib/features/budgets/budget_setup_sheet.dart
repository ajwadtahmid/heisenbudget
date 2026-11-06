import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../domain/budget.dart';
import '../../domain/date_range.dart';
import '../../providers/budget_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';

/// Sets a monthly limit on several categories in one go. Each category that
/// has spending in the last three months starts ticked, with the average of
/// those months filled in; the rest start empty. Nothing is saved until Save,
/// and then all of it is saved together or not at all.
Future<void> showBudgetSetup(
  BuildContext context,
  List<CategoryRow> categories,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BudgetSetup(categories: categories),
  );
}

class _BudgetSetup extends ConsumerStatefulWidget {
  const _BudgetSetup({required this.categories});

  final List<CategoryRow> categories;

  @override
  ConsumerState<_BudgetSetup> createState() => _BudgetSetupState();
}

class _BudgetSetupState extends ConsumerState<_BudgetSetup> {
  late final Map<int, TextEditingController> _amounts;
  final _ticked = <int>{};
  final _errors = <int, String>{};
  bool _loading = true;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _amounts = {
      for (final c in widget.categories) c.id: TextEditingController(),
    };
    _loadSuggestions();
  }

  @override
  void dispose() {
    for (final controller in _amounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  DateRange get _range => currentRangeFor(
    BudgetUnit.month,
    ref.read(clockProvider),
    monthStartDay: ref.read(monthStartDayProvider),
    weekStartDay: ref.read(weekStartDayProvider),
  );

  Future<void> _loadSuggestions() async {
    final repo = ref.read(transactionRepositoryProvider);
    final startDay = ref.read(monthStartDayProvider);
    final range = _range;
    final found = <int, int>{};
    try {
      for (final c in widget.categories) {
        final cents = await suggestedLimit(
          repo: repo,
          unit: BudgetUnit.month,
          current: range,
          monthStartDay: startDay,
          categoryId: c.id,
        );
        if (cents != null) found[c.id] = cents;
      }
    } catch (_) {
      // No suggestions is fine: the amounts can still be typed.
    }
    if (!mounted) return;
    setState(() {
      for (final entry in found.entries) {
        _amounts[entry.key]!.text = centsToInputText(entry.value);
        _ticked.add(entry.key);
      }
      _loading = false;
    });
  }

  void _toggle(int id, bool on) {
    setState(() {
      on ? _ticked.add(id) : _ticked.remove(id);
      _errors.remove(id);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final cents = <int, int>{};
    final errors = <int, String>{};
    for (final id in _ticked) {
      final parsed = parseMoney(_amounts[id]!.text);
      if (parsed.cents == null) {
        errors[id] = parsed.error!;
      } else {
        cents[id] = parsed.cents!;
      }
    }
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty || cents.isEmpty) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    final repo = ref.read(budgetRepositoryProvider);
    final today = ref.read(clockProvider);
    final start = _range.start;
    try {
      await ref.read(appDatabaseProvider).transaction(() async {
        for (final entry in cents.entries) {
          await repo.setLimit(
            start: start,
            unit: BudgetUnit.month,
            categoryId: entry.key,
            amountCents: entry.value,
            today: today,
          );
        }
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Nothing was saved. Stay open so what was typed is kept.
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Could not save these limits. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final count = _ticked.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.xs),
            child: Text(
              'Set several limits',
              style: theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.s),
            child: Text(
              'Monthly limits, starting this month. Amounts are the average of '
              'the last three months where there was spending. Untick what '
              'you do not want a limit on.',
              style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(Gap.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final category in widget.categories)
                    _row(category, symbol),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, Gap.s, 20, Gap.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_saveError != null) ...[
                  Text(
                    _saveError!,
                    key: const ValueKey('setup-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: Gap.s),
                ],
                FilledButton(
                  key: const ValueKey('setup-save'),
                  onPressed: _saving || _loading || count == 0 ? null : _save,
                  child: Text(
                    count == 1 ? 'Save 1 limit' : 'Save $count limits',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(CategoryRow category, String symbol) {
    final id = category.id;
    final on = _ticked.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('setup-tick-$id'),
            value: on,
            onChanged: (v) => _toggle(id, v ?? false),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CategoryTile(iconKey: category.icon, size: 32),
          ),
          const SizedBox(width: Gap.m),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(category.name),
            ),
          ),
          const SizedBox(width: Gap.m),
          SizedBox(
            width: 124,
            child: ClampedTextScale(
              child: TextField(
                key: ValueKey('setup-amount-$id'),
                controller: _amounts[id],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  prefixText: symbol,
                  hintText: 'Amount',
                  errorText: _errors[id],
                  errorMaxLines: 2,
                  isDense: true,
                ),
                onChanged: (text) {
                  // Typing an amount means the person wants the limit.
                  if (text.trim().isNotEmpty && !_ticked.contains(id)) {
                    _toggle(id, true);
                  } else if (_errors.containsKey(id)) {
                    setState(() => _errors.remove(id));
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: Gap.s),
        ],
      ),
    );
  }
}
