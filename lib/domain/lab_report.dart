// PURE DART: no Flutter imports. The numbers and rules behind the month-end
// report.
import 'backup_status.dart';
import 'budget.dart';
import 'date_range.dart';
import 'goals.dart';
import 'iso_date.dart';

/// The report is announced on Home for this many days after a budget month
/// ends (the first days of the next one).
const reportNoticeDays = 7;

/// How many finished months the Reports list offers.
const reportMonthsListed = 12;

/// The month the report is about on [today]: the last finished budget month.
BudgetMonth reportMonthFor(DateTime today, int startDay) =>
    BudgetMonth.containing(today, startDay).shift(-1);

/// The report Home should announce on [today], or null: only in the first
/// [reportNoticeDays] days of a budget month, and not once that month's report
/// (or a later one) has been opened. [seenMonth] is a budget month key such as
/// `2026-09`.
BudgetMonth? reportDue({
  required DateTime today,
  required int startDay,
  required String? seenMonth,
}) {
  final current = BudgetMonth.containing(today, startDay);
  final first = current.range(startDay).start;
  final day = dateOnly(today);
  final elapsed = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
  if (elapsed >= reportNoticeDays) return null;
  final month = current.shift(-1);
  if (seenMonth != null && seenMonth.compareTo(month.key) >= 0) return null;
  return month;
}

/// One finished period of a budget, with what was spent.
class BudgetPeriodResult {
  const BudgetPeriodResult({
    required this.categoryId,
    required this.name,
    required this.limitCents,
    required this.spentCents,
  });

  /// Null for the budget on all spending.
  final int? categoryId;
  final String name;
  final int limitCents;
  final int spentCents;

  int get overCents => spentCents > limitCents ? spentCents - limitCents : 0;
}

/// How one budget did over a month: one period for a monthly budget, several
/// for a weekly one.
class ReportBudget {
  const ReportBudget({
    required this.categoryId,
    required this.name,
    required this.periods,
    required this.overPeriods,
    required this.limitCents,
    required this.spentCents,
    required this.overCents,
  });

  final int? categoryId;
  final String name;

  /// How many of its periods ended in the month, and how many of those ended
  /// over the limit.
  final int periods;
  final int overPeriods;

  /// All the periods added together.
  final int limitCents;
  final int spentCents;

  /// Summed over the periods that ended over, not netted against the ones
  /// that stayed under.
  final int overCents;

  bool get wentOver => overPeriods > 0;

  /// What was left across the periods (negative: over in total).
  int get leftCents => limitCents - spentCents;
}

/// Groups [results] by budget. The ones that went over come first, the
/// biggest overshoot first; then the rest by name.
List<ReportBudget> reportBudgetsOf(List<BudgetPeriodResult> results) {
  final byBudget = <int?, List<BudgetPeriodResult>>{};
  for (final r in results) {
    byBudget.putIfAbsent(r.categoryId, () => []).add(r);
  }
  final out = [
    for (final MapEntry(key: id, value: list) in byBudget.entries)
      ReportBudget(
        categoryId: id,
        name: list.first.name,
        periods: list.length,
        overPeriods: list.where((r) => r.overCents > 0).length,
        limitCents: list.fold(0, (a, r) => a + r.limitCents),
        spentCents: list.fold(0, (a, r) => a + r.spentCents),
        overCents: list.fold(0, (a, r) => a + r.overCents),
      ),
  ];
  out.sort((a, b) {
    if (a.wentOver != b.wentOver) return a.wentOver ? -1 : 1;
    final byOver = b.overCents.compareTo(a.overCents);
    return byOver != 0 ? byOver : a.name.compareTo(b.name);
  });
  return out;
}

/// How a goal did over a month: what went in (net of what came out) and where
/// it stood at the end of the month.
class ReportGoal {
  const ReportGoal({
    required this.goalId,
    required this.name,
    required this.movedCents,
    required this.savedAtEndCents,
    required this.targetCents,
  });

  final int goalId;
  final String name;

  /// Net put in during the month (negative: more came out than went in).
  final int movedCents;
  final int savedAtEndCents;
  final int targetCents;

  int get permilleAtEnd => goalPermille(savedAtEndCents, targetCents);
  bool get reachedByEnd => savedAtEndCents >= targetCents;
}

/// The goals that had an entry in [range], in the order given.
List<ReportGoal> reportGoalsOf(
  List<({int id, String name, int targetCents, List<GoalMove> moves})> goals,
  DateRange range,
) {
  final first = dateOnly(range.start);
  final last = dateOnly(range.end);
  final out = <ReportGoal>[];
  for (final g in goals) {
    var moved = 0;
    var saved = 0;
    var any = false;
    for (final m in g.moves) {
      final day = dateOnly(m.date);
      if (day.isAfter(last)) continue;
      saved += m.cents;
      if (!day.isBefore(first)) {
        moved += m.cents;
        any = true;
      }
    }
    if (any) {
      out.add(
        ReportGoal(
          goalId: g.id,
          name: g.name,
          movedCents: moved,
          savedAtEndCents: saved,
          targetCents: g.targetCents,
        ),
      );
    }
  }
  return out;
}

/// What the report suggests doing next. Actions only: no advice.
sealed class ReportSuggestion {
  const ReportSuggestion();
}

/// A category that took a big share of the month's spending has no budget.
class SetLimitSuggestion extends ReportSuggestion {
  const SetLimitSuggestion({
    required this.categoryId,
    required this.name,
    required this.spentCents,
  });

  final int categoryId;
  final String name;
  final int spentCents;
}

/// A goal that was being saved for had nothing added in the month.
class AddToGoalSuggestion extends ReportSuggestion {
  const AddToGoalSuggestion({required this.goalId, required this.name});

  final int goalId;
  final String name;
}

/// There is no recent backup.
class BackUpSuggestion extends ReportSuggestion {
  const BackUpSuggestion();
}

/// A category has to hold at least this share of the month's spending (in
/// percent) to be worth a budget suggestion.
const suggestLimitSharePercent = 15;

/// At most [max] suggestions, in this order: a budget for each of the biggest
/// unbudgeted categories (at most two), the first of [idleGoals] (goals being
/// saved for that got nothing in the month), then a backup if there is no
/// recent one. The goal and the backup are kept before a second budget.
/// [spending] is the month's expenses by category, biggest first.
List<ReportSuggestion> suggestionsOf({
  required List<({int id, String name, int spentCents})> spending,
  required Set<int> budgetedCategoryIds,
  required BackupFreshness backup,
  List<({int id, String name})> idleGoals = const [],
  int max = 3,
}) {
  final goal = idleGoals.isEmpty ? null : idleGoals.first;
  final needsBackup = backup != BackupFreshness.recent;
  final limitRoom = (max - (goal == null ? 0 : 1) - (needsBackup ? 1 : 0))
      .clamp(0, 2);
  final total = spending.fold<int>(0, (a, s) => a + s.spentCents);
  final out = <ReportSuggestion>[];
  for (final s in spending) {
    if (out.length >= limitRoom) break;
    if (s.spentCents <= 0 || budgetedCategoryIds.contains(s.id)) continue;
    if (s.spentCents * 100 < total * suggestLimitSharePercent) continue;
    out.add(
      SetLimitSuggestion(
        categoryId: s.id,
        name: s.name,
        spentCents: s.spentCents,
      ),
    );
  }
  if (goal != null) {
    out.add(AddToGoalSuggestion(goalId: goal.id, name: goal.name));
  }
  if (needsBackup) out.add(const BackUpSuggestion());
  return out.take(max).toList();
}
