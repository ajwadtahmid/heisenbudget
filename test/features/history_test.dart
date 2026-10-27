import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/saved_filter.dart';
import 'package:heisenbudget/domain/sort_option.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/history/history_screen.dart';
import 'package:heisenbudget/providers/history_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';

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
      // Filter and Sort are not in the app bar: only the two quiet icons,
      // jump to a date and Search.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(IconButton),
        ),
        findsNWidgets(2),
      );
      for (final key in ['filter-button', 'sort-button']) {
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byKey(ValueKey(key)),
          ),
          findsNothing,
          reason: key,
        );
      }
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const ValueKey('search-button')),
        ),
        findsOneWidget,
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

  group('reading a page at a time', () {
    /// 250 transactions, five a day, the oldest 40 noted "coffee".
    Future<void> many(WidgetTester tester, TestEnv env) async {
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 250; i++) {
          await env.txs.add(
            TransactionInput(
              amountCents: 100 + i,
              type: TransactionType.expense,
              // Oldest first: i = 0 is the oldest day, five to a day.
              date: DateTime(2026, 1, 1).add(Duration(days: i ~/ 5)),
              categoryId: food,
              note: i < 40 ? 'coffee' : null,
            ),
          );
        }
      });
    }

    HistoryPage page(WidgetTester tester) =>
        _container(tester).read(historyListProvider).value!;

    testWidgets('reads 100 first, more as the end is reached, then stops', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await many(tester, env);
      await pumpHistory(tester, env);
      expect(page(tester).rows, hasLength(historyPageSize));
      expect(page(tester).hasMore, isTrue);

      for (var i = 0; i < 14 && page(tester).hasMore; i++) {
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -8000),
        );
        await settle(tester);
      }
      expect(page(tester).hasMore, isFalse);
      expect(page(tester).rows, hasLength(250));
      expect(find.byKey(const ValueKey('history-more')), findsNothing);
      expect(find.byKey(const ValueKey('history-loading-more')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a day on a page boundary shows its whole total', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await many(tester, env);
      await pumpHistory(tester, env);
      // 100 rows are exactly 20 whole days of five: nothing is cut.
      final days = page(tester).rows.map((r) => r.transaction.date).toSet();
      expect(days, hasLength(20));
      await disposeEnv(tester, env);
    });

    testWidgets(
      'changing the sort or a filter starts again at the first page',
      (tester) async {
        final env = await createEnv(tester);
        await many(tester, env);
        await pumpHistory(tester, env);
        final container = _container(tester);
        container.read(historyLimitProvider.notifier).more();
        await settle(tester);
        expect(container.read(historyLimitProvider), historyPageSize * 2);

        container
            .read(historyFilterProvider.notifier)
            .setSort(SortOption.highestAmount);
        await settle(tester);
        expect(container.read(historyLimitProvider), historyPageSize);
        expect(page(tester).rows.first.transaction.amountCents, 349);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a search finds matches far beyond the first page and counts '
        'them all', (tester) async {
      final env = await createEnv(tester);
      await many(tester, env);
      await pumpHistory(tester, env);

      await tester.tap(find.byKey(const ValueKey('search-button')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'coffee',
      );
      await settle(tester);
      await settle(tester);

      expect(page(tester).rows, hasLength(40));
      expect(page(tester).hasMore, isFalse);
      expect(find.textContaining('40 results'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  testWidgets('the empty message leaves room for the + button at large text', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpHistory(tester, env);
    final room = tester.widget<Padding>(
      find.byKey(const ValueKey('history-empty')),
    );
    expect((room.padding as EdgeInsets).bottom, greaterThan(0));
    expect(tester.takeException(), isNull);
    await disposeEnv(tester, env);
  });

  group('amount range', () {
    Future<void> enter(WidgetTester tester, String key, String text) async {
      await tester.enterText(find.byKey(ValueKey(key)), text);
      await settle(tester);
    }

    testWidgets('keeps only the rows between the two amounts', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env); // 10.00, 30.00, 300.00 spent; 200.00 received
      await pumpHistory(tester, env);

      await openFilterSheet(tester);
      await enter(tester, 'amount-min', '50');
      expect(amount('-\$10.00'), findsNothing);
      expect(amount('-\$30.00'), findsNothing);
      expect(amount('-\$300.00'), findsOneWidget);
      expect(amount('+\$200.00'), findsOneWidget);

      await enter(tester, 'amount-max', '250');
      expect(amount('-\$300.00'), findsNothing);
      expect(amount('+\$200.00'), findsOneWidget);
      await closeFilterSheet(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('active-amount')),
          matching: find.text('\$50.00 to \$250.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Filter · 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove filter'));
      await settle(tester);
      expect(amount('-\$10.00'), findsOneWidget, reason: 'back to everything');
      expect(find.byKey(const ValueKey('active-amount')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('one bound alone reads "At least" or "At most"', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      await enter(tester, 'amount-max', '30,00');
      await closeFilterSheet(tester);
      expect(find.text('At most \$30.00'), findsOneWidget);
      expect(amount('-\$30.00'), findsOneWidget, reason: 'the edge is in');
      expect(amount('-\$300.00'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('bad input says so and changes nothing', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);

      await enter(tester, 'amount-min', 'abc');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      expect(amount('-\$10.00'), findsOneWidget, reason: 'not applied');

      await enter(tester, 'amount-min', '300');
      expect(find.text('Enter a valid amount'), findsNothing);
      expect(amount('-\$300.00'), findsOneWidget);
      expect(amount('+\$200.00'), findsNothing);

      await enter(tester, 'amount-max', '100');
      expect(find.text('The maximum is below the minimum'), findsOneWidget);
      expect(
        amount('-\$300.00'),
        findsOneWidget,
        reason: 'still the old range',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('Clear filters empties the two fields too', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      await enter(tester, 'amount-min', '50');
      await tester.tap(find.text('Clear filters'));
      await settle(tester);

      TextField field(String key) =>
          tester.widget<TextField>(find.byKey(ValueKey(key)));
      expect(field('amount-min').controller!.text, isEmpty);
      expect(amount('-\$10.00'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('jump to a date', () {
    Future<void> pickDay(WidgetTester tester, String day) async {
      await tester.tap(find.byKey(const ValueKey('jump-button')));
      await settle(tester);
      await tester.tap(find.text(day));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);
    }

    testWidgets('starts the list from the picked day and goes back', (
      tester,
    ) async {
      final env = await createEnv(tester); // today = Oct 15, 2026
      await seed(tester, env); // Oct 2, Oct 1, Sep 20
      await pumpHistory(tester, env);
      expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);

      await pickDay(tester, '1');
      expect(find.text('Fri, Oct 2, 2026'), findsNothing);
      expect(find.text('Thu, Oct 1, 2026'), findsOneWidget);
      expect(find.text('Sun, Sep 20, 2026'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('active-jump')),
          matching: find.text('Starting Oct 1, 2026'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Back to the latest'));
      await settle(tester);
      expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('active-jump')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('oldest first starts from the picked day going forward', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      _container(tester)
          .read(historyFilterProvider.notifier)
          .setSort(SortOption.oldestFirst);
      await settle(tester);

      await pickDay(tester, '1');
      expect(find.text('Sun, Sep 20, 2026'), findsNothing);
      expect(find.text('Thu, Oct 1, 2026'), findsOneWidget);
      expect(find.text('Fri, Oct 2, 2026'), findsOneWidget);
      expect(find.byTooltip('Back to the start'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'is offered only while sorted by date, and counts as a filter',
      (tester) async {
        final env = await createEnv(tester);
        await seed(tester, env);
        await pumpHistory(tester, env);
        expect(find.byKey(const ValueKey('jump-button')), findsOneWidget);

        await pickDay(tester, '1');
        expect(find.text('Filter · 1'), findsOneWidget);

        _container(tester)
            .read(historyFilterProvider.notifier)
            .setSort(SortOption.highestAmount);
        await settle(tester);
        expect(find.byKey(const ValueKey('jump-button')), findsNothing);
        expect(
          find.byKey(const ValueKey('active-jump')),
          findsNothing,
          reason: 'sorting by amount drops the jump',
        );
        await disposeEnv(tester, env);
      },
    );
  });

  group('saved filters', () {
    Future<void> save(WidgetTester tester, String name) async {
      final button = find.byKey(const ValueKey('save-filter'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-filter-name')),
        name,
      );
      await tester.tap(find.byKey(const ValueKey('saved-filter-save')));
      await settle(tester);
    }

    Future<void> pickRent(WidgetTester tester, TestEnv env) async {
      final rent = await categoryId(
        tester,
        env,
        'Rent',
        TransactionType.expense,
      );
      await tester.tap(find.byKey(ValueKey('filter-category-$rent')));
      await settle(tester);
    }

    testWidgets('save the filters, clear them, bring them back in one tap', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      expect(find.byKey(const ValueKey('saved-filter-0')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('save-filter')))
            .onPressed,
        isNull,
        reason: 'nothing to save yet',
      );

      await pickRent(tester, env);
      await save(tester, 'Rent only');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('saved-filter-0')),
          matching: find.text('Rent only'),
        ),
        findsOneWidget,
      );
      expect(env.prefs.getString('saved_filters'), contains('Rent only'));

      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      expect(amount('-\$10.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('saved-filter-0')));
      await settle(tester);
      expect(find.text('Done'), findsNothing, reason: 'the sheet closed');
      expect(amount('-\$300.00'), findsOneWidget);
      expect(amount('-\$10.00'), findsNothing);
      expect(
        _container(tester).read(historyFilterProvider).categoryIds,
        hasLength(1),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('keeps the amount range, the type and the sort', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      await tester.tap(find.text('Expense'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('amount-min')), '20');
      await settle(tester);
      await save(tester, 'Big spending');
      await tester.tap(find.text('Clear filters'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('saved-filter-0')));
      await settle(tester);

      final f = _container(tester).read(historyFilterProvider);
      expect(f.type, TransactionType.expense);
      expect(f.minCents, 2000);
      expect(amount('-\$30.00'), findsOneWidget);
      expect(amount('-\$10.00'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a repeated name replaces, a blank name is refused', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      await pickRent(tester, env);
      await save(tester, 'Mine');

      // Blank: the dialog stays open with a message.
      final button = find.byKey(const ValueKey('save-filter'));
      await tester.tap(button);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('saved-filter-save')));
      await settle(tester);
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('saved-filter-name')),
        'mine',
      );
      await tester.tap(find.byKey(const ValueKey('saved-filter-save')));
      await settle(tester);

      expect(find.byKey(const ValueKey('saved-filter-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-filter-1')), findsNothing);
      expect(find.text('mine'), findsOneWidget, reason: 'replaced, not added');
      await disposeEnv(tester, env);
    });

    testWidgets('a full list refuses a new name', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await _container(tester).read(settingsProvider.notifier).setSavedFilters([
        for (var i = 0; i < maxSavedFilters; i++) SavedFilter(name: 'F$i'),
      ]);
      await openFilterSheet(tester);
      await pickRent(tester, env);

      final button = find.byKey(const ValueKey('save-filter'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('saved-filter-name')),
        'One more',
      );
      await tester.tap(find.byKey(const ValueKey('saved-filter-save')));
      await settle(tester);
      expect(find.textContaining('up to $maxSavedFilters'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-filter-name')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a saved filter can be deleted', (tester) async {
      final env = await createEnv(tester);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      await pickRent(tester, env);
      await save(tester, 'Temp');
      expect(find.byKey(const ValueKey('saved-filter-0')), findsOneWidget);

      await tester.tap(find.byTooltip('Delete "Temp"'));
      await settle(tester);
      expect(find.byKey(const ValueKey('saved-filter-0')), findsNothing);
      expect(
        find.textContaining('Keep a set of filters you use often'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('the sheet fits at 200% text on a small phone', (tester) async {
      final env = await createEnv(
        tester,
        prefs: {
          'saved_filters': jsonEncode([
            const SavedFilter(name: 'A rather long saved filter name here')
                .toJson(),
            const SavedFilter(name: 'Short').toJson(),
          ]),
        },
      );
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await seed(tester, env);
      await pumpHistory(tester, env);
      await openFilterSheet(tester);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });
}
