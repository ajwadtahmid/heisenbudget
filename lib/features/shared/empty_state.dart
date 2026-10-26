import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Centered outlined icon + message, with an optional button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.panel),
                border: Border.all(color: c.hairline),
              ),
              child: Icon(icon, size: 26, color: c.faint),
            ),
            const SizedBox(height: Gap.l),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: c.dim),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: Gap.m),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
    // In a short, bounded area (large text, a tall header above) it scrolls
    // instead of overflowing; inside a list it simply takes its own height.
    return LayoutBuilder(
      builder: (context, box) => box.hasBoundedHeight
          ? SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: content,
              ),
            )
          : content,
    );
  }
}
