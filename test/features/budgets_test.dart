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

/// Adds a limit directly. Defaults: monthly, repeating, starting this
/// month (today in the tests is Oct 15, 2026, a Thursday).
Future<void> limit(
  WidgetTester tester,
  TestEnv env,
  String? category,
  int? cents, {
  DateTime? start,
  BudgetUnit unit = BudgetUnit.month,
  bool repeats = true,
}) async {
  final id = category == null ? null : await catId(tester, env, category);
  await tester.runAsync(
    () => BudgetRepository(env.db).setLimit(
      start:
          start ??
          (unit == BudgetUnit.month ? d(2026, 10, 1) : d(2026, 10, 12)),
      unit: unit,
      repeats: repeats,
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

/// Opens the editor for a new limit on a category.
Future<void> startNewLimit(
  WidgetTester tester,
  TestEnv env,
  String category,
) async {
  final id = await catId(tester, env, category);
  await tester.tap(find.text('Set a limit'));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('budget-pick-$id')));
  await settle(tester);
}

/// Chooses Days or Months in the editor's unit dropdown.
Future<void> chooseLengthUnit(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<bool>));
  await tester.pump();
  await tester.tap(find.text(label).last);
  await tester.pump();
}

Future<void> saveEditor(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(const ValueKey('budget-amount')), amount);
  await tester.tap(find.byKey(const ValueKey('budget-save')));
  await settle(tester);
}

void main() {
  group('the tab', () {
    testWidgets('Budgets is the second tab', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('with nothing set it explains and offers to set one', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      expect(find.textContaining('No budgets right now.'), findsOneWidget);
      expect(find.text('Set a limit'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('there is no month menu any more', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      expect(find.byKey(const ValueKey('budget-month-menu')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('when the budgets cannot be read', () {
    testWidgets('shows an error with Try again instead of waiting forever', (
      tester,
    ) async {
      final env = await createEnv(tester);
      // A table from an older build: it has a saved row but no length column.
      await tester.runAsync(() async {
        await env.db.customStatement('DROP TABLE budget_limits');
        await env.db.customStatement(
          'CREATE TABLE budget_limits (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'category_id INTEGER NULL, unit TEXT NOT NULL, '
          'repeats INTEGER NOT NULL DEFAULT 1, start TEXT NOT NULL, '
          'amount_cents INTEGER NULL, created_at INTEGER NOT NULL)',
        );
        await env.db.customStatement(
          "INSERT INTO budget_limits (unit, start, amount_cents, created_at) "
          "VALUES ('month', '2026-10-01', 50000, 0)",
        );
      });
      await openBudgets(tester, env);
      await settle(tester);

      expect(find.byKey(const ValueKey('budgets-error')), findsOneWidget);
      expect(find.text('Could not load your budgets.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Once the table is right again, Try again loads it.
      await tester.runAsync(() async {
        await env.db.customStatement('DROP TABLE budget_limits');
        await env.db.createMigrator().createTable(env.db.budgetLimits);
      });
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.byKey(const ValueKey('budgets-error')), findsNothing);
      expect(find.textContaining('No budgets right now'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('setting a limit', () {
    testWidgets('the editor defaults to monthly and repeating', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');

      ChoiceChip chip(String key) =>
          tester.widget<ChoiceChip>(find.byKey(ValueKey(key)));
      expect(chip('budget-unit-month').selected, isTrue);
      expect(chip('budget-unit-custom').selected, isFalse);
      expect(find.byKey(const ValueKey('budget-length')), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('budget-once')))
            .value,
        isFalse,
      );
      expect(find.text('Just this period'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('budget-from-this')),
        findsNothing,
        reason: 'no this/next choice',
      );
      expect(find.byKey(const ValueKey('budget-from-next')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a monthly limit: pick a category, enter an amount, a gauge appears',
      (tester) async {
        final env = await createEnv(tester);
        await openBudgets(tester, env);
        await tester.tap(find.text('Set a limit'));
        await settle(tester);

        expect(
          find.byKey(const ValueKey('budget-pick-overall')),
          findsOneWidget,
        );
        final food = await catId(tester, env, 'Food');
        final salary = await categoryId(
          tester,
          env,
          'Salary',
          TransactionType.income,
        );
        expect(find.byKey(ValueKey('budget-pick-$food')), findsOneWidget);
        expect(find.byKey(ValueKey('budget-pick-$salary')), findsNothing);

        await tester.tap(find.byKey(ValueKey('budget-pick-$food')));
        await settle(tester);
        await saveEditor(tester, '200');

        expect(find.byKey(ValueKey('gauge-$food')), findsOneWidget);
        expect(find.text('\$0.00 of \$200.00'), findsOneWidget);
        expect(find.text('Monthly · October 2026'), findsOneWidget);
        final row = (await limitRows(tester, env)).single;
        expect(
          (
            row.categoryId,
            row.entry.unit,
            row.repeats,
            row.start,
            row.amountCents,
          ),
          (food, BudgetUnit.month, true, '2026-10-01', 20000),
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a weekly limit starts on the week-start day', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      expect(
        find.textContaining('Applies from this period: Oct 12 – Oct 18, 2026'),
        findsOneWidget,
      );
      await saveEditor(tester, '50');

      final row = (await limitRows(tester, env)).single;
      expect(
        (row.entry.unit, row.repeats, row.start),
        (BudgetUnit.week, true, '2026-10-12'),
      );
      expect(find.text('Weekly · Oct 12 – Oct 18, 2026'), findsOneWidget);
      // Thursday Oct 15 to Sunday Oct 18 is 4 days: 5000 / 4 = 1250.
      expect(find.text('4 days left · about \$12.50 a day'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a weekly limit follows the Week starts on setting', (
      tester,
    ) async {
      final env = await createEnv(
        tester,
        prefs: {'week_start_day': 7},
      ); // Sunday
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await saveEditor(tester, '50');
      expect((await limitRows(tester, env)).single.start, '2026-10-11');
      await disposeEnv(tester, env);
    });

    testWidgets('weekly budgets ignore fixed 7-day blocks mode', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'week_mode': 'fixed'});
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await saveEditor(tester, '50');
      expect((await limitRows(tester, env)).single.start, '2026-10-12');
      await disposeEnv(tester, env);
    });

    testWidgets(
      'every 2 weeks shows a first-day choice and defaults to this week',
      (tester) async {
        final env = await createEnv(tester);
        await openBudgets(tester, env);
        await startNewLimit(tester, env, 'Food');
        expect(find.byKey(const ValueKey('budget-first-day')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('budget-length')),
          '14',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('budget-first-day')), findsOneWidget);
        expect(find.text('Oct 12, 2026'), findsOneWidget);
        await saveEditor(tester, '90');

        final row = (await limitRows(tester, env)).single;
        expect(
          (row.entry.unit, row.start),
          (BudgetUnit.fortnight, '2026-10-12'),
        );
        expect(
          find.text('Every 2 weeks · Oct 12 – Oct 25, 2026'),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets(
      'just once: the chip names the period and the limit does not repeat',
      (tester) async {
        final env = await createEnv(tester);
        await openBudgets(tester, env);
        await startNewLimit(tester, env, 'Food');
        await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
        await tester.pump();
        expect(find.text('Off: repeats every week.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('budget-length')),
          '14',
        );
        await tester.pump();
        expect(find.text('Off: repeats every 2 weeks.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('budget-unit-month')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('budget-once')));
        await tester.pump();
        await saveEditor(tester, '200');

        final row = (await limitRows(tester, env)).single;
        expect((row.entry.unit, row.repeats), (BudgetUnit.month, false));
        expect(find.text('Just this month · October 2026'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a custom length in days, counted from today', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      expect(find.byKey(const ValueKey('budget-length')), findsOneWidget);
      expect(find.text('Off: repeats every week.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('budget-length')), '10');
      await tester.pump();
      expect(find.text('Off: repeats every 10 days.'), findsOneWidget);
      expect(find.byKey(const ValueKey('budget-first-day')), findsOneWidget);
      expect(
        find.textContaining('Applies from this period: Oct 15 – Oct 24, 2026'),
        findsOneWidget,
      );
      await saveEditor(tester, '100');

      final row = (await limitRows(tester, env)).single;
      expect(
        (row.lengthDays, row.repeats, row.start),
        (10, true, '2026-10-15'),
      );
      expect(
        find.text('Every 10 days · Oct 15 – Oct 24, 2026'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('quarter, year and months lengths', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('budget-quick-quarter')));
      await tester.pump();
      expect(find.text('Off: repeats every 3 months.'), findsOneWidget);
      expect(
        find.textContaining('Applies from this period: Oct 1 – Dec 31, 2026'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('budget-first-day')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('budget-quick-year')));
      await tester.pump();
      expect(find.text('Off: repeats every year.'), findsOneWidget);

      await chooseLengthUnit(tester, 'Days');
      await chooseLengthUnit(tester, 'Months');
      await tester.enterText(find.byKey(const ValueKey('budget-length')), '4');
      await tester.pump();
      expect(find.text('Off: repeats every 4 months.'), findsOneWidget);
      await saveEditor(tester, '400');

      final row = (await limitRows(tester, env)).single;
      expect(
        (row.lengthDays, row.lengthMonths, row.repeats, row.start),
        (0, 4, true, '2026-10-01'),
      );
      expect(find.textContaining('Every 4 months · '), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('Rest of this year is one run of days to Dec 31', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('budget-quick-rest')));
      await tester.pump();
      // Oct 15 to Dec 31 is 17 + 30 + 31 days.
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('budget-length')))
            .controller!
            .text,
        '78',
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('budget-once')))
            .value,
        isTrue,
        reason: 'it cannot repeat',
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('budget-quick-rest')))
            .selected,
        isTrue,
      );
      await saveEditor(tester, '300');

      final row = (await limitRows(tester, env)).single;
      expect(
        (row.lengthDays, row.lengthMonths, row.repeats, row.start),
        (78, 0, false, '2026-10-15'),
      );
      expect(
        find.text('Just this period · Oct 15 – Dec 31, 2026'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('Rest of this year turns the switch back off with any other '
        'length, but never one the person turned on', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      bool once() => tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('budget-once')))
          .value;
      Future<void> pick(String key) async {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pump();
      }

      await pick('budget-unit-custom');
      expect(once(), isFalse);
      for (final other in [
        'budget-quick-week',
        'budget-quick-quarter',
        'budget-quick-year',
      ]) {
        await pick('budget-quick-rest');
        expect(once(), isTrue, reason: 'rest of the year is one-time');
        await pick(other);
        expect(once(), isFalse, reason: '$other goes back to repeating');
      }

      // Typing a length or going back to Monthly also restores it.
      await pick('budget-quick-rest');
      await tester.enterText(find.byKey(const ValueKey('budget-length')), '10');
      await tester.pump();
      expect(once(), isFalse);
      await pick('budget-quick-rest');
      await pick('budget-unit-month');
      expect(once(), isFalse);

      // A switch the person turned on stays on.
      await pick('budget-once');
      expect(once(), isTrue);
      await pick('budget-unit-custom');
      await pick('budget-quick-rest');
      await pick('budget-quick-quarter');
      expect(once(), isTrue, reason: 'their own choice');

      // Turning it off by hand after Rest of this year sticks, too.
      await pick('budget-once'); // off
      await pick('budget-quick-rest'); // on, from the pick
      await pick('budget-once'); // off by hand
      await pick('budget-quick-week');
      expect(once(), isFalse);
      await disposeEnv(tester, env);
    });

    testWidgets('the length and its unit sit on one row', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      final field = tester.getRect(find.byKey(const ValueKey('budget-length')));
      final unit = tester.getRect(find.byType(DropdownButtonFormField<bool>));
      expect(unit.left, greaterThan(field.right));
      expect((unit.top - field.top).abs(), lessThan(1));
      await chooseLengthUnit(tester, 'Months');
      expect(find.text('Off: repeats every 7 months.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a length in months is limited to 60', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await chooseLengthUnit(tester, 'Months');
      await tester.enterText(find.byKey(const ValueKey('budget-length')), '61');
      await tester.enterText(
        find.byKey(const ValueKey('budget-amount')),
        '100',
      );
      await tester.tap(find.byKey(const ValueKey('budget-save')));
      await settle(tester);
      expect(find.text('Enter 1 to 60 months'), findsOneWidget);
      expect(await limitRows(tester, env), isEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('a custom length must be 1 to 365 days', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      for (final bad in ['', '0', '366']) {
        await tester.enterText(
          find.byKey(const ValueKey('budget-length')),
          bad,
        );
        await tester.enterText(
          find.byKey(const ValueKey('budget-amount')),
          '100',
        );
        await tester.tap(find.byKey(const ValueKey('budget-save')));
        await settle(tester);
        expect(find.text('Enter 1 to 365 days'), findsOneWidget, reason: bad);
      }
      expect(await limitRows(tester, env), isEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('the Just this period switch is off until turned on', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await startNewLimit(tester, env, 'Food');
      SwitchListTile toggle() =>
          tester.widget(find.byKey(const ValueKey('budget-once')));
      expect(toggle().value, isFalse);
      await tester.tap(find.byKey(const ValueKey('budget-once')));
      await tester.pump();
      expect(toggle().value, isTrue);
      expect(find.text('On: ends Oct 31, 2026.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('budget-once')));
      await tester.pump();
      expect(toggle().value, isFalse);
      await disposeEnv(tester, env);
    });

    testWidgets('a limit on all spending', (tester) async {
      final env = await createEnv(tester);
      await openBudgets(tester, env);
      await tester.tap(find.text('Set a limit'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-pick-overall')));
      await settle(tester);
      await saveEditor(tester, '900');
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
      await saveEditor(tester, '');
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
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 12000, d(2026, 10, 3));
      await openBudgets(tester, env);
      expect(find.text('\$120.00 of \$200.00'), findsOneWidget);
      expect(find.text('\$80.00 left'), findsOneWidget);
      // Oct 15 to 31 is 17 days: 8000 / 17 = 470 cents.
      expect(find.text('17 days left · about \$4.70 a day'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a weekly gauge counts only its own week', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 10000, unit: BudgetUnit.week);
      await addExpense(tester, env, 3000, d(2026, 10, 13)); // this week
      await addExpense(tester, env, 9000, d(2026, 10, 9)); // last week
      await addExpense(tester, env, 9000, d(2026, 10, 19)); // next week
      await openBudgets(tester, env);
      expect(find.text('\$30.00 of \$100.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a future-dated expense inside the period counts', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await addExpense(tester, env, 5000, d(2026, 10, 28));
      await openBudgets(tester, env);
      expect(find.text('\$50.00 of \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('spending in other periods or categories does not count', (
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

    testWidgets(
      'the screen reader hears one sentence per gauge, with its period',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, 'Food', 20000);
        await addExpense(tester, env, 12000, d(2026, 10, 3));
        await openBudgets(tester, env);
        expect(
          find.bySemanticsLabel(
            'Food, Monthly · October 2026: \$120.00 of \$200.00. \$80.00 left. '
            '17 days left · about \$4.70 a day.',
          ),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets('the worst budget is listed first, whatever its period', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000);
      await limit(tester, env, 'Rent', 20000, unit: BudgetUnit.week);
      await limit(tester, env, 'Transport', 20000);
      await addExpense(tester, env, 3000, d(2026, 10, 14), category: 'Rent');
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
                find.byKey(ValueKey('gauge-${await catId(tester, env, name)}')),
              )
              .dy,
      ];
      expect(order, orderedEquals([...order]..sort()));
      await disposeEnv(tester, env);
    });

    testWidgets('budgets with different periods sit side by side', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, unit: BudgetUnit.week);
      await limit(tester, env, 'Rent', 100000);
      await limit(tester, env, 'Transport', 9000, unit: BudgetUnit.fortnight);
      await openBudgets(tester, env);
      expect(find.textContaining('Weekly ·'), findsOneWidget);
      expect(find.textContaining('Monthly ·'), findsOneWidget);
      expect(find.textContaining('Every 2 weeks ·'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a one-time budget leaves the list once its period is over', (
      tester,
    ) async {
      final env = await createEnv(tester, now: d(2026, 11, 3));
      await limit(tester, env, 'Food', 20000, repeats: false); // October only
      await openBudgets(tester, env);
      expect(find.textContaining('No budgets right now.'), findsOneWidget);
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
      'a note when category limits in the same period add up to more',
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

    testWidgets(
      'no note when the periods differ (a week and a month cannot be compared)',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, null, 10000);
        await limit(tester, env, 'Food', 8000, unit: BudgetUnit.week);
        await limit(tester, env, 'Transport', 6000, unit: BudgetUnit.week);
        await openBudgets(tester, env);
        expect(find.byKey(const ValueKey('budget-note')), findsNothing);
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

  group('changing and stopping', () {
    testWidgets(
      'changing the amount starts with the current period; earlier ones keep theirs',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        await limit(tester, env, 'Food', 20000, start: d(2026, 8, 1));
        await openBudgets(tester, env);
        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('budget-amount')),
              )
              .controller!
              .text,
          '200.00',
        );
        expect(
          find.textContaining('Applies from this month: Oct 1 – Oct 31, 2026'),
          findsOneWidget,
        );
        await saveEditor(tester, '300');

        expect(find.text('\$0.00 of \$300.00'), findsOneWidget);
        final rows = await limitRows(tester, env);
        expect(rows, hasLength(2));
        final entries = rows.map((r) => r.entry).toList();
        int? at(DateTime date) =>
            resolveBudget(entries, food, date, monthStartDay: 1)?.limit;
        expect(at(d(2026, 9, 15)), 20000, reason: 'September unchanged');
        expect(at(d(2026, 10, 15)), 30000);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('editing again in the same period replaces, not stacks', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 20000);
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      await saveEditor(tester, '250');
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      await saveEditor(tester, '260');
      final rows = await limitRows(tester, env);
      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 26000);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'changing the period starts the new one now and keeps the old row',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        await limit(tester, env, 'Food', 20000, start: d(2026, 9, 1));
        await openBudgets(tester, env);
        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
        await tester.pump();
        await saveEditor(tester, '60');

        expect(find.textContaining('Weekly ·'), findsOneWidget);
        final rows = await limitRows(tester, env);
        expect(rows, hasLength(2));
        expect(
          (rows.last.entry.unit, rows.last.start),
          (BudgetUnit.week, '2026-10-12'),
        );
        expect(
          (rows.first.entry.unit, rows.first.start),
          (BudgetUnit.month, '2026-09-01'),
        );
        await disposeEnv(tester, env);
      },
    );

    testWidgets(
      'a fortnight keeps its alignment when only the amount changes',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        // A cycle starting Oct 2: the current block is Oct 2 - Oct 15.
        await limit(
          tester,
          env,
          'Food',
          9000,
          unit: BudgetUnit.fortnight,
          start: d(2026, 10, 2),
        );
        await openBudgets(tester, env);
        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        expect(
          find.byKey(const ValueKey('budget-first-day')),
          findsNothing,
          reason: 'unchanged period',
        );
        await saveEditor(tester, '100');
        final rows = await limitRows(tester, env);
        expect(rows.single.start, '2026-10-02');
        expect(rows.single.amountCents, 10000);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('stopping ends the budget from now; earlier periods are kept', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final food = await catId(tester, env, 'Food');
      await limit(tester, env, 'Food', 20000, start: d(2026, 9, 1));
      await openBudgets(tester, env);
      await tester.tap(find.byKey(ValueKey('gauge-$food')));
      await settle(tester);
      await tapKey(tester, 'budget-remove');

      expect(find.byKey(ValueKey('gauge-$food')), findsNothing);
      final entries = (await limitRows(
        tester,
        env,
      )).map((r) => r.entry).toList();
      expect(
        resolveBudget(entries, food, d(2026, 9, 15), monthStartDay: 1)!.limit,
        20000,
      );
      expect(
        resolveBudget(entries, food, d(2026, 10, 15), monthStartDay: 1),
        isNull,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the stop button only shows when there is a budget', (
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
    testWidgets('monthly: the average of the last three months', (
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

    testWidgets(
      'weekly: the average of the last three weeks, and it follows the chosen period',
      (tester) async {
        final env = await createEnv(tester);
        final food = await catId(tester, env, 'Food');
        await addExpense(tester, env, 30000, d(2026, 10, 6)); // Oct 5 - 11
        await addExpense(tester, env, 20000, d(2026, 9, 30)); // Sep 28 - Oct 4
        await addExpense(tester, env, 10000, d(2026, 9, 22)); // Sep 21 - 27
        await limit(tester, env, 'Food', 5000);
        await openBudgets(tester, env);
        await tester.tap(find.byKey(ValueKey('gauge-$food')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
        await settle(tester);
        expect(
          find.textContaining('average of the last 3 weeks: \$200.00'),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );

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

  group('the month start day', () {
    testWidgets('a start day of 25 shifts which month today is in', (
      tester,
    ) async {
      final env = await createEnv(tester, prefs: {'month_start_day': 25});
      await limit(tester, env, 'Food', 20000, start: d(2026, 9, 25));
      await addExpense(tester, env, 4000, d(2026, 10, 1));
      await addExpense(tester, env, 9000, d(2026, 9, 20)); // before the period
      await addExpense(tester, env, 9000, d(2026, 10, 25)); // after it
      await openBudgets(tester, env);
      expect(find.text('Monthly · Sep 25 – Oct 24, 2026'), findsOneWidget);
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
    Future<void> rentRule(
      WidgetTester tester,
      TestEnv env, {
      bool paused = false,
    }) async {
      final rent = await catId(tester, env, 'Rent');
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
        if (paused) {
          final rule = await env.db.select(env.db.recurringRules).getSingle();
          await RecurringRepository(env.db).setActive(rule.id, false);
        }
      });
    }

    testWidgets('are shown, and flagged when they would break the limit', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Rent', 150000);
      await addExpense(tester, env, 50000, d(2026, 10, 2), category: 'Rent');
      await rentRule(tester, env);
      await openBudgets(tester, env);
      expect(find.text('\$500.00 of \$1,500.00'), findsOneWidget);
      expect(
        find.textContaining('Planned: \$1,200.00 from repeating transactions'),
        findsOneWidget,
      );
      expect(find.textContaining('over by \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a rule due next week is not planned inside this week', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Rent', 150000, unit: BudgetUnit.week);
      await rentRule(tester, env); // next due Oct 28: outside Oct 12 - 18
      await openBudgets(tester, env);
      expect(find.byKey(const ValueKey('gauge-planned')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a paused rule is not planned', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Rent', 150000);
      await rentRule(tester, env, paused: true);
      await openBudgets(tester, env);
      expect(find.byKey(const ValueKey('gauge-planned')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('past budgets', () {
    testWidgets(
      'the app bar button and the link open History on its Budgets side',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, 'Food', 20000);
        await openBudgets(tester, env);
        await tester.tap(find.byKey(const ValueKey('budgets-past')));
        await settle(tester);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        expect(
          find.byKey(const ValueKey('budget-filter-button')),
          findsOneWidget,
        );

        await goToTab(tester, 'Budgets');
        // Back on Transactions first, so the link has something to change.
        await goToTab(tester, 'History');
        await tester.tap(
          find.byKey(const ValueKey('history-mode-transactions')),
        );
        await settle(tester);
        await goToTab(tester, 'Budgets');
        await tapKey(tester, 'budgets-past-link');
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        expect(
          find.byKey(const ValueKey('budget-filter-button')),
          findsOneWidget,
        );
        await disposeEnv(tester, env);
      },
    );
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

    testWidgets('counts budgets of every period, and the overall limit', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 10000);
      await limit(tester, env, 'Food', 5000, unit: BudgetUnit.week);
      await addExpense(tester, env, 12000, d(2026, 10, 14));
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

    testWidgets('a budget that starts next month is not counted yet', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, start: d(2026, 11, 1));
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
      await saveExpense(tester, env, '50');
      expect(find.text('Food is now over budget.'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
          .clearSnackBars();
      await settle(tester);
      await saveExpense(tester, env, '10');
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('works for a weekly budget, judged over that week', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 10000, unit: BudgetUnit.week);
      await addExpense(tester, env, 8000, d(2026, 10, 13));
      // Last week's spending must not count towards this week.
      await addExpense(tester, env, 50000, d(2026, 10, 8));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '50');
      expect(find.text('Food is now over budget.'), findsOneWidget);
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

    testWidgets('a budget that has not started is not involved', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 5000, start: d(2026, 11, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '90');
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a one-time budget that has ended is not involved', (
      tester,
    ) async {
      final env = await createEnv(tester, now: d(2026, 11, 5));
      await limit(tester, env, 'Food', 5000, repeats: false); // October only
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await saveExpense(tester, env, '90');
      expect(find.textContaining('now over budget'), findsNothing);
      await disposeEnv(tester, env);
    });

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
    testWidgets('four tabs, the gauges and the editor fit at 200% text', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 90000);
      await limit(tester, env, 'Food', 20000, unit: BudgetUnit.week);
      await limit(tester, env, 'Transport', 15000, unit: BudgetUnit.fortnight);
      await addExpense(tester, env, 25000, d(2026, 10, 14));
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
      await tester.tap(find.byKey(const ValueKey('budget-unit-custom')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('budget-quick-week')),
        100,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const ValueKey('budget-quick-week')));
      await settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the editor with a custom length',
      );
      await disposeEnv(tester, env);
    });
  });
}
