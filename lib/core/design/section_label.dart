import 'package:flutter/material.dart';

/// A section head for ledger-style screens: a tracked caps label with a
/// hairline running out to the right, and an optional action at the end.
///
/// At large text the label can fill the line. Then the hairline is left out, so
/// the label wraps between words (never inside one) and keeps the whole width.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  /// Room the hairline needs to be worth drawing, and the gap before it.
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
          // The action's width is not known; leave generous room for it.
          final reserved = trailing == null ? 0.0 : 56.0;
          final fits =
              painter.width + _gap + _minLine + reserved <= box.maxWidth;
          painter.dispose();
          return Row(
            children: [
              // Flexible so a long heading wraps at large text instead of overflowing.
              Flexible(child: Text(label, style: style)),
              if (fits) ...[
                const SizedBox(width: _gap),
                Expanded(child: Divider(color: theme.dividerColor)),
              ],
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          );
        },
      ),
    );
  }
}
