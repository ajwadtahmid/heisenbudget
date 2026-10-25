import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:intl/intl.dart';

import '../../core/design/tick_ruler.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/date_range.dart';
import '../../domain/period.dart';
import '../../domain/week_mode.dart';

DateRange _resolve(Period p, WeekMode mode, int weekStartDay) {
  return resolvePeriod(clampPeriod(p, mode, weekStartDay), mode, weekStartDay);
}

/// Opens the date range picker and reports the choice as a [Custom] period.
Future<void> _pickCustomRange(
  BuildContext context,
  Period? current,
  ValueChanged<Period> onChanged,
) async {
  final result = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDateRange: current is Custom
        ? DateTimeRange(start: current.range.start, end: current.range.end)
        : null,
  );
  if (result != null) onChanged(Custom(result.start, result.end));
}

/// The resolved dates under a picker, e.g. `Oct 1 – Oct 7, 2026`.
Widget _rangeText(BuildContext context, DateRange range) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      formatRange(range),
      key: const ValueKey('resolved-range'),
      style: monoText(
        size: 13,
        weight: FontWeight.w400,
        color: context.appColors.dim,
      ),
    ),
  );
}

enum _Pick { thisWeek, lastWeek, thisMonth, lastMonth, custom }

/// Compact period picker for Home: one outlined drop-down button, and a tick
/// ruler under it that shows how far through the period you are.
///
/// The menu holds This week, Last week, This month, Last month, Week 1 to N
/// and Custom. To step further back or forward, swipe across the ruler (screen
/// readers get "Previous period" / "Next period" actions instead).
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.period,
    required this.today,
    required this.weekMode,
    required this.weekStartDay,
    required this.onChanged,
  });

  final Period period;
  final DateTime today;
  final WeekMode weekMode;
  final int weekStartDay;
  final ValueChanged<Period> onChanged;

  /// The month that the "Week N" entries belong to.
  DateTime get _contextMonth => switch (period) {
    WeekOfMonth(:final year, :final month) => DateTime(year, month, 1),
    ThisMonth(:final anchor) => anchor,
    ThisWeek(:final anchor) => anchor,
    Custom() => today,
  };

  DateRange get _thisWeek => thisWeek(today, weekMode, weekStartDay);

  DateRange get _lastWeek => thisWeek(
    shiftWeek(today, -1, weekMode, weekStartDay),
    weekMode,
    weekStartDay,
  );

  bool _isMonth(DateTime anchor, DateTime month) =>
      anchor.year == month.year && anchor.month == month.month;

  /// Which fixed menu entry the period equals, if any.
  _Pick? get _matching {
    final p = period;
    if (p is ThisWeek) {
      final shown = thisWeek(p.anchor, weekMode, weekStartDay);
      if (shown == _thisWeek) return _Pick.thisWeek;
      if (shown == _lastWeek) return _Pick.lastWeek;
    } else if (p is ThisMonth) {
      if (_isMonth(p.anchor, today)) return _Pick.thisMonth;
      if (_isMonth(p.anchor, shiftMonth(today, -1))) return _Pick.lastMonth;
    } else if (p is Custom) {
      return _Pick.custom;
    }
    return null;
  }

  String get _label {
    switch (_matching) {
      case _Pick.thisWeek:
        return 'This week';
      case _Pick.lastWeek:
        return 'Last week';
      case _Pick.thisMonth:
        return 'This month';
      case _Pick.lastMonth:
        return 'Last month';
      case _Pick.custom:
        return 'Custom';
      case null:
        break;
    }
    switch (period) {
      case ThisWeek(:final anchor):
        final shown = thisWeek(anchor, weekMode, weekStartDay);
        return 'Week of ${DateFormat.MMMd().format(shown.start)}';
      case ThisMonth(:final anchor):
        return formatMonth(anchor);
      case WeekOfMonth(:final n):
        return 'Week $n';
      case Custom():
        return 'Custom';
    }
  }

  void _onPick(BuildContext context, Object value) {
    final month = _contextMonth;
    if (value is int) {
      onChanged(WeekOfMonth(month.year, month.month, value));
      return;
    }
    switch (value as _Pick) {
      case _Pick.thisWeek:
        onChanged(ThisWeek(today));
      case _Pick.lastWeek:
        onChanged(ThisWeek(shiftWeek(today, -1, weekMode, weekStartDay)));
      case _Pick.thisMonth:
        onChanged(ThisMonth(today));
      case _Pick.lastMonth:
        onChanged(ThisMonth(shiftMonth(today, -1)));
      case _Pick.custom:
        _pickCustomRange(context, period, onChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = period;
    final month = _contextMonth;
    final weekCount = weeksInMonth(
      month.year,
      month.month,
      weekMode,
      weekStartDay,
    );
    final c = context.appColors;
    final range = _resolve(current, weekMode, weekStartDay);
    final matching = _matching;

    PopupMenuEntry<Object> item(
      String key,
      Object value,
      String text,
      bool checked,
    ) {
      return CheckedPopupMenuItem<Object>(
        key: ValueKey(key),
        value: value,
        checked: checked,
        child: Text(text),
      );
    }

    // Custom ranges have no "next": stepping leaves them unchanged.
    void step(int delta) =>
        onChanged(stepPeriod(current, delta, weekMode, weekStartDay));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<Object>(
            key: const ValueKey('period-menu'),
            tooltip: 'Choose period',
            onSelected: (value) => _onPick(context, value),
            itemBuilder: (_) => [
              item(
                'menu-this-week',
                _Pick.thisWeek,
                'This week',
                matching == _Pick.thisWeek,
              ),
              item(
                'menu-last-week',
                _Pick.lastWeek,
                'Last week',
                matching == _Pick.lastWeek,
              ),
              item(
                'menu-this-month',
                _Pick.thisMonth,
                'This month',
                matching == _Pick.thisMonth,
              ),
              item(
                'menu-last-month',
                _Pick.lastMonth,
                'Last month',
                matching == _Pick.lastMonth,
              ),
              const PopupMenuDivider(),
              for (var n = 1; n <= weekCount; n++)
                item(
                  'menu-week-$n',
                  n,
                  'Week $n',
                  current is WeekOfMonth && current.n == n,
                ),
              const PopupMenuDivider(),
              item(
                'menu-custom',
                _Pick.custom,
                'Custom range…',
                current is Custom,
              ),
            ],
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.only(left: 14, right: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.input),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _label,
                      key: const ValueKey('period-label'),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: c.text),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: c.dim),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Swipe across the ruler to move to the previous / next period.
        Semantics(
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Previous period'): () =>
                step(-1),
            const CustomSemanticsAction(label: 'Next period'): () => step(1),
          },
          child: GestureDetector(
            key: const ValueKey('period-swipe'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 250) {
                step(-1); // swiped right: back in time
              } else if (velocity < -250) {
                step(1);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                TickRuler(range: range, today: today),
                const SizedBox(height: 4),
                _rangeText(context, range),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrapping chips for the History filter: All time, This week, This month,
/// Last month, Custom. A null [period] means "All time".
class PeriodChips extends StatelessWidget {
  const PeriodChips({
    super.key,
    required this.period,
    required this.today,
    required this.weekMode,
    required this.weekStartDay,
    required this.onChanged,
  });

  final Period? period;
  final DateTime today;
  final WeekMode weekMode;
  final int weekStartDay;
  final ValueChanged<Period?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = period;
    final lastMonth = shiftMonth(today, -1);

    bool isMonth(DateTime m) =>
        current is ThisMonth &&
        current.anchor.year == m.year &&
        current.anchor.month == m.month;

    final thisWeekSelected =
        current is ThisWeek &&
        thisWeek(current.anchor, weekMode, weekStartDay) ==
            thisWeek(today, weekMode, weekStartDay);

    Widget chip(String key, String label, bool selected, VoidCallback onTap) {
      return ChoiceChip(
        key: ValueKey('chip-$key'),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(
              'all-time',
              'All time',
              current == null,
              () => onChanged(null),
            ),
            chip(
              'this-week',
              'This week',
              thisWeekSelected,
              () => onChanged(ThisWeek(today)),
            ),
            chip(
              'this-month',
              'This month',
              isMonth(today),
              () => onChanged(ThisMonth(today)),
            ),
            chip(
              'last-month',
              'Last month',
              isMonth(lastMonth),
              () => onChanged(ThisMonth(lastMonth)),
            ),
            chip(
              'custom',
              'Custom',
              current is Custom,
              () => _pickCustomRange(context, current, onChanged),
            ),
          ],
        ),
        if (current != null)
          _rangeText(context, _resolve(current, weekMode, weekStartDay)),
      ],
    );
  }
}
