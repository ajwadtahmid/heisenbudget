import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../domain/date_range.dart';
import '../../domain/iso_date.dart';
import '../../providers/budget_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';

/// Sets, changes or stops a budget for [categoryId] (null = all spending).
///
/// [current] is the budget in force now, if any. A change always starts with
/// the current period, so earlier periods keep what they had.
Future<void> showBudgetEditor(
  BuildContext context, {
  required int? categoryId,
  required String name,
  BudgetLine? current,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _BudgetEditor(categoryId: categoryId, name: name, current: current),
  );
}

String _plural(BudgetUnit unit) => switch (unit) {
  BudgetUnit.week => 'weeks',
  BudgetUnit.fortnight => '2-week periods',
  BudgetUnit.month => 'months',
};

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({
    required this.categoryId,
    required this.name,
    required this.current,
  });

  final int? categoryId;
  final String name;
  final BudgetLine? current;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late BudgetUnit _unit;
  late bool _repeats;

  /// The first day of the fortnight cycle, when picked by hand.
  DateTime? _fortnightFirstDay;
  bool _saving = false;
  int? _suggestion;

  BudgetLine? get _current => widget.current;

  @override
  void initState() {
    super.initState();
    final current = _current;
    _unit = current?.unit ?? BudgetUnit.month;
    _repeats = current?.entry.repeats ?? true;
    _amount = TextEditingController(
      text: current == null ? '' : centsToInputText(current.status.limit),
    );
    _loadSuggestion();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The period this change starts with: the current one of the existing
  /// budget when its period is not being changed (keeping its alignment),
  /// otherwise the current period of the chosen kind.
  DateRange get _range {
    final current = _current;
    if (current != null &&
        current.unit == _unit &&
        _fortnightFirstDay == null) {
      return current.range;
    }
    return currentRangeFor(
      _unit,
      ref.read(clockProvider),
      monthStartDay: ref.read(monthStartDayProvider),
      weekStartDay: ref.read(weekStartDayProvider),
      anchor: _unit == BudgetUnit.fortnight ? _fortnightFirstDay : null,
    );
  }

  Future<void> _loadSuggestion() async {
    final range = _range;
    final unit = _unit;
    final suggestion = await suggestedLimit(
      repo: ref.read(transactionRepositoryProvider),
      unit: unit,
      current: range,
      monthStartDay: ref.read(monthStartDayProvider),
      categoryId: widget.categoryId,
    );
    // The period may have been changed while this was working out.
    if (mounted && unit == _unit) setState(() => _suggestion = suggestion);
  }

  void _setUnit(BudgetUnit unit) {
    if (unit == _unit) return;
    setState(() {
      _unit = unit;
      _suggestion = null;
      _fortnightFirstDay = null;
    });
    _loadSuggestion();
  }

  Future<void> _pickFirstDay() async {
    final today = ref.read(clockProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _range.start,
      firstDate: DateTime(today.year, today.month, today.day - 13),
      lastDate: today,
      helpText: 'First day of a two-week period',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fortnightFirstDay = dateOnly(picked);
      _suggestion = null;
    });
    _loadSuggestion();
  }

  Future<void> _save({required bool stop}) async {
    if (_saving) return;
    if (!stop && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(budgetRepositoryProvider);
    if (stop) {
      final current = _current!;
      await repo.setLimit(
        start: current.range.start,
        unit: current.unit,
        categoryId: widget.categoryId,
        amountCents: null,
      );
    } else {
      await repo.setLimit(
        start: _range.start,
        unit: _unit,
        repeats: _repeats,
        categoryId: widget.categoryId,
        amountCents: parseMoney(_amount.text).cents,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final range = _range;
    final suggestion = _suggestion;
    final isNew = _current == null;
    final showFirstDay =
        _unit == BudgetUnit.fortnight &&
        (isNew || _current!.unit != BudgetUnit.fortnight);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isNew ? 'Set a limit' : 'Change the limit',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(widget.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Gap.m),
                  ClampedTextScale(
                    child: TextFormField(
                      key: const ValueKey('budget-amount'),
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                      ],
                      style: monoText(
                        size: 28,
                        weight: FontWeight.w600,
                        color: c.text,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Limit',
                        prefixText: '$symbol ',
                        prefixStyle: monoText(
                          size: 28,
                          weight: FontWeight.w500,
                          color: c.dim,
                        ),
                      ),
                      validator: (v) => parseMoney(v ?? '').error,
                    ),
                  ),
                  const SizedBox(height: Gap.l),
                  Text('Per', style: theme.textTheme.labelLarge),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: Gap.m,
                    children: [
                      for (final unit in BudgetUnit.values)
                        ChoiceChip(
                          key: ValueKey('budget-unit-${unit.name}'),
                          showCheckmark: false,
                          label: Text(unit.label),
                          selected: _unit == unit,
                          onSelected: (_) => _setUnit(unit),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.m),
                  Wrap(
                    spacing: Gap.m,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('budget-repeats'),
                        showCheckmark: false,
                        label: const Text('Keeps repeating'),
                        selected: _repeats,
                        onSelected: (_) => setState(() => _repeats = true),
                      ),
                      ChoiceChip(
                        key: const ValueKey('budget-once'),
                        showCheckmark: false,
                        label: Text('Just this ${_unit.noun}'),
                        selected: !_repeats,
                        onSelected: (_) => setState(() => _repeats = false),
                      ),
                    ],
                  ),
                  if (showFirstDay) ...[
                    const SizedBox(height: Gap.s),
                    ListTile(
                      key: const ValueKey('budget-first-day'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('First day of a two-week period'),
                      subtitle: Text(formatDate(range.start)),
                      onTap: _pickFirstDay,
                    ),
                  ],
                  if (suggestion != null) ...[
                    const SizedBox(height: Gap.s),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: const ValueKey('budget-suggest'),
                        onPressed: () => setState(
                          () => _amount.text = centsToInputText(suggestion),
                        ),
                        child: Text(
                          'Use the average of the last 3 ${_plural(_unit)}: '
                          '${formatMoney(suggestion, symbol)}',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.m),
                  Text(
                    'Applies from this ${_unit.noun}: ${formatRange(range)}. '
                    'Earlier ones keep what they had.',
                    key: const ValueKey('budget-starts'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                  const SizedBox(height: Gap.l),
                  FilledButton(
                    key: const ValueKey('budget-save'),
                    onPressed: _saving ? null : () => _save(stop: false),
                    child: const Text('Save'),
                  ),
                  if (!isNew) ...[
                    const SizedBox(height: Gap.s),
                    TextButton(
                      key: const ValueKey('budget-remove'),
                      style: TextButton.styleFrom(foregroundColor: c.error),
                      onPressed: _saving ? null : () => _save(stop: true),
                      child: const Text('Stop this budget'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
