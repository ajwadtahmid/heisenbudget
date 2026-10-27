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
///
/// [copyFrom] is a finished period whose amount and length are offered again
/// (the budget is not in force now): it is a new budget, filled in.
Future<void> showBudgetEditor(
  BuildContext context, {
  required int? categoryId,
  required String name,
  BudgetLine? current,
  PastBudget? copyFrom,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _BudgetEditor(
      categoryId: categoryId,
      name: name,
      current: current,
      copyFrom: copyFrom,
    ),
  );
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor({
    required this.categoryId,
    required this.name,
    required this.current,
    this.copyFrom,
  });

  final int? categoryId;
  final String name;
  final BudgetLine? current;
  final PastBudget? copyFrom;

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _length;
  late bool _custom;

  /// Whether a custom length is counted in months rather than days.
  late bool _inMonths;
  late bool _repeats;

  /// True while "Just this period" is on only because Rest of this year
  /// turned it on: choosing another length turns it back off. A switch the
  /// person flipped themselves is left alone.
  bool _onceFromRestOfYear = false;

  /// The last valid length typed, so the preview holds while it is edited.
  late int _lastCount;

  /// The first day of a run of days, when picked by hand.
  DateTime? _firstDay;
  bool _saving = false;
  String? _saveError;
  int? _suggestion;

  BudgetLine? get _current => widget.current;

  @override
  void initState() {
    super.initState();
    // What the fields start with: the budget in force, or the finished period
    // being copied forward, or nothing.
    final copy = widget.copyFrom;
    final unit = _current?.unit ?? copy?.unit;
    final startLimit = _current?.status.limit ?? copy?.limit;
    _custom = unit != null && !unit.isMonth;
    _inMonths = _custom && unit!.inMonths;
    _lastCount = !_custom
        ? 7
        : _inMonths
        ? unit!.months
        : unit!.days;
    _length = TextEditingController(text: '$_lastCount');
    _repeats = _current?.entry.repeats ?? copy?.entry.repeats ?? true;
    _amount = TextEditingController(
      text: startLimit == null ? '' : centsToInputText(startLimit),
    );
    _loadSuggestion();
  }

  @override
  void dispose() {
    _amount.dispose();
    _length.dispose();
    super.dispose();
  }

  BudgetUnit get _unit => !_custom
      ? BudgetUnit.month
      : _inMonths
      ? BudgetUnit.months(_lastCount)
      : BudgetUnit.days(_lastCount);

  int get _largest => _inMonths ? maxBudgetMonths : maxBudgetDays;

  String? _checkLength(String? text) {
    final n = int.tryParse((text ?? '').trim());
    if (n == null || n < 1 || n > _largest) {
      return 'Enter 1 to $_largest ${_inMonths ? 'months' : 'days'}';
    }
    return null;
  }

  /// Rest of this year is the current choice: a one-time run of days from today
  /// to Dec 31.
  bool get _restOfYearSelected =>
      _custom &&
      !_inMonths &&
      !_repeats &&
      _lastCount == _daysLeftInYear &&
      _firstDay == dateOnly(ref.read(clockProvider));

  /// The months a multi-month budget could start in: this one, or an earlier
  /// one that is still under way (a quarter set in November can start in
  /// October, so it is the calendar quarter). The first is today's.
  List<DateTime> get _startMonths {
    final startDay = ref.read(monthStartDayProvider);
    final now = BudgetMonth.containing(ref.read(clockProvider), startDay);
    final back = (_lastCount - 1).clamp(0, 11);
    return [
      for (var k = 0; k <= back; k++) now.shift(-k).range(startDay).start,
    ];
  }

  Widget _firstMonthPicker() {
    final months = _startMonths;
    final chosen = _firstDay == null
        ? months.first
        : months.firstWhere((m) => m == _firstDay, orElse: () => months.first);
    return DropdownButtonFormField<DateTime>(
      key: ValueKey(
        'budget-first-month-$_lastCount-${chosen.toIso8601String()}',
      ),
      isExpanded: true,
      initialValue: chosen,
      decoration: const InputDecoration(
        labelText: 'First month',
        helperText: 'Spending counts from this month.',
        helperMaxLines: 2,
      ),
      items: [
        for (final m in months)
          DropdownMenuItem(value: m, child: Text(formatMonth(m))),
      ],
      onChanged: (m) {
        if (m == null) return;
        // The current month is the default, and keeps an existing budget's own
        // alignment untouched.
        _changeLength(() {}, firstDay: m == months.first ? null : m);
      },
    );
  }

  /// Days from today to the end of this year, today included.
  int get _daysLeftInYear {
    final today = dateOnly(ref.read(clockProvider));
    return DateTime.utc(
          today.year,
          12,
          31,
        ).difference(DateTime.utc(today.year, today.month, today.day)).inDays +
        1;
  }

  /// The period this change starts with: the current one of the existing
  /// budget when its period is not being changed (keeping its alignment),
  /// otherwise the current period of the chosen kind.
  DateRange get _range {
    final current = _current;
    if (current != null && current.unit == _unit && _firstDay == null) {
      return current.range;
    }
    return currentRangeFor(
      _unit,
      ref.read(clockProvider),
      monthStartDay: ref.read(monthStartDayProvider),
      weekStartDay: ref.read(weekStartDayProvider),
      anchor: _firstDay,
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

  void _changeLength(void Function() change, {DateTime? firstDay}) {
    setState(() {
      if (_onceFromRestOfYear) {
        _repeats = true;
        _onceFromRestOfYear = false;
      }
      change();
      _suggestion = null;
      _firstDay = firstDay;
    });
    _loadSuggestion();
  }

  void _setCustom(bool custom) {
    if (custom == _custom) return;
    _changeLength(() => _custom = custom);
  }

  void _setLength(String text) {
    final n = int.tryParse(text.trim());
    if (_checkLength(text) != null || n == _lastCount) return;
    _changeLength(() => _lastCount = n!);
  }

  void _setInMonths(bool months) {
    if (months == _inMonths) return;
    _changeLength(() {
      _inMonths = months;
      if (_lastCount > _largest) _lastCount = _largest;
      _length.text = '$_lastCount';
    });
  }

  void _quickPick(int count, {required bool months}) {
    _length.text = '$count';
    _changeLength(() {
      _inMonths = months;
      _lastCount = count;
    });
  }

  /// From today to the end of this year, once: a one-time run of days.
  void _restOfYear() {
    final days = _daysLeftInYear;
    // Already one-time because the person chose it: that stays theirs.
    final chosenOnce = !_repeats && !_onceFromRestOfYear;
    _length.text = '$days';
    _changeLength(() {
      _inMonths = false;
      _lastCount = days;
      _repeats = false;
      _onceFromRestOfYear = !chosenOnce;
    }, firstDay: dateOnly(ref.read(clockProvider)));
  }

  Future<void> _pickFirstDay() async {
    final today = ref.read(clockProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _range.start,
      firstDate: DateTime(today.year, today.month, today.day - _lastCount + 1),
      lastDate: today,
      helpText: 'First day of the first period',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _firstDay = dateOnly(picked);
      _suggestion = null;
    });
    _loadSuggestion();
  }

  Future<void> _save({required bool stop}) async {
    if (_saving) return;
    if (!stop && !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final repo = ref.read(budgetRepositoryProvider);
    final today = ref.read(clockProvider);
    try {
      if (stop) {
        final current = _current!;
        await repo.setLimit(
          start: current.range.start,
          unit: current.unit,
          categoryId: widget.categoryId,
          amountCents: null,
          today: today,
        );
      } else {
        await repo.setLimit(
          start: _range.start,
          unit: _unit,
          repeats: _repeats,
          categoryId: widget.categoryId,
          amountCents: parseMoney(_amount.text).cents,
          today: today,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Stay open with Save available again, so nothing typed is lost.
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Could not save this limit. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final range = _range;
    final suggestion = _suggestion;
    final isNew = _current == null;
    final changed = isNew || _current!.unit != _unit;
    final showFirstDay = _custom && !_inMonths && changed;
    final showFirstMonth = _custom && _inMonths && _lastCount > 1 && changed;

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
                    widget.copyFrom != null && isNew
                        ? 'Copy forward'
                        : isNew
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
                  if (widget.copyFrom != null && isNew) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      'Same amount and length as the budget that ran '
                      '${formatRange(widget.copyFrom!.range)}. It starts '
                      'with the current period.',
                      key: const ValueKey('budget-copy-note'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.appColors.dim,
                      ),
                    ),
                  ],
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
                      ChoiceChip(
                        key: const ValueKey('budget-unit-month'),
                        showCheckmark: false,
                        label: const Text('Monthly'),
                        selected: !_custom,
                        onSelected: (_) => _setCustom(false),
                      ),
                      ChoiceChip(
                        key: const ValueKey('budget-unit-custom'),
                        showCheckmark: false,
                        label: const Text('Custom'),
                        selected: _custom,
                        onSelected: (_) => _setCustom(true),
                      ),
                    ],
                  ),
                  if (_custom) ...[
                    const SizedBox(height: Gap.m),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('budget-length'),
                            controller: _length,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Length',
                            ),
                            validator: _checkLength,
                            onChanged: _setLength,
                          ),
                        ),
                        const SizedBox(width: Gap.m),
                        Expanded(
                          child: DropdownButtonFormField<bool>(
                            key: ValueKey('budget-length-unit-$_inMonths'),
                            isExpanded: true,
                            initialValue: _inMonths,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: false,
                                child: Text('Days'),
                              ),
                              DropdownMenuItem(
                                value: true,
                                child: Text('Months'),
                              ),
                            ],
                            onChanged: (months) => _setInMonths(months!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.s),
                    Wrap(
                      spacing: Gap.m,
                      runSpacing: Gap.s,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('budget-quick-week'),
                          showCheckmark: false,
                          label: const Text('1 week'),
                          selected: !_inMonths && _lastCount == 7,
                          onSelected: (_) => _quickPick(7, months: false),
                        ),
                        ChoiceChip(
                          key: const ValueKey('budget-quick-quarter'),
                          showCheckmark: false,
                          label: const Text('Quarter (3 months)'),
                          selected: _inMonths && _lastCount == 3,
                          onSelected: (_) => _quickPick(3, months: true),
                        ),
                        ChoiceChip(
                          key: const ValueKey('budget-quick-year'),
                          showCheckmark: false,
                          label: const Text('1 year'),
                          selected: _inMonths && _lastCount == 12,
                          onSelected: (_) => _quickPick(12, months: true),
                        ),
                        ChoiceChip(
                          key: const ValueKey('budget-quick-rest'),
                          showCheckmark: false,
                          label: const Text('Rest of this year'),
                          selected: _restOfYearSelected,
                          onSelected: (_) => _restOfYear(),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Gap.s),
                  SwitchListTile(
                    key: const ValueKey('budget-once'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Just this period'),
                    subtitle: Text(
                      _repeats
                          ? 'Off: repeats every ${_unit.noun}.'
                          : 'On: ends ${formatDate(range.end)}.',
                    ),
                    value: !_repeats,
                    onChanged: (once) => setState(() {
                      _repeats = !once;
                      _onceFromRestOfYear = false;
                    }),
                  ),
                  if (showFirstDay) ...[
                    const SizedBox(height: Gap.s),
                    ListTile(
                      key: const ValueKey('budget-first-day'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('First day'),
                      subtitle: Text(formatDate(range.start)),
                      onTap: _pickFirstDay,
                    ),
                  ],
                  if (showFirstMonth) ...[
                    const SizedBox(height: Gap.s),
                    _firstMonthPicker(),
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
                          'Use the average of the last 3 ${_unit.plural}: '
                          '${formatMoney(suggestion, symbol)}',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.m),
                  Text(
                    _restOfYearSelected
                        ? 'Applies from today: ${formatRange(range)}. '
                              'Spending earlier this year is not counted.'
                        : 'Applies from this '
                              '${_unit.isMonth ? 'month' : 'period'}: '
                              '${formatRange(range)}. '
                              'Earlier ones keep what they had.',
                    key: const ValueKey('budget-starts'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: Gap.m),
                    Text(
                      _saveError!,
                      key: const ValueKey('budget-save-error'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: c.error,
                      ),
                    ),
                  ],
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
