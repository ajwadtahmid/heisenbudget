import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
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

Future<void> limit(
  WidgetTester tester,
  TestEnv env,
  String? category,
  int? cents,
  DateTime start, {
  BudgetUnit unit = BudgetUnit.month,
  bool repeats = true,
}) async {
  final id = category == null ? null : await catId(tester, env, category);
  await tester.runAsync(
    () => BudgetRepository(env.db).setLimit(
      start: start,
      unit: unit,
      repeats: repeats,
      categoryId: id,
      amountCents: cents,
    ),
  );
}

/// Opens History and switches to its Budgets side.
Future<void> openPastBudgets(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
  await goToTab(tester, 'History');
  await tester.tap(find.byKey(const ValueKey('history-mode-budgets')));
  await settle(tester);
}

int rows() => find
    .byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('past-');
    })
    .evaluate()
    .length;

String? text(WidgetTester tester, Finder f) => tester.widget<Text>(f).data;

void main() {
  group('the pill', () {
    testWidgets(
      'History starts on Transactions, with the pill above the controls',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wholeApp(env));
        await settle(tester);
        await goToTab(tester, 'History');

        expect(
          find.byKey(const ValueKey('history-mode-transactions')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('history-mode-budgets')),
          findsOneWidget,
        );
        expect(find.text('Transactions'), findsWidgets);
        final pill = tester.getRect(
          find.byKey(const ValueKey('history-mode-transactions')),
        );
        final filter = tester.getRect(
          find.byKey(const ValueKey('filter-button')),
        );
        expect(
          filter.top,
          greaterThan(pill.bottom),
          reason: 'Filter and Sort sit under the pill',
        );
        expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
        expect(find.byTooltip('Add transaction'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('Budgets swaps the content, hides search and the add key', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openPastBudgets(tester, env);
      expect(
        find.byKey(const ValueKey('budget-filter-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('budget-sort-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-button')), findsNothing);
      expect(find.byKey(const ValueKey('search-button')), findsNothing);
      expect(find.byTooltip('Add transaction'), findsNothing);
      final pill = tester.getRect(
        find.byKey(const ValueKey('history-mode-budgets')),
      );
      final filter = tester.getRect(
        find.byKey(const ValueKey('budget-filter-button')),
      );
      expect(filter.top, greaterThan(pill.bottom));
      await disposeEnv(tester, env);
    });

    testWidgets('switching back restores Transactions untouched', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 450, d(2026, 10, 5), note: 'Latte');
      await openPastBudgets(tester, env);
      await tester.tap(find.byKey(const ValueKey('history-mode-transactions')));
      await settle(tester);
      expect(find.text('Latte'), findsOneWidget);
      expect(find.byTooltip('Add transaction'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-button')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('each side keeps its own filters', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await goToTab(tester, 'History');
      // A transactions filter.
      await tester.tap(find.byKey(const ValueKey('filter-button')));
      await settle(tester);
      await tester.tap(find.text('Expense'));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('Filter · 1'), findsOneWidget);

      // A budgets filter.
      await tester.tap(find.byKey(const ValueKey('history-mode-budgets')));
      await settle(tester);
      expect(
        find.text('Filter'),
        findsOneWidget,
        reason: 'budgets side starts unfiltered',
      );
      await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-filter-result-over')));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('Filter · 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('history-mode-transactions')));
      await settle(tester);
      expect(find.text('Filter · 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('active-type')),
        findsOneWidget,
        reason: 'its own chip',
      );
      expect(find.byKey(const ValueKey('budget-active-result')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('the list', () {
    testWidgets('says so when there are no past budgets', (tester) async {
      final env = await createEnv(tester);
      await openPastBudgets(tester, env);
      expect(find.textContaining('No past budgets yet.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a budget that has only just started has no past', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 10, 1));
      await openPastBudgets(tester, env);
      expect(rows(), 0);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'finished months, newest first, grouped by the month they ended in',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
        await addExpense(tester, env, 12000, d(2026, 9, 10));
        await addExpense(tester, env, 25000, d(2026, 8, 10));
        await addExpense(tester, env, 20000, d(2026, 7, 10));
        await addExpense(
          tester,
          env,
          99000,
          d(2026, 10, 3),
        ); // the current month: not here
        await openPastBudgets(tester, env);

        expect(rows(), 3);
        for (final header in ['September 2026', 'August 2026', 'July 2026']) {
          expect(find.text(header), findsOneWidget, reason: header);
        }
        final food = await catId(tester, env, 'Food');
        Finder row(DateTime start) =>
            find.byKey(ValueKey('past-$food-${start.toIso8601String()}'));
        final order = [
          tester.getTopLeft(row(d(2026, 9, 1))).dy,
          tester.getTopLeft(row(d(2026, 8, 1))).dy,
          tester.getTopLeft(row(d(2026, 7, 1))).dy,
        ];
        expect(order, orderedEquals([...order]..sort()));

        expect(find.text('\$120.00 of \$200.00'), findsOneWidget);
        expect(find.text('Under by \$80.00'), findsOneWidget);
        expect(find.text('Over by \$50.00'), findsOneWidget);
        expect(find.text('Used it all'), findsOneWidget);
        expect(find.text('Monthly · September 2026'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('each period shows the limit that was in force then', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await limit(tester, env, 'Food', 30000, d(2026, 9, 1));
      await openPastBudgets(tester, env);
      expect(
        find.text('\$0.00 of \$200.00'),
        findsNWidgets(2),
        reason: 'July and August',
      );
      expect(
        find.text('\$0.00 of \$300.00'),
        findsOneWidget,
        reason: 'September',
      );
      await disposeEnv(tester, env);
    });

    testWidgets(
      'weekly periods, one-time budgets and stopped budgets are all there',
      (tester) async {
        final env = await createEnv(tester);
        await limit(
          tester,
          env,
          'Food',
          5000,
          d(2026, 9, 28),
          unit: BudgetUnit.week,
        );
        await limit(tester, env, 'Rent', 100000, d(2026, 8, 1), repeats: false);
        await limit(tester, env, 'Transport', 9000, d(2026, 7, 1));
        await limit(tester, env, 'Transport', null, d(2026, 9, 1)); // stopped
        await openPastBudgets(tester, env);

        // Food: Sep 28 - Oct 4 and Oct 5 - 11 have ended (today is Oct 15).
        expect(
          find.textContaining('Weekly · Sep 28 – Oct 4, 2026'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Weekly · Oct 5 – Oct 11, 2026'),
          findsOneWidget,
        );
        // Rent: only August, a one-time budget.
        expect(find.text('Just this month · August 2026'), findsOneWidget);
        // Transport: July and August, then it stopped.
        expect(find.text('Monthly · July 2026'), findsOneWidget);
        expect(find.text('Monthly · August 2026'), findsOneWidget);
        expect(find.text('Monthly · September 2026'), findsNothing);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('all spending appears alongside categories', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, null, 90000, d(2026, 8, 1));
      await addExpense(tester, env, 30000, d(2026, 8, 5));
      await addExpense(tester, env, 20000, d(2026, 8, 6), category: 'Rent');
      await openPastBudgets(tester, env);
      expect(find.text('All spending'), findsWidgets);
      expect(find.text('\$500.00 of \$900.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a past gauge is read-only: tapping it opens nothing', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 9, 1));
      await openPastBudgets(tester, env);
      final food = await catId(tester, env, 'Food');
      await tester.tap(
        find.byKey(ValueKey('past-$food-${d(2026, 9, 1).toIso8601String()}')),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('budget-amount')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a correction to an old transaction updates the figures', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 9, 1));
      await openPastBudgets(tester, env);
      expect(find.text('\$0.00 of \$200.00'), findsOneWidget);
      await addExpense(tester, env, 7500, d(2026, 9, 12));
      await settle(tester);
      expect(find.text('\$75.00 of \$200.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('it screen-reads each row as a sentence with its result', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 9, 1));
      await addExpense(tester, env, 12000, d(2026, 9, 10));
      await openPastBudgets(tester, env);
      expect(
        find.bySemanticsLabel(
          'Food, Monthly · September 2026: \$120.00 of \$200.00. Under by \$80.00.',
        ),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });
  });

  group('filter', () {
    Future<void> setUpMixed(WidgetTester tester, TestEnv env) async {
      await limit(
        tester,
        env,
        'Food',
        20000,
        d(2026, 8, 1),
      ); // Aug, Sep monthly
      await limit(
        tester,
        env,
        'Rent',
        5000,
        d(2026, 9, 28),
        unit: BudgetUnit.week,
      ); // 2 weeks
      await limit(
        tester,
        env,
        'Transport',
        9000,
        d(2026, 8, 1),
        repeats: false,
      ); // Aug once
      await addExpense(tester, env, 30000, d(2026, 8, 10)); // Food Aug: over
      await addExpense(
        tester,
        env,
        8000,
        d(2026, 9, 29),
        category: 'Rent',
      ); // Rent week 1: over
    }

    testWidgets('Sort sits at the right edge, Filter at the left', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await setUpMixed(tester, env);
      await openPastBudgets(tester, env);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final filter = tester.getRect(
        find.byKey(const ValueKey('budget-filter-button')),
      );
      final sort = tester.getRect(
        find.byKey(const ValueKey('budget-sort-button')),
      );
      expect(filter.left, 20);
      expect(sort.right, width - 20);
      await disposeEnv(tester, env);
    });

    testWidgets('by period', (tester) async {
      final env = await createEnv(tester);
      await setUpMixed(tester, env);
      await openPastBudgets(tester, env);
      expect(rows(), 5, reason: '2 Food months, 2 Rent weeks, 1 Transport');

      Future<void> choose(String key) async {
        await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
        await settle(tester);
        await tester.tap(find.byKey(ValueKey(key)));
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
      }

      await choose('budget-filter-period-custom');
      expect(rows(), 2);
      expect(find.text('Filter · 1'), findsOneWidget);
      await choose('budget-filter-period-month');
      expect(rows(), 3, reason: 'Food x2 and the one-time monthly Transport');
      await choose('budget-filter-period-oneTime');
      expect(rows(), 1);
      await choose('budget-filter-period-all');
      expect(rows(), 5);
      await disposeEnv(tester, env);
    });

    testWidgets('by result', (tester) async {
      final env = await createEnv(tester);
      await setUpMixed(tester, env);
      await openPastBudgets(tester, env);

      Future<void> choose(String key) async {
        await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
        await settle(tester);
        await tester.tap(find.byKey(ValueKey(key)));
        await settle(tester);
        await tester.tap(find.text('Done'));
        await settle(tester);
      }

      await choose('budget-filter-result-over');
      expect(rows(), 2, reason: 'Food August and Rent week one');
      await choose('budget-filter-result-within');
      expect(rows(), 3);
      await disposeEnv(tester, env);
    });

    testWidgets('by budget, with chips that remove the filter', (tester) async {
      final env = await createEnv(tester);
      await setUpMixed(tester, env);
      await openPastBudgets(tester, env);
      final food = await catId(tester, env, 'Food');
      await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('budget-filter-target-$food')));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(rows(), 2);
      expect(
        find.byKey(ValueKey('budget-active-target-$food')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('budget-active-target-$food')),
          matching: find.byTooltip('Remove filter'),
        ),
      );
      await settle(tester);
      expect(rows(), 5);
      await disposeEnv(tester, env);
    });

    testWidgets('filters combine, and Clear filters resets them', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await setUpMixed(tester, env);
      await openPastBudgets(tester, env);
      await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
      await settle(tester);
      await tester.tap(
        find.byKey(const ValueKey('budget-filter-period-month')),
      );
      await tester.tap(find.byKey(const ValueKey('budget-filter-result-over')));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(rows(), 1, reason: 'monthly and over: Food August');
      expect(find.text('Filter · 2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
      await settle(tester);
      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(rows(), 5);
      await disposeEnv(tester, env);
    });

    testWidgets('no matches says so and offers to clear', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 8, 1));
      await openPastBudgets(tester, env);
      await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('budget-filter-result-over')));
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('No results for these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      expect(rows(), 2);
      await disposeEnv(tester, env);
    });
  });

  group('sort', () {
    Future<List<String>> order(WidgetTester tester) async => [
      for (final f in find.byWidgetPredicate((w) {
        final key = w.key;
        return key is ValueKey<String> && key.value.startsWith('past-');
      }).evaluate())
        (f.widget.key! as ValueKey<String>).value,
    ];

    Future<void> chooseSort(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const ValueKey('budget-sort-button')));
      await settle(tester);
      await tester.tap(find.text(label).last);
      await settle(tester);
    }

    testWidgets('newest first by default, and the button says so', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await openPastBudgets(tester, env);
      expect(find.text('Date: newest first'), findsOneWidget);
      final food = await catId(tester, env, 'Food');
      expect(await order(tester), [
        'past-$food-${d(2026, 9, 1).toIso8601String()}',
        'past-$food-${d(2026, 8, 1).toIso8601String()}',
        'past-$food-${d(2026, 7, 1).toIso8601String()}',
      ]);
      await disposeEnv(tester, env);
    });

    testWidgets('oldest first reverses it', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await openPastBudgets(tester, env);
      await chooseSort(tester, 'Date: oldest first');
      final food = await catId(tester, env, 'Food');
      expect(
        (await order(tester)).first,
        'past-$food-${d(2026, 7, 1).toIso8601String()}',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('most over budget first, and most spent first', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await addExpense(tester, env, 21000, d(2026, 7, 10)); // over by 10
      await addExpense(tester, env, 50000, d(2026, 8, 10)); // over by 300
      await addExpense(tester, env, 30000, d(2026, 9, 10)); // over by 100
      await openPastBudgets(tester, env);
      final food = await catId(tester, env, 'Food');
      String key(DateTime d) => 'past-$food-${d.toIso8601String()}';

      await chooseSort(tester, 'Most over budget first');
      expect(await order(tester), [
        key(d(2026, 8, 1)),
        key(d(2026, 9, 1)),
        key(d(2026, 7, 1)),
      ]);
      await chooseSort(tester, 'Most spent first');
      expect(await order(tester), [
        key(d(2026, 8, 1)),
        key(d(2026, 9, 1)),
        key(d(2026, 7, 1)),
      ]);
      await disposeEnv(tester, env);
    });
  });

  group('show more', () {
    testWidgets('loads 12 periods of a budget, then more on request', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await limit(
        tester,
        env,
        'Food',
        20000,
        d(2025, 1, 1),
      ); // 21 finished months
      await openPastBudgets(tester, env);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('budget-history-more')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(rows(), lessThanOrEqualTo(12));
      await tester.tap(find.byKey(const ValueKey('budget-history-more')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('January 2025'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('January 2025'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('budget-history-more')),
        findsNothing,
        reason: 'everything is loaded',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('no button when everything fits', (tester) async {
      final env = await createEnv(tester);
      await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
      await openPastBudgets(tester, env);
      expect(find.byKey(const ValueKey('budget-history-more')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    testWidgets(
      'the pill, controls and rows fit at 200% text on a small screen',
      (tester) async {
        final env = await createEnv(tester);
        await limit(tester, env, 'Food', 20000, d(2026, 7, 1));
        await limit(
          tester,
          env,
          null,
          90000,
          d(2026, 8, 1),
          unit: BudgetUnit.week,
        );
        await addExpense(tester, env, 25000, d(2026, 8, 10));
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openPastBudgets(tester, env);
        expect(tester.takeException(), isNull, reason: 'the list');
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -1500));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scrolled');
        await tester.tap(find.byKey(const ValueKey('budget-filter-button')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: 'the filter sheet');
        await disposeEnv(tester, env);
      },
    );
  });
}
