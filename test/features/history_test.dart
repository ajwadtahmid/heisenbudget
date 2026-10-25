import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/providers/history_providers.dart';

import 'test_helpers.dart';

/// Oct 2: Rent -300.00 and Salary +200.00 (net -100.00); Oct 1: Food -10.00;
/// Sep 20: Food -30.00.
Future<void> seed(WidgetTester tester, TestEnv env) async {
  await addExpense(tester, env, 1000, DateTime(2026, 10, 1), note: 'snack');
  await addExpense(tester, env, 30000, DateTime(2026, 10, 2), category: 'Rent');
  await addIncome(tester, env, 20000, DateTime(2026, 10, 2));
  await addExpense(tester, env, 3000, DateTime(2026, 9, 20));
}

Future<void> pumpHistory(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wrap(env, const HistoryScreen()));
  await settle(tester);
}

/// An amount shown on a transaction row (a day header can show the same text).
Finder amount(String text) =>
    find.descendant(of: find.byType(ListTile), matching: find.text(text));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HistoryScreen)));

double _y(WidgetTester tester, String text) => tester
    .getTopLeft(
      text.startsWith('-') || text.startsWith('+')
          ? amount(text)
          : find.text(text),
    )
    .dy;

Future<void> openFilterSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filter'));
  await settle(tester);
}

Future<void> closeFilterSheet(WidgetTester tester) async {
  await tester.tap(find.text('Done'));
  await settle(tester);
}

void main() {
  testWidgets('groups by day with each day\'s net, newest first', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);

    expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);
    expect(find.text('Thu, Oct 1, 2026'), findsOneWidget);
    expect(find.text('Sun, Sep 20, 2026'), findsOneWidget);
    // Oct 2 net: +200.00 - 300.00
    expect(find.text('-\$100.00'), findsOneWidget);

    expect(
      _y(tester, 'Fri, Oct 2, 2026'),
      lessThan(_y(tester, 'Thu, Oct 1, 2026')),
    );
    expect(
      _y(tester, 'Thu, Oct 1, 2026'),
      lessThan(_y(tester, 'Sun, Sep 20, 2026')),
    );
    // Notes show; amounts carry a sign.
    expect(find.text('snack'), findsOneWidget);
    expect(amount('+\$200.00'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('filter by type', (tester) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);

    await openFilterSheet(tester);
    await tester.tap(find.text('Income'));
    await settle(tester);
    await closeFilterSheet(tester);

    expect(amount('+\$200.00'), findsOneWidget);
    expect(amount('-\$300.00'), findsNothing);
    expect(find.byKey(const ValueKey('active-type')), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('filter by several categories', (tester) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    final rent = await categoryId(tester, env, 'Rent', TransactionType.expense);

    await openFilterSheet(tester);
    await tester.tap(find.byKey(ValueKey('filter-category-$food')));
    await settle(tester);
    expect(amount('-\$300.00'), findsNothing);
    expect(amount('-\$10.00'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('filter-category-$rent')));
    await settle(tester);
    expect(amount('-\$300.00'), findsOneWidget);
    expect(amount('-\$10.00'), findsOneWidget);
    expect(amount('+\$200.00'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('filter by period, and "All time" removes it', (tester) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);
    expect(amount('-\$30.00'), findsOneWidget, reason: 'all time by default');

    await openFilterSheet(tester);
    await tester.tap(find.byKey(const ValueKey('chip-this-month')));
    await settle(tester);
    expect(amount('-\$30.00'), findsNothing, reason: 'September excluded');
    expect(amount('-\$10.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chip-all-time')));
    await settle(tester);
    expect(amount('-\$30.00'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('the date filter offers All time, This week, This month, '
      'Last month and Custom, with no week chips', (tester) async {
    final env = await createEnv(tester);
    await pumpHistory(tester, env);

    await openFilterSheet(tester);
    for (final key in [
      'all-time',
      'this-week',
      'this-month',
      'last-month',
      'custom',
    ]) {
      expect(find.byKey(ValueKey('chip-$key')), findsOneWidget, reason: key);
    }
    expect(find.textContaining('Week 1'), findsNothing);
    expect(find.byKey(const ValueKey('period-menu')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('Last month shows only last month\'s transactions', (
    tester,
  ) async {
    final env = await createEnv(tester); // today = Oct 15, 2026
    await seed(tester, env); // Sep 20 expense is last month
    await pumpHistory(tester, env);

    await openFilterSheet(tester);
    await tester.tap(find.byKey(const ValueKey('chip-last-month')));
    await settle(tester);

    expect(amount('-\$30.00'), findsOneWidget);
    expect(amount('-\$10.00'), findsNothing);
    expect(find.text('Sep 1 – Sep 30, 2026'), findsWidgets);
    await closeFilterSheet(tester);
    expect(find.byKey(const ValueKey('active-period')), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('This week limits the list to the current week', (tester) async {
    final env = await createEnv(tester); // Thu Oct 15; week = Oct 12-18
    await addExpense(tester, env, 100, DateTime(2026, 10, 13));
    await addExpense(tester, env, 200, DateTime(2026, 10, 11)); // Sunday before
    await pumpHistory(tester, env);

    await openFilterSheet(tester);
    await tester.tap(find.byKey(const ValueKey('chip-this-week')));
    await settle(tester);

    expect(amount('-\$1.00'), findsOneWidget);
    expect(amount('-\$2.00'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('the date chips wrap on a narrow screen', (tester) async {
    final env = await createEnv(tester);
    tester.view.physicalSize = const Size(320, 1400);
    await pumpHistory(tester, env);

    await openFilterSheet(tester);

    final first = tester
        .getTopLeft(find.byKey(const ValueKey('chip-all-time')))
        .dy;
    final last = tester
        .getTopLeft(find.byKey(const ValueKey('chip-custom')))
        .dy;
    expect(last, greaterThan(first), reason: 'wrapped onto another line');
    await disposeEnv(tester, env);
  });

  testWidgets('filters combine and chips remove them one by one', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);

    await openFilterSheet(tester);
    await tester.tap(find.text('Expense'));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('filter-category-$food')));
    await tester.tap(find.byKey(const ValueKey('chip-this-month')));
    await settle(tester);
    await closeFilterSheet(tester);

    // Only October's Food expense remains.
    expect(amount('-\$10.00'), findsOneWidget);
    expect(amount('-\$30.00'), findsNothing);
    expect(amount('-\$300.00'), findsNothing);
    expect(find.byKey(const ValueKey('active-type')), findsOneWidget);
    expect(find.byKey(ValueKey('active-category-$food')), findsOneWidget);
    expect(find.byKey(const ValueKey('active-period')), findsOneWidget);

    // Remove the period chip: September's Food comes back.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('active-period')),
        matching: find.byTooltip('Remove filter'),
      ),
    );
    await settle(tester);
    expect(amount('-\$30.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-period')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('sorting by amount and by date', (tester) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);

    Future<void> sortBy(String label) async {
      await tester.tap(find.byTooltip('Sort'));
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    await sortBy('Amount: highest first');
    expect(_y(tester, '-\$300.00'), lessThan(_y(tester, '+\$200.00')));
    expect(_y(tester, '+\$200.00'), lessThan(_y(tester, '-\$30.00')));
    expect(_y(tester, '-\$30.00'), lessThan(_y(tester, '-\$10.00')));
    expect(
      find.text('Fri, Oct 2, 2026'),
      findsNothing,
      reason: 'amount sorts are a plain list',
    );

    await sortBy('Amount: lowest first');
    expect(_y(tester, '-\$10.00'), lessThan(_y(tester, '-\$30.00')));
    expect(_y(tester, '-\$30.00'), lessThan(_y(tester, '+\$200.00')));

    await sortBy('Date: oldest first');
    expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);
    expect(
      _y(tester, 'Sun, Sep 20, 2026'),
      lessThan(_y(tester, 'Thu, Oct 1, 2026')),
    );
    await disposeEnv(tester, env);
  });

  testWidgets('swipe to delete, then Undo restores the same data', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final id = await addExpense(
      tester,
      env,
      1234,
      DateTime(2026, 10, 5),
      category: 'Travel',
      note: 'train ticket',
    );
    await pumpHistory(tester, env);

    await tester.drag(find.byKey(ValueKey('tx-$id')), const Offset(-600, 0));
    await settle(tester);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1)); // snackbar slides in

    expect(await savedTransactions(tester, env), isEmpty);
    expect(find.text('Transaction deleted'), findsOneWidget);
    expect(find.text('Flat line.\nNothing logged yet.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);

    final restored = await savedTransactions(tester, env);
    expect(restored, hasLength(1));
    final tx = restored.single.transaction;
    expect(tx.amountCents, 1234);
    expect(tx.date, '2026-10-05');
    expect(tx.note, 'train ticket');
    expect(tx.type, TransactionType.expense);
    expect(restored.single.category.name, 'Travel');
    expect(find.text('train ticket'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('tapping a row opens the editor', (tester) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);

    await tester.tap(find.text('snack'));
    await settle(tester);
    expect(find.text('Edit transaction'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('empty state: no transactions yet', (tester) async {
    final env = await createEnv(tester);
    await pumpHistory(tester, env);

    expect(find.textContaining('Flat line'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('empty state: no results, with a Clear filters button', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1000, DateTime(2026, 10, 1));
    await pumpHistory(tester, env);

    _container(tester)
        .read(historyFilterProvider.notifier)
        .setType(TransactionType.income);
    await settle(tester);

    expect(find.text('No results for these filters.'), findsOneWidget);
    expect(find.textContaining('Flat line'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear filters'));
    await settle(tester);
    expect(amount('-\$10.00'), findsOneWidget);
    expect(find.text('No results for these filters.'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('archived categories: shown on old rows, offered only if used', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    final rent = await categoryId(tester, env, 'Rent', TransactionType.expense);
    final travel = await categoryId(
      tester,
      env,
      'Travel',
      TransactionType.expense,
    );
    await tester.runAsync(() async {
      await env.cats.archive(rent); // used by a transaction
      await env.cats.archive(travel); // never used
    });
    await pumpHistory(tester, env);

    expect(find.text('Rent (archived)'), findsOneWidget);

    await openFilterSheet(tester);
    expect(find.byKey(ValueKey('filter-category-$rent')), findsOneWidget);
    expect(find.text('Rent (archived)'), findsWidgets);
    expect(find.byKey(ValueKey('filter-category-$travel')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('switching the type drops categories of the other type', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await seed(tester, env);
    await pumpHistory(tester, env);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);

    await openFilterSheet(tester);
    await tester.tap(find.byKey(ValueKey('filter-category-$food')));
    await settle(tester);
    expect(_container(tester).read(historyFilterProvider).categoryIds, {food});

    await tester.tap(find.text('Income'));
    await settle(tester);
    expect(_container(tester).read(historyFilterProvider).categoryIds, isEmpty);
    expect(amount('+\$200.00'), findsOneWidget, reason: 'not an empty list');
    await disposeEnv(tester, env);
  });

  testWidgets('long notes and huge amounts do not overflow at 200% text', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await addIncome(tester, env, 99999999999, DateTime(2026, 10, 1));
    await addExpense(
      tester,
      env,
      99999999999,
      DateTime(2026, 10, 1),
      note: 'an extremely long note ' * 8,
    );
    await pumpHistory(tester, env);

    expect(tester.takeException(), isNull);
    await disposeEnv(tester, env);
  });

  group('header controls and filter order', () {
    testWidgets('Filter and Sort sit under the title, not in the app bar', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);

      final title = tester.getRect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('History'),
        ),
      );
      final filter = tester.getRect(
        find.byKey(const ValueKey('filter-button')),
      );
      final sort = tester.getRect(find.byKey(const ValueKey('sort-button')));
      expect(filter.top, greaterThan(title.bottom));
      expect(sort.top, greaterThan(title.bottom));
      // Nothing is left in the app bar's action area.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      expect(filter.height, greaterThanOrEqualTo(48));
      expect(sort.height, greaterThanOrEqualTo(48));
      await disposeEnv(tester, env);
    });

    testWidgets('Sort shows how the list is sorted, in plain words', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sort-button')),
          matching: find.text('Date: newest first'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Sort'));
      await settle(tester);
      for (final label in [
        'Date: newest first',
        'Date: oldest first',
        'Amount: highest first',
        'Amount: lowest first',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      await tester.tap(find.text('Amount: lowest first'));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sort-button')),
          matching: find.text('Amount: lowest first'),
        ),
        findsOneWidget,
        reason: 'the button now names the new ordering',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the open Sort menu ticks the current choice', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      await tester.tap(find.byTooltip('Sort'));
      await settle(tester);
      final items = tester.widgetList<CheckedPopupMenuItem<SortOption>>(
        find.byType(CheckedPopupMenuItem<SortOption>),
      );
      expect(items.where((i) => i.checked).map((i) => i.value), [
        SortOption.newestFirst,
      ]);
      await disposeEnv(tester, env);
    });

    testWidgets('Filter shows how many filters are on', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      expect(find.text('Filter'), findsOneWidget);

      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await openFilterSheet(tester);
      await tester.tap(find.text('Expense'));
      await tester.tap(find.byKey(ValueKey('filter-category-$food')));
      await tester.tap(find.byKey(const ValueKey('chip-this-month')));
      await settle(tester);
      await closeFilterSheet(tester);

      expect(
        find.text('Filter · 3'),
        findsOneWidget,
        reason: 'type + category + date',
      );
      await disposeEnv(tester, env);
    });

    testWidgets(
      'the filter sheet runs type, date range, income, then expense categories',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wrap(env, const HistoryScreen()));
        await settle(tester);
        await openFilterSheet(tester);

        double y(Finder f) => tester.getTopLeft(f).dy;
        final type = y(find.text('All'));
        final date = y(find.text('Date range'));
        final income = y(find.text('Income categories'));
        final expense = y(find.text('Expense categories'));
        expect(type, lessThan(date));
        expect(date, lessThan(income));
        expect(income, lessThan(expense));
        await disposeEnv(tester, env);
      },
    );

    testWidgets(
      'choosing a type keeps the new order and hides the other list',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wrap(env, const HistoryScreen()));
        await settle(tester);
        await openFilterSheet(tester);

        await tester.tap(find.text('Income'));
        await settle(tester);
        expect(find.text('Income categories'), findsOneWidget);
        expect(find.text('Expense categories'), findsNothing);
        expect(
          tester.getTopLeft(find.text('Date range')).dy,
          lessThan(tester.getTopLeft(find.text('Income categories')).dy),
        );

        await tester.tap(find.text('Expense'));
        await settle(tester);
        expect(find.text('Expense categories'), findsOneWidget);
        expect(find.text('Income categories'), findsNothing);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('both controls fit a small screen at 200% text', (
      tester,
    ) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(wrap(env, const HistoryScreen()));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('filter-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('sort-button')), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });
}
