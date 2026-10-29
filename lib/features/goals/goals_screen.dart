import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/theme.dart';
import '../../providers/goal_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/empty_state.dart';
import 'goal_detail_screen.dart';
import 'goal_sheet.dart';
import 'goal_tile.dart';

/// Opens the list of goals over the app.
Future<void> openGoals(BuildContext context) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));
}

/// Every goal: the ones still being saved for (drag to reorder), then the ones
/// that are reached.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final all = ref.watch(goalViewsProvider);
    final active = ref.watch(activeGoalsProvider).value ?? const [];
    final done = ref.watch(doneGoalsProvider).value ?? const [];

    final Widget body;
    if (all.hasError && !all.isLoading) {
      body = EmptyState(
        key: const ValueKey('goals-error'),
        icon: Icons.error_outline,
        message: 'Could not load your goals.',
        actionLabel: 'Try again',
        onAction: () => reloadGoals(ref),
      );
    } else if (all.value == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (all.value!.isEmpty) {
      body = EmptyState(
        key: const ValueKey('goals-empty'),
        icon: Icons.savings_outlined,
        message: ref.watch(copyProvider).emptyGoals,
        actionLabel: 'Set a goal',
        onAction: () => showGoalSheet(context),
      );
    } else {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 40),
        buildDefaultDragHandles: false,
        header: Padding(
          padding: const EdgeInsets.only(right: 12, bottom: Gap.s),
          child: Text(
            active.length > 1
                ? 'Goals are tracked separately from your balance. Number 1 is '
                      'your top priority: drag the handles to change the order.'
                : 'Goals are tracked separately from your balance.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
        ),
        footer: done.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Gap.xl),
                    const SectionLabel('Reached'),
                    const SizedBox(height: Gap.s),
                    for (final g in done)
                      DecoratedBox(
                        key: ValueKey('goal-row-${g.goal.id}'),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: c.hairline)),
                        ),
                        child: GoalTile(
                          view: g,
                          onTap: () => openGoal(context, g.goal.id),
                        ),
                      ),
                  ],
                ),
              ),
        itemCount: active.length,
        onReorderItem: (from, to) {
          final ids = [for (final g in active) g.goal.id];
          ids.insert(to, ids.removeAt(from));
          ref.read(goalRepositoryProvider).reorder(ids);
        },
        itemBuilder: (context, index) {
          final g = active[index];
          return DecoratedBox(
            key: ValueKey('goal-row-${g.goal.id}'),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: GoalTile(
              view: g,
              rank: index + 1,
              onTap: () => openGoal(context, g.goal.id),
              trailing: ReorderableDragStartListener(
                index: index,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.drag_handle,
                    semanticLabel: 'Drag to reorder',
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          IconButton(
            key: const ValueKey('goals-add'),
            tooltip: 'New goal',
            icon: const Icon(Icons.add),
            onPressed: () => showGoalSheet(context),
          ),
        ],
      ),
      body: body,
    );
  }
}
