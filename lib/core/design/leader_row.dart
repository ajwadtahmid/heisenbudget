import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_font.dart';

/// A ruled readout line: `RECEIVED ········ +$5,000.00`.
/// The label sits left, the amount right in tabular mono, joined by a dotted
/// leader like a printed ledger or instrument panel.
class LeaderRow extends StatelessWidget {
  const LeaderRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;

  /// Small arrow or glyph in front of the label (never the only cue: the
  /// value always carries its own sign).
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: valueColor ?? c.dim),
          const SizedBox(width: 8),
        ],
        Text(label, style: labelStyle),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 12,
            child: CustomPaint(painter: _LeaderPainter(c.faint)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: monoText(
            size: 17,
            weight: FontWeight.w500,
            color: valueColor ?? c.text,
          ),
        ),
      ],
    );

    return MergeSemantics(
      child: Semantics(
        label: '$label $value',
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            // At the normal size the row simply fills the width. When large
            // text or a huge amount would not fit, the whole row scales down
            // together instead of overflowing.
            child: LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: IntrinsicWidth(child: row),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dots along the baseline, 4dp apart.
class _LeaderPainter extends CustomPainter {
  const _LeaderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final y = size.height - 2;
    for (var x = 1.0; x < size.width; x += 4) {
      canvas.drawCircle(Offset(x, y), 0.8, paint);
    }
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => old.color != color;
}
