import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/section_label.dart';
import '../../core/design/text_scale.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repositories/goal_repository.dart';
import '../../domain/category_spend.dart' show purityText;
import '../../domain/iso_date.dart';
import '../../providers/goal_providers.dart';
import '../../providers/settings_providers.dart';
import '../shared/category_tile.dart';
import 'goal_entry_sheet.dart';
import 'goal_sheet.dart';
import 'goal_text.dart';
import 'goal_tile.dart';

/// Opens one goal over the app.
Future<void> openGoal(BuildContext context, int goalId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => GoalDetailScreen(goalId: goalId)),
  );
}

/// One goal: how far along it is, what its pace and date say, buttons to put
/// money in or take it out, and every entry with a way to remove it.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final int goalId;

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    int entryId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this entry?'),
        content: const Text('What is in the goal changes by that amount.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('goal-entry-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(goalRepositoryProvider).deleteEntry(entryId);
    } on GoalBelowZeroException {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Later money taken out depends on this entry. Remove that '
              'first.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.appColors;
    final copy = ref.watch(copyProvider);
    final symbol = ref.watch(settingsProvider.select((s) => s.currencySymbol));
    final view = ref.watch(goalViewProvider(goalId));
    final loaded = ref.watch(goalViewsProvider).hasValue;

    // The goal was deleted (from its own edit sheet): leave the page.
    ref.listen(goalViewProvider(goalId), (before, after) {
      if (before != null && after == null && context.mounted) {
        Navigator.of(context).maybePop();
      }
    });

    if (view == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Goal')),
        body: Center(
          child: loaded
              ? const Text('This goal is gone.')
              : const CircularProgressIndicator(),
        ),
      );
    }
    final goal = view.goal;
    final plan = view.plan;
    final lines = goalPlanLines(plan, view.targetDate, symbol);

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('goal-edit'),
            tooltip: 'Edit goal',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGoalSheet(context, existing: view),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(
            children: [
              CategoryTile(iconKey: goal.icon, size: 48),
              const SizedBox(width: Gap.l),
              Expanded(
                child: ClampedTextScale(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy.goalYield,
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 2.2,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          purityText(plan.permille),
                          key: const ValueKey('goal-percent'),
                          style: monoText(
                            size: 32,
                            weight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.m),
          GoalBar(permille: plan.permille, height: 8),
          const SizedBox(height: Gap.s),
          Text(
            '${formatMoney(plan.savedCents, symbol)} of '
            '${formatMoney(plan.targetCents, symbol)}',
            key: const ValueKey('goal-amounts'),
            style: theme.textTheme.bodyMedium,
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: Gap.xs),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
              ),
            ),
          const SizedBox(height: Gap.l),
          OverflowBar(
            alignment: MainAxisAlignment.start,
            spacing: Gap.s,
            overflowSpacing: Gap.xs,
            children: [
              FilledButton.tonal(
                key: const ValueKey('goal-add-money'),
                onPressed: () => showGoalEntrySheet(context, view: view),
                child: const Text('Add money'),
              ),
              TextButton(
                key: const ValueKey('goal-take-out'),
                onPressed: plan.savedCents > 0
                    ? () =>
                          showGoalEntrySheet(context, view: view, takeOut: true)
                    : null,
                child: const Text('Take out'),
              ),
            ],
          ),
          const SizedBox(height: Gap.s),
          Text(
            'Goals are tracked separately from your balance.',
            style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
          ),
          const SizedBox(height: Gap.xl),
          const SectionLabel('History'),
          const SizedBox(height: Gap.s),
          if (view.entries.isEmpty)
            Text(
              'Nothing put in yet.',
              key: const ValueKey('goal-no-entries'),
              style: theme.textTheme.bodySmall?.copyWith(color: c.dim),
            )
          else
            for (final e in view.entries)
              Container(
                key: ValueKey('goal-entry-${e.id}'),
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.hairline)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatDate(fromIsoDate(e.date)),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatMoney(e.amountCents, symbol, showPlus: true),
                          style: monoText(size: 15, color: c.text),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('goal-entry-delete-${e.id}'),
                      tooltip: 'Remove this entry',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmRemove(context, ref, e.id),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
