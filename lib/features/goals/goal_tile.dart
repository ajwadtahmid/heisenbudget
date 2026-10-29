import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../providers/goal_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';

/// A slim bar showing [permille] (0 to 1000) of a goal. Decorative: the
/// percentage is always written next to it.
class GoalBar extends StatelessWidget {
  const GoalBar({super.key, required this.permille, this.height = 6});

  final int permille;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: c.hairline)),
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (permille.clamp(0, 1000)) / 1000,
                  child: ColoredBox(color: c.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One goal in a list: its icon and name, "$320.00 of $1,000.00", a slim bar
/// and the percentage. Tapping opens [onTap].
class GoalTile extends ConsumerWidget {
  const GoalTile({
    super.key,
    required this.view,
    this.onTap,
    this.trailing,
    this.rank,
  });

  final GoalView view;
  final VoidCallback? onTap;

  /// Something after the percentage, such as a drag handle.
  final Widget? trailing;

  /// Its place in the list, 1 first (the priority), shown before the icon.
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final plan = view.plan;
    final percent = purityText(plan.permille);
    final amounts =
        '${formatMoney(plan.savedCents, symbol)} of '
        '${formatMoney(plan.targetCents, symbol)}';

    return MergeSemantics(
      child: Semantics(
        label:
            '${rank == null ? '' : 'Number $rank, '}${view.goal.name}, '
            '${copy.goalYield.toLowerCase()} $percent, $amounts',
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.s),
              child: Row(
                children: [
                  if (rank != null) ...[
                    SizedBox(
                      width: 28,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$rank',
                          key: ValueKey('goal-rank-${view.goal.id}'),
                          style: monoText(size: 15, color: c.dim),
                        ),
                      ),
                    ),
                  ],
                  CategoryTile(iconKey: view.goal.icon, size: 40),
                  const SizedBox(width: Gap.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.goal.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          amounts,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.dim,
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        GoalBar(permille: plan.permille),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.m),
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 88),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          percent,
                          style: monoText(size: 15, color: c.text),
                        ),
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
