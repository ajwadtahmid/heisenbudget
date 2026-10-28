import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/domain/period.dart';
import 'package:heisenbudget/domain/week_mode.dart';
import 'package:heisenbudget/features/home/home_screen.dart';
import 'package:heisenbudget/providers/navigation_providers.dart';
import 'package:heisenbudget/providers/period_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';

import 'test_helpers.dart';

/// A value inside one of the ruled rows (`received`, `spent` or `net`).
Finder _inRow(String row, String text) => find.descendant(
  of: find.byKey(ValueKey('row-$row')),
  matching: find.text(text),
);

String _balanceText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('balance'))).data!;

Future<void> openPeriodMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('period-menu')));
  await settle(tester);
}

Future<void> choosePeriod(WidgetTester tester, String menuKey) async {
  await openPeriodMenu(tester);
  await tester.tap(find.byKey(ValueKey(menuKey)));
  await settle(tester);
}

String _periodLabel(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('period-label'))).data!;

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

void main() {
  testWidgets('empty state shows when there are no transactions', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    expect(find.textContaining('Log your first transaction'), findsOneWidget);
    expect(find.textContaining('Nothing spent in this period'), findsOneWidget);
    expect(_balanceText(tester), r'$0.00');
    expect(_inRow('received', r'$0.00'), findsOneWidget);
    expect(_inRow('spent', r'$0.00'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets(
    'adding a transaction updates balance and cards with no refresh',
    (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      await addIncome(tester, env, 100000, DateTime(2026, 10, 1));
      await addExpense(tester, env, 2500, DateTime(2026, 10, 2));
      await settle(tester);

      expect(_balanceText(tester), r'$975.00');
      expect(_inRow('received', r'+$1,000.00'), findsOneWidget);
      expect(_inRow('spent', r'-$25.00'), findsOneWidget);
      expect(_inRow('net', r'+$975.00'), findsOneWidget);
      expect(find.textContaining('Log your first transaction'), findsNothing);
      // "Food" shows in the chart and in the recent list.
      expect(find.text('Food'), findsWidgets);
      expect(find.byType(ListTile), findsNWidgets(2));
      await disposeEnv(tester, env);
    },
  );

  testWidgets('a negative balance is shown in the amber Spent colour', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 5000, DateTime(2026, 10, 2));
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    expect(_balanceText(tester), r'-$50.00');
    final style = tester
        .widget<Text>(find.byKey(const ValueKey('balance')))
        .style!;
    final colors = Theme.of(tester.element(find.byType(HomeScreen)))
        .extension<AppColors>()!;
    expect(style.color, colors.spent);
    await disposeEnv(tester, env);
  });

  testWidgets(
    'future-dated transactions count in the period but not the balance',
    (tester) async {
      final env = await createEnv(tester); // today = Oct 15
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await addExpense(tester, env, 1000, DateTime(2026, 10, 15)); // today
      await addExpense(tester, env, 400, DateTime(2026, 10, 20)); // future
      await settle(tester);

      expect(_balanceText(tester), r'-$10.00');
      expect(_inRow('spent', r'-$14.00'), findsOneWidget);
      await disposeEnv(tester, env);
    },
  );

  testWidgets('week chips follow the week mode setting', (tester) async {
    // Aug 2026 starts on a Saturday: 6 Monday-start weeks, 5 fixed blocks.
    final env = await createEnv(tester, now: DateTime(2026, 8, 15));
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);
    await openPeriodMenu(tester);
    expect(find.byKey(const ValueKey('menu-week-6')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await settle(tester);

    final container = _container(tester);
    await tester.runAsync(
      () =>
          container.read(settingsProvider.notifier).setWeekMode(WeekMode.fixed),
    );
    await settle(tester);
    await openPeriodMenu(tester);
    expect(find.byKey(const ValueKey('menu-week-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-week-6')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('choosing Week 2 shows its dates and totals', (tester) async {
    final env = await createEnv(tester); // Oct 2026, Monday weeks
    await addExpense(tester, env, 700, DateTime(2026, 10, 6));
    await addExpense(tester, env, 300, DateTime(2026, 10, 20));
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);
    expect(_inRow('spent', r'-$10.00'), findsOneWidget, reason: 'whole month');

    await choosePeriod(tester, 'menu-week-2');

    expect(_periodLabel(tester), 'Week 2');
    expect(find.text('Oct 5 – Oct 11, 2026'), findsOneWidget);
    expect(_inRow('spent', r'-$7.00'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('stepping the month moves the range and totals', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 500, DateTime(2026, 11, 3));
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);
    expect(_periodLabel(tester), 'This month');
    expect(find.text('Oct 1 – Oct 31, 2026'), findsOneWidget);

    await swipePeriod(tester, forward: true);
    expect(_periodLabel(tester), 'November 2026');
    expect(find.text('Nov 1 – Nov 30, 2026'), findsOneWidget);
    expect(_inRow('spent', r'-$5.00'), findsOneWidget);

    await swipePeriod(tester, forward: false);
    await swipePeriod(tester, forward: false);
    expect(_periodLabel(tester), 'Last month');
    expect(find.text('Sep 1 – Sep 30, 2026'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('a custom range filters the totals', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 100, DateTime(2026, 10, 2));
    await addExpense(tester, env, 200, DateTime(2026, 10, 7));
    await addExpense(tester, env, 400, DateTime(2026, 10, 8));
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    _container(tester)
        .read(selectedPeriodProvider.notifier)
        .select(Custom(DateTime(2026, 10, 7), DateTime(2026, 10, 2)));
    await settle(tester);

    expect(
      find.text('Oct 2 – Oct 7, 2026'),
      findsOneWidget,
      reason: 'ends are swapped into order',
    );
    expect(_inRow('spent', r'-$3.00'), findsOneWidget);
    expect(_periodLabel(tester), 'Custom');
    await swipePeriod(tester, forward: true);
    expect(
      find.text('Oct 2 – Oct 7, 2026'),
      findsOneWidget,
      reason: 'a custom range cannot be stepped',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('the Custom chip opens the date range picker', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    await choosePeriod(tester, 'menu-custom');
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('recent shows only the last 3 and opens the editor on tap', (
    tester,
  ) async {
    final env = await createEnv(tester);
    for (var day = 1; day <= 7; day++) {
      await addExpense(tester, env, 100 * day, DateTime(2026, 10, day));
    }
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.text('-\$7.00'), findsOneWidget);
    expect(find.text('-\$5.00'), findsOneWidget);
    expect(find.text('-\$4.00'), findsNothing);

    await tester.tap(find.text('-\$7.00'));
    await settle(tester);
    expect(find.text('Edit transaction'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('Home uses one compact period button, not a row of chips', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('period-menu')), findsOneWidget);
    expect(_periodLabel(tester), 'This month');

    // Everything is inside the one menu, including Custom.
    await openPeriodMenu(tester);
    for (final key in [
      'menu-this-week',
      'menu-this-month',
      'menu-week-1',
      'menu-custom',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    await disposeEnv(tester, env);
  });

  testWidgets('the + button opens the add form', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wrap(env, const HomeScreen()));
    await settle(tester);

    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Add transaction'), findsWidgets);
    expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('See all switches to the History tab', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    await tester.tap(find.text('See all'));
    await settle(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, historyTab);
    await disposeEnv(tester, env);
  });

  testWidgets(
    'largest amounts do not overflow on a small screen at 200% text',
    (tester) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await addIncome(tester, env, 99999999999, DateTime(2026, 10, 1));
      await addExpense(
        tester,
        env,
        100,
        DateTime(2026, 10, 2),
        note: 'a very long note ' * 10,
      );
      await tester.pumpWidget(wrap(env, const HomeScreen()));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(_balanceText(tester), r'$999,999,998.99');
      await disposeEnv(tester, env);
    },
  );

  testWidgets('dark mode renders without errors', (tester) async {
    final env = await createEnv(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await addExpense(tester, env, 1234, DateTime(2026, 10, 2));
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('-\$12.34'), findsWidgets);
    await disposeEnv(tester, env);
  });
}
