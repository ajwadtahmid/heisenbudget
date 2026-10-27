import 'package:flutter/material.dart';

import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/budget.dart';
import '../../domain/date_range.dart';
import '../shared/category_tile.dart';

/// How a gauge reads: the words under the bar, as one place so the screen
/// reader hears exactly what is shown.
class GaugeText {
  GaugeText(
    this.status,
    this.range,
    this.symbol,
    this.name, {
    this.finished = false,
    this.periodLabel,
  });

  final BudgetStatus status;
  final DateRange range;
  final String symbol;
  final String name;

  /// A period that is over (History): no days left, no planned, and the
  /// result is "Under by", "Over by" or "Used it all".
  final bool finished;

  /// "Monthly · October 2026", shown under the name.
  final String? periodLabel;

  String money(int cents) => formatMoney(cents, symbol);

  /// "$120.00 of $200.00"
  String get amounts => '${money(status.spent)} of ${money(status.limit)}';

  /// What is left, or by how much it is over.
  String get headline {
    if (finished) {
      if (status.isOver) return 'Over by ${money(status.overBy)}';
      if (status.left == 0) return 'Used it all';
      return 'Under by ${money(status.left)}';
    }
    switch (status.level) {
      case BudgetLevel.over:
        return 'Over by ${money(status.overBy)}';
      case BudgetLevel.almost:
        return status.left == 0
            ? 'Almost: nothing left'
            : 'Almost: ${money(status.left)} left';
      case BudgetLevel.ok:
        return '${money(status.left)} left';
    }
  }

  /// "12 days left · about $6.67 a day", "Month ended", or when it starts.
  String get timing {
    if (finished) return '';
    if (status.hasEnded) return 'Period ended';
    if (!status.hasStarted) return 'Starts ${formatDate(range.start)}';
    final days = status.daysLeft;
    final left = days == 1 ? '1 day left' : '$days days left';
    final perDay = status.perDay;
    return perDay == null ? left : '$left · about ${money(perDay)} a day';
  }

  /// Repeating expenses still due this month, and whether they break the limit.
  String? get planned {
    if (status.planned <= 0) return null;
    final base =
        'Planned: ${money(status.planned)} from repeating transactions';
    return status.plannedWouldExceed
        ? '$base. That would take it over by ${money(status.plannedOverBy)}.'
        : base;
  }

  String get spoken {
    final parts = [
      '$name${periodLabel == null ? '' : ', $periodLabel'}: $amounts.',
      '${headline.replaceFirst('Almost: ', 'almost at the limit, ')}.',
      if (timing.isNotEmpty) '$timing.',
      ?planned,
    ];
    return parts.join(' ');
  }
}

/// One budget: a name, the amounts, a bar and what is left.
///
/// The bar is spending (the Spent amber). Over the limit it turns to the
/// error colour **and** is striped, and the words say "Over by"; "almost" is
/// words and an icon. Colour is never the only signal.
/// "Usually runs over by $12.00 (over in 4 of the last 6 periods)".
String overrunText(OverrunHint hint, String symbol) =>
    'Usually runs over by ${formatMoney(hint.averageOverCents, symbol)} '
    '(over in ${hint.over} of the last ${hint.of} periods)';

class BudgetGauge extends StatelessWidget {
  const BudgetGauge({
    super.key,
    required this.name,
    required this.status,
    required this.range,
    required this.symbol,
    this.iconKey,
    this.onTap,
    this.periodLabel,
    this.finished = false,
    this.hint,
  });

  final String name;

  /// A category icon key, or null for "All spending".
  final String? iconKey;
  final BudgetStatus status;
  final DateRange range;
  final String symbol;

  /// Opens the editor; null when it cannot be changed (a finished period).
  final VoidCallback? onTap;

  /// "Monthly · October 2026": how often it repeats and which dates this is.
  final String? periodLabel;

  /// A finished period (History): shows the result, not what is left.
  final bool finished;

  /// A line about how the budget has gone in past periods, when worth saying
  /// (see [overrunText]).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final text = GaugeText(
      status,
      range,
      symbol,
      name,
      finished: finished,
      periodLabel: periodLabel,
    );
    // A finished period is either over or it is not: no "almost".
    final level = finished
        ? (status.isOver ? BudgetLevel.over : BudgetLevel.ok)
        : status.level;
    final isOver = level == BudgetLevel.over;

    final headlineStyle = theme.textTheme.bodyMedium?.copyWith(
      color: isOver ? c.error : c.text,
      fontWeight: level == BudgetLevel.ok ? FontWeight.w500 : FontWeight.w700,
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: hint == null ? text.spoken : '${text.spoken}. $hint',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.panel),
          child: Container(
            margin: const EdgeInsets.only(bottom: Gap.m),
            padding: const EdgeInsets.all(Gap.l),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(Radii.panel),
              border: Border.all(color: isOver ? c.error : c.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (iconKey != null) ...[
                      CategoryTile(iconKey: iconKey!, size: 32),
                      const SizedBox(width: Gap.m),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (periodLabel != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    periodLabel!,
                    key: const ValueKey('gauge-period'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
                const SizedBox(height: Gap.s),
                ClampedTextScale(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      text.amounts,
                      style: monoText(
                        size: 18,
                        weight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.m),
                _Bar(status: status, colors: c),
                const SizedBox(height: Gap.s),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (level != BudgetLevel.ok) ...[
                      Icon(
                        isOver
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: isOver ? c.error : c.text,
                      ),
                      const SizedBox(width: Gap.xs),
                    ],
                    Expanded(child: Text(text.headline, style: headlineStyle)),
                  ],
                ),
                if (text.timing.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    text.timing,
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
                if (text.planned != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    text.planned!,
                    key: const ValueKey('gauge-planned'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
                if (hint != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    hint!,
                    key: const ValueKey('gauge-hint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar: spent, then the lighter planned part, on a track.
class _Bar extends StatelessWidget {
  const _Bar({required this.status, required this.colors});

  final BudgetStatus status;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isOver = status.isOver;
    final spentFraction = status.permille / 1000;
    final plannedFraction = status.limit <= 0
        ? 0.0
        : (((status.spent + status.planned) * 1000 ~/ status.limit).clamp(
                    0,
                    1000,
                  ) /
                  1000)
              .clamp(spentFraction, 1.0);
    final fill = isOver ? colors.error : colors.spentFill;

    return Semantics(
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            color: colors.panelHigh,
            border: Border.all(color: colors.hairline),
            borderRadius: BorderRadius.circular(5),
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Stack(
                children: [
                  if (plannedFraction > spentFraction)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: w * plannedFraction,
                      child: ColoredBox(
                        color: colors.spentFill.withValues(alpha: 0.3),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: w * spentFraction,
                    child: CustomPaint(
                      painter: _FillPainter(
                        fill,
                        striped: isOver,
                        stripe: colors.ground,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A solid fill, with diagonal stripes when over the limit.
class _FillPainter extends CustomPainter {
  _FillPainter(this.color, {required this.striped, required this.stripe});

  final Color color;
  final bool striped;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    if (!striped) return;
    final paint = Paint()
      ..color = stripe.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width + size.height; x += 7) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FillPainter old) =>
      old.color != color || old.striped != striped || old.stripe != stripe;
}

/// "Monthly · October 2026", "Weekly · Oct 12 – 18, 2026", "Every 10 days ·
/// Oct 12 – 21, 2026", or for a one-time budget "Just this month · October 2026".
/// A period a change cut short shows its real dates and "Ended early".
String budgetPeriodLabel(
  LimitEntry entry,
  DateRange range,
  int monthStartDay, {
  bool endedEarly = false,
}) {
  final dates = entry.unit.isMonth && monthStartDay == 1 && !endedEarly
      ? formatMonth(range.start)
      : formatRange(range);
  final what = entry.repeats
      ? entry.unit.label
      : 'Just this ${entry.unit.isMonth ? 'month' : 'period'}';
  return '$what · $dates${endedEarly ? ' · Ended early' : ''}';
}
