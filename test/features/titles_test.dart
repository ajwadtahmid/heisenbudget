import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

Future<int> addTitled(
  WidgetTester tester,
  TestEnv env, {
  String? title,
  String? note,
  String category = 'Food',
  int cents = 2500,
  DateTime? date,
}) async {
  final id = await categoryId(tester, env, category, TransactionType.expense);
  return (await tester.runAsync(
    () => env.txs.add(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.expense,
        date: date ?? d(2026, 10, 15),
        categoryId: id,
        title: title,
        note: note,
      ),
    ),
  ))!;
}

Future<List<TransactionRow>> allTx(WidgetTester tester, TestEnv env) async {
  return (await tester.runAsync(
    () => (env.db.select(
      env.db.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get(),
  ))!;
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  group('how a row reads', () {
    testWidgets('with a title: "In & Out · Food" over the date', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addTitled(tester, env, title: 'In & Out');
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      final row = find.byKey(ValueKey('recent-$id'));
      expect(
        find.descendant(of: row, matching: find.text('In & Out · Food')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Oct 15, 2026')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Food')),
        findsNothing,
        reason: 'the category is inside the title line',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('without a title: just "Food" over the date', (tester) async {
      final env = await createEnv(tester);
      final id = await addTitled(tester, env);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      final row = find.byKey(ValueKey('recent-$id'));
      expect(
        find.descendant(of: row, matching: find.text('Food')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Oct 15, 2026')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('·')),
        findsNothing,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a note still follows the date on Home', (tester) async {
      final env = await createEnv(tester);
      await addTitled(tester, env, title: 'In & Out', note: 'Burger');
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('Oct 15, 2026 · Burger'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('History shows the title line, with the note under it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addTitled(tester, env, title: 'In & Out', note: 'Burger');
      await addTitled(tester, env, cents: 100, category: 'Rent');
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      expect(find.text('In & Out · Food'), findsOneWidget);
      expect(find.text('Burger'), findsOneWidget);
      expect(find.text('Rent'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an archived category is still marked', (tester) async {
      final env = await createEnv(tester);
      await addTitled(tester, env, title: 'In & Out');
      final food = await categoryId(
        tester,
        env,
        'Food',
        TransactionType.expense,
      );
      await tester.runAsync(() => CategoryRepository(env.db).archive(food));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('In & Out · Food (archived)'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('a very long title is cut with an ellipsis at 200% text', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addTitled(tester, env, title: 'x' * maxTitleLength);
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await goToTab(tester, 'History');
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });

  group('the Title field in the Add sheet', () {
    testWidgets('is optional and sits under the amount', (tester) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      expect(find.byKey(const ValueKey('title-field')), findsOneWidget);
      final amount = tester
          .getTopLeft(find.byKey(const ValueKey('amount-field')))
          .dy;
      final title = tester
          .getTopLeft(find.byKey(const ValueKey('title-field')))
          .dy;
      final note = tester
          .getTopLeft(find.byKey(const ValueKey('note-field')))
          .dy;
      expect(title, greaterThan(amount));
      expect(note, greaterThan(title));

      await tester.enterText(find.byKey(const ValueKey('amount-field')), '25');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      expect((await allTx(tester, env)).single.title, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('saves what you type, and the category still shows', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      await tester.enterText(find.byKey(const ValueKey('amount-field')), '25');
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'In & Out',
      );
      await tester.enterText(
        find.byKey(const ValueKey('note-field')),
        'Burger',
      );
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      final row = (await allTx(tester, env)).single;
      expect((row.title, row.note), ('In & Out', 'Burger'));
      await disposeEnv(tester, env);
    });

    testWidgets('stops at the length limit', (tester) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'x' * 100,
      );
      expect(fieldText(tester, 'title-field').length, maxTitleLength);
      await disposeEnv(tester, env);
    });

    testWidgets('editing shows it, and clearing it removes it', (tester) async {
      final env = await createEnv(tester);
      final id = await addTitled(tester, env, title: 'In & Out');
      await openForm(tester, env, editId: id);
      expect(fieldText(tester, 'title-field'), 'In & Out');
      await tester.enterText(find.byKey(const ValueKey('title-field')), '');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      expect((await allTx(tester, env)).single.title, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('Duplicate keeps the title', (tester) async {
      final env = await createEnv(tester);
      final id = await addTitled(tester, env, title: 'In & Out');
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await tester.longPress(find.byKey(ValueKey('tx-$id')));
      await settle(tester);
      expect(
        find.text('In & Out  -\$25.00'),
        findsOneWidget,
        reason: 'menu header',
      );
      await tester.tap(find.byKey(const ValueKey('menu-duplicate')));
      await settle(tester);
      expect(fieldText(tester, 'title-field'), 'In & Out');
      await disposeEnv(tester, env);
    });

    testWidgets('a repeating transaction passes its title on', (tester) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        '1200',
      );
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Landlord',
      );
      await tester.tap(find.byKey(const ValueKey('repeat-tile')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-monthly')));
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      final rule = (await tester.runAsync(
        () => env.db.select(env.db.recurringRules).getSingle(),
      ))!;
      expect(rule.title, 'Landlord');
      await disposeEnv(tester, env);
    });
  });

  group('search and favorites', () {
    testWidgets('search finds a title and highlights it', (tester) async {
      final env = await createEnv(tester);
      await addTitled(tester, env, title: 'In & Out');
      await addTitled(tester, env, title: 'Five Guys', cents: 100);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await tester.tap(find.byKey(const ValueKey('search-button')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'five',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(find.byKey(const ValueKey('search-summary')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('search-summary'))).data,
        '1 result · net -\$1.00',
      );
      final marked = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((r) {
            final spans = <TextSpan>[];
            r.text.visitChildren((s) {
              if (s is TextSpan) spans.add(s);
              return true;
            });
            return spans;
          })
          .where(
            (s) => s.style?.fontWeight == FontWeight.w700 && s.text == 'Five',
          );
      expect(marked, isNotEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('Save as favorite starts from the title and keeps it', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addTitled(
        tester,
        env,
        title: 'In & Out',
        note: 'Burger',
      );
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'History');
      await tester.longPress(find.byKey(ValueKey('tx-$id')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('menu-favorite')));
      await settle(tester);
      expect(fieldText(tester, 'favorite-label'), 'In & Out');
      expect(fieldText(tester, 'favorite-title'), 'In & Out');
      await tester.ensureVisible(find.byKey(const ValueKey('favorite-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('favorite-save')));
      await settle(tester);
      final fav = (await tester.runAsync(
        () => env.db.select(env.db.favorites).getSingle(),
      ))!;
      expect((fav.label, fav.title), ('In & Out', 'In & Out'));
      await disposeEnv(tester, env);
    });
  });

  group('repeating rules', () {
    Future<int> addRule(
      WidgetTester tester,
      TestEnv env, {
      String? title,
    }) async {
      final cat = await categoryId(
        tester,
        env,
        'Rent',
        TransactionType.expense,
      );
      await tester.runAsync(
        () => RecurringRepository(env.db).addWithRule(
          TransactionInput(
            amountCents: 120000,
            type: TransactionType.expense,
            date: d(2026, 9, 18),
            categoryId: cat,
            title: title,
          ),
          RecurringInput(
            amountCents: 120000,
            type: TransactionType.expense,
            categoryId: cat,
            title: title,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 9, 18),
          ),
        ),
      );
      return (await tester.runAsync(
        () => env.db.select(env.db.recurringRules).getSingle(),
      ))!.id;
    }

    testWidgets('Coming up and the list name a rule by its title', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addRule(tester, env, title: 'Landlord');
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('Landlord'), findsOneWidget, reason: 'Coming up');
      await goToTab(tester, 'Settings');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('manage-recurring')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('manage-recurring')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('manage-recurring')));
      await settle(tester);
      expect(find.text('Landlord'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the rule editor edits the title', (tester) async {
      final env = await createEnv(tester);
      final id = await addRule(tester, env, title: 'Landlord');
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('manage-recurring')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('manage-recurring')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('manage-recurring')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);
      expect(fieldText(tester, 'rule-title'), 'Landlord');
      await tester.enterText(
        find.byKey(const ValueKey('rule-title')),
        'New flat',
      );
      final save = find.byKey(const ValueKey('rule-save'));
      await tester.ensureVisible(save);
      await tester.pump();
      await tester.tap(save);
      await settle(tester);
      final rule = (await tester.runAsync(
        () => env.db.select(env.db.recurringRules).getSingle(),
      ))!;
      expect(rule.title, 'New flat');
      await disposeEnv(tester, env);
    });
  });
}
