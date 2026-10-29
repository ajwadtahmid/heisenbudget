import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/goals.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

GoalPlan plan({
  int target = 100000,
  List<GoalMove> moves = const [],
  DateTime? today,
  DateTime? started,
  DateTime? targetDate,
}) => planGoal(
  targetCents: target,
  moves: moves,
  today: today ?? d(2026, 10, 27),
  startedOn: started ?? d(2026, 10, 1),
  targetDate: targetDate,
);

void main() {
  group('goalPermille', () {
    test('saved over target in tenths of a percent', () {
      expect(goalPermille(0, 1000), 0);
      expect(goalPermille(320, 1000), 320);
      expect(goalPermille(1, 3), 333);
    });

    test('never 100.0% before the goal is reached', () {
      expect(goalPermille(99999, 100000), 999);
      expect(goalPermille(100000, 100000), 1000);
      expect(goalPermille(250000, 100000), 1000);
    });

    test('nothing saved, or less than nothing, is zero', () {
      expect(goalPermille(-500, 1000), 0);
      expect(goalPermille(0, 0), 0);
    });
  });

  group('savedOf', () {
    test('adds puts in and takes out', () {
      expect(
        savedOf([
          GoalMove(d(2026, 10, 1), 5000),
          GoalMove(d(2026, 10, 2), -1500),
          GoalMove(d(2026, 10, 3), 250),
        ]),
        3750,
      );
      expect(savedOf(const []), 0);
    });
  });

  group('planGoal', () {
    test('no entries: nothing saved, nothing projected', () {
      final p = plan();
      expect(p.savedCents, 0);
      expect(p.permille, 0);
      expect(p.reached, isFalse);
      expect(p.remainingCents, 100000);
      expect(p.paceCentsPerMonth, isNull);
      expect(p.reachesOn, isNull);
      expect(p.neededPerMonthCents, isNull);
      expect(p.behindCents, isNull);
      expect(p.pastTargetDate, isFalse);
    });

    test('a pace is the net added over 90 days, per 30 days', () {
      // 300.00 in on Oct 1: 100.00 a month; 700.00 to go is 210 days.
      final p = plan(moves: [GoalMove(d(2026, 10, 1), 30000)]);
      expect(p.savedCents, 30000);
      expect(p.permille, 300);
      expect(p.paceCentsPerMonth, 10000);
      expect(p.reachesOn, d(2027, 5, 25));
    });

    test('takings out lower the pace', () {
      final p = plan(
        moves: [
          GoalMove(d(2026, 10, 1), 30000),
          GoalMove(d(2026, 10, 10), -9000),
        ],
      );
      // 210.00 net over 90 days: 70.00 a month.
      expect(p.paceCentsPerMonth, 7000);
      expect(p.savedCents, 21000);
    });

    test('no pace when nothing net went in lately', () {
      final out = plan(
        moves: [
          GoalMove(d(2026, 7, 1), 30000), // before the window
          GoalMove(d(2026, 10, 20), -10000),
        ],
      );
      expect(out.savedCents, 20000);
      expect(out.paceCentsPerMonth, isNull);
      expect(out.reachesOn, isNull);

      final old = plan(moves: [GoalMove(d(2026, 7, 1), 30000)]);
      expect(old.paceCentsPerMonth, isNull, reason: 'older than 90 days');
    });

    test('the 90 days include today and stop at the 90th day back', () {
      final inside = plan(moves: [GoalMove(d(2026, 7, 30), 9000)]); // 89 days
      final outside = plan(moves: [GoalMove(d(2026, 7, 29), 9000)]); // 90 days
      expect(inside.paceCentsPerMonth, 3000);
      expect(outside.paceCentsPerMonth, isNull);
    });

    test(
      'an entry dated in the future adds to savings but not to the pace',
      () {
        final p = plan(moves: [GoalMove(d(2026, 11, 5), 10000)]);
        expect(p.savedCents, 10000);
        expect(p.paceCentsPerMonth, isNull);
      },
    );

    test('reached: no pace, nothing remaining', () {
      final p = plan(moves: [GoalMove(d(2026, 10, 1), 100000)]);
      expect(p.reached, isTrue);
      expect(p.permille, 1000);
      expect(p.remainingCents, 0);
      expect(p.paceCentsPerMonth, isNull);
      expect(p.reachesOn, isNull);
    });

    test('over the target is still reached', () {
      expect(plan(moves: [GoalMove(d(2026, 10, 1), 150000)]).reached, isTrue);
    });

    test('taking money out can bring a reached goal back', () {
      final p = plan(
        moves: [
          GoalMove(d(2026, 10, 1), 100000),
          GoalMove(d(2026, 10, 5), -1000),
        ],
      );
      expect(p.reached, isFalse);
      expect(p.remainingCents, 1000);
    });

    test('a projection beyond fifty years is left out', () {
      final p = plan(
        target: 99999999999,
        moves: [GoalMove(d(2026, 10, 1), 100)],
      );
      expect(p.paceCentsPerMonth, isNotNull);
      expect(p.reachesOn, isNull);
    });
  });

  group('a target date', () {
    test('says what each month has to bring', () {
      // 182 days left, 800.00 to go: 800.00 * 30 / 182, rounded up.
      final p = plan(
        moves: [GoalMove(d(2026, 10, 1), 20000)],
        targetDate: d(2027, 4, 27),
      );
      expect(p.neededPerMonthCents, 13187);
      expect(p.dueWithinAMonth, isFalse);
      expect(p.pastTargetDate, isFalse);
    });

    test('on or ahead of the straight line is not behind', () {
      // Day 26 of 208: 12,500 would be on the line; 20,000 is ahead.
      final p = plan(
        moves: [GoalMove(d(2026, 10, 1), 20000)],
        targetDate: d(2027, 4, 27),
      );
      expect(p.behindCents, isNull);
    });

    test('below the straight line says by how much', () {
      final p = plan(
        moves: [GoalMove(d(2026, 10, 1), 5000)],
        targetDate: d(2027, 4, 27),
      );
      expect(p.behindCents, 7500);
    });

    test('less than a month left needs everything that remains', () {
      final p = plan(
        moves: [GoalMove(d(2026, 10, 1), 40000)],
        targetDate: d(2026, 11, 10),
      );
      expect(p.neededPerMonthCents, 60000);
      expect(p.dueWithinAMonth, isTrue);
    });

    test('a date that has come is past, with no monthly need', () {
      for (final due in [d(2026, 10, 27), d(2026, 10, 20)]) {
        final p = plan(
          moves: [GoalMove(d(2026, 10, 1), 40000)],
          targetDate: due,
        );
        expect(p.pastTargetDate, isTrue, reason: '$due');
        expect(p.neededPerMonthCents, isNull);
        expect(p.behindCents, isNull);
      }
    });

    test('a reached goal has no need and is never past', () {
      final p = plan(
        moves: [GoalMove(d(2026, 10, 1), 100000)],
        targetDate: d(2026, 10, 1),
      );
      expect(p.reached, isTrue);
      expect(p.pastTargetDate, isFalse);
      expect(p.neededPerMonthCents, isNull);
    });

    test('a goal made on its target date has no line to be behind', () {
      final p = plan(
        started: d(2027, 4, 27),
        today: d(2027, 4, 1),
        targetDate: d(2027, 4, 27),
      );
      expect(p.behindCents, isNull);
    });

    test('time of day on the dates does not matter', () {
      final p = plan(
        today: DateTime(2026, 10, 27, 23, 59),
        started: DateTime(2026, 10, 1, 8),
        targetDate: DateTime(2027, 4, 27, 1),
        moves: [GoalMove(DateTime(2026, 10, 1, 22), 20000)],
      );
      expect(p.neededPerMonthCents, 13187);
    });
  });
}
