import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A row that opens a page: an icon, a title, a dim line under it, an optional
/// extra under that, and an arrow. Wraps at large text instead of overflowing.
class InsightRow extends StatelessWidget {
  const InsightRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.bottom,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Shown under the subtitle, such as a slim bar.
  final Widget? bottom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: Gap.s),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 24, color: c.dim),
                const SizedBox(width: Gap.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.dim,
                          ),
                        ),
                      if (bottom != null) ...[
                        const SizedBox(height: Gap.xs),
                        bottom!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gap.s),
                Icon(Icons.chevron_right, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
