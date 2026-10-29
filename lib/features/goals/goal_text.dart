import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../domain/goals.dart';

/// The dim lines under a goal's figures: where it stands against its pace and
/// its date. Nothing is guessed: no entries, no pace line; no date, no date
/// line.
List<String> goalPlanLines(GoalPlan plan, DateTime? targetDate, String symbol) {
  if (plan.reached) return const ['Reached.'];
  final lines = <String>[];
  final pace = plan.paceCentsPerMonth;
  if (pace != null) {
    final perMonth = '${formatMoney(pace, symbol)} a month';
    final when = plan.reachesOn;
    lines.add(
      when == null
          ? 'At your pace of $perMonth.'
          : 'At your pace of $perMonth: ${DateFormat.yMMM().format(when)}',
    );
  }
  if (targetDate != null) {
    if (plan.pastTargetDate) {
      lines.add(
        'The date, ${formatDate(targetDate)}, has passed. '
        '${formatMoney(plan.remainingCents, symbol)} to go.',
      );
    } else {
      final needed = formatMoney(
        plan.neededPerMonthCents ?? plan.remainingCents,
        symbol,
      );
      final behind = plan.behindCents;
      lines.add(
        'Needs $needed${plan.dueWithinAMonth ? '' : ' a month'} to reach it by '
        '${formatDate(targetDate)}'
        '${behind == null ? '' : ' (you are ${formatMoney(behind, symbol)} behind)'}',
      );
    }
  }
  return lines;
}
