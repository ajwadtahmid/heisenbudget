import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/category_spend.dart' show purityText;
import '../../providers/goal_providers.dart';
import '../shared/insight_row.dart';
import 'goal_sheet.dart';
import 'goal_tile.dart';
import 'goals_screen.dart';

/// Goals on the Insights tab, as one small row: the first goal still being
/// saved for with its bar, and a way to all of them. With none yet, it starts
/// one.
class GoalsRow extends ConsumerWidget {
  const GoalsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(goalViewsProvider);
    final active = ref.watch(activeGoalsProvider).value ?? const [];

    String? subtitle;
    Widget? bar;
    VoidCallback onTap = () => openGoals(context);
    if (all.hasError && !all.isLoading) {
      subtitle = 'Could not load your goals. Tap to try again.';
      onTap = () => reloadGoals(ref);
    } else if (all.value != null) {
      if (all.value!.isEmpty) {
        subtitle = 'Set a goal';
        onTap = () => showGoalSheet(context);
      } else if (active.isEmpty) {
        subtitle = 'Every goal is reached.';
      } else {
        final top = active.first;
        final more = active.length - 1;
        subtitle =
            'Top priority: ${top.goal.name} · '
            '${purityText(top.plan.permille)}'
            '${more > 0 ? ' · $more more' : ''}';
        bar = GoalBar(permille: top.plan.permille);
      }
    }

    return InsightRow(
      key: const ValueKey('insights-goals'),
      icon: Icons.savings_outlined,
      title: 'Goals',
      subtitle: subtitle,
      bottom: bar,
      onTap: onTap,
    );
  }
}
