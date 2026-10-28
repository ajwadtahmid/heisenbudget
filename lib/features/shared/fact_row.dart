import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A label (and a dim line under it) at the left, a value at the right. Both
/// shrink and wrap together at large text instead of overflowing.
class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.valueIsPlain = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String? subtitle;

  /// Words rather than an amount: not set in the mono figures.
  final bool valueIsPlain;

  /// Makes the whole row a button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Gap.m),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                style: valueIsPlain
                    ? theme.textTheme.bodyMedium?.copyWith(color: c.dim)
                    : monoText(size: 15, color: c.text),
              ),
            ),
          ),
        ],
      ),
    );
    return MergeSemantics(
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}
