import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/theme.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

String? deltaText(WidgetTester tester, String key) {
  final finder = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Text),
  );
  return finder.evaluate().isEmpty
      ? null
      : tester.widget<Text>(finder.first).data;
}

Future<void> openHome(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
}

void main() {
  testWidgets(
    'in progress: this month so far against the same days last month',
    (tester) async {
      final env = await createEnv(tester); // today is Oct 15
      await addExpense(tester, env, 10000, d(2026, 9, 10));
      await addExpense(
        tester,
        env,
        20000,
        d(2026, 9, 20),
      ); // after Sep 15: left out
      await addIncome(tester, env, 100000, d(2026, 9, 2));
      await addExpense(tester, env, 8800, d(2026, 10, 10));
      await addIncome(tester, env, 125000, d(2026, 10, 2));
      await openHome(tester, env);

      expect(deltaText(tester, 'delta-spent'), '▼ 12% vs Sep 1–15');
      expect(deltaText(tester, 'delta-received'), '▲ 25% vs Sep 1–15');
      await disposeEnv(tester, env);
    },
  );

  testWidgets('a finished month is compared whole, and named by its month', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 15000, d(2026, 8, 5));
    await addExpense(tester, env, 20000, d(2026, 9, 5));
    await addExpense(tester, env, 10000, d(2026, 9, 25));
    await openHome(tester, env);
    await swipePeriod(tester, forward: false); // September

    expect(deltaText(tester, 'delta-spent'), '▲ 100% vs Aug');
    expect(
      deltaText(tester, 'delta-received'),
      isNull,
      reason: 'no income either time',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('nothing in the earlier window means no delta at all', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 8800, d(2026, 10, 10));
    await addIncome(tester, env, 100000, d(2026, 10, 2));
    await openHome(tester, env);
    expect(find.byKey(const ValueKey('delta-spent')), findsNothing);
    expect(find.byKey(const ValueKey('delta-received')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('spending from nothing shows the amount, not a percentage', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addIncome(
      tester,
      env,
      100000,
      d(2026, 9, 2),
    ); // something happened before
    await addExpense(tester, env, 2500, d(2026, 10, 10));
    await openHome(tester, env);
    expect(deltaText(tester, 'delta-spent'), '▲ +\$25.00 vs Sep 1–15');
    await disposeEnv(tester, env);
  });

  testWidgets('spending that stopped is down 100%', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 5000, d(2026, 9, 5));
    await addIncome(tester, env, 100000, d(2026, 10, 2));
    await openHome(tester, env);
    expect(deltaText(tester, 'delta-spent'), '▼ 100% vs Sep 1–15');
    await disposeEnv(tester, env);
  });

  testWidgets('the same spending reads "about the same"', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 5000, d(2026, 9, 5));
    await addExpense(tester, env, 5000, d(2026, 10, 5));
    await openHome(tester, env);
    expect(deltaText(tester, 'delta-spent'), '= about the same vs Sep 1–15');
    await disposeEnv(tester, env);
  });

  testWidgets('percentages are capped at 999%', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 100, d(2026, 9, 5));
    await addExpense(tester, env, 1000000, d(2026, 10, 5));
    await openHome(tester, env);
    expect(deltaText(tester, 'delta-spent'), '▲ 999%+ vs Sep 1–15');
    await disposeEnv(tester, env);
  });

  testWidgets(
    'a future-dated transaction is in the Spent row but not the comparison',
    (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 5000, d(2026, 9, 5));
      await addExpense(tester, env, 5000, d(2026, 10, 5));
      await addExpense(tester, env, 90000, d(2026, 10, 28)); // not yet
      await openHome(tester, env);
      expect(deltaText(tester, 'delta-spent'), '= about the same vs Sep 1–15');
      await disposeEnv(tester, env);
    },
  );

  testWidgets('a period that has not started shows nothing', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 5000, d(2026, 10, 5));
    await openHome(tester, env);
    await swipePeriod(tester, forward: true); // November
    expect(find.byKey(const ValueKey('delta-spent')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets(
    'the Net row has no comparison and the opening balance is ignored',
    (tester) async {
      final env = await createEnv(
        tester,
        prefs: {'opening_balance_cents': 500000},
      );
      await addExpense(tester, env, 5000, d(2026, 9, 5));
      await addExpense(tester, env, 5000, d(2026, 10, 5));
      await openHome(tester, env);
      expect(find.byKey(const ValueKey('delta-net')), findsNothing);
      expect(deltaText(tester, 'delta-spent'), '= about the same vs Sep 1–15');
      expect(find.byKey(const ValueKey('delta-received')), findsNothing);
      await disposeEnv(tester, env);
    },
  );

  testWidgets('a week is compared with the same days of the week before', (
    tester,
  ) async {
    final env = await createEnv(tester); // Thursday Oct 15; week Oct 12 to 18
    await addExpense(tester, env, 10000, d(2026, 10, 6)); // previous Tuesday
    await addExpense(
      tester,
      env,
      30000,
      d(2026, 10, 10),
    ); // after the matched days
    await addExpense(tester, env, 5000, d(2026, 10, 13));
    await openHome(tester, env);
    // Switch the period to "This week" through the menu.
    await tester.tap(find.byKey(const ValueKey('period-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('menu-this-week')));
    await settle(tester);
    expect(deltaText(tester, 'delta-spent'), '▼ 50% vs Oct 5–8');
    await disposeEnv(tester, env);
  });

  testWidgets('it is quiet text, not the green or amber of the money rows', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 5000, d(2026, 9, 5));
    await addExpense(tester, env, 8000, d(2026, 10, 5));
    await openHome(tester, env);

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('delta-spent')),
        matching: find.byType(Text),
      ),
    );
    final colors = Theme.of(
      tester.element(find.byKey(const ValueKey('delta-spent'))),
    ).extension<AppColors>()!;
    expect(text.style?.color, colors.dim);
    expect(text.style?.color, isNot(colors.spent));
    expect(text.style?.color, isNot(colors.received));
    await disposeEnv(tester, env);
  });

  testWidgets('the screen reader hears the full sentence', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 10000, d(2026, 9, 5));
    await addExpense(tester, env, 8800, d(2026, 10, 5));
    await openHome(tester, env);
    expect(
      find.bySemanticsLabel('Spent 12% less than Sep 1 to 15, \$12.00 less.'),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('follows the data when a transaction is added', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 10000, d(2026, 9, 5));
    await addExpense(tester, env, 5000, d(2026, 10, 5));
    await openHome(tester, env);
    expect(deltaText(tester, 'delta-spent'), '▼ 50% vs Sep 1–15');
    await addExpense(tester, env, 5000, d(2026, 10, 6));
    await settle(tester);
    expect(deltaText(tester, 'delta-spent'), '= about the same vs Sep 1–15');
    await disposeEnv(tester, env);
  });

  testWidgets(
    'January compares with December of the year before, with the year',
    (tester) async {
      final env = await createEnv(tester, now: d(2027, 1, 15));
      await addExpense(tester, env, 10000, d(2026, 12, 5));
      await addExpense(tester, env, 20000, d(2027, 1, 5));
      await openHome(tester, env);
      expect(deltaText(tester, 'delta-spent'), '▲ 100% vs Dec 1–15, 2026');
      await disposeEnv(tester, env);
    },
  );

  testWidgets('fits at 200% text on a small screen', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 10000, d(2026, 9, 5));
    await addIncome(tester, env, 100000, d(2026, 9, 5));
    await addExpense(tester, env, 20000, d(2026, 10, 5));
    await addIncome(tester, env, 300000, d(2026, 10, 5));
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openHome(tester, env);
    expect(find.byKey(const ValueKey('delta-spent')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeEnv(tester, env);
  });
}
