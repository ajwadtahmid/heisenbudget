import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/money_parser.dart';
import '../../core/theme.dart';
import '../../data/repositories/goal_repository.dart';
import '../../domain/iso_date.dart';
import '../../providers/goal_providers.dart';
import '../../providers/period_providers.dart';
import '../../providers/settings_providers.dart';

/// Puts money into a goal, or (with [takeOut]) takes some out, on a day.
Future<void> showGoalEntrySheet(
  BuildContext context, {
  required GoalView view,
  bool takeOut = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GoalEntrySheet(view: view, takeOut: takeOut),
  );
}

class _GoalEntrySheet extends ConsumerStatefulWidget {
  const _GoalEntrySheet({required this.view, required this.takeOut});

  final GoalView view;
  final bool takeOut;

  @override
  ConsumerState<_GoalEntrySheet> createState() => _GoalEntrySheetState();
}

class _GoalEntrySheetState extends ConsumerState<_GoalEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late DateTime _date = dateOnly(ref.read(clockProvider));
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: earliestDate,
      lastDate: latestDate,
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final cents = parseMoney(_amount.text).cents!;
    setState(() {
      _saving = true;
      _error = null;
    });
    final goal = widget.view.goal;
    try {
      await ref
          .read(goalRepositoryProvider)
          .addEntry(
            goal.id,
            cents: widget.takeOut ? -cents : cents,
            date: _date,
          );
    } on GoalBelowZeroException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'There is not that much in this goal.';
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Something went wrong. Nothing was saved.';
        });
      }
      return;
    }
    // A quiet tick, no fuss, when this entry fills the goal.
    final reached = widget.view.plan.savedCents + cents >= goal.targetCents;
    if (!widget.takeOut && !widget.view.plan.reached && reached) {
      HapticFeedback.selectionClick();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final saved = widget.view.plan.savedCents;
    final title = widget.takeOut ? 'Take money out' : 'Add money';

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
                    '$title · ${widget.view.goal.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  ClampedTextScale(
                    child: TextFormField(
                      key: const ValueKey('goal-entry-amount'),
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
                        labelText: 'Amount',
                        helperText: widget.takeOut
                            ? 'Up to ${formatMoney(saved, symbol)}, what is in it'
                            : null,
                        prefixText: '$symbol ',
                        prefixStyle: monoText(
                          size: 28,
                          weight: FontWeight.w500,
                          color: c.dim,
                        ),
                      ),
                      validator: (v) {
                        final r = parseMoney(v ?? '');
                        if (!r.isValid) return r.error;
                        if (r.cents! > maxAmountCents) return errorTooLarge;
                        if (widget.takeOut && r.cents! > saved) {
                          return 'There is not that much in this goal';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _save(),
                    ),
                  ),
                  const SizedBox(height: Gap.m),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('goal-entry-date'),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(formatDate(_date)),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.s),
                      child: Text(
                        _error!,
                        key: const ValueKey('goal-entry-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: Gap.l),
                  FilledButton(
                    key: const ValueKey('goal-entry-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(widget.takeOut ? 'Take out' : 'Add'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
