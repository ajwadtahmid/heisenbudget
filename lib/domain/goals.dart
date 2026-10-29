// PURE DART: no Flutter imports. The numbers behind savings goals.
//
// A goal is tracked on its own: money is added to it and taken out of it with
// dated entries, and none of it touches the balance, budgets or any
// transaction. A "month" here is 30 days.
import 'iso_date.dart';

/// Pace is worked out from the entries of this many days.
const goalPaceDays = 90;

/// A projection further away than this many years is not worth stating.
const goalProjectionYears = 50;

/// One entry: [cents] put in (positive) or taken out (negative) on [date].
class GoalMove {
  const GoalMove(this.date, this.cents);

  final DateTime date;
  final int cents;
}

/// Where a goal stands.
class GoalPlan {
  const GoalPlan({
    required this.savedCents,
    required this.targetCents,
    required this.permille,
    required this.reached,
    this.paceCentsPerMonth,
    this.reachesOn,
    this.neededPerMonthCents,
    this.behindCents,
    this.pastTargetDate = false,
    this.dueWithinAMonth = false,
  });

  final int savedCents;
  final int targetCents;

  /// Saved over the target, in tenths of a percent, 0 to 1000.
  final int permille;

  /// The entries add up to the target (or more).
  final bool reached;

  /// What was put in per month over the last [goalPaceDays] days, when that
  /// is above zero; null with no entries, or when nothing net was added.
  final int? paceCentsPerMonth;

  /// When the pace would reach the target; null without a pace, when it is
  /// reached already, or when it is too far away to say.
  final DateTime? reachesOn;

  /// With a target date still ahead: what has to go in each month to reach it.
  final int? neededPerMonthCents;

  /// With a target date: how far below a straight line from the day the goal
  /// was made to the target date the savings are; null when on or ahead of it.
  final int? behindCents;

  /// The target date has come and the goal is not reached.
  final bool pastTargetDate;

  /// The target date is less than a month (30 days) away, so
  /// [neededPerMonthCents] is everything that remains, not a monthly amount.
  final bool dueWithinAMonth;

  int get remainingCents => reached ? 0 : targetCents - savedCents;
}

/// The saved sum of [moves].
int savedOf(Iterable<GoalMove> moves) =>
    moves.fold<int>(0, (sum, m) => sum + m.cents);

/// Saved over target in tenths of a percent, 0 to 1000 (rounded down, so it
/// never shows 100.0% before the goal is reached).
int goalPermille(int savedCents, int targetCents) {
  if (targetCents <= 0 || savedCents <= 0) return 0;
  if (savedCents >= targetCents) return 1000;
  return savedCents * 1000 ~/ targetCents;
}

int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Works out [GoalPlan] for a goal made on [startedOn] (the day it was
/// created) with [moves], as of [today]. [targetDate] is optional.
GoalPlan planGoal({
  required int targetCents,
  required List<GoalMove> moves,
  required DateTime today,
  required DateTime startedOn,
  DateTime? targetDate,
}) {
  final day = dateOnly(today);
  final saved = savedOf(moves);
  final reached = saved >= targetCents;
  final permille = goalPermille(saved, targetCents);
  if (reached) {
    return GoalPlan(
      savedCents: saved,
      targetCents: targetCents,
      permille: permille,
      reached: true,
    );
  }
  final remaining = targetCents - saved;

  // Pace: net added in the last goalPaceDays days, per 30 days.
  var recent = 0;
  for (final m in moves) {
    final age = _daysBetween(m.date, day);
    if (age >= 0 && age < goalPaceDays) recent += m.cents;
  }
  int? pace;
  DateTime? reachesOn;
  if (recent > 0) {
    final perMonth = (recent * 30 + goalPaceDays ~/ 2) ~/ goalPaceDays;
    if (perMonth > 0) {
      pace = perMonth;
      final days = (remaining * 30 + perMonth - 1) ~/ perMonth;
      if (days <= goalProjectionYears * 365) {
        reachesOn = DateTime(day.year, day.month, day.day + days);
      }
    }
  }

  int? needed;
  int? behind;
  var past = false;
  var soon = false;
  if (targetDate != null) {
    final due = dateOnly(targetDate);
    final left = _daysBetween(day, due);
    if (left <= 0) {
      past = true;
    } else {
      soon = left < 30;
      needed = soon ? remaining : (remaining * 30 + left - 1) ~/ left;
      final total = _daysBetween(dateOnly(startedOn), due);
      if (total > 0) {
        final elapsed = _daysBetween(dateOnly(startedOn), day).clamp(0, total);
        final expected = targetCents * elapsed ~/ total;
        if (expected > saved) behind = expected - saved;
      }
    }
  }

  return GoalPlan(
    savedCents: saved,
    targetCents: targetCents,
    permille: permille,
    reached: false,
    paceCentsPerMonth: pace,
    reachesOn: reachesOn,
    neededPerMonthCents: needed,
    behindCents: behind,
    pastTargetDate: past,
    dueWithinAMonth: soon,
  );
}
