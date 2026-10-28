import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/trends.dart';
import '../shared/category_tile.dart';

/// One category that spent more (up) or less than it usually does: its name,
/// this month against the usual, and the difference.
class MoverRow extends StatelessWidget {
  const MoverRow({
    super.key,
    required this.move,
    required this.up,
    required this.symbol,
  });

  final CategoryMove move;
  final bool up;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.appColors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: Row(
          children: [
            CategoryTile(iconKey: move.icon, size: 32),
            const SizedBox(width: Gap.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(move.name, style: theme.textTheme.bodyMedium),
                  Text(
                    '${formatMoney(move.currentCents, symbol)} against '
                    '${formatMoney(move.averageCents, symbol)} usually',
                    style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.s),
            // The figure shrinks before it can push the name off the row.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      up ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 16,
                      color: up ? c.spent : c.dim,
                    ),
                    Text(
                      formatMoney(move.deltaCents, symbol, showPlus: true),
                      style: monoText(size: 14, color: up ? c.spent : c.dim),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
