import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/repositories/goal_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/features/goals/goal_detail_screen.dart';
import 'package:heisenbudget/features/goals/goals_screen.dart';
import 'package:heisenbudget/features/trends/lab_report_screen.dart';
import 'package:heisenbudget/providers/goal_providers.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

GoalRepository repoOf(TestEnv env) => GoalRepository(env.db);

Future<int> addGoal(
  WidgetTester tester,
  TestEnv env, {
  String name = 'Laptop',
  int target = 100000,
  DateTime? date,
  DateTime? created,
}) async {
  final id = await tester.runAsync(
    () => repoOf(env).add(
      GoalInput(name: name, targetCents: target, targetDate: date),
      now: created ?? d(2026, 10, 1),
    ),
  );
  return id!;
}

Future<void> put(
  WidgetTester tester,
  TestEnv env,
  int goalId,
  int cents,
  DateTime date,
) async {
  await tester.runAsync(
    () => repoOf(env).addEntry(goalId, cents: cents, date: date),
  );
}

Future<void> openInsights(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Insights'),
    ),
  );
  await settle(tester);
}

Future<void> openDetail(WidgetTester tester, TestEnv env, int id) async {
  await tester.pumpWidget(wrap(env, GoalDetailScreen(goalId: id)));
  await settle(tester);
}

Future<void> enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  group('Goals on the Insights tab', () {
    final row = find.byKey(const ValueKey('insights-goals'));
    Finder inRow(String text) =>
        find.descendant(of: row, matching: find.text(text));

    testWidgets('with none, the row offers to set one', (tester) async {
      final env = await createEnv(tester);
      await openInsights(tester, env);
      expect(inRow('Goals'), findsOneWidget);
      expect(inRow('Set a goal'), findsOneWidget);
      await tester.tap(row);
      await settle(tester);
      expect(find.byKey(const ValueKey('goal-name')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('Home has no goals section', (tester) async {
      final env = await createEnv(tester);
      await addGoal(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('GOALS'), findsNothing);
      expect(row, findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a goal can be made from the row', (tester) async {
      final env = await createEnv(tester);
      await openInsights(tester, env);
      await tester.tap(row);
      await settle(tester);

      await enter(tester, 'goal-name', 'Laptop');
      await enter(tester, 'goal-target', '1000');
      await tapKey(tester, 'goal-save');

      final goals = await tester.runAsync(() => repoOf(env).watchGoals().first);
      expect(goals!.single.name, 'Laptop');
      expect(goals.single.targetCents, 100000);
      expect(goals.single.targetDate, isNull);
      // Made today (Oct 15) by the clock the app uses.
      expect(
        goals.single.createdAt.toIso8601String(),
        startsWith('2026-10-15'),
      );

      expect(inRow('Top priority: Laptop \u00b7 0.0%'), findsOneWidget);
      expect(inRow('Set a goal'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('the sheet asks for a name and a real target', (tester) async {
      final env = await createEnv(tester);
      await openInsights(tester, env);
      await tester.tap(row);
      await settle(tester);

      await tapKey(tester, 'goal-save');
      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter an amount'), findsOneWidget);

      await enter(tester, 'goal-name', 'Trip');
      await enter(tester, 'goal-target', '0');
      await tapKey(tester, 'goal-save');
      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(
        (await tester.runAsync(() => repoOf(env).watchGoals().first)),
        isEmpty,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('shows the first goal still being saved for, and a count', (
      tester,
    ) async {
      final env = await createEnv(tester);
      for (final n in ['A', 'B', 'C', 'D']) {
        await addGoal(tester, env, name: n);
      }
      await openInsights(tester, env);
      expect(
        inRow('Top priority: A \u00b7 0.0% \u00b7 3 more'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a reached goal gives its place to the next', (tester) async {
      final env = await createEnv(tester);
      final done = await addGoal(tester, env, name: 'Done', target: 5000);
      await addGoal(tester, env, name: 'Open');
      await put(tester, env, done, 5000, d(2026, 10, 2));
      await openInsights(tester, env);
      expect(inRow('Top priority: Open \u00b7 0.0%'), findsOneWidget);
      expect(find.textContaining('Done'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('when every goal is reached it says so', (tester) async {
      final env = await createEnv(tester);
      final done = await addGoal(tester, env, target: 5000);
      await put(tester, env, done, 5000, d(2026, 10, 2));
      await openInsights(tester, env);
      expect(inRow('Every goal is reached.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the row and the app bar button both open the Goals page', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addGoal(tester, env);
      await openInsights(tester, env);

      await tester.tap(row);
      await settle(tester);
      expect(find.byType(GoalsScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('insights-goals-button')));
      await settle(tester);
      expect(find.byType(GoalsScreen), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await createEnv(tester);
      for (final n in ['A rather long goal name to wrap', 'B', 'C']) {
        final id = await addGoal(tester, env, name: n, target: 9999999999);
        await put(tester, env, id, 1234567, d(2026, 10, 2));
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openInsights(tester, env);
      expect(tester.takeException(), isNull);
      expect(row, findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('The Goals page', () {
    Future<void> openList(WidgetTester tester, TestEnv env) async {
      await tester.pumpWidget(wrap(env, const GoalsScreen()));
      await settle(tester);
    }

    testWidgets('empty: a message and a way to start', (tester) async {
      final env = await createEnv(tester);
      await openList(tester, env);
      expect(find.byKey(const ValueKey('goals-empty')), findsOneWidget);
      await tester.tap(find.text('Set a goal'));
      await settle(tester);
      expect(find.byKey(const ValueKey('goal-name')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the empty message follows the Lab flavor', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const GoalsScreen()));
      await settle(tester);
      expect(
        find.text('Nothing in the flask yet. Set a goal to start filling it.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);

      final plain = await createEnv(tester, prefs: {'lab_flavor': false});
      await tester.pumpWidget(wrap(plain, const GoalsScreen()));
      await settle(tester);
      expect(
        find.text('No goals yet. Set one to start saving towards it.'),
        findsOneWidget,
      );
      await disposeEnv(tester, plain);
    });

    testWidgets('goals in order, then the ones reached', (tester) async {
      final env = await createEnv(tester);
      final a = await addGoal(tester, env, name: 'A');
      final b = await addGoal(tester, env, name: 'B', target: 5000);
      final c = await addGoal(tester, env, name: 'C');
      await put(tester, env, b, 5000, d(2026, 10, 2));
      await openList(tester, env);

      final ay = tester.getTopLeft(find.byKey(ValueKey('goal-row-$a'))).dy;
      final cy = tester.getTopLeft(find.byKey(ValueKey('goal-row-$c'))).dy;
      final by = tester.getTopLeft(find.byKey(ValueKey('goal-row-$b'))).dy;
      expect(ay, lessThan(cy));
      expect(cy, lessThan(by), reason: 'the reached goal is last');
      expect(find.text('REACHED'), findsOneWidget);
      expect(
        find.text(
          'Goals are tracked separately from your balance. Number 1 is your '
          'top priority: drag the handles to change the order.',
        ),
        findsOneWidget,
      );
      // Numbered by priority; the reached goal has no number.
      expect(
        tester.widget<Text>(find.byKey(ValueKey('goal-rank-$a'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(ValueKey('goal-rank-$c'))).data,
        '2',
      );
      expect(find.byKey(ValueKey('goal-rank-$b')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a goal that was reached and then drawn on is active again', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final a = await addGoal(tester, env, name: 'A', target: 5000);
      await put(tester, env, a, 5000, d(2026, 10, 2));
      await put(tester, env, a, -1000, d(2026, 10, 3));
      await openList(tester, env);
      expect(find.text('REACHED'), findsNothing);
      expect(find.text('\$40.00 of \$50.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('New goal in the app bar opens the sheet', (tester) async {
      final env = await createEnv(tester);
      await addGoal(tester, env);
      await openList(tester, env);
      await tapKey(tester, 'goals-add');
      expect(find.byKey(const ValueKey('goal-name')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a failed read shows an error with Try again', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            goalsProvider.overrideWith((ref) => Stream.error(StateError('x'))),
          ],
          child: MaterialApp(theme: lightTheme(), home: const GoalsScreen()),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('goals-error')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('A goal\'s page', () {
    testWidgets('the readout, the amounts and the lab or plain name', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 32000, d(2026, 10, 2));
      await openDetail(tester, env, id);

      expect(find.text('YIELD'), findsOneWidget);
      expect(find.text('32.0%'), findsOneWidget);
      expect(find.text('\$320.00 of \$1,000.00'), findsOneWidget);
      expect(
        find.text('Goals are tracked separately from your balance.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('with Lab flavor off it says SAVED', (tester) async {
      final env = await createEnv(tester, prefs: {'lab_flavor': false});
      final id = await addGoal(tester, env);
      await openDetail(tester, env, id);
      expect(find.text('SAVED'), findsOneWidget);
      expect(find.text('YIELD'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('says nothing about a pace until money has gone in', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await openDetail(tester, env, id);
      expect(find.textContaining('At your pace'), findsNothing);
      expect(find.byKey(const ValueKey('goal-no-entries')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('goal-take-out')))
            .onPressed,
        isNull,
        reason: 'nothing to take out',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the pace and the date it points to', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      // 300.00 in on Oct 1: 100.00 a month; 700.00 to go is 210 days.
      await put(tester, env, id, 30000, d(2026, 10, 1));
      await openDetail(tester, env, id);
      expect(
        find.text('At your pace of \$100.00 a month: May 2027'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a target date says what each month has to bring', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env, date: d(2027, 4, 15));
      await put(tester, env, id, 20000, d(2026, 10, 1));
      await openDetail(tester, env, id);
      // 182 days from Oct 15 to Apr 15; 800.00 to go.
      expect(find.textContaining('Needs \$'), findsOneWidget);
      expect(
        find.textContaining('a month to reach it by Apr 15, 2027'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a date that has passed says so', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env, date: d(2026, 10, 1));
      await put(tester, env, id, 20000, d(2026, 9, 20));
      await openDetail(tester, env, id);
      expect(
        find.text('The date, Oct 1, 2026, has passed. \$800.00 to go.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('Add money puts it in the goal and the history', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await openDetail(tester, env, id);

      await tapKey(tester, 'goal-add-money');
      await enter(tester, 'goal-entry-amount', '250');
      await tapKey(tester, 'goal-entry-save');

      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('\$250.00 of \$1,000.00'), findsOneWidget);
      expect(find.text('+\$250.00'), findsOneWidget);
      expect(find.text('Oct 15, 2026'), findsOneWidget, reason: 'today');
      expect(find.byKey(const ValueKey('goal-no-entries')), findsNothing);
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 25000);
      await disposeEnv(tester, env);
    });

    testWidgets('Take out lowers it, but not below what is in it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 10000, d(2026, 10, 2));
      await openDetail(tester, env, id);

      await tapKey(tester, 'goal-take-out');
      await enter(tester, 'goal-entry-amount', '150');
      await tapKey(tester, 'goal-entry-save');
      expect(find.text('There is not that much in this goal'), findsOneWidget);
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 10000);

      await enter(tester, 'goal-entry-amount', '40');
      await tapKey(tester, 'goal-entry-save');
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 6000);
      expect(find.text('-\$40.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the entry sheet asks for a real amount', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await openDetail(tester, env, id);
      await tapKey(tester, 'goal-add-money');
      await tapKey(tester, 'goal-entry-save');
      expect(find.text('Enter an amount'), findsOneWidget);
      await enter(tester, 'goal-entry-amount', '0');
      await tapKey(tester, 'goal-entry-save');
      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 0);
      await disposeEnv(tester, env);
    });

    testWidgets('filling the goal makes it reached', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env, target: 5000);
      await openDetail(tester, env, id);
      await tapKey(tester, 'goal-add-money');
      await enter(tester, 'goal-entry-amount', '50');
      await tapKey(tester, 'goal-entry-save');
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('Reached.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an entry can be removed after confirming', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 10000, d(2026, 10, 2));
      final entry = (await tester.runAsync(
        () => repoOf(env).watchEntries().first,
      ))!.single;
      await openDetail(tester, env, id);

      await tapKey(tester, 'goal-entry-delete-${entry.id}');
      expect(find.text('Remove this entry?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 10000);

      await tapKey(tester, 'goal-entry-delete-${entry.id}');
      await tapKey(tester, 'goal-entry-remove-confirm');
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 0);
      expect(find.byKey(const ValueKey('goal-no-entries')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an entry later money depends on cannot be removed', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 10000, d(2026, 10, 2));
      await put(tester, env, id, -8000, d(2026, 10, 3));
      final deposit = (await tester.runAsync(
        () => repoOf(env).watchEntries().first,
      ))!.firstWhere((e) => e.amountCents > 0);
      await openDetail(tester, env, id);

      await tapKey(tester, 'goal-entry-delete-${deposit.id}');
      await tapKey(tester, 'goal-entry-remove-confirm');
      expect(
        find.textContaining('Later money taken out depends'),
        findsOneWidget,
      );
      expect(await tester.runAsync(() => repoOf(env).savedIn(id)), 2000);
      await disposeEnv(tester, env);
    });

    testWidgets('editing changes the goal and keeps the money', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 10000, d(2026, 10, 2));
      await openDetail(tester, env, id);

      await tapKey(tester, 'goal-edit');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('goal-target')))
            .controller!
            .text,
        '1000.00',
      );
      await enter(tester, 'goal-name', 'Better laptop');
      await enter(tester, 'goal-target', '2000');
      await tapKey(tester, 'goal-save');

      expect(find.text('Better laptop'), findsWidgets);
      expect(find.text('\$100.00 of \$2,000.00'), findsOneWidget);
      expect(find.text('5.0%'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the date can be cleared', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env, date: d(2027, 4, 15));
      await openDetail(tester, env, id);
      await tapKey(tester, 'goal-edit');
      await tapKey(tester, 'goal-date-clear');
      await tapKey(tester, 'goal-save');
      final goal = await tester.runAsync(() => repoOf(env).getById(id));
      expect(goal!.targetDate, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('deleting a goal asks first, then leaves the page', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addGoal(tester, env);
      await put(tester, env, id, 10000, d(2026, 10, 2));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      // Through the list so there is a page to go back to.
      final context = tester.element(find.byType(NavigationBar));
      openGoal(context, id);
      await settle(tester);
      expect(find.byType(GoalDetailScreen), findsOneWidget);

      await tapKey(tester, 'goal-edit');
      await tapKey(tester, 'goal-delete');
      expect(
        find.textContaining('Your transactions and balance are not affected'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await tester.runAsync(() => repoOf(env).getById(id)), isNotNull);

      await tapKey(tester, 'goal-delete');
      await tapKey(tester, 'goal-delete-confirm');
      expect(await tester.runAsync(() => repoOf(env).getById(id)), isNull);
      expect(
        await tester.runAsync(() => repoOf(env).watchEntries().first),
        isEmpty,
      );
      expect(find.byType(GoalDetailScreen), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a goal never changes the balance or the totals', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addIncome(tester, env, 100000, d(2026, 10, 2));
      final id = await addGoal(tester, env);
      await put(tester, env, id, 30000, d(2026, 10, 3));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.textContaining('1,000.00'), findsWidgets);
      expect(find.textContaining('700.00'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('at the limit, a new goal says so', (tester) async {
      final env = await createEnv(tester);
      for (var i = 0; i < maxActiveGoals; i++) {
        await addGoal(tester, env, name: 'Goal $i');
      }
      await tester.pumpWidget(wrap(env, const GoalsScreen()));
      await settle(tester);
      await tapKey(tester, 'goals-add');
      await enter(tester, 'goal-name', 'One too many');
      await enter(tester, 'goal-target', '10');
      await tapKey(tester, 'goal-save');
      expect(find.byKey(const ValueKey('goal-error')), findsOneWidget);
      expect(
        find.textContaining('up to $maxActiveGoals goals'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('goal-save')),
        findsOneWidget,
        reason: 'sheet stays open',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await createEnv(tester);
      final id = await addGoal(
        tester,
        env,
        name: 'A long name for a goal that keeps going',
        target: 99999999999,
        date: d(2027, 4, 15),
      );
      await put(tester, env, id, 1234567, d(2026, 10, 2));
      for (var i = 0; i < 4; i++) {
        await put(tester, env, id, 100 + i, d(2026, 10, 3 + i));
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openDetail(tester, env, id);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('goal-entry-delete-1')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(tester.takeException(), isNull);

      await tapKey(tester, 'goal-edit');
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('Goals in the month-end report', () {
    const september = BudgetMonth(2026, 9);

    Future<TestEnv> withGoals(WidgetTester tester) async {
      final env = await createEnv(tester, now: d(2026, 10, 3));
      await addExpense(tester, env, 20000, d(2026, 9, 9));
      final laptop = await addGoal(
        tester,
        env,
        created: d(2026, 9, 5),
        target: 100000,
      );
      await put(tester, env, laptop, 50000, d(2026, 9, 10));
      await put(tester, env, laptop, -5000, d(2026, 9, 20));
      await put(tester, env, laptop, 7000, d(2026, 10, 2)); // after the month
      return env;
    }

    testWidgets('what went in during the month, and where it stood', (
      tester,
    ) async {
      final env = await withGoals(tester);
      await tester.pumpWidget(
        wrap(env, const LabReportScreen(month: september)),
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('GOALS'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('+\$450.00'), findsOneWidget);
      // 450.00 of 1,000.00 at the end of September, not counting October.
      expect(
        find.textContaining('\$450.00 of \$1,000.00 · YIELD 45.0%'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a goal left alone in the month is suggested', (tester) async {
      final env = await withGoals(tester);
      final trip = await addGoal(
        tester,
        env,
        name: 'Trip',
        created: d(2026, 9, 1),
      );
      await tester.pumpWidget(
        wrap(env, const LabReportScreen(month: september)),
      );
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('report-add-goal-$trip')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Trip had nothing added in September.'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('report-add-goal-$trip')));
      await settle(tester);
      expect(find.byKey(const ValueKey('goal-entry-amount')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a goal made after the month is not blamed for it', (
      tester,
    ) async {
      final env = await withGoals(tester);
      final later = await addGoal(
        tester,
        env,
        name: 'Later',
        created: d(2026, 10, 2),
      );
      await tester.pumpWidget(
        wrap(env, const LabReportScreen(month: september)),
      );
      await settle(tester);
      expect(find.byKey(ValueKey('report-add-goal-$later')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('no goals, no goals section', (tester) async {
      final env = await createEnv(tester, now: d(2026, 10, 3));
      await addExpense(tester, env, 20000, d(2026, 9, 9));
      await tester.pumpWidget(
        wrap(env, const LabReportScreen(month: september)),
      );
      await settle(tester);
      expect(find.text('GOALS'), findsNothing);
      await disposeEnv(tester, env);
    });
  });
}
