import 'package:flutter/material.dart';

import '../../core/category_icons.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/database/app_database.dart';

/// One favorite as a button: category icon, name and, when it has one, the
/// amount in mono. 48dp tall; wraps onto the next line instead of overflowing.
class FavoriteChip extends StatelessWidget {
  const FavoriteChip({
    super.key,
    required this.favorite,
    required this.iconKey,
    required this.symbol,
    required this.onTap,
    required this.onLongPress,
  });

  final FavoriteRow favorite;
  final String? iconKey;
  final String symbol;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = Theme.of(context);
    final cents = favorite.amountCents;
    final amount = cents == null ? null : formatMoney(cents, symbol);
    final radius = BorderRadius.circular(Radii.chip);

    return Semantics(
      container: true,
      button: true,
      label: amount == null
          ? '${favorite.label}. Opens the Add sheet to enter the amount.'
          : '${favorite.label}, $amount. Logs it today.',
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: 'Fill in the form',
      child: ExcludeSemantics(
        child: Material(
          color: c.panel,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.hairline),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(categoryIconFor(iconKey).icon, size: 18, color: c.dim),
                    const SizedBox(width: Gap.s),
                    Flexible(
                      child: Text(
                        favorite.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (amount != null) ...[
                      const SizedBox(width: Gap.s),
                      Text(amount, style: monoText(size: 13, color: c.dim)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
