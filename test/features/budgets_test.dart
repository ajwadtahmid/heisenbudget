import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
BudgetMonth bm(int y, int m) => BudgetMonth(y, m);

Future<void> goToTab(WidgetTester tester, String label) async {
  for (var i = 0; i < 3 && find.byType(NavigationBar).evaluate().isEmpty; i++) {
    await tester.pageBack();
    await settle(tester);
  }
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<int> catId(WidgetTester tester, TestEnv env, String name) =>
    categoryId(tester, env, name, TransactionType.expense);

Future<void> limit(
  WidgetTester tester,
  TestEnv env,
  String? category,
  int cents, {
  BudgetMonth? month,
}) async {
  final id = category == null ? null : await catId(tester, env, category);
  await tester.runAsync(
    () => BudgetRepository(env.db).setLimit(
      month: month ?? bm(2026, 10),
      categoryId: id,
      amountCents: cents,
    ),
  );
}

Future<void> openBudgets(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
  await goToTab(tester, 'Budgets');
}

Future<List<BudgetLimitRow>> limitRows(
  WidgetTester tester,
  TestEnv env,
) async => (await tester.runAsync(
  () => (env.db.select(
    env.db.budgetLimits,
  )..orderBy([(l) => OrderingTerm.asc(l.id)])).get(),
))!;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  group('the tab', () {
    testWidgets('Budgets is the second tab', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      expect(find.text('Budgets'), findsWidgets);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
      await disposeEnv(tester, env);
    });

    testWidgets('with nothing set it explains and offers to set one', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      expect(find.textContaining('No budgets yet.'), findsOneWidget);
      expect(find.text('Set a limit'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('setting a limit', () {
    testWidgets('pick a category, enter an amount, and a gauge appears', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await tester.tap(find.text('Set a limit'));
      await settle(tester);

      // All spending first, then expense categories; no income ones.
      expect(find.byKey(const ValueKey('budget-pick-overall')), findsOneWidget);
      final food = await catId(tester, env, 'Food');
      expect(find.byKey(ValueKey('budget-pick-$food')), findsOneWidget);
      final salary = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      expect(find.byKey(ValueKey('budget-pick-$salary')), findsNothing);

      await tester.tap(find.byKey(ValueKey('budget-pick-$food')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '200',
      );
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);

      expect(find.byKey(ValueKey('gauge-$food')), findsOneWidget);
      expect(find.text('\$0.00 of \$200.00'), findsOneWidget);
      expect(find.text('\$200.00 left'), findsOneWidget);
      final rows = await limitRows(tester, env);
      expect(
        (
          rows.single.categoryId,
          rows.single.startMonth,
          rows.single.amountCents,
        ),
        (food, '2026-10', 20000),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a limit on all spending', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await tester.tap(find.text('Set a limit'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-pick-overall')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '900',
      );
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);
      expect(find.byKey(const ValueKey('gauge-overall')), findsOneWidget);
      expect(find.text('All spending'), findsOneWidget);
      expect((await limitRows(tester, env)).single.categoryId, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('an empty or bad amount is not saved', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      final food = await catId(tester, env, 'Food');
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('budget-amount')), '');
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);
      expect(find.text('Enter an amount'), findsOneWidget);
      expect((await limitRows(tester, env)).single.amountCents, 20000);
      await disposeEnv(tester, env);
    });

    testWidgets('"Add a limit" lists only what has none', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await limit(tester, env, null, 90000);
      await openBudgets(tester, env);
      await tapKey(tester, 'budget-add');
      final food = await catId(tester, env, 'Food');
      final rent = await catId(tester, env, 'Rent');
      expect(find.byKey(ValueKey('budget-pick-$food')), findsNothing);
      expect(find.byKey(ValueKey('budget-pick-$rent')), findsOneWidget);
      expect(find.byKey(const ValueKey('budget-pick-overall')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('how a gauge reads', () {
    testWidgets('amounts, what is left, and days and per-day left', (
      tester,
    ) async {
      final env = await createEnv(tester); // Oct 15
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 12000, d(2026, 10, 3));
      await openBudgets(tester, env);
      expect(find.text('\$120.00 of \$200.00'), findsOneWidget);
      expect(find.text('\$80.00 left'), findsOneWidget);
      // Oct 15 to 31 is 17 days: 8000 / 17 = 470 cents.
      expect(find.text('17 days left · about \$4.70 a day'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a future-dated expense in the month counts', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 5000, d(2026, 10, 28));
      await openBudgets(tester, env);
      expect(find.text('\$50.00 of \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('spending in other months or categories does not count', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 9000, d(2026, 9, 30));
      await addExpense(tester, env, 9000, d(2026, 11, 1));
      await addExpense(tester, env, 4000, d(2026, 10, 5), category: 'Rent');
      await openBudgets(tester, env);
      expect(find.text('\$0.00 of \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('"almost" from 80 percent, in words and with an icon', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 17000, d(2026, 10, 3));
      await openBudgets(tester, env);
      expect(find.text('Almost: \$30.00 left'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('over: "Over by", an error icon and no per-day figure', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 23500, d(2026, 10, 3));
      await openBudgets(tester, env);
      expect(find.text('Over by \$35.00'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('17 days left'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the screen reader hears one sentence per gauge', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 12000, d(2026, 10, 3));
      await openBudgets(tester, env);
      expect(
        find.bySemanticsLabel(
          'Food: \$120.00 of \$200.00. \$80.00 left. '
          '17 days left · about \$4.70 a day.',
        ),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the worst budget is listed first', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await limit(tester, env, 'Rent', 20000);
      await limit(tester, env, 'Transport', 20000);
      await addExpense(tester, env, 3000, d(2026, 10, 3), category: 'Rent');
      await addExpense(
        tester,
        env,
        25000,
        d(2026, 10, 3),
        category: 'Transport',
      );
      await addExpense(tester, env, 17000, d(2026, 10, 3), category: 'Food');
      await openBudgets(tester, env);
      final order = [
        for (final name in ['Transport', 'Food', 'Rent'])
          tester
              .getTopLeft(
                find.byKey(
                  ValueKey('gauge-${(await catId(tester, env, name))}'),
                ),
              )
              .dy,
      ];
      expect(order, orderedEquals([...order]..sort()));
      await disposeEnv(tester, env);
    });
  });

  group('all spending', () {
    testWidgets('counts every expense, even in categories with no limit', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 90000);
      await addExpense(tester, env, 10000, d(2026, 10, 3));
      await addExpense(tester, env, 20000, d(2026, 10, 4), category: 'Rent');
      await openBudgets(tester, env);
      expect(find.text('\$300.00 of \$900.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a note appears when category limits add up to more than the overall one',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, null, 10000);
        await limit(tester, env, 'Food', 8000);
        await limit(tester, env, 'Transport', 6000);
        await openBudgets(tester, env);
        expect(find.byKey(const ValueKey('budget-note')), findsOneWidget);
        expect(find.textContaining('add up to \$140.00'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('no note when they fit', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 20000);
      await limit(tester, env, 'Food', 8000);
      await openBudgets(tester, env);
      expect(find.byKey(const ValueKey('budget-note')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('changing and removing limits', () {
    testWidgets('from this month changes this month, and the past stays', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 20000, month: bm(2026, 8));
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('budget-amount')))
            .controller!
            .text,
        '200.00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '300',
      );
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);

      expect(find.text('\$0.00 of \$300.00'), findsOneWidget);
      final entries = (await limitRows(
        tester,
        env,
      )).map((r) => r.entry).toList();
      expect(
        resolveLimit(entries, food, bm(2026, 9)),
        20000,
        reason: 'before this month',
      );
      expect(resolveLimit(entries, food, bm(2026, 10)), 30000);
      await disposeEnv(tester, env);
    });

    testWidgets('from next month leaves this month alone', (tester) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-from-next')));
      await tester.pump();
      expect(find.textContaining('From Nov 1, 2026'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '350',
      );
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);

      expect(
        find.text('\$0.00 of \$200.00'),
        findsOneWidget,
        reason: 'this month unchanged',
      );
      final entries = (await limitRows(
        tester,
        env,
      )).map((r) => r.entry).toList();
      expect(resolveLimit(entries, food, bm(2026, 10)), 20000);
      expect(resolveLimit(entries, food, bm(2026, 11)), 35000);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'removing from this month on ends the limit, and the past keeps it',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        await limit(tester, env, 'Food', 20000, month: bm(2026, 9));
        await openBudgets(tester, env);
        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        await tapKey(tester, 'budget-remove');

        expect(find.byKey(ValueKey('gauge-$food')), findsNothing);
        final entries = (await limitRows(
          tester,
          env,
        )).map((r) => r.entry).toList();
        expect(resolveLimit(entries, food, bm(2026, 9)), 20000);
        expect(resolveLimit(entries, food, bm(2026, 10)), isNull);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('the remove button only shows when there is a limit', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await tester.tap(find.text('Set a limit'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-pick-overall')));
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-remove')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('the average suggestion', () {
    testWidgets('offers the average of the last three months and fills it in', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await addExpense(tester, env, 30000, d(2026, 7, 10));
      await addExpense(tester, env, 20000, d(2026, 8, 10));
      await addExpense(tester, env, 10000, d(2026, 9, 10));
      await limit(tester, env, 'Food', 5000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);

      expect(
        find.textContaining('average of the last 3 months: \$200.00'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('budget-suggest')));
      await tester.pump();
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('budget-amount')))
            .controller!
            .text,
        '200.00',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('is not offered when nothing was spent before', (tester) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 5000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-suggest')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('is for this category only', (tester) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await addExpense(tester, env, 90000, d(2026, 9, 10), category: 'Rent');
      await limit(tester, env, 'Food', 5000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-suggest')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('months', () {
    testWidgets(
      'the menu moves between months, and past months cannot be changed',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        await limit(tester, env, 'Food', 20000, month: bm(2026, 8));
        await addExpense(tester, env, 7000, d(2026, 9, 10));
        await openBudgets(tester, env);
        expect(find.text('October 2026'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('budget-month-menu')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('budget-month--1')));
        await settle(tester);
        expect(find.text('September 2026'), findsOneWidget);
        expect(find.text('\$70.00 of \$200.00'), findsOneWidget);
        expect(find.text('Month ended'), findsOneWidget);
        expect(find.byKey(const ValueKey('budget-past-note')), findsOneWidget);
        expect(find.byKey(const ValueKey('budget-add')), findsNothing);

        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        expect(
          find.byKey(const ValueKey('budget-amount')),
          findsNothing,
          reason: 'no editor',
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets('next month shows what carries over, with nothing spent', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(const ValueKey('budget-month-menu')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-month-1')));
      await settle(tester);
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('\$0.00 of \$200.00'), findsOneWidget);
      expect(find.text('Starts Nov 1, 2026'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('swiping sideways changes the month', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      await tester.fling(
        find.byKey(const ValueKey('gauge-overall')).evaluate().isEmpty
            ? find.byType(ListView).last
            : find.byKey(const ValueKey('gauge-overall')),
        const Offset(300, 0),
        1500,
      );
      await settle(tester);
      expect(find.text('September 2026'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a month with no limits set says so', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(const ValueKey('budget-month-menu')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-month--2')));
      await settle(tester);
      // The limit started in October, so August has none.
      expect(find.text('No limits were set for this month.'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('the month start day', () {
    testWidgets('a start day of 25 shifts which month today is in', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'month_start_day': 25});
      // Oct 15 with start day 25 is still in September (Sep 25 - Oct 24).
      await limit(tester, env, 'Food', 20000, month: bm(2026, 9));
      await addExpense(tester, env, 4000, d(2026, 10, 1));
      await addExpense(tester, env, 9000, d(2026, 9, 20)); // before the month
      await addExpense(tester, env, 9000, d(2026, 10, 25)); // after it
      await openBudgets(tester, env);
      expect(find.text('Sep 25 – Oct 24, 2026'), findsOneWidget);
      expect(find.text('\$40.00 of \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the setting lives in Money & dates and is saved', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await goToTab(tester, 'Settings');
      await openSettingsPage(tester, 'money');
      final dropdown = find.byKey(const ValueKey('month-start-1'));
      await tester.ensureVisible(dropdown);
      await tester.pump();
      expect(find.text('Budget month starts on'), findsOneWidget);
      await tester.tap(dropdown);
      await settle(tester);
      await tester.tap(find.text('25th').last);
      await settle(tester);
      expect(env.prefs.getInt('month_start_day'), 25);
      await disposeEnv(tester, env);
    });
  });

  group('planned repeating expenses', () {
    testWidgets('are shown, and flagged when they would break the limit', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final rent = await catId(tester, env, 'Rent');
      await limit(tester, env, 'Rent', 150000);
      await addExpense(tester, env, 50000, d(2026, 10, 2), category: 'Rent');
      await tester.runAsync(
        () => RecurringRepository(env.db).addWithRule(
          TransactionInput(
            amountCents: 120000,
            type: TransactionType.expense,
            date: d(2026, 9, 28),
            categoryId: rent,
          ),
          RecurringInput(
            amountCents: 120000,
            type: TransactionType.expense,
            categoryId: rent,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 9, 28),
          ),
        ),
      );
      await openBudgets(tester, env);
      // Spent: the Sep 28 one is last month, so only the 500.00 counts now.
      expect(find.text('\$500.00 of \$1,500.00'), findsOneWidget);
      expect(
        find.textContaining('Planned: \$1,200.00 from repeating transactions'),
        findsOneWidget,
      );
      expect(find.textContaining('over by \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a paused rule is not planned', (tester) async {
      final env = await createEnv(tester);
      final rent = await catId(tester, env, 'Rent');
      await limit(tester, env, 'Rent', 150000);
      await tester.runAsync(() async {
        await RecurringRepository(env.db).addWithRule(
          TransactionInput(
            amountCents: 120000,
            type: TransactionType.expense,
            date: d(2026, 9, 28),
            categoryId: rent,
          ),
          RecurringInput(
            amountCents: 120000,
            type: TransactionType.expense,
            categoryId: rent,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 9, 28),
          ),
        );
        final rule = await env.db.select(env.db.recurringRules).getSingle();
        await RecurringRepository(env.db).setActive(rule.id, false);
      });
      await openBudgets(tester, env);
      expect(find.byKey(const ValueKey('gauge-planned')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('Home', () {
    testWidgets('shows nothing when no budget is set', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-budget-line')), findsNothing);
      await disposeEnv(tester, env);
    });

    Future<String?> line(WidgetTester tester) async {
      final finder = find.byKey(const ValueKey('home-budget-text'));
      return finder.evaluate().isEmpty
          ? null
          : tester.widget<Text>(finder).data;
    }

    testWidgets('says all is well, almost, or how many are over', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(await line(tester), 'All within budget');

      await addExpense(tester, env, 17000, d(2026, 10, 3));
      await settle(tester);
      expect(await line(tester), '1 almost at its limit');

      await addExpense(tester, env, 9000, d(2026, 10, 4));
      await settle(tester);
      expect(await line(tester), '1 over budget');
      await disposeEnv(tester, env);
    });

    testWidgets('counts the overall limit and each category', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 10000);
      await limit(tester, env, 'Food', 5000);
      await addExpense(tester, env, 12000, d(2026, 10, 3));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(await line(tester), '2 over budget');
      await disposeEnv(tester, env);
    });

    testWidgets('tapping it opens Budgets', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('home-budget-line')));
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('looks at the current budget month only', (tester) async {
      final env = await createEnv(tester);
      await limit(
        tester,
        env,
        'Food',
        20000,
        month: bm(2026, 11),
      ); // starts next month
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-budget-line')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('the "now over budget" line', () {
    Future<void> saveExpense(
      WidgetTester tester,
      TestEnv env,
      String amount, {
      String category = 'Food',
    }) async {
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        amount,
      );
      final id = await catId(tester, env, category);
      await tester.tap(find.byKey(ValueKey('category-$id')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
    }

    testWidgets('appears when an expense takes a category over, once', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 10000);
      await addExpense(tester, env, 8000, d(2026, 10, 3));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      await saveExpense(tester, env, '50'); // 80 + 50 > 100
      expect(find.text('Food is now over budget.'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await settle(tester);
      await saveExpense(tester, env, '10'); // already over: stay quiet
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('stays quiet while still under the limit', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 10000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '50');
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('also says so for all spending', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 5000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '60');
      expect(find.text('All spending is now over budget.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('both lines when both limits are crossed at once', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 5000);
      await limit(tester, env, null, 5000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '60');
      expect(
        find.text('Food is now over budget. All spending is now over budget.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('income never triggers it', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 5000);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.tap(find.text('Income'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        '9000',
      );
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'an expense dated in another month is judged against that month',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, 'Food', 5000, month: bm(2026, 11));
        await tester.pumpWidget(wholeApp(env));
        await settle(tester);
        // Saved today (October): November's limit is not involved.
        await saveExpense(tester, env, '90');
        expect(find.textContaining('now over budget'), findsNothing);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a favorite that crosses the limit says so in its own line', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 5000);
      final id = (await tester.runAsync(
        () => FavoriteRepository(env.db).add(
          FavoriteInput(
            label: 'Burger',
            type: TransactionType.expense,
            categoryId: food,
            amountCents: 6000,
          ),
        ),
      ))!;
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);
      expect(
        find.text('Logged Burger -\$60.00. Food is now over budget.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    testWidgets('four tabs and the Budgets screen fit at 200% text', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 90000);
      await limit(tester, env, 'Food', 20000);
      await limit(tester, env, 'Transport', 15000);
      await addExpense(tester, env, 25000, d(2026, 10, 3));
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openBudgets(tester, env);
      expect(tester.takeException(), isNull, reason: 'tab bar and gauges');
      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scrolled');

      await goToTab(tester, 'Home');
      expect(
        tester.takeException(),
        isNull,
        reason: 'Home with the budget line',
      );
      await goToTab(tester, 'Budgets');
      await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gauge-overall')));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'the editor');
      await disposeEnv(tester, env);
    });
  });
}
