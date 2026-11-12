import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// A tracked section label and rule, with an optional trailing action. The
/// rule uses the space remaining after the action has actually been laid out.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;
  static const _minLine = 24.0;
  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium;
    final label = text.toUpperCase();
    return Semantics(
      header: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final labelWidth = painter.width;
          painter.dispose();
          return Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, remaining) {
                    if (labelWidth + _gap + _minLine <= remaining.maxWidth) {
                      return Row(
                        children: [
                          Text(label, style: style),
                          const SizedBox(width: _gap),
                          Expanded(child: Divider(color: theme.dividerColor)),
                        ],
                      );
                    }
                    return Text(label, style: style);
                  },
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                // Preserve room for the label. Long actions can wrap instead of
                // consuming an unbounded width or relying on a fixed estimate.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(
                      0,
                      box.maxWidth - math.min(labelWidth, box.maxWidth / 2) - 4,
                    ),
                  ),
                  child: trailing!,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
