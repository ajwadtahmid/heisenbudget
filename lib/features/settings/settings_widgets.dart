import 'package:flutter/material.dart';

import '../../core/design/section_label.dart';
import '../../core/theme.dart';

/// A labelled group of rows on the Settings page.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: Gap.s),
        ...children,
        const SizedBox(height: Gap.l),
      ],
    );
  }
}

/// One row: outlined icon, title, a dim summary that says where it leads or
/// what is set, and a chevron when it opens a page.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.summary,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
    this.enabled = true,
    this.emphasizeSummary = false,
  });

  final IconData icon;
  final String title;
  final String? summary;
  final VoidCallback? onTap;

  /// Shows a chevron, for rows that open a page.
  final bool chevron;

  /// Draws the row in the error colour (Erase everything).
  final bool destructive;
  final bool enabled;

  /// The summary in full-strength text instead of dim (for a warning that
  /// must not be missed, never by colour alone: the words say it too).
  final bool emphasizeSummary;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final tint = destructive ? c.error : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(icon, color: tint),
      title: Text(title, style: tint == null ? null : TextStyle(color: tint)),
      subtitle: summary == null
          ? null
          : Text(
              summary!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: emphasizeSummary
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
      trailing: chevron ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

/// Opens [page] from Settings.
Future<T?> pushSettingsPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push(MaterialPageRoute<T>(builder: (_) => page));
}
