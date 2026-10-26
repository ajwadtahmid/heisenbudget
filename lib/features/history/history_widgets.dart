import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// An outlined 48dp control: icon, a label, and an optional trailing icon.
/// Used for the Filter and Sort controls under the History title. Passing
/// [onTap] makes it a button; inside a PopupMenuButton the menu handles taps.
class ControlFace extends StatelessWidget {
  const ControlFace({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.trailing,
    this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final IconData? trailing;
  final VoidCallback? onTap;

  /// Draws the border and icon in the accent (an active filter).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final face = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.only(left: 12, right: trailing == null ? 14 : 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.input),
        border: Border.all(
          color: highlighted ? c.accent : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: highlighted ? c.accent : c.dim),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: highlighted ? c.accent : c.text),
            ),
          ),
          if (trailing != null) Icon(trailing, color: c.dim),
        ],
      ),
    );
    if (onTap == null) return face;
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.input),
        onTap: onTap,
        child: face,
      ),
    );
  }
}

/// A day's date and net total. Pinned: it stays at the top while that day's
/// rows scroll under it, then the next day pushes it away.
class DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  DayHeaderDelegate({
    required this.label,
    required this.net,
    required this.colors,
    required this.labelStyle,
  });

  final String label;
  final String? net;
  final AppColors colors;
  final TextStyle? labelStyle;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
          if (net != null) ...[
            const SizedBox(width: 12),
            Text(net!, style: monoText(size: 14, color: colors.dim)),
          ],
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(DayHeaderDelegate old) =>
      label != old.label ||
      net != old.net ||
      !identical(colors, old.colors) ||
      labelStyle != old.labelStyle;
}
