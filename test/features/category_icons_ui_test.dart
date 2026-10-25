import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

/// Taps an icon in the picker, scrolling its grid to it first.
Future<void> tapIcon(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey('icon-$key'));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<void> openCategoryManager(WidgetTester tester) async {
  await goToTab(tester, 'Settings');
  // On a small screen at large text the row may start below the fold.
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('manage-categories')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  // Bring the row clear of the bottom navigation bar on small screens.
  await tester.ensureVisible(find.byKey(const ValueKey('manage-categories')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('manage-categories')));
  await settle(tester);
}

Future<String> savedIcon(
  WidgetTester tester,
  TestEnv env,
  String name,
  TransactionType type,
) async {
  final all = await tester.runAsync(() => env.cats.watchAll().first);
  return all!.firstWhere((c) => c.name == name && c.type == type).icon;
}

Finder rowIcon(int categoryId, IconData icon) => find.descendant(
  of: find.byKey(ValueKey('category-row-$categoryId')),
  matching: find.byIcon(icon),
);

void main() {
  testWidgets('every default category shows its icon in the manager', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    for (final (name, icon) in [
      ('Food', Icons.restaurant),
      ('Rent', Icons.home),
      ('Shopping', Icons.shopping_bag),
      ('Medical', Icons.medical_services),
      ('Travel', Icons.flight),
      ('Transport', Icons.directions_bus),
      ('Bills', Icons.receipt_long),
      ('Entertainment', Icons.movie),
    ]) {
      final id = await categoryId(tester, env, name, TransactionType.expense);
      expect(rowIcon(id, icon), findsOneWidget, reason: name);
    }
    final other = await categoryId(
      tester,
      env,
      'Other',
      TransactionType.expense,
    );
    expect(rowIcon(other, Icons.category_outlined), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('the income tab shows its icons too', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);
    await tester.tap(find.text('Income'));
    await settle(tester);

    final salary = await categoryId(
      tester,
      env,
      'Salary',
      TransactionType.income,
    );
    final gift = await categoryId(tester, env, 'Gift', TransactionType.income);
    expect(rowIcon(salary, Icons.payments), findsOneWidget);
    expect(rowIcon(gift, Icons.card_giftcard), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('change a category\'s icon', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);

    await tester.tap(find.byTooltip('Edit Food'));
    await settle(tester);
    expect(find.text('Edit category'), findsOneWidget);
    await tapIcon(tester, 'groceries');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Food', TransactionType.expense),
      'groceries',
    );
    expect(rowIcon(food, Icons.local_grocery_store), findsOneWidget);
    expect(rowIcon(food, Icons.restaurant), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('rename and change the icon in one go', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Edit Rent'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Housing',
    );
    await tapIcon(tester, 'bank');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Housing'), findsOneWidget);
    expect(
      await savedIcon(tester, env, 'Housing', TransactionType.expense),
      'bank',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('the edit dialog starts on the category\'s current icon', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Edit Travel'));
    await settle(tester);
    IconButton button(String key) => tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(IconButton),
      ),
    );
    expect(button('icon-flight').isSelected, isTrue, reason: 'current icon');
    expect(button('icon-car').isSelected, isNot(isTrue));
    await disposeEnv(tester, env);
  });

  testWidgets('a new category gets the icon you pick', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);
    expect(find.text('New category'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Dog food',
    );
    await tapIcon(tester, 'pets');
    await tester.tap(find.text('Add').last);
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Dog food', TransactionType.expense),
      'pets',
    );
    final id = await categoryId(
      tester,
      env,
      'Dog food',
      TransactionType.expense,
    );
    expect(rowIcon(id, Icons.pets), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('a new category without a choice gets the general icon', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Misc stuff',
    );
    await tester.tap(find.text('Add').last);
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Misc stuff', TransactionType.expense),
      'category',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('a category made from the add sheet carries its icon', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.tap(find.byKey(const ValueKey('new-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Coffee',
    );
    await tapIcon(tester, 'cafe');
    await tester.tap(find.text('Add').last);
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Coffee', TransactionType.expense),
      'cafe',
    );
    // The chip in the sheet shows it, selected.
    final chip = find.widgetWithText(ChoiceChip, 'Coffee');
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.byIcon(Icons.local_cafe)),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('category chips in the add sheet show their icons', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('category-$food')),
        matching: find.byIcon(Icons.restaurant),
      ),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('"Other" can change its icon but not its name', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Edit Other'));
    await settle(tester);

    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey('category-name-field')),
    );
    expect(nameField.enabled, isFalse);
    expect(find.text('"Other" keeps its name'), findsWidgets);

    await tapIcon(tester, 'star');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Other', TransactionType.expense),
      'star',
    );
    expect(find.text('Other'), findsOneWidget, reason: 'name unchanged');
    await disposeEnv(tester, env);
  });

  testWidgets('cancelling the dialog leaves the icon alone', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Edit Food'));
    await settle(tester);
    await tapIcon(tester, 'car');
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Food', TransactionType.expense),
      'restaurant',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('transactions show their category icon, also once archived', (
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
    await settle(tester);
    await goToTab(tester, 'History');

    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(Icons.flight),
      ),
      findsOneWidget,
    );

    final travel = await categoryId(
      tester,
      env,
      'Travel',
      TransactionType.expense,
    );
    await tester.runAsync(() => env.cats.archive(travel));
    await settle(tester);
    expect(find.text('Travel (archived)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byIcon(Icons.flight),
      ),
      findsOneWidget,
      reason: 'the icon stays after archiving',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('History filter chips show category icons', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 800, DateTime(2026, 10, 3));
    await tester.pumpWidget(wholeApp(env));
    await settle(tester);
    await goToTab(tester, 'History');

    await tester.tap(find.byTooltip('Filter'));
    await settle(tester);
    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('filter-category-$food')),
        matching: find.byIcon(Icons.restaurant),
      ),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('the picker fits a small screen at 200% text and stays usable', (
    tester,
  ) async {
    final env = await createEnv(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);
    expect(tester.takeException(), isNull);

    // The grid scrolls inside the dialog; search gets to any icon quickly.
    await tester.enterText(find.byKey(const ValueKey('icon-search')), 'star');
    await tester.pump();
    expect(find.byKey(const ValueKey('icon-star')), findsOneWidget);
    await tapIcon(tester, 'star');
    expect(tester.takeException(), isNull);
    await disposeEnv(tester, env);
  });

  testWidgets('search finds icons that are far down the grid', (tester) async {
    final env = await createEnv(tester);
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);
    await tester.tap(find.byKey(const ValueKey('add-category-expense')));
    await settle(tester);

    await tester.enterText(find.byKey(const ValueKey('icon-search')), 'rocket');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('icon-rocket')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Side project',
    );
    await tester.tap(find.text('Add').last);
    await settle(tester);

    expect(
      await savedIcon(tester, env, 'Side project', TransactionType.expense),
      'rocket',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('the dialog opens with the current icon scrolled into view', (
    tester,
  ) async {
    final env = await createEnv(tester);
    // A far-down icon: it is not visible without scrolling.
    final id = await categoryId(tester, env, 'Other', TransactionType.expense);
    await tester.runAsync(
      () => env.cats.update(id, name: 'Other', icon: 'construction'),
    );
    await tester.pumpWidget(wholeApp(env));
    await openCategoryManager(tester);

    await tester.tap(find.byTooltip('Edit Other'));
    await settle(tester);

    final iconRect = tester.getRect(
      find.byKey(const ValueKey('icon-construction')),
    );
    final gridRect = tester.getRect(find.byType(SingleChildScrollView).last);
    expect(
      gridRect.overlaps(iconRect),
      isTrue,
      reason: 'the selected icon is inside the visible grid',
    );
    await disposeEnv(tester, env);
  });
}
