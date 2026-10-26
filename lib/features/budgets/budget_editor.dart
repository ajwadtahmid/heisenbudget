import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../providers/budget_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_providers.dart';

/// Sets, changes or removes a monthly limit for [categoryId] (null = all
/// spending). [currentLimit] is what applies this budget month, if anything.
///
/// A change always starts **this month or next**, never earlier, so past
/// months stay as they were.
Future<void> showBudgetEditor(
  BuildContext context, {
  required int? categoryId,
  required String name,
  required int? currentLimit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BudgetEditor(
      categoryId: categoryId,
      name: name,
      currentLimit: currentLimit,
    ),
  );
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({
    required this.categoryId,
    required this.name,
    required this.currentLimit,
  });

  final int? categoryId;
  final String name;
  final int? currentLimit;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  bool _fromNext = false;
  bool _saving = false;
  int? _suggestion;

  @override
  void initState() {
    super.initState();
    final limit = widget.currentLimit;
    _amount = TextEditingController(
      text: limit == null ? '' : centsToInputText(limit),
    );
    _loadSuggestion();
  }

  Future<void> _loadSuggestion() async {
    final suggestion = await suggestedLimit(
      repo: ref.read(transactionRepositoryProvider),
      startDay: ref.read(monthStartDayProvider),
      month: ref.read(currentBudgetMonthProvider),
      categoryId: widget.categoryId,
    );
    if (mounted) setState(() => _suggestion = suggestion);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  BudgetMonth get _start {
    final thisMonth = ref.read(currentBudgetMonthProvider);
    return _fromNext ? thisMonth.shift(1) : thisMonth;
  }

  Future<void> _save({required bool remove}) async {
    if (_saving) return;
    if (!remove && !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ref
        .read(budgetRepositoryProvider)
        .setLimit(
          month: _start,
          categoryId: widget.categoryId,
          amountCents: remove ? null : parseMoney(_amount.text).cents,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final startDay = ref.watch(monthStartDayProvider);
    final starts = _start.range(startDay).start;
    final suggestion = _suggestion;

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
                    widget.currentLimit == null
                        ? 'Set a limit'
                        : 'Change the limit',
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
                        labelText: 'Limit per month',
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
                          'Use the average of the last 3 months: '
                          '${formatMoney(suggestion, symbol)}',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.l),
                  Text('Starts', style: theme.textTheme.labelLarge),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: Gap.m,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('budget-from-this'),
                        showCheckmark: false,
                        label: const Text('This month'),
                        selected: !_fromNext,
                        onSelected: (_) => setState(() => _fromNext = false),
                      ),
                      ChoiceChip(
                        key: const ValueKey('budget-from-next'),
                        showCheckmark: false,
                        label: const Text('Next month'),
                        selected: _fromNext,
                        onSelected: (_) => setState(() => _fromNext = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.s),
                  Text(
                    'From ${formatDate(starts)}. Earlier months keep what they had.',
                    key: const ValueKey('budget-starts'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                  const SizedBox(height: Gap.l),
                  FilledButton(
                    key: const ValueKey('budget-save'),
                    onPressed: _saving ? null : () => _save(remove: false),
                    child: const Text('Save'),
                  ),
                  if (widget.currentLimit != null) ...[
                    const SizedBox(height: Gap.s),
                    TextButton(
                      key: const ValueKey('budget-remove'),
                      style: TextButton.styleFrom(foregroundColor: c.error),
                      onPressed: _saving ? null : () => _save(remove: true),
                      child: Text(
                        'Remove the limit from ${_fromNext ? 'next' : 'this'} month on',
                      ),
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
