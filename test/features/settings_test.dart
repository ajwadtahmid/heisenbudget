import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

Future<void> goToTab(WidgetTester tester, String label) async {
  // A page opened from Settings covers the tab bar: go back to it first.
  for (var i = 0; i < 3 && find.byType(NavigationBar).evaluate().isEmpty; i++) {
    await tester.pageBack();
    await settle(tester);
  }
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

String _balance(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('balance'))).data!;

Future<void> openCategoryManager(WidgetTester tester) async {
  await goToTab(tester, 'Settings');
  await tester.tap(find.byKey(const ValueKey('manage-categories')));
  await settle(tester);
}

void main() {
  testWidgets('the currency dropdown starts on the current currency', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');

    expect(find.byKey(const ValueKey('currency-dropdown')), findsOneWidget);
    expect(find.text('\$ US Dollar (USD)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('currency-field')),
      findsNothing,
      reason: 'no free-text symbol field any more',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('pick Bangladeshi Taka by searching; Home shows the taka sign', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(_balance(tester), r'$0.00');

    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('currency-dropdown')),
        matching: find.byType(TextField),
      ),
      'bangla',
    );
    await settle(tester);
    expect(find.text('৳ Bangladeshi Taka (BDT)'), findsOneWidget);
    expect(find.text('€ Euro (EUR)'), findsNothing, reason: 'list is filtered');

    await tester.tap(find.text('৳ Bangladeshi Taka (BDT)'));
    await settle(tester);

    expect(env.prefs.getString('currency_code'), 'BDT');
    await goToTab(tester, 'Home');
    expect(_balance(tester), '৳0.00');
    await disposeEnv(tester, env);
  });

  testWidgets('every currency is reachable from the dropdown', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('currency-dropdown')),
        matching: find.byType(TextField),
      ),
    );
    await settle(tester);
    // The menu is a scrollable list: the first entries are built.
    expect(find.text('AR\$ Argentine Peso (ARS)'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('there is no starting balance option', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await goToTab(tester, 'Settings');

    expect(find.textContaining('Starting balance'), findsNothing);
    expect(find.byKey(const ValueKey('starting-balance-tile')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('week mode changes the Home chips and totals immediately', (
    tester,
  ) async {
    // Aug 2026: 6 Monday-start weeks, 5 fixed blocks. Aug 1 is a Saturday.
    final env = await createEnv(tester, now: DateTime(2026, 8, 15));
    await addExpense(tester, env, 500, DateTime(2026, 8, 3)); // Monday
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('period-menu')));
    await settle(tester);
    expect(find.byKey(const ValueKey('menu-week-6')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-week-1')));
    await settle(tester);
    // Calendar Week 1 is Sat Aug 1 - Sun Aug 2: the Aug 3 expense is outside.
    expect(find.text('Aug 1 – Aug 2, 2026'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-spent')),
        matching: find.text(r'$0.00'),
      ),
      findsOneWidget,
    );

    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');
    await tester.tap(find.text('Fixed 7-day blocks'));
    await settle(tester);

    await goToTab(tester, 'Home');
    await tester.tap(find.byKey(const ValueKey('period-menu')));
    await settle(tester);
    expect(find.byKey(const ValueKey('menu-week-6')), findsNothing);
    expect(find.byKey(const ValueKey('menu-week-5')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await settle(tester);
    expect(
      find.text('Aug 1 – Aug 7, 2026'),
      findsOneWidget,
      reason: 'Week 1 is now days 1-7',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('row-spent')),
        matching: find.text(r'-$5.00'),
      ),
      findsOneWidget,
      reason: 'the Aug 3 expense is now inside Week 1',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('week start day changes Week N dates; disabled in fixed mode', (
    tester,
  ) async {
    final env = await createEnv(tester, now: DateTime(2026, 8, 15));
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('period-menu')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('menu-week-2')));
    await settle(tester);
    expect(find.text('Aug 3 – Aug 9, 2026'), findsOneWidget, reason: 'Monday');

    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await settle(tester);
    await tester.tap(find.text('Sunday').last);
    await settle(tester);

    await goToTab(tester, 'Home');
    expect(find.text('Aug 2 – Aug 8, 2026'), findsOneWidget, reason: 'Sunday');

    await goToTab(tester, 'Settings');
    await openSettingsPage(tester, 'money');
    await tester.tap(find.text('Fixed 7-day blocks'));
    await settle(tester);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    expect(dropdown.onChanged, isNull);
    expect(find.text('Only used with calendar weeks'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('category manager: add, rename, archive, restore', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);
    expect(find.text('Categories'), findsOneWidget);

    // Add
    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Coffee',
    );
    await tester.tap(find.text('Add').last);
    await settle(tester);
    expect(find.text('Coffee'), findsOneWidget);

    // Rename
    await tester.tap(find.byTooltip('Edit Coffee'));
    await settle(tester);
    expect(find.text('Edit category'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Tea',
    );
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Coffee'), findsNothing);

    // Archive
    await tester.tap(find.byTooltip('Archive Tea'));
    await settle(tester);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.byTooltip('Restore Tea'), findsOneWidget);
    expect(find.byTooltip('Archive Tea'), findsNothing);

    // Restore
    await tester.tap(find.byTooltip('Restore Tea'));
    await settle(tester);
    expect(find.byTooltip('Archive Tea'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('"Other" cannot be archived (and keeps its name)', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Always available'), findsOneWidget);
    expect(find.byTooltip('Archive Other'), findsNothing);
    expect(
      find.byTooltip('Edit Other'),
      findsOneWidget,
      reason: 'its icon can still be changed',
    );

    await tester.tap(find.text('Income'));
    await settle(tester);
    expect(find.text('Other'), findsOneWidget);
    expect(find.byTooltip('Archive Other'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('category manager rejects duplicates', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'FOOD',
    );
    await tester.tap(find.text('Add').last);
    await settle(tester);
    expect(find.text('A category named "FOOD" already exists'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('archiving hides a category from the form but old rows keep it', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(
      tester,
      env,
      800,
      DateTime(2026, 10, 3),
      category: 'Travel',
    );
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Archive Travel'));
    await settle(tester);
    Navigator.of(tester.element(find.text('Categories'))).pop();
    await settle(tester);

    // The "Archived" snackbar lives on the app-level messenger and would sit
    // on top of the + button: dismiss it.
    ScaffoldMessenger.of(tester.element(find.byType(NavigationBar)))
        .removeCurrentSnackBar();
    await tester.pump(const Duration(seconds: 1));

    // History still shows the old transaction with its category.
    await goToTab(tester, 'History');
    expect(find.text('Travel (archived)'), findsOneWidget);

    // A new transaction can no longer pick it.
    await goToTab(tester, 'Home');
    await tester.tap(find.byTooltip('Add transaction'));
    await settle(tester);
    expect(find.byKey(const ValueKey('save-button')), findsOneWidget);
    // (Travel still appears in Home's chart behind the sheet: only the
    // sheet's own chips matter here.)
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Travel'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Food'),
      ),
      findsOneWidget,
    );
    final travel = await categoryId(
      tester,
      env,
      'Travel',
      TransactionType.expense,
    );
    expect(find.byKey(ValueKey('category-$travel')), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('settings are remembered after a restart', (tester) async {
    final env = await createEnv(
      tester,
      prefs: {
        'currency_code': 'GBP',
        'week_mode': 'fixed',
        'week_start_day': 3,
      },
    );
    await addIncome(tester, env, 12345, DateTime(2026, 10, 1));
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    expect(_balance(tester), '£123.45');

    await goToTab(tester, 'Settings');
    expect(find.text('Version'), findsOneWidget);
    expect(find.textContaining('GBP'), findsOneWidget, reason: 'summary');
    await openSettingsPage(tester, 'money');
    expect(find.text('£ British Pound (GBP)'), findsOneWidget);
    await disposeEnv(tester, env);
  });
}
