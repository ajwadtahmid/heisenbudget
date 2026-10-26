import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
import '../../core/constants.dart';
import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../../domain/iso_date.dart';
import '../../domain/recurrence.dart';
import '../../domain/transaction_type.dart';
import '../../providers/category_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/recurring_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/recurring_catch_up.dart';
import '../transaction_form/repeat_sheet.dart';

/// Edit one repeating rule. Changes apply to transactions added from now on;
/// the ones already in History are left as they are.
class RecurringEditorScreen extends ConsumerWidget {
  const RecurringEditorScreen({super.key, required this.ruleId});

  final int ruleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider);
    RecurringRuleRow? rule;
    for (final r in rules.value ?? const <RecurringRuleRow>[]) {
      if (r.id == ruleId) rule = r;
    }
    Widget message(Widget child) => Scaffold(
      appBar: AppBar(title: const Text('Repeating transaction')),
      body: Center(child: child),
    );
    if (rule == null) {
      return rules.isLoading
          ? message(const CircularProgressIndicator())
          : message(const Text('This repeating transaction was deleted.'));
    }
    return _Editor(key: ValueKey(ruleId), rule: rule);
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.rule});

  final RecurringRuleRow rule;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late int _categoryId;
  late RepeatChoice _choice;

  /// The date the user picked for the next transaction; null = unchanged.
  DateTime? _pickedNext;
  bool _busy = false;

  RecurringRuleRow get _rule => widget.rule;

  @override
  void initState() {
    super.initState();
    final rule = _rule;
    _amount = TextEditingController(text: centsToInputText(rule.amountCents));
    _note = TextEditingController(text: rule.note ?? '');
    _categoryId = rule.categoryId;
    _choice = RepeatChoice(
      unit: rule.unit,
      interval: rule.interval,
      end: rule.endDate == null ? null : fromIsoDate(rule.endDate!),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// What the screen shows as the next date.
  DateTime? get _shownNext => _pickedNext ?? _rule.nextDate;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickRepeat() async {
    final result = await showRepeatSheet(
      context,
      start: _shownNext ?? ref.read(clockProvider),
      current: _choice,
      allowNone: false,
    );
    final choice = result?.choice;
    if (choice != null && mounted) setState(() => _choice = choice);
  }

  Future<void> _pickNext() async {
    final today = ref.read(clockProvider);
    final shown = _shownNext;
    final picked = await showDatePicker(
      context: context,
      initialDate: shown != null && !shown.isBefore(today) ? shown : today,
      firstDate: today,
      lastDate: DateTime(2100),
      helpText: 'Next transaction on',
    );
    if (picked != null && mounted) {
      setState(() => _pickedNext = dateOnly(picked));
    }
  }

  String? get _endError {
    final end = _choice.end;
    final start = _shownNext;
    if (end != null && start != null && end.isBefore(start)) {
      return 'The end date is before the next date.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate() || _endError != null) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    final rule = _rule;
    final today = ref.read(clockProvider);
    final scheduleChanged =
        _choice.unit != rule.unit || _choice.interval != rule.interval;
    final reanchor = scheduleChanged || _pickedNext != null;
    final start = reanchor
        ? (_shownNext ?? today)
        : fromIsoDate(rule.startDate);
    await ref
        .read(recurringRepositoryProvider)
        .update(
          rule.id,
          RecurringInput(
            amountCents: parseMoney(_amount.text).cents!,
            type: rule.type,
            categoryId: _categoryId,
            note: _note.text,
            unit: _choice.unit,
            interval: _choice.interval,
            start: start,
            end: _choice.end,
          ),
          reanchor: reanchor,
        );
    // A next date of today (or earlier) is due straight away.
    if (reanchor) await runRecurringCatchUp(ref);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skipNext() async {
    final next = _rule.nextDate;
    final ok = await ref.read(recurringRepositoryProvider).skipNext(_rule.id);
    if (!mounted) return;
    _say(
      ok && next != null
          ? 'Skipped ${formatDate(next)}.'
          : 'Nothing left to skip.',
    );
  }

  Future<void> _addNow() async {
    final id = await ref
        .read(recurringServiceProvider)
        .addNow(_rule.id, ref.read(clockProvider));
    if (!mounted) return;
    _say(
      id == null
          ? 'Not added: it already has one today, or nothing is left.'
          : 'Added for today. The schedule moves on.',
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this repeating transaction?'),
        content: const Text(
          'It stops adding new transactions. The ones it already added stay '
          'in History.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('rule-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(recurringRepositoryProvider).delete(_rule.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rule = _rule;
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final active = ref.watch(activeCategoriesProvider(rule.type)).value ?? [];
    final all = ref.watch(allCategoriesProvider).value ?? const [];
    final chips = [...active];
    if (!chips.any((c) => c.id == _categoryId)) {
      chips.addAll(all.where((c) => c.id == _categoryId));
    }
    final next = _shownNext;
    final recurrence = Recurrence(
      unit: _choice.unit,
      interval: _choice.interval,
      start: next ?? ref.watch(clockProvider),
      end: _choice.end,
    );
    final end = _choice.end;

    return Scaffold(
      appBar: AppBar(title: const Text('Repeating transaction')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              rule.type == TransactionType.income ? 'Income' : 'Expense',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: Gap.m),
            ClampedTextScale(
              child: TextFormField(
                key: const ValueKey('rule-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                style: monoText(
                  size: 32,
                  weight: FontWeight.w600,
                  color: c.text,
                ),
                cursorHeight: 30,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '$symbol ',
                  prefixStyle: monoText(
                    size: 32,
                    weight: FontWeight.w500,
                    color: c.dim,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
                validator: (v) => parseMoney(v ?? '').error,
              ),
            ),
            const SizedBox(height: Gap.l),
            Text('Category', style: theme.textTheme.labelLarge),
            const SizedBox(height: Gap.s),
            Wrap(
              spacing: 12,
              runSpacing: 0,
              children: [
                for (final cat in chips)
                  ChoiceChip(
                    key: ValueKey('rule-category-${cat.id}'),
                    showCheckmark: false,
                    avatar: Icon(
                      categoryIconFor(cat.icon).icon,
                      size: 18,
                      color: cat.id == _categoryId ? c.accent : c.text,
                    ),
                    label: Text(
                      cat.isArchived ? '${cat.name} (archived)' : cat.name,
                    ),
                    selected: cat.id == _categoryId,
                    onSelected: (_) => setState(() => _categoryId = cat.id),
                  ),
              ],
            ),
            const SizedBox(height: Gap.l),
            TextFormField(
              key: const ValueKey('rule-note'),
              controller: _note,
              maxLength: maxNoteLength,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Gap.s),
            ListTile(
              key: const ValueKey('rule-repeat'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.repeat),
              title: const Text('Repeats'),
              subtitle: Text(
                '${recurrence.scheduleText}'
                '${end == null ? '' : ' · until ${formatDate(end)}'}',
              ),
              onTap: _pickRepeat,
            ),
            if (_endError != null)
              Text(
                _endError!,
                key: const ValueKey('rule-end-error'),
                style: theme.textTheme.bodySmall?.copyWith(color: c.error),
              ),
            ListTile(
              key: const ValueKey('rule-next'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Next transaction'),
              subtitle: Text(
                next == null ? 'None: it has ended' : formatDate(next),
              ),
              onTap: _pickNext,
            ),
            SwitchListTile(
              key: const ValueKey('rule-active'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Turn off to pause without deleting.'),
              value: rule.isActive,
              onChanged: (v) =>
                  ref.read(recurringRepositoryProvider).setActive(rule.id, v),
            ),
            const SizedBox(height: Gap.s),
            OverflowBar(
              alignment: MainAxisAlignment.start,
              spacing: Gap.m,
              overflowSpacing: Gap.s,
              children: [
                OutlinedButton(
                  key: const ValueKey('rule-skip'),
                  onPressed: rule.hasEnded ? null : _skipNext,
                  child: const Text('Skip next'),
                ),
                OutlinedButton(
                  key: const ValueKey('rule-add-now'),
                  onPressed: rule.hasEnded ? null : _addNow,
                  child: const Text('Add now'),
                ),
              ],
            ),
            const SizedBox(height: Gap.l),
            FilledButton(
              key: const ValueKey('rule-save'),
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(height: Gap.s),
            TextButton(
              key: const ValueKey('rule-delete'),
              style: TextButton.styleFrom(foregroundColor: c.error),
              onPressed: _confirmDelete,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
