import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/iso_date.dart';
import '../../domain/recurrence.dart';

/// How a transaction repeats: every [interval] [unit]s, until [end] if set.
class RepeatChoice {
  const RepeatChoice({required this.unit, required this.interval, this.end});

  final RecurrenceUnit unit;
  final int interval;
  final DateTime? end;

  @override
  bool operator ==(Object other) =>
      other is RepeatChoice &&
      other.unit == unit &&
      other.interval == interval &&
      other.end == end;

  @override
  int get hashCode => Object.hash(unit, interval, end);
}

/// What the sheet hands back. `choice == null` means "does not repeat"; the
/// sheet returning null instead means it was dismissed.
typedef RepeatResult = ({RepeatChoice? choice});

/// Asks how a transaction repeats. [start] is the transaction's date.
Future<RepeatResult?> showRepeatSheet(
  BuildContext context, {
  required DateTime start,
  RepeatChoice? current,
  bool allowNone = true,
}) {
  return showModalBottomSheet<RepeatResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _RepeatSheet(start: start, current: current, allowNone: allowNone),
  );
}

enum _Preset { none, weekly, monthly, yearly, custom }

const _unitLabels = {
  RecurrenceUnit.day: 'Days',
  RecurrenceUnit.week: 'Weeks',
  RecurrenceUnit.month: 'Months',
  RecurrenceUnit.year: 'Years',
};

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({
    required this.start,
    required this.current,
    required this.allowNone,
  });

  final DateTime start;
  final RepeatChoice? current;
  final bool allowNone;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late RecurrenceUnit _unit;
  late _Preset _preset;
  late final TextEditingController _interval;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _unit = c?.unit ?? RecurrenceUnit.month;
    _end = c?.end;
    _interval = TextEditingController(text: '${c?.interval ?? 1}');
    _preset = c == null
        ? (widget.allowNone ? _Preset.none : _Preset.monthly)
        : _presetOf(c);
  }

  @override
  void dispose() {
    _interval.dispose();
    super.dispose();
  }

  _Preset _presetOf(RepeatChoice c) {
    if (c.interval == 1) {
      switch (c.unit) {
        case RecurrenceUnit.week:
          return _Preset.weekly;
        case RecurrenceUnit.month:
          return _Preset.monthly;
        case RecurrenceUnit.year:
          return _Preset.yearly;
        case RecurrenceUnit.day:
          break;
      }
    }
    return _Preset.custom;
  }

  /// The number typed in the custom box, or null while it is not 1 to 365.
  int? get _customInterval {
    final n = int.tryParse(_interval.text.trim());
    return n != null && n >= 1 && n <= maxRecurrenceInterval ? n : null;
  }

  RepeatChoice? get _choice {
    switch (_preset) {
      case _Preset.none:
        return null;
      case _Preset.weekly:
        return RepeatChoice(unit: RecurrenceUnit.week, interval: 1, end: _end);
      case _Preset.monthly:
        return RepeatChoice(unit: RecurrenceUnit.month, interval: 1, end: _end);
      case _Preset.yearly:
        return RepeatChoice(unit: RecurrenceUnit.year, interval: 1, end: _end);
      case _Preset.custom:
        final n = _customInterval;
        return n == null
            ? null
            : RepeatChoice(unit: _unit, interval: n, end: _end);
    }
  }

  bool get _valid => _preset != _Preset.custom || _customInterval != null;

  void _select(_Preset preset) => setState(() => _preset = preset);

  Future<void> _pickEnd() async {
    final start = dateOnly(widget.start);
    final initial = _end != null && !_end!.isBefore(start)
        ? _end!
        : DateTime(start.year + 1, start.month, start.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: start,
      lastDate: latestDate,
      helpText: 'Stop repeating after',
    );
    if (picked != null) setState(() => _end = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final choice = _choice;
    final summary = choice == null
        ? null
        : Recurrence(
            unit: choice.unit,
            interval: choice.interval,
            start: widget.start,
            end: choice.end,
          ).scheduleText;

    Widget preset(_Preset p, String label) => ChoiceChip(
      key: ValueKey('repeat-${p.name}'),
      showCheckmark: false,
      label: Text(label),
      selected: _preset == p,
      onSelected: (_) => _select(p),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Repeat', style: theme.textTheme.titleLarge),
            const SizedBox(height: Gap.m),
            Wrap(
              spacing: Gap.m,
              runSpacing: 0,
              children: [
                if (widget.allowNone) preset(_Preset.none, 'Does not repeat'),
                preset(_Preset.weekly, 'Weekly'),
                preset(_Preset.monthly, 'Monthly'),
                preset(_Preset.yearly, 'Yearly'),
                preset(_Preset.custom, 'Custom'),
              ],
            ),
            if (_preset == _Preset.custom) ...[
              const SizedBox(height: Gap.m),
              Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: TextField(
                      key: const ValueKey('repeat-interval'),
                      controller: _interval,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Every',
                        errorText: _customInterval == null ? '1 to 365' : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.s),
              Wrap(
                spacing: Gap.m,
                children: [
                  for (final entry in _unitLabels.entries)
                    ChoiceChip(
                      key: ValueKey('repeat-unit-${entry.key.name}'),
                      showCheckmark: false,
                      label: Text(entry.value),
                      selected: _unit == entry.key,
                      onSelected: (_) => setState(() => _unit = entry.key),
                    ),
                ],
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: Gap.m),
              Text(
                summary,
                key: const ValueKey('repeat-summary'),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
              ),
              ListTile(
                key: const ValueKey('repeat-end'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Ends'),
                subtitle: Text(_end == null ? 'Never' : formatDate(_end!)),
                trailing: _end == null
                    ? null
                    : IconButton(
                        key: const ValueKey('repeat-end-clear'),
                        tooltip: 'Never end',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _end = null),
                      ),
                onTap: _pickEnd,
              ),
            ],
            const SizedBox(height: Gap.m),
            FilledButton(
              key: const ValueKey('repeat-done'),
              onPressed: _valid
                  ? () => Navigator.of(context).pop((choice: _choice))
                  : null,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
