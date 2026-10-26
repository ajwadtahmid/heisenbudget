import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<List<TransactionRow>> allTx(WidgetTester tester, TestEnv env) async {
  return (await tester.runAsync(
    () => (env.db.select(
      env.db.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
  ))!;
}

Future<List<FavoriteRow>> allFavorites(WidgetTester tester, TestEnv env) async {
  return (await tester.runAsync(
    () => FavoriteRepository(env.db).watchAll().first,
  ))!;
}

Future<int> addFavorite(
  WidgetTester tester,
  TestEnv env, {
  String label = 'Coffee',
  int? cents = 400,
  String category = 'Food',
  String? note = 'Flat white',
}) async {
  final cat = await categoryId(tester, env, category, TransactionType.expense);
  return (await tester.runAsync(
    () => FavoriteRepository(env.db).add(
      FavoriteInput(
        label: label,
        type: TransactionType.expense,
        categoryId: cat,
        amountCents: cents,
        note: note,
      ),
    ),
  ))!;
}

Future<void> longPressRow(WidgetTester tester, String key) async {
  await tester.longPress(find.byKey(ValueKey(key)));
  await settle(tester);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

String amountText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byKey(const ValueKey('amount-field')))
    .controller!
    .text;

String noteText(WidgetTester tester) => tester
    .widget<TextFormField>(find.byKey(const ValueKey('note-field')))
    .controller!
    .text;

void main() {
  group('the row menu', () {
    testWidgets(
      'long-pressing a History row opens Edit, Duplicate, Save as favorite, Delete',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addExpense(
          tester,
          env,
          450,
          d(2026, 10, 5),
          note: 'Latte',
        );
        await tester.pumpWidget(wholeApp(env));
        await goToTab(tester, 'History');
        await longPressRow(tester, 'tx-$id');

        for (final key in [
          'menu-edit',
          'menu-duplicate',
          'menu-favorite',
          'menu-delete',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
        await disposeEnv(tester, env);
      },
    );

    testWidgets('Home\'s Recent rows have the same menu', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        450,
        d(2026, 10, 5),
        note: 'Latte',
      );
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await longPressRow(tester, 'recent-$id');
      expect(find.byKey(const ValueKey('menu-duplicate')), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('Edit opens the Edit sheet', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        450,
        d(2026, 10, 5),
        note: 'Latte',
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-edit')));
      await settle(tester);
      expect(find.text('Edit transaction'), findsOneWidget);
      expect(amountText(tester), '4.50');
      await disposeEnv(tester, env);
    });

    testWidgets('Delete removes it and Undo brings it back', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        450,
        d(2026, 10, 5),
        note: 'Latte',
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-delete')));
      await settle(tester);

      expect(await allTx(tester, env), isEmpty);
      expect(find.text('Transaction deleted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      final back = await allTx(tester, env);
      expect(back.single.amountCents, 450);
      expect(back.single.note, 'Latte');
      await disposeEnv(tester, env);
    });
  });

  group('Duplicate', () {
    testWidgets(
      'opens the Add sheet filled in, dated today, and saves nothing yet',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addExpense(
          tester,
          env,
          450,
          d(2026, 9, 1),
          category: 'Transport',
          note: 'Bus pass',
        );
        await tester.pumpWidget(wholeApp(env));
        await goToTab(tester, 'History');
        await longPressRow(tester, 'tx-$id');
        await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
        await settle(tester);

        expect(find.text('Add transaction'), findsOneWidget);
        expect(amountText(tester), '4.50');
        expect(noteText(tester), 'Bus pass');
        final transport = await categoryId(
          tester,
          env,
          'Transport',
          TransactionType.expense,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(ValueKey('category-$transport')))
              .selected,
          isTrue,
        );
        expect(
          find.text('Oct 15, 2026'),
          findsOneWidget,
          reason: 'today, not Sep 1',
        );
        expect(await allTx(tester, env), hasLength(1), reason: 'not saved yet');

        await tester.tap(find.byKey(const ValueKey('save-button')));
        await settle(tester);
        final txs = await allTx(tester, env);
        expect(txs, hasLength(2));
        expect(txs.last.date, '2026-10-15');
        expect(txs.last.amountCents, 450);
        expect(txs.last.categoryId, transport);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('closing the sheet leaves just the original', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(tester, env, 450, d(2026, 9, 1), note: 'x');
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(await allTx(tester, env), hasLength(1));
      await disposeEnv(tester, env);
    });

    testWidgets('an archived category falls back to the default one', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        450,
        d(2026, 9, 1),
        category: 'Transport',
      );
      final transport = await categoryId(
        tester,
        env,
        'Transport',
        TransactionType.expense,
      );
      await tester.runAsync(
        () => CategoryRepository(env.db).archive(transport),
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
      await settle(tester);

      final other = await categoryId(
        tester,
        env,
        'Other',
        TransactionType.expense,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ValueKey('category-$other')))
            .selected,
        isTrue,
      );
      expect(find.byKey(ValueKey('category-$transport')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('the Edit sheet\'s menu duplicates too', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        450,
        d(2026, 9, 1),
        note: 'Latte',
      );
      await openForm(tester, env, editId: id);
      await tester.tap(find.byKey(const ValueKey('form-menu')));
      await settle(tester);
      await tester.tap(find.text('Duplicate'));
      await settle(tester);

      expect(find.text('Add transaction'), findsOneWidget);
      expect(amountText(tester), '4.50');
      expect(noteText(tester), 'Latte');
      expect(find.text('Oct 15, 2026'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an income duplicate stays income', (tester) async {
      final env = await createEnv(tester);
      final id = await addIncome(tester, env, 500000, d(2026, 9, 1));
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
      await settle(tester);
      final salary = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ValueKey('category-$salary')))
            .selected,
        isTrue,
      );
      await disposeEnv(tester, env);
    });
  });

  group('Save as favorite', () {
    testWidgets(
      'from the row menu: name from the note, amount and category kept',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addExpense(
          tester,
          env,
          400,
          d(2026, 10, 5),
          note: 'Coffee',
        );
        await tester.pumpWidget(wholeApp(env));
        await goToTab(tester, 'History');
        await longPressRow(tester, 'tx-$id');
        await tester.tap(find.byKey(const ValueKey('menu-favorite')));
        await settle(tester);

        expect(find.text('Save as favorite'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('favorite-label')),
              )
              .controller!
              .text,
          'Coffee',
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('favorite-amount')),
              )
              .controller!
              .text,
          '4.00',
        );
        await tapKey(tester, 'favorite-save');

        final favs = await allFavorites(tester, env);
        expect(favs, hasLength(1));
        expect((favs.single.label, favs.single.amountCents), ('Coffee', 400));
        expect(find.text('Saved “Coffee” to Quick add.'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('from the Edit sheet menu', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        400,
        d(2026, 10, 5),
        note: 'Tea',
      );
      await openForm(tester, env, editId: id);
      await tester.tap(find.byKey(const ValueKey('form-menu')));
      await settle(tester);
      await tester.tap(find.text('Save as favorite'));
      await settle(tester);
      await tapKey(tester, 'favorite-save');
      expect((await allFavorites(tester, env)).single.label, 'Tea');
      await disposeEnv(tester, env);
    });

    testWidgets('clearing the amount makes it ask each time', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        400,
        d(2026, 10, 5),
        note: 'Coffee',
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('favorite-amount')), '');
      await tapKey(tester, 'favorite-save');
      expect((await allFavorites(tester, env)).single.amountCents, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('a blank name falls back to the category', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(tester, env, 400, d(2026, 10, 5));
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('favorite-label')),
        '   ',
      );
      await tapKey(tester, 'favorite-save');
      expect((await allFavorites(tester, env)).single.label, 'Food');
      await disposeEnv(tester, env);
    });

    testWidgets('a bad amount is refused', (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(tester, env, 400, d(2026, 10, 5), note: 'x');
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('favorite-amount')),
        '0',
      );
      await tapKey(tester, 'favorite-save');
      expect(find.text('Amount must be greater than zero'), findsOneWidget);
      expect(await allFavorites(tester, env), isEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('at the limit it explains instead of saving', (tester) async {
      final env = await createEnv(tester);
      for (var i = 0; i < maxFavorites; i++) {
        await addFavorite(tester, env, label: 'F$i');
      }
      final id = await addExpense(
        tester,
        env,
        400,
        d(2026, 10, 5),
        note: 'One more',
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$id');
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      await tapKey(tester, 'favorite-save');

      expect(find.byKey(const ValueKey('favorite-error')), findsOneWidget);
      expect(find.textContaining('up to 12 favorites'), findsOneWidget);
      expect(await allFavorites(tester, env), hasLength(maxFavorites));
      await disposeEnv(tester, env);
    });
  });

  group('the Quick add strip on Home', () {
    testWidgets('is absent until there is a favorite', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('QUICK ADD'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('shows each favorite with its amount, in order', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addFavorite(tester, env, label: 'Coffee', cents: 400);
      await addFavorite(
        tester,
        env,
        label: 'Bus',
        cents: 250,
        category: 'Transport',
      );
      await addFavorite(tester, env, label: 'Lunch', cents: null);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      expect(find.text('QUICK ADD'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('\$4.00'), findsOneWidget);
      expect(find.text('\$2.50'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      final xs = [
        for (final l in ['Coffee', 'Bus', 'Lunch'])
          tester.getTopLeft(find.text(l)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      await disposeEnv(tester, env);
    });

    testWidgets('tapping logs it today, then Undo removes it', (tester) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);
      final txs = await allTx(tester, env);
      expect(txs, hasLength(1));
      expect(
        (
          txs.single.amountCents,
          txs.single.date,
          txs.single.note,
          txs.single.type,
        ),
        (400, '2026-10-15', 'Flat white', TransactionType.expense),
      );
      expect(find.text('Logged Coffee -\$4.00.'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing, reason: 'no sheet opened');

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(await allTx(tester, env), isEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('tapping twice logs twice', (tester) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);
      expect(await allTx(tester, env), hasLength(2));
      await disposeEnv(tester, env);
    });

    testWidgets('an income favorite logs as income', (tester) async {
      final env = await createEnv(tester);
      final cat = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      final id = (await tester.runAsync(
        () => FavoriteRepository(env.db).add(
          FavoriteInput(
            label: 'Pay',
            type: TransactionType.income,
            categoryId: cat,
            amountCents: 100000,
          ),
        ),
      ))!;
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);
      expect((await allTx(tester, env)).single.type, TransactionType.income);
      expect(find.text('Logged Pay \$1,000.00.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a favorite with no amount opens the sheet to enter one', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addFavorite(
        tester,
        env,
        label: 'Lunch',
        cents: null,
        note: 'Canteen',
      );
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester);

      expect(find.text('Add transaction'), findsOneWidget);
      expect(amountText(tester), '');
      expect(noteText(tester), 'Canteen');
      expect(await allTx(tester, env), isEmpty);

      await tester.enterText(find.byKey(const ValueKey('amount-field')), '12');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      expect((await allTx(tester, env)).single.amountCents, 1200);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a favorite whose category was archived opens the sheet instead',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addFavorite(tester, env, category: 'Transport');
        final transport = await categoryId(
          tester,
          env,
          'Transport',
          TransactionType.expense,
        );
        await tester.runAsync(
          () => CategoryRepository(env.db).archive(transport),
        );
        await tester.pumpWidget(wholeApp(env));
        await settle(tester);
        await tester.tap(find.byKey(ValueKey('favorite-$id')));
        await settle(tester);
        expect(find.text('Add transaction'), findsOneWidget);
        expect(amountText(tester), '4.00');
        expect(await allTx(tester, env), isEmpty);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('long-press offers to open it or edit it', (tester) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await longPressRow(tester, 'favorite-$id');
      expect(find.byKey(const ValueKey('favorite-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-edit')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('favorite-open')));
      await settle(tester);
      expect(find.text('Add transaction'), findsOneWidget);
      expect(amountText(tester), '4.00');
      expect(await allTx(tester, env), isEmpty, reason: 'opening does not log');
      await disposeEnv(tester, env);
    });

    testWidgets('editing from the long-press menu changes the favorite', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await longPressRow(tester, 'favorite-$id');
      await tester.tap(find.byKey(const ValueKey('favorite-edit')));
      await settle(tester);
      expect(find.text('Edit favorite'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('favorite-amount')),
        '4.50',
      );
      await tapKey(tester, 'favorite-save');
      expect((await allFavorites(tester, env)).single.amountCents, 450);
      expect(find.text('\$4.50'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('Settings > Quick add', () {
    Future<void> openManager(WidgetTester tester) async {
      await goToTab(tester, 'Settings');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('manage-favorites')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('manage-favorites')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('manage-favorites')));
      await settle(tester);
    }

    testWidgets('the Settings row counts them', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      expect(find.text('One tap to log what you buy often'), findsOneWidget);
      await addFavorite(tester, env);
      await settle(tester);
      expect(find.text('1 favorite'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an empty list says how to make one', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await openManager(tester);
      expect(find.textContaining('No favorites yet.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('lists them with amounts, and "Amount each time"', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addFavorite(tester, env, label: 'Coffee', cents: 400);
      await addFavorite(tester, env, label: 'Lunch', cents: null);
      await tester.pumpWidget(wholeApp(env));
      await openManager(tester);
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('\$4.00'), findsOneWidget);
      expect(find.text('Amount each time'), findsOneWidget);
      expect(
        find.text('2 of 12. Drag the handles to reorder.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('tapping a row edits it', (tester) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await openManager(tester);
      await tester.tap(find.byKey(ValueKey('favorite-row-$id')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('favorite-label')),
        'Flat white',
      );
      await tapKey(tester, 'favorite-save');
      expect((await allFavorites(tester, env)).single.label, 'Flat white');
      expect(find.text('Flat white'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('delete asks first and leaves past transactions alone', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await settle(tester); // logs one
      await openManager(tester);

      await tester.tap(find.byKey(ValueKey('favorite-delete-$id')));
      await settle(tester);
      expect(find.textContaining('stay in History'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await allFavorites(tester, env), hasLength(1));

      await tester.tap(find.byKey(ValueKey('favorite-delete-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-delete-confirm')));
      await settle(tester);
      expect(await allFavorites(tester, env), isEmpty);
      expect(await allTx(tester, env), hasLength(1));
      await disposeEnv(tester, env);
    });

    testWidgets('dragging a handle reorders the strip', (tester) async {
      final env = await createEnv(tester);
      await addFavorite(tester, env, label: 'A');
      await addFavorite(tester, env, label: 'B');
      await addFavorite(tester, env, label: 'C');
      await tester.pumpWidget(wholeApp(env));
      await openManager(tester);

      final handles = find.byIcon(Icons.drag_handle);
      expect(handles, findsNWidgets(3));
      await tester.drag(handles.first, const Offset(0, 160));
      await settle(tester);
      expect(
        (await allFavorites(tester, env)).map((f) => f.label),
        isNot(['A', 'B', 'C']),
      );
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    testWidgets('the strip, menus and editor fit at 200% text', (tester) async {
      final env = await createEnv(tester);
      for (var i = 0; i < 5; i++) {
        await addFavorite(tester, env, label: 'A fairly long favorite $i');
      }
      final tx = await addExpense(
        tester,
        env,
        450,
        d(2026, 10, 5),
        note: 'Latte',
      );
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'Home with the strip');

      await goToTab(tester, 'History');
      await longPressRow(tester, 'tx-$tx');
      expect(tester.takeException(), isNull, reason: 'the row menu');
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      expect(
        find.text('Save as favorite'),
        findsOneWidget,
        reason: 'it opened',
      );
      expect(tester.takeException(), isNull, reason: 'the editor');
      await disposeEnv(tester, env);
    });
  });
}
