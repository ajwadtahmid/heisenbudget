import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/transaction_form/transaction_form_screen.dart';
import 'package:heisenbudget/providers/database_providers.dart';
import 'package:heisenbudget/providers/period_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything a widget test needs: an in-memory database, preferences and a
/// fixed "today".
class TestEnv {
  TestEnv(this.db, this.prefs, this.now);

  final AppDatabase db;
  final SharedPreferences prefs;
  DateTime now;

  TransactionRepository get txs => TransactionRepository(db);
  CategoryRepository get cats => CategoryRepository(db);

  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(db),
    sharedPreferencesProvider.overrideWithValue(prefs),
    nowProvider.overrideWithValue(() => now),
  ];
}

/// Creates the environment. Call [disposeEnv] at the end of the test.
Future<TestEnv> createEnv(
  WidgetTester tester, {
  DateTime? now,
  Map<String, Object> prefs = const {},
}) async {
  // A tall phone-like surface so long forms fit without scrolling.
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Every test makes its own in-memory database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late TestEnv env;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({
      'currency_code': 'USD',
      // Most tests start past the first-run tour.
      'onboarding_done': true,
      ...prefs,
    });
    env = TestEnv(
      AppDatabase.memory(),
      await SharedPreferences.getInstance(),
      now ?? DateTime(2026, 10, 15),
    );
  });
  return env;
}

Future<void> disposeEnv(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(env.db.close);
}

/// Wraps [child] in the providers and theme the app uses.
Widget wrap(TestEnv env, Widget child) {
  return ProviderScope(
    overrides: env.overrides,
    child: MaterialApp(
      theme: lightTheme(),
      darkTheme: darkTheme(),
      home: child,
    ),
  );
}

/// The whole app (with bottom navigation).
Widget wholeApp(TestEnv env) =>
    ProviderScope(overrides: env.overrides, child: const HeisenbudgetApp());

/// Lets database streams deliver and the UI rebuild. Drift works on real
/// async, which the test clock does not advance, so wait for real time.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Finish route transitions (a closed form is only gone after its animation).
  await tester.pump(const Duration(milliseconds: 500));
}

Future<int> categoryId(
  WidgetTester tester,
  TestEnv env,
  String name,
  TransactionType type,
) async {
  final all = await tester.runAsync(() => env.cats.watchAll().first);
  return all!.firstWhere((c) => c.name == name && c.type == type).id;
}

Future<int> addExpense(
  WidgetTester tester,
  TestEnv env,
  int cents,
  DateTime date, {
  String category = 'Food',
  String? note,
}) async {
  final id = await categoryId(tester, env, category, TransactionType.expense);
  return (await tester.runAsync(
    () => env.txs.add(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.expense,
        date: date,
        categoryId: id,
        note: note,
      ),
    ),
  ))!;
}

Future<int> addIncome(
  WidgetTester tester,
  TestEnv env,
  int cents,
  DateTime date, {
  String category = 'Salary',
}) async {
  final id = await categoryId(tester, env, category, TransactionType.income);
  return (await tester.runAsync(
    () => env.txs.add(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.income,
        date: date,
        categoryId: id,
      ),
    ),
  ))!;
}

/// Reads all saved transactions, newest first.
Future<List<TransactionWithCategory>> savedTransactions(
  WidgetTester tester,
  TestEnv env,
) async {
  return (await tester.runAsync(() => env.txs.watchFiltered().first))!;
}

/// Pumps a page with one button that opens the form, then opens it.
Future<void> openForm(WidgetTester tester, TestEnv env, {int? editId}) async {
  await tester.pumpWidget(
    wrap(
      env,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTransactionForm(context, editId: editId),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

/// Swipes across the period ruler: forward = next period, otherwise previous.
Future<void> swipePeriod(WidgetTester tester, {required bool forward}) async {
  await tester.fling(
    find.byKey(const ValueKey('period-swipe')),
    Offset(forward ? -300 : 300, 0),
    1500,
  );
  await settle(tester);
}
