import 'package:flutter/material.dart';

/// A section head for ledger-style screens: a tracked caps label with a
/// hairline running out to the right, and an optional action at the end.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Text(text.toUpperCase(), style: theme.textTheme.labelMedium),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.dividerColor)),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}
