import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/providers/quick_add_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:heisenbudget/features/shell/app_shell.dart';

import 'test_helpers.dart';

import 'package:heisenbudget/providers/settings_providers.dart';

Future<int> addFavorite(
  WidgetTester tester,
  TestEnv env, {
  String label = 'Coffee',
  int? cents = 400,
  String category = 'Food',
}) async {
  final cat = await categoryId(tester, env, category, TransactionType.expense);
  return (await tester.runAsync(
    () => FavoriteRepository(env.db).add(
      FavoriteInput(
        label: label,
        type: TransactionType.expense,
        categoryId: cat,
        amountCents: cents,
        note: 'Flat white',
      ),
    ),
  ))!;
}

Future<void> start(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(wholeApp(env));
  await settle(tester);
}

Future<void> choose(WidgetTester tester, TestEnv env, String type) async {
  env.shortcuts.choose(type);
  await settle(tester);
}

bool selected(WidgetTester tester, int category) => tester
    .widget<ChoiceChip>(find.byKey(ValueKey('category-$category')))
    .selected;

void main() {
  group('registering shortcuts', () {
    testWidgets(
      'the app starts listening and registers Add expense and Add income',
      (tester) async {
        final env = await createEnv(tester);
        await start(tester, env);
        expect(env.shortcuts.starts, 1);
        expect(env.shortcuts.items.map((s) => s.type), [
          'add_expense',
          'add_income',
        ]);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('the first favorite gets a shortcut of its own', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addFavorite(tester, env, label: 'Coffee');
      await addFavorite(tester, env, label: 'Bus', category: 'Transport');
      await start(tester, env);
      expect(env.shortcuts.items.map((s) => s.type), [
        'add_expense',
        'add_income',
        'favorite:$id',
      ]);
      expect(env.shortcuts.items.last.title, 'Add Coffee');
      await disposeEnv(tester, env);
    });

    testWidgets('the favorite shortcut follows the favorites', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env);
      expect(env.shortcuts.items, hasLength(2));

      final a = await addFavorite(tester, env, label: 'Coffee');
      final b = await addFavorite(
        tester,
        env,
        label: 'Bus',
        category: 'Transport',
      );
      await settle(tester);
      expect(env.shortcuts.items.last.type, 'favorite:$a');

      await tester.runAsync(() => FavoriteRepository(env.db).reorder([b, a]));
      await settle(tester);
      expect(env.shortcuts.items.last.type, 'favorite:$b');
      expect(env.shortcuts.items.last.title, 'Add Bus');

      await tester.runAsync(() => FavoriteRepository(env.db).delete(a));
      await settle(tester);
      expect(env.shortcuts.items.last.type, 'favorite:$b');
      await tester.runAsync(() => FavoriteRepository(env.db).delete(b));
      await settle(tester);
      expect(env.shortcuts.items, hasLength(2));
      await disposeEnv(tester, env);
    });
  });

  group('choosing a shortcut', () {
    testWidgets('Add expense opens the Add sheet on Expense', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'add_expense');

      expect(find.text('Add transaction'), findsOneWidget);
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      expect(find.byKey(ValueKey('category-$food')), findsOneWidget);
      final salary = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      expect(find.byKey(ValueKey('category-$salary')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('Add income opens it on Income, and saving makes income', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'add_income');

      final salary = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      expect(find.byKey(ValueKey('category-$salary')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('amount-field')), '50');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      final txs = (await tester.runAsync(
        () => env.db.select(env.db.transactions).get(),
      ))!;
      expect(txs.single.type, TransactionType.income);
      expect(txs.single.amountCents, 5000);
      await disposeEnv(tester, env);
    });

    testWidgets('the amount field is focused, ready to type', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'add_expense');
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('amount-field')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await disposeEnv(tester, env);
    });

    testWidgets('it works from any tab', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await settle(tester);
      await choose(tester, env, 'add_expense');
      expect(find.text('Add transaction'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a favorite shortcut opens the sheet filled in and logs nothing',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addFavorite(tester, env, cents: 450);
        await start(tester, env);
        await choose(tester, env, 'favorite:$id');

        expect(find.text('Add transaction'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('amount-field')))
              .controller!
              .text,
          '4.50',
        );
        expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('note-field')))
              .controller!
              .text,
          'Flat white',
        );
        final txs = (await tester.runAsync(
          () => env.db.select(env.db.transactions).get(),
        ))!;
        expect(txs, isEmpty);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a favorite that was deleted still opens a plain Add sheet', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'favorite:999');
      expect(find.text('Add transaction'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('amount-field')))
            .controller!
            .text,
        '',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a shortcut this version does not know does nothing', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'something_new');
      expect(find.text('Add transaction'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('it acts once: closing the sheet does not reopen it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await choose(tester, env, 'add_expense');
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.text('Add transaction'), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('choosing one while an Add sheet is open leaves it alone', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        '12.34',
      );

      await choose(tester, env, 'add_income');
      expect(
        find.text('Add transaction'),
        findsOneWidget,
        reason: 'still just one',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('amount-field')))
            .controller!
            .text,
        '12.34',
        reason: 'what was typed is kept',
      );
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(
        find.text('Add transaction'),
        findsNothing,
        reason: 'the ignored one is gone',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('after a sheet closes, a shortcut works again', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(
        ProviderScope.containerOf(tester.element(find.byType(AppShell)))
            .read(addSheetCountProvider),
        0,
      );
      await choose(tester, env, 'add_expense');
      expect(find.text('Add transaction'), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('during the welcome tour', () {
    testWidgets('a shortcut waits for the tour, then opens', (tester) async {
      final env = await createEnv(tester, prefs: {'onboarding_done': false});
      await start(tester, env);
      expect(find.byKey(const ValueKey('welcome-skip')), findsOneWidget);

      await choose(tester, env, 'add_income');
      expect(find.text('Add transaction'), findsNothing, reason: 'tour first');

      await tester.tap(find.byKey(const ValueKey('welcome-skip')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Add transaction'), findsOneWidget);
      final salary = await categoryId(
        tester,
        env,
        'Salary',
        TransactionType.income,
      );
      expect(find.byKey(ValueKey('category-$salary')), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  testWidgets('the sheet count is back to zero when the app has nothing open', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await start(tester, env);
    await openFormViaKey(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(addSheetCountProvider), 0);
    await disposeEnv(tester, env);
  });

  group('the favorite launcher shortcut can be switched off', () {
    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));

    testWidgets('off drops it from the launcher, on brings it back', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addFavorite(tester, env);
      await start(tester, env);
      expect(env.shortcuts.items, hasLength(3));

      await containerOf(tester)
          .read(settingsProvider.notifier)
          .setFavoriteShortcut(false);
      await settle(tester);
      expect(env.shortcuts.items.map((s) => s.type), [
        'add_expense',
        'add_income',
      ]);
      expect(
        env.shortcuts.items.any((s) => s.title.contains('Coffee')),
        isFalse,
        reason: 'the name is no longer on the launcher',
      );

      await containerOf(tester)
          .read(settingsProvider.notifier)
          .setFavoriteShortcut(true);
      await settle(tester);
      expect(env.shortcuts.items.last.title, 'Add Coffee');
      await disposeEnv(tester, env);
    });

    testWidgets('the Quick add page has the switch, on by default', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addFavorite(tester, env);
      await start(tester, env);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Settings'),
        ),
      );
      await settle(tester);
      final manage = find.byKey(const ValueKey('manage-favorites'));
      await tester.ensureVisible(manage);
      await tester.pump();
      await tester.tap(manage);
      await settle(tester);

      final tile = find.byKey(const ValueKey('favorite-shortcut'));
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.tap(tile);
      await settle(tester);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(env.prefs.getBool('favorite_shortcut'), isFalse);
      expect(env.shortcuts.items, hasLength(2));
      await disposeEnv(tester, env);
    });
  });
}

Future<void> openFormViaKey(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add transaction'));
  await settle(tester);
}
