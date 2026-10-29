import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/goal_repository.dart';
import '../domain/goals.dart';
import '../domain/iso_date.dart';
import 'database_providers.dart';
import 'period_providers.dart';

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(appDatabaseProvider)),
);

/// Every goal in list order.
final goalsProvider = StreamProvider<List<SavingsGoalRow>>(
  (ref) => ref.watch(goalRepositoryProvider).watchGoals(),
);

/// Every entry of every goal, oldest first.
final goalEntriesProvider = StreamProvider<List<GoalEntryRow>>(
  (ref) => ref.watch(goalRepositoryProvider).watchEntries(),
);

/// A goal with its entries (newest first) and where it stands today.
class GoalView {
  const GoalView({
    required this.goal,
    required this.entries,
    required this.plan,
  });

  final SavingsGoalRow goal;
  final List<GoalEntryRow> entries;
  final GoalPlan plan;

  DateTime? get targetDate =>
      goal.targetDate == null ? null : fromIsoDate(goal.targetDate!);
}

/// Every goal worked out as of today, in list order. Loading and errors pass
/// through, so a screen can tell a failed read from an empty list.
final goalViewsProvider = Provider<AsyncValue<List<GoalView>>>((ref) {
  final goalsAsync = ref.watch(goalsProvider);
  final entriesAsync = ref.watch(goalEntriesProvider);
  final today = ref.watch(clockProvider);
  for (final input in [goalsAsync, entriesAsync]) {
    if (input.isLoading) return const AsyncLoading();
    if (input.hasError) return AsyncError(input.error!, input.stackTrace!);
  }
  final byGoal = <int, List<GoalEntryRow>>{};
  for (final e in entriesAsync.requireValue) {
    byGoal.putIfAbsent(e.goalId, () => []).add(e);
  }
  GoalView viewOf(SavingsGoalRow goal) {
    final entries = byGoal[goal.id] ?? const <GoalEntryRow>[];
    final due = goal.targetDate == null ? null : fromIsoDate(goal.targetDate!);
    return GoalView(
      goal: goal,
      // Newest first, for the history list.
      entries: entries.reversed.toList(),
      plan: planGoal(
        targetCents: goal.targetCents,
        moves: [
          for (final e in entries) GoalMove(fromIsoDate(e.date), e.amountCents),
        ],
        today: today,
        startedOn: dateOnly(goal.createdAt),
        targetDate: due,
      ),
    );
  }

  return AsyncData([for (final goal in goalsAsync.requireValue) viewOf(goal)]);
});

/// The goals not yet reached, in list order.
final activeGoalsProvider = Provider<AsyncValue<List<GoalView>>>(
  (ref) => ref.watch(goalViewsProvider).whenData((all) {
    return [
      for (final g in all)
        if (!g.plan.reached) g,
    ];
  }),
);

/// The goals that are reached, in list order.
final doneGoalsProvider = Provider<AsyncValue<List<GoalView>>>(
  (ref) => ref.watch(goalViewsProvider).whenData((all) {
    return [
      for (final g in all)
        if (g.plan.reached) g,
    ];
  }),
);

/// One goal by id; null when it does not exist (deleted).
final goalViewProvider = Provider.family<GoalView?, int>(
  (ref, id) => ref
      .watch(goalViewsProvider)
      .value
      ?.where((g) => g.goal.id == id)
      .firstOrNull,
);

/// Reads the goals again (a screen's "Try again").
void reloadGoals(WidgetRef ref) {
  ref.invalidate(goalsProvider);
  ref.invalidate(goalEntriesProvider);
}
