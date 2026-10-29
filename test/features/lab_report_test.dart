import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/trends/lab_report_screen.dart';
import 'package:heisenbudget/features/trends/insights_screen.dart';
import 'package:heisenbudget/features/trends/reports_screen.dart';
import 'package:heisenbudget/features/transaction_form/transaction_form_screen.dart';
import 'package:heisenbudget/providers/lab_report_providers.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

const september = BudgetMonth(2026, 9);

/// Jul, Aug and Sep of steady spending and a little in October. Today is
/// Oct 3, so September's report is the one on offer.
Future<TestEnv> withHistory(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  DateTime? now,
}) async {
  final env = await createEnv(tester, now: now ?? d(2026, 10, 3), prefs: prefs);
  await addIncome(tester, env, 200000, d(2026, 7, 1));
  await addExpense(tester, env, 10000, d(2026, 7, 9), category: 'Food');
  await addIncome(tester, env, 200000, d(2026, 8, 1));
  await addExpense(tester, env, 10000, d(2026, 8, 9), category: 'Food');
  await addExpense(tester, env, 30000, d(2026, 8, 10), category: 'Rent');
  await addIncome(tester, env, 200000, d(2026, 9, 1));
  await addExpense(tester, env, 20000, d(2026, 9, 9), category: 'Food');
  await addExpense(tester, env, 10000, d(2026, 9, 10), category: 'Rent');
  await addExpense(tester, env, 1000, d(2026, 10, 2), category: 'Food');
  return env;
}

Future<void> limit(
  WidgetTester tester,
  TestEnv env,
  String category,
  int cents, {
  bool repeats = true,
}) async {
  final id = await categoryId(tester, env, category, TransactionType.expense);
  await tester.runAsync(
    () => BudgetRepository(env.db).setLimit(
      start: d(2026, 9, 1),
      unit: BudgetUnit.month,
      repeats: repeats,
      categoryId: id,
      amountCents: cents,
      today: env.now,
    ),
  );
}

Future<void> openHome(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
}

Future<void> openReport(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wrap(env, const LabReportScreen(month: september)));
  await settle(tester);
}

/// Scrolls the report until the widget with [key] is built and on screen.
Future<void> reveal(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Finder card() => find.byKey(const ValueKey('report-notice'));

void main() {
  group('Home card', () {
    testWidgets('announces last month in the first week', (tester) async {
      final env = await withHistory(tester);
      await openHome(tester, env);

      expect(card(), findsOneWidget);
      expect(find.text('Your September lab report is ready'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('plain wording when Lab flavor is off', (tester) async {
      final env = await withHistory(tester, prefs: {'lab_flavor': false});
      await openHome(tester, env);

      expect(find.text('Your September review is ready'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('is gone after the first week', (tester) async {
      final env = await withHistory(tester, now: d(2026, 10, 8));
      await openHome(tester, env);
      expect(card(), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('says nothing when nothing was logged in that month', (
      tester,
    ) async {
      final env = await createEnv(tester, now: d(2026, 10, 3));
      await addExpense(tester, env, 500, d(2026, 7, 9));
      await openHome(tester, env);
      expect(card(), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('Dismiss hides it for good', (tester) async {
      final env = await withHistory(tester);
      await openHome(tester, env);

      await tester.tap(find.byKey(const ValueKey('report-dismiss')));
      await settle(tester);

      expect(card(), findsNothing);
      expect(env.prefs.getString('report_seen_month'), '2026-09');
      await disposeEnv(tester, env);
    });

    testWidgets('opening the report hides it too', (tester) async {
      final env = await withHistory(tester);
      await openHome(tester, env);

      await tester.tap(find.byKey(const ValueKey('report-open')));
      await settle(tester);
      expect(find.byType(LabReportScreen), findsOneWidget);
      expect(env.prefs.getString('report_seen_month'), '2026-09');

      await tester.pageBack();
      await settle(tester);
      expect(card(), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('comes before the backup reminder, which follows it', (
      tester,
    ) async {
      final env = await withHistory(
        tester,
        prefs: {
          'last_backup_at': DateTime(2026, 1, 1).toUtc().toIso8601String(),
        },
      );
      await openHome(tester, env);
      expect(card(), findsOneWidget);
      expect(find.byKey(const ValueKey('backup-reminder')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('report-dismiss')));
      await settle(tester);
      expect(card(), findsNothing);
      expect(find.byKey(const ValueKey('backup-reminder')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await withHistory(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHome(tester, env);
      expect(card(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('Report page', () {
    testWidgets('the month against the month before', (tester) async {
      final env = await withHistory(tester);
      await openReport(tester, env);

      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Sep 1 – Sep 30, 2026'), findsOneWidget);
      expect(find.text('+\$2,000.00'), findsOneWidget, reason: 'received');
      expect(find.text('-\$300.00'), findsOneWidget, reason: 'spent');
      expect(find.text('+\$1,700.00'), findsOneWidget, reason: 'net');
      // August spent 400.00, so September spent 100.00 less; received the same.
      expect(find.text('\$100.00 less than August'), findsOneWidget);
      expect(find.text('The same as August'), findsOneWidget);
      expect(find.text('85.0%'), findsOneWidget);
      expect(find.text('August: 80.0%'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('opening it counts as read', (tester) async {
      final env = await withHistory(tester);
      await openReport(tester, env);
      expect(env.prefs.getString('report_seen_month'), '2026-09');
      await disposeEnv(tester, env);
    });

    testWidgets('an older report does not bring back a newer one', (
      tester,
    ) async {
      final env = await withHistory(
        tester,
        prefs: {'report_seen_month': '2026-09'},
      );
      await tester.pumpWidget(
        wrap(env, const LabReportScreen(month: BudgetMonth(2026, 8))),
      );
      await settle(tester);
      expect(env.prefs.getString('report_seen_month'), '2026-09');
      await disposeEnv(tester, env);
    });

    testWidgets('what moved, biggest expenses and how the month ran', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openReport(tester, env);

      expect(find.text('WHAT MOVED'), findsOneWidget);
      expect(find.text('Against the 2 months before it.'), findsOneWidget);
      // Food 200.00 against a usual 100.00; Rent 100.00 against 150.00.
      expect(find.text('\$200.00 against \$100.00 usually'), findsOneWidget);
      expect(find.text('\$100.00 against \$150.00 usually'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('HOW IT RAN'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('BIGGEST EXPENSES'), findsOneWidget);
      // Two days with spending out of 30.
      expect(find.text('28'), findsOneWidget);
      expect(find.text('of 30 days'), findsOneWidget);
      expect(find.text('Busiest day'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a biggest expense opens for editing', (tester) async {
      final env = await withHistory(tester);
      await openReport(tester, env);
      final saved = await savedTransactions(tester, env);
      final food = saved.firstWhere((t) => t.transaction.amountCents == 20000);

      final row = find.byKey(ValueKey('report-expense-${food.transaction.id}'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(row);
      await settle(tester);
      expect(find.byType(TransactionFormSheet), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('budgets: over, within, adjust and copy forward', (
      tester,
    ) async {
      final env = await withHistory(tester);
      // Food runs on (in force now); Rent's was for September only.
      await limit(tester, env, 'Food', 15000);
      await limit(tester, env, 'Rent', 12000, repeats: false);
      await openReport(tester, env);

      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      final rent = await categoryId(
        tester,
        env,
        'Rent',
        TransactionType.expense,
      );
      await reveal(tester, 'report-budget-$food');
      expect(find.text('BUDGETS'), findsOneWidget);
      expect(find.text('Over by \$50.00'), findsOneWidget);
      expect(find.text('\$200.00 of \$150.00'), findsOneWidget);
      expect(find.text('\$20.00 under'), findsOneWidget);
      expect(find.text('\$100.00 of \$120.00'), findsOneWidget);

      // Over comes first.
      expect(
        tester.getTopLeft(find.byKey(ValueKey('report-budget-$food'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(ValueKey('report-budget-$rent'))).dy,
        ),
      );

      final adjust = find.byKey(ValueKey('report-budget-action-$food'));
      final copy = find.byKey(ValueKey('report-budget-action-$rent'));
      expect(
        find.descendant(of: adjust, matching: find.text('Adjust')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: copy, matching: find.text('Copy forward')),
        findsOneWidget,
      );

      await tester.tap(copy);
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('no budgets, no budgets section', (tester) async {
      final env = await withHistory(tester);
      await openReport(tester, env);
      expect(find.text('BUDGETS'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('next steps: a limit for a big category, and a backup', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openReport(tester, env);

      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await reveal(tester, 'report-backup');
      expect(find.text('NEXT'), findsOneWidget);
      expect(
        find.text('Food took \$200.00 and has no budget.'),
        findsOneWidget,
      );
      expect(
        find.text('There is no recent backup of your data.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ValueKey('report-set-limit-$food')));
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a recent backup and a budget leave nothing to suggest', (
      tester,
    ) async {
      final env = await withHistory(
        tester,
        prefs: {
          'last_backup_at': DateTime(2026, 10, 1).toUtc().toIso8601String(),
        },
      );
      await limit(tester, env, 'Food', 15000);
      await limit(tester, env, 'Rent', 12000);
      await openReport(tester, env);
      expect(find.text('NEXT'), findsNothing);
      expect(find.byKey(const ValueKey('report-backup')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a failed read shows an error with Try again', (tester) async {
      final env = await withHistory(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            labReportProvider.overrideWith(
              (ref, month) => throw StateError('no'),
            ),
          ],
          child: MaterialApp(
            theme: lightTheme(),
            home: const LabReportScreen(month: september),
          ),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('report-error')), findsOneWidget);
      expect(find.text('Could not load this report.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      final env = await withHistory(tester);
      await limit(tester, env, 'Food', 15000);
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openReport(tester, env);

      // Scroll to the end: every section has been built once.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('report-backup')),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('The Reports page', () {
    testWidgets('lists the finished months with something in them', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await tester.pumpWidget(wrap(env, const ReportsScreen()));
      await settle(tester);

      final sep = find.byKey(const ValueKey('report-month-2026-09'));
      expect(find.text('Lab reports'), findsOneWidget);
      expect(sep, findsOneWidget);
      expect(find.byKey(const ValueKey('report-month-2026-08')), findsOne);
      expect(find.byKey(const ValueKey('report-month-2026-07')), findsOne);
      // June had nothing; October is still going.
      expect(find.byKey(const ValueKey('report-month-2026-06')), findsNothing);
      expect(find.byKey(const ValueKey('report-month-2026-10')), findsNothing);

      await tester.tap(sep);
      await settle(tester);
      expect(find.byType(LabReportScreen), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('before any month is finished, it says so', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 500, d(2026, 10, 2));
      await tester.pumpWidget(wrap(env, const ReportsScreen()));
      await settle(tester);
      expect(find.byKey(const ValueKey('reports-empty')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the Insights tab counts them and opens the page', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await tester.pumpWidget(wrap(env, const InsightsScreen()));
      await settle(tester);
      final row = find.byKey(const ValueKey('insights-reports'));
      expect(
        find.descendant(of: row, matching: find.text('3 finished months')),
        findsOneWidget,
      );
      await tester.tap(row);
      await settle(tester);
      expect(find.byType(ReportsScreen), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('the report card on the Insights tab', () {
    testWidgets('is at the top there too, and one dismissal clears both', (
      tester,
    ) async {
      final env = await withHistory(tester);
      await openHome(tester, env);
      expect(card(), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Insights'),
        ),
      );
      await settle(tester);
      expect(card(), findsOneWidget, reason: 'the Home copy is offstage');
      await tester.tap(find.byKey(const ValueKey('report-dismiss')));
      await settle(tester);
      expect(card(), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await settle(tester);
      expect(card(), findsNothing);
      await disposeEnv(tester, env);
    });
  });
}
