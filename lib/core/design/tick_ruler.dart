import 'package:flutter/material.dart';

import '../../domain/date_range.dart';
import 'app_colors.dart';

/// A ruler of ticks under the period control: one tick per day of the period
/// (per week for very long ranges). Days up to today are drawn solid, days to
/// come are faint, and today carries a tall accent tick, so it doubles as a
/// "how far through the period are we" gauge.
class TickRuler extends StatelessWidget {
  const TickRuler({super.key, required this.range, required this.today});

  final DateRange range;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          // The ruler fills in once when it appears or the period changes.
          key: ValueKey((range.start, range.end)),
          tween: Tween(begin: reduce ? 1 : 0, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, progress, _) => CustomPaint(
            painter: _TickPainter(
              range: range,
              today: today,
              past: c.dim,
              future: c.faint.withValues(alpha: 0.8),
              marker: c.accent,
              progress: progress,
            ),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter({
    required this.range,
    required this.today,
    required this.past,
    required this.future,
    required this.marker,
    required this.progress,
  });

  final DateRange range;
  final DateTime today;
  final Color past;
  final Color future;
  final Color marker;
  final double progress;

  static int _days(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  @override
  void paint(Canvas canvas, Size size) {
    final total = range.lengthInDays;
    // Dense ranges tick by week so the ticks stay readable.
    final unit = total > 62 ? 7 : 1;
    final count = (total + unit - 1) ~/ unit;
    final slot = size.width / count;
    final elapsed = _days(range.start, today); // negative = not started
    final todayIndex = elapsed >= 0 && elapsed < total ? elapsed ~/ unit : -1;
    final stroke = slot > 5 ? 1.5 : 1.0;

    for (var i = 0; i < count; i++) {
      final isToday = i == todayIndex;
      final isMajor = unit == 1 ? i % 7 == 0 : i % 4 == 0;
      final height = isToday ? 14.0 : (isMajor ? 10.0 : 6.0);
      final started = i * unit <= elapsed;
      final paint = Paint()
        ..strokeWidth = isToday ? 2 : stroke
        ..strokeCap = StrokeCap.round
        ..color = isToday ? marker : (started ? past : future);

      // Ticks rise from a common baseline, left to right as time passes.
      final reveal = (progress * count - i * 0.6).clamp(0.0, 1.0);
      if (reveal <= 0) continue;
      final x = slot * i + slot / 2;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - height * reveal),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.range != range ||
      old.today != today ||
      old.progress != progress ||
      old.past != past ||
      old.future != future ||
      old.marker != marker;
}
