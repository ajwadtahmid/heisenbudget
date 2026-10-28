import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../domain/trends.dart';
import '../home/spectrum_chart.dart' show GraticulePainter;

/// One month on the trace: what came in (green) and what went out (amber), or
/// just what went out for a single category.
class TracePoint {
  const TracePoint({
    required this.label,
    required this.title,
    required this.spent,
    this.received,
    this.purity,
    this.inProgress = false,
  });

  /// `Oct`, under the peaks.
  final String label;

  /// `October 2026`, in the readout.
  final String title;
  final int spent;

  /// Null in a single-category trace.
  final int? received;

  /// Tenths of a percent kept; null when nothing came in (or not shown).
  final int? purity;

  /// The month is still going: its peaks are drawn lighter.
  final bool inProgress;

  int? get net => received == null ? null : received! - spent;
}

String _monthLabel(MonthTotals t) =>
    DateFormat.MMM().format(DateTime(t.month.year, t.month.month));
String _monthTitle(MonthTotals t) =>
    formatMonth(DateTime(t.month.year, t.month.month));

/// The points for money in and out.
List<TracePoint> tracePointsOf(List<MonthTotals> totals) => [
  for (final t in totals)
    TracePoint(
      label: _monthLabel(t),
      title: _monthTitle(t),
      spent: t.spentCents,
      received: t.receivedCents,
      purity: t.purity,
      inProgress: t.inProgress,
    ),
];

/// The points for one category's spending ([spent] is in the order of
/// [months]).
List<TracePoint> categoryPointsOf(List<MonthTotals> months, List<int> spent) =>
    [
      for (var i = 0; i < months.length; i++)
        TracePoint(
          label: _monthLabel(months[i]),
          title: _monthTitle(months[i]),
          spent: spent[i],
          inProgress: months[i].inProgress,
        ),
    ];

/// Months side by side as peaks over the graticule. Tap a month to focus it:
/// the others dim and a readout gives its exact figures. Drawn with plain
/// widgets, like the spectrum chart; each month is also a labelled button for
/// screen readers.
class TraceChart extends StatefulWidget {
  const TraceChart({
    super.key,
    required this.points,
    required this.symbol,
    required this.emptyText,
    this.height = 152,
  });

  final List<TracePoint> points;
  final String symbol;

  /// Shown on the flat line when nothing was logged.
  final String emptyText;
  final double height;

  @override
  State<TraceChart> createState() => _TraceChartState();
}

class _TraceChartState extends State<TraceChart> {
  int? _focus;

  static const _bottomInset = 24.0;

  @override
  void didUpdateWidget(TraceChart old) {
    super.didUpdateWidget(old);
    if (_focus != null && _focus! >= widget.points.length) _focus = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final points = widget.points;
    final both = points.any((p) => p.received != null);
    var biggest = 0;
    for (final p in points) {
      if (p.spent > biggest) biggest = p.spent;
      if ((p.received ?? 0) > biggest) biggest = p.received!;
    }

    if (biggest == 0) {
      return SizedBox(
        key: const ValueKey('trace-chart'),
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: 8,
              bottom: _bottomInset,
              child: CustomPaint(painter: GraticulePainter(c, flat: true)),
            ),
            Text(
              widget.emptyText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final signature = points
        .map((p) => '${p.label}${p.spent}${p.received}')
        .join('|');
    return Column(
      key: const ValueKey('trace-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClampedTextScale(
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(
                  top: 8,
                  bottom: _bottomInset,
                  child: CustomPaint(painter: GraticulePainter(c)),
                ),
                TweenAnimationBuilder<double>(
                  key: ValueKey(signature),
                  tween: Tween(begin: reduce ? 1 : 0, end: 1),
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 700),
                  builder: (context, t, _) => Row(
                    children: [
                      for (var i = 0; i < points.length; i++)
                        Expanded(
                          child: _MonthColumn(
                            key: ValueKey('trace-month-$i'),
                            point: points[i],
                            symbol: widget.symbol,
                            both: both,
                            biggest: biggest,
                            rise: Curves.easeOutCubic.transform(
                              (t * 1.6 - i * 0.06).clamp(0.0, 1.0),
                            ),
                            dimmed: _focus != null && _focus != i,
                            focused: _focus == i,
                            bottomInset: _bottomInset,
                            onTap: () =>
                                setState(() => _focus = _focus == i ? null : i),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _TraceReadout(
          key: const ValueKey('trace-readout'),
          point: _focus == null ? null : points[_focus!],
          symbol: widget.symbol,
        ),
      ],
    );
  }
}

class _MonthColumn extends StatelessWidget {
  const _MonthColumn({
    super.key,
    required this.point,
    required this.symbol,
    required this.both,
    required this.biggest,
    required this.rise,
    required this.dimmed,
    required this.focused,
    required this.bottomInset,
    required this.onTap,
  });

  final TracePoint point;
  final String symbol;
  final bool both;
  final int biggest;
  final double rise;
  final bool dimmed;
  final bool focused;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final labelColor = dimmed ? c.faint : (focused ? c.text : c.dim);
    final spoken = StringBuffer(point.title);
    if (point.inProgress) spoken.write(', so far');
    if (point.received != null) {
      spoken.write(', received ${formatMoney(point.received!, symbol)}');
    }
    spoken.write(', spent ${formatMoney(point.spent, symbol)}');

    Widget peak(int cents, Color color, double width, double room) {
      if (cents == 0) return SizedBox(width: width);
      final fraction = (cents / biggest * rise).clamp(0.0, 1.0);
      return Container(
        width: width,
        height: (room * fraction).clamp(3.0, room),
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: dimmed ? 0.32 : (point.inProgress ? 0.6 : 1),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
    }

    return Semantics(
      button: true,
      selected: focused,
      label: spoken.toString(),
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.bottomCenter,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (both) ...[
                          peak(
                            point.received ?? 0,
                            c.received,
                            9,
                            box.maxHeight,
                          ),
                          const SizedBox(width: 2),
                          peak(point.spent, c.spentFill, 9, box.maxHeight),
                        ] else
                          peak(point.spent, c.spentFill, 18, box.maxHeight),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: bottomInset,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      point.label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: labelColor,
                        letterSpacing: 0,
                        fontWeight: focused ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TraceReadout extends StatelessWidget {
  const _TraceReadout({super.key, required this.point, required this.symbol});

  final TracePoint? point;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final p = point;
    if (p == null) {
      return Text(
        'Tap a month for detail',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return TraceFigures(point: p, symbol: symbol, showTitle: true);
  }
}

/// A month's figures as labelled values: Received, Spent, Net and the share
/// kept (or just Spent for a single category).
class TraceFigures extends StatelessWidget {
  const TraceFigures({
    super.key,
    required this.point,
    required this.symbol,
    this.showTitle = false,
  });

  final TracePoint point;
  final String symbol;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    // One piece of text, so a long figure wraps at large sizes instead of
    // overflowing.
    Widget value(String label, String text, Color color) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
          TextSpan(
            text: text,
            style: monoText(size: 14, color: color),
          ),
        ],
      ),
    );
    final p = point;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: Text(
              '${p.title.toUpperCase()}${p.inProgress ? ' · SO FAR' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(color: c.text),
            ),
          ),
        Wrap(
          spacing: Gap.l,
          runSpacing: Gap.xs,
          children: [
            if (p.received != null)
              value(
                'Received',
                formatMoney(p.received!, symbol, showPlus: true),
                c.received,
              ),
            value('Spent', formatMoney(-p.spent, symbol), c.spent),
            if (p.net != null)
              value(
                'Net',
                formatMoney(p.net!, symbol, showPlus: true),
                p.net! < 0 ? c.spent : c.text,
              ),
            if (p.purity != null) value('Kept', purityText(p.purity!), c.dim),
          ],
        ),
      ],
    );
  }
}

/// The same months as text, newest first, for people who read the figures
/// rather than the peaks (and at very large text sizes).
class TraceList extends StatelessWidget {
  const TraceList({super.key, required this.points, required this.symbol});

  final List<TracePoint> points;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('trace-list'),
      children: [
        for (final p in points.reversed)
          MergeSemantics(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: Gap.s),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.inProgress ? '${p.title} (so far)' : p.title,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: Gap.xs),
                  TraceFigures(point: p, symbol: symbol),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
