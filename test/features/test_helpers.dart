import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app.dart';
import 'package:heisenbudget/core/theme.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/shortcuts/shortcut_service.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/shell/app_shell.dart';
import 'package:heisenbudget/features/transaction_form/transaction_form_screen.dart';
import 'package:heisenbudget/providers/database_providers.dart';
import 'package:heisenbudget/providers/period_providers.dart';
import 'package:heisenbudget/providers/quick_add_providers.dart';
import 'package:heisenbudget/providers/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the phone's launcher shortcuts.
class FakeShortcutService extends ShortcutService {
  FakeShortcutService();

  void Function(String type)? handler;
  List<AppShortcut> items = const [];
  int starts = 0;

  @override
  Future<void> start(void Function(String type) onAction) async {
    starts++;
    handler = onAction;
  }

  @override
  Future<void> setShortcuts(List<AppShortcut> items) async {
    this.items = items;
  }

  /// Pretends the person chose a shortcut on the launcher.
  void choose(String type) => handler?.call(type);
}

/// Everything a widget test needs: an in-memory database, preferences and a
/// fixed "today".
class TestEnv {
  TestEnv(this.db, this.prefs, this.now);

  final AppDatabase db;
  final SharedPreferences prefs;
  DateTime now;
  final shortcuts = FakeShortcutService();

  TransactionRepository get txs => TransactionRepository(db);
  CategoryRepository get cats => CategoryRepository(db);

  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(db),
    sharedPreferencesProvider.overrideWithValue(prefs),
    nowProvider.overrideWithValue(() => now),
    shortcutServiceProvider.overrideWithValue(shortcuts),
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
  // A page opened from Settings covers the app: go back to it first, so the
  // screens underneath wake up normally instead of during the teardown.
  for (var i = 0; i < 3; i++) {
    final covered =
        find.byType(AppShell, skipOffstage: false).evaluate().isNotEmpty &&
        find.byType(NavigationBar).evaluate().isEmpty;
    if (!covered || find.byType(BackButton).evaluate().isEmpty) break;
    await tester.pageBack();
    await settle(tester);
  }
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

/// From the Settings tab, opens a sub-page: `'appearance'` or `'money'`.
Future<void> openSettingsPage(WidgetTester tester, String which) async {
  final row = find.byKey(
    ValueKey(which == 'appearance' ? 'settings-appearance' : 'settings-money'),
  );
  await tester.ensureVisible(row);
  await tester.pump();
  await tester.tap(row);
  await settle(tester);
}
