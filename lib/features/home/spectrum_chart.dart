import 'package:flutter/material.dart';

import '../../core/category_icons.dart';
import '../../core/theme.dart';
import '../../core/formatters.dart';
import '../../domain/category_spend.dart';

/// Spending per category as sorted amber "peaks" over a faint graticule.
///
/// Tap a peak to focus it: the others dim and a readout line gives its exact
/// share and amount. Drawn with plain widgets and one painter (no chart
/// package), so every bar is also a real, labelled button for screen readers.
class SpectrumChart extends StatefulWidget {
  const SpectrumChart({
    super.key,
    required this.bars,
    required this.symbol,
    required this.emptyText,
    this.height = 152,
  });

  final List<SpectrumBar> bars;
  final String symbol;

  /// Shown on the flat line when nothing was spent.
  final String emptyText;
  final double height;

  @override
  State<SpectrumChart> createState() => _SpectrumChartState();
}

class _SpectrumChartState extends State<SpectrumChart> {
  int? _focus;

  // Space above and below the plot area for the % label and icon + name.
  static const _topInset = 20.0;
  static const _bottomInset = 46.0;

  @override
  void didUpdateWidget(SpectrumChart old) {
    super.didUpdateWidget(old);
    // A new period or new data: drop a focus that no longer exists.
    if (_focus != null && _focus! >= widget.bars.length) _focus = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final mq = MediaQuery.of(context);
    final bars = widget.bars;

    if (bars.isEmpty) {
      return SizedBox(
        key: const ValueKey('spectrum-chart'),
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: _topInset,
              bottom: _bottomInset,
              child: CustomPaint(painter: _GraticulePainter(c, flat: true)),
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

    final biggest = bars.map((b) => b.cents).reduce((a, b) => a > b ? a : b);
    final signature = bars.map((b) => '${b.label}${b.cents}').join('|');

    return Column(
      key: const ValueKey('spectrum-chart'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Labels inside the chart stay compact even at huge text sizes: the
        // full figures are always in the readout line and screen-reader text.
        MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                Positioned.fill(
                  top: _topInset,
                  bottom: _bottomInset,
                  child: CustomPaint(painter: _GraticulePainter(c)),
                ),
                TweenAnimationBuilder<double>(
                  key: ValueKey(signature),
                  tween: Tween(begin: reduce ? 1 : 0, end: 1),
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 700),
                  builder: (context, t, _) => Row(
                    children: [
                      for (var i = 0; i < bars.length; i++)
                        Expanded(
                          child: _PeakColumn(
                            key: ValueKey('spectrum-bar-$i'),
                            bar: bars[i],
                            symbol: widget.symbol,
                            // Peaks rise left to right, each easing out.
                            rise: Curves.easeOutCubic.transform(
                              (t * 1.6 - i * 0.12).clamp(0.0, 1.0),
                            ),
                            heightFactor: bars[i].cents / biggest,
                            dimmed: _focus != null && _focus != i,
                            focused: _focus == i,
                            topInset: _topInset,
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
        _Readout(
          key: const ValueKey('spectrum-readout'),
          bar: _focus == null ? null : bars[_focus!],
          symbol: widget.symbol,
        ),
      ],
    );
  }
}

class _PeakColumn extends StatelessWidget {
  const _PeakColumn({
    super.key,
    required this.bar,
    required this.symbol,
    required this.rise,
    required this.heightFactor,
    required this.dimmed,
    required this.focused,
    required this.topInset,
    required this.bottomInset,
    required this.onTap,
  });

  final SpectrumBar bar;
  final String symbol;
  final double rise;
  final double heightFactor;
  final bool dimmed;
  final bool focused;
  final double topInset;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final barColor = c.spentFill.withValues(alpha: dimmed ? 0.32 : 1);
    final labelColor = dimmed ? c.faint : (focused ? c.text : c.dim);

    return Semantics(
      button: true,
      selected: focused,
      label:
          '${bar.label}, ${bar.percentDetailText}, '
          '${formatMoney(bar.cents, symbol)}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.chip),
          child: Column(
            children: [
              SizedBox(
                height: topInset,
                child: Center(
                  child: Text(
                    bar.percentText,
                    maxLines: 1,
                    style: monoText(
                      size: 12,
                      weight: focused ? FontWeight.w600 : FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: (heightFactor * rise).clamp(0.0, 1.0),
                    child: Container(
                      width: 24,
                      constraints: const BoxConstraints(minHeight: 3),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: bottomInset,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      categoryIconFor(bar.iconKey).icon,
                      size: 18,
                      color: labelColor,
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        bar.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: labelColor,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({super.key, required this.bar, required this.symbol});

  final SpectrumBar? bar;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final focused = bar;
    if (focused == null) {
      return Text('Tap a peak for detail', style: theme.textTheme.bodySmall);
    }
    return Row(
      children: [
        Icon(categoryIconFor(focused.iconKey).icon, size: 16, color: c.spent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${focused.label.toUpperCase()} · ${focused.percentDetailText}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: c.text),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatMoney(focused.cents, symbol),
          style: monoText(size: 15, color: c.spent),
        ),
      ],
    );
  }
}

/// Four hairlines and a stronger baseline: the chart's graticule. With
/// [flat] only the baseline is drawn (the "flat line" empty state).
class _GraticulePainter extends CustomPainter {
  const _GraticulePainter(this.colors, {this.flat = false});

  final AppColors colors;
  final bool flat;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = colors.hairline.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final base = Paint()
      ..color = flat ? colors.dim : colors.faint
      ..strokeWidth = 1.5;
    if (!flat) {
      for (var i = 1; i <= 4; i++) {
        final y = size.height * (1 - i / 4);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }
    }
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      base,
    );
  }

  @override
  bool shouldRepaint(_GraticulePainter old) =>
      old.colors != colors || old.flat != flat;
}
