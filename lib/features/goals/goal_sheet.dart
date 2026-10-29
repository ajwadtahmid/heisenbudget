import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart';
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
import '../shared/category_tile.dart';
import '../shared/icon_picker.dart';

/// Opens the goal sheet: a new goal, or [existing] to change or delete it.
/// Returns true when the goal was deleted.
Future<bool?> showGoalSheet(BuildContext context, {GoalView? existing}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GoalSheet(existing: existing),
  );
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({this.existing});

  final GoalView? existing;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _target;
  DateTime? _date;
  late String _icon;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final goal = widget.existing?.goal;
    _name = TextEditingController(text: goal?.name ?? '');
    _target = TextEditingController(
      text: goal == null ? '' : centsToInputText(goal.targetCents),
    );
    _date = widget.existing?.targetDate;
    _icon = goal?.icon ?? defaultGoalIconKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(ref.read(clockProvider));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: earliestDate,
      lastDate: latestDate,
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickIcon() async {
    var chosen = _icon;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Icon'),
        content: SizedBox(
          width: double.maxFinite,
          child: IconPicker(
            selectedKey: chosen,
            onChanged: (key) => chosen = key,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('goal-icon-ok'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _icon = chosen);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final input = GoalInput(
      name: _name.text,
      targetCents: parseMoney(_target.text).cents!,
      targetDate: _date,
      icon: _icon,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(goalRepositoryProvider);
    try {
      if (_isNew) {
        await repo.add(input, now: ref.read(nowProvider)());
      } else {
        await repo.update(widget.existing!.goal.id, input);
      }
    } on GoalLimitException {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'You can have up to $maxActiveGoals goals at a time. Finish or '
              'delete one first.';
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
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _delete() async {
    final goal = widget.existing!.goal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${goal.name}”?'),
        content: const Text(
          'The goal and everything you put into it are removed. Your '
          'transactions and balance are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('goal-delete-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(goalRepositoryProvider).delete(goal.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));

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
                    _isNew ? 'New goal' : 'Edit goal',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
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
                  TextFormField(
                    key: const ValueKey('goal-name'),
                    controller: _name,
                    maxLength: maxGoalNameLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      helperText: 'What you are saving for',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: Gap.m),
                  ClampedTextScale(
                    child: TextFormField(
                      key: const ValueKey('goal-target'),
                      controller: _target,
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
                        labelText: 'Target',
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
                        return r.cents! > maxAmountCents ? errorTooLarge : null;
                      },
                    ),
                  ),
                  const SizedBox(height: Gap.l),
                  OverflowBar(
                    alignment: MainAxisAlignment.start,
                    spacing: Gap.s,
                    overflowSpacing: Gap.xs,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('goal-date'),
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          _date == null
                              ? 'Target date (optional)'
                              : formatDate(_date!),
                        ),
                      ),
                      if (_date != null)
                        TextButton(
                          key: const ValueKey('goal-date-clear'),
                          onPressed: () => setState(() => _date = null),
                          child: const Text('No date'),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.m),
                  Wrap(
                    spacing: Gap.m,
                    runSpacing: Gap.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CategoryTile(iconKey: _icon, size: 40),
                      OutlinedButton(
                        key: const ValueKey('goal-icon'),
                        onPressed: _pickIcon,
                        child: const Text('Change icon'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Gap.m),
                      child: Text(
                        _error!,
                        key: const ValueKey('goal-error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: c.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: Gap.l),
                  FilledButton(
                    key: const ValueKey('goal-save'),
                    onPressed: _saving ? null : _save,
                    child: const Text('Save'),
                  ),
                  if (!_isNew)
                    TextButton(
                      key: const ValueKey('goal-delete'),
                      onPressed: _saving ? null : _delete,
                      child: Text(
                        'Delete goal',
                        style: TextStyle(color: c.error),
                      ),
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
