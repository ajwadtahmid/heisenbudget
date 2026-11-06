import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Future<TestEnv> withTransactions(WidgetTester tester, int n) async {
  // A backup was made today, so the backup reminder does not take the slot.
  final env = await createEnv(
    tester,
    now: d(2026, 10, 20),
    prefs: {'last_backup_at': DateTime.utc(2026, 10, 19).toIso8601String()},
  );
  for (var i = 0; i < n; i++) {
    await addExpense(tester, env, 500, d(2026, 10, 1 + (i % 15)));
  }
  return env;
}

Future<void> openHome(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
}

void main() {
  const tips = ValueKey('quick-tips');

  testWidgets('appears after ten transactions and names what is unused', (
    tester,
  ) async {
    final env = await withTransactions(tester, 10);
    await openHome(tester, env);

    expect(find.byKey(tips), findsOneWidget);
    expect(find.textContaining('Favorites:'), findsOneWidget);
    expect(find.textContaining('Repeat:'), findsOneWidget);
    expect(find.textContaining('Budgets:'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('stays away before ten transactions', (tester) async {
    final env = await withTransactions(tester, 9);
    await openHome(tester, env);

    expect(find.byKey(tips), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('leaves out what is already in use', (tester) async {
    final env = await withTransactions(tester, 10);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    await tester.runAsync(
      () => BudgetRepository(env.db).setLimit(
        start: d(2026, 10, 1),
        unit: BudgetUnit.month,
        categoryId: food,
        amountCents: 20000,
        today: env.now,
      ),
    );
    await openHome(tester, env);

    expect(find.textContaining('Budgets:'), findsNothing);
    expect(find.textContaining('Favorites:'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('Got it removes it and it stays gone after a restart', (
    tester,
  ) async {
    final env = await withTransactions(tester, 10);
    await openHome(tester, env);

    await tester.ensureVisible(
      find.byKey(const ValueKey('quick-tips-dismiss')),
    );
    await tester.tap(find.byKey(const ValueKey('quick-tips-dismiss')));
    await settle(tester);
    expect(find.byKey(tips), findsNothing);
    expect(env.prefs.getBool('tips_dismissed'), isTrue);

    await openHome(tester, env);
    expect(find.byKey(tips), findsNothing);
    await disposeEnv(tester, env);
  });
}
