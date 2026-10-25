import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/money_parser.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

import 'test_helpers.dart';

final _amountField = find.byKey(const ValueKey('amount-field'));
final _noteField = find.byKey(const ValueKey('note-field'));
final _saveButton = find.byKey(const ValueKey('save-button'));

Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(_saveButton);
  await tester.tap(_saveButton);
  await settle(tester);
}

void main() {
  testWidgets('the form opens as a bottom sheet over the page', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Add transaction'), findsOneWidget);
    // The page underneath is still there, not replaced by a new screen.
    expect(find.text('open', skipOffstage: false), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('the Close button dismisses the sheet without saving', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.enterText(_amountField, '12');
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    expect(find.byType(BottomSheet), findsNothing);
    expect(await savedTransactions(tester, env), isEmpty);
    await disposeEnv(tester, env);
  });

  testWidgets('the sheet moves up with the keyboard', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);
    final before = tester
        .getBottomLeft(find.byKey(const ValueKey('save-button')))
        .dy;

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final after = tester
        .getBottomLeft(find.byKey(const ValueKey('save-button')))
        .dy;
    expect(after, lessThan(before), reason: 'save stays above the keyboard');
    expect(after, lessThanOrEqualTo(1800 - 600));
    await disposeEnv(tester, env);
  });

  testWidgets('successful add saves the transaction and closes the form', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    await tester.enterText(_amount(), '12,50');
    await tester.enterText(_noteField, '  lunch  ');
    await tester.tap(find.byKey(ValueKey('category-$food')));
    await tester.pump();
    await tapSave(tester);

    final saved = await savedTransactions(tester, env);
    expect(saved, hasLength(1));
    final tx = saved.single.transaction;
    expect(tx.amountCents, 1250);
    expect(tx.type, TransactionType.expense);
    expect(tx.date, '2026-10-15', reason: 'defaults to today');
    expect(tx.note, 'lunch');
    expect(saved.single.category.name, 'Food');
    expect(find.text('Add transaction'), findsNothing, reason: 'form closed');

    await disposeEnv(tester, env);
  });

  group('validation errors', () {
    final cases = {
      'empty amount': ('', errorEmptyAmount),
      'zero amount': ('0', errorNotPositive),
      'letters are filtered out of the field': ('abc', errorEmptyAmount),
      'two decimal points': ('1.2.3', errorInvalidAmount),
      'three decimals': ('1.234', errorTooManyDecimals),
      'too large': ('1000000000', errorTooLarge),
    };
    cases.forEach((name, c) {
      testWidgets(name, (tester) async {
        final env = await createEnv(tester);
        await openForm(tester, env);

        await tester.enterText(_amount(), c.$1);
        await tapSave(tester);

        expect(find.text(c.$2), findsOneWidget);
        expect(await savedTransactions(tester, env), isEmpty);
        expect(
          find.text('Add transaction'),
          findsOneWidget,
          reason: 'form stays open',
        );
        await disposeEnv(tester, env);
      });
    });
  });

  testWidgets('a long note is capped at 200 characters', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.enterText(_noteField, 'x' * 250);
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(of: _noteField, matching: find.byType(TextField)),
    );
    expect(field.controller!.text.length, 200);
    await disposeEnv(tester, env);
  });

  testWidgets('the amount and note are saved with the chosen type and date', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.tap(find.text('Income'));
    await tester.pump();
    await tester.enterText(_amount(), '100');

    // Pick a date: open the picker, choose the 20th.
    await tester.tap(find.byKey(const ValueKey('date-tile')));
    await settle(tester);
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    await tapSave(tester);

    final tx = (await savedTransactions(tester, env)).single.transaction;
    expect(tx.type, TransactionType.income);
    expect(tx.date, '2026-10-20', reason: 'future dates are allowed');
    await disposeEnv(tester, env);
  });

  testWidgets('edit prefills the form and saves the changes', (tester) async {
    final env = await createEnv(tester);
    final id = await addExpense(
      tester,
      env,
      4550,
      DateTime(2026, 10, 3),
      category: 'Rent',
      note: 'october',
    );
    await openForm(tester, env, editId: id);

    expect(find.text('Edit transaction'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: _amount(), matching: find.byType(TextField)),
          )
          .controller!
          .text,
      '45.50',
    );
    expect(find.text('october'), findsOneWidget);
    expect(find.text('Oct 3, 2026'), findsOneWidget);
    final rent = await categoryId(tester, env, 'Rent', TransactionType.expense);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(ValueKey('category-$rent')))
          .selected,
      isTrue,
    );

    await tester.enterText(_amount(), '50');
    await tapSave(tester);

    final saved = await savedTransactions(tester, env);
    expect(saved, hasLength(1), reason: 'updated, not duplicated');
    expect(saved.single.transaction.id, id);
    expect(saved.single.transaction.amountCents, 5000);
    expect(saved.single.transaction.note, 'october');
    await disposeEnv(tester, env);
  });

  testWidgets('changing type resets the category to one of the new type', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    final food = await categoryId(tester, env, 'Food', TransactionType.expense);
    await tester.tap(find.byKey(ValueKey('category-$food')));
    await tester.pump();
    expect(find.text('Food'), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pump();
    await settle(tester);

    expect(find.text('Food'), findsNothing, reason: 'expense categories gone');
    expect(find.text('Salary'), findsOneWidget);
    // "Other" is preselected when nothing was used before for income.
    final other = await categoryId(
      tester,
      env,
      'Other',
      TransactionType.income,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(ValueKey('category-$other')))
          .selected,
      isTrue,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('preselects "Other", then the last used category per type', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

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

    final rent = await categoryId(tester, env, 'Rent', TransactionType.expense);
    await tester.enterText(_amount(), '5');
    await tester.tap(find.byKey(ValueKey('category-$rent')));
    await tester.pump();
    await tapSave(tester);

    // Open a fresh form: Rent is remembered for expenses.
    await openForm(tester, env);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(ValueKey('category-$rent')))
          .selected,
      isTrue,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('new category: created, selected and usable', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.tap(find.byKey(const ValueKey('new-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      '  Coffee ',
    );
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('Coffee'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Coffee'),
    );
    expect(chip.selected, isTrue, reason: 'auto-selected');

    await tester.enterText(_amount(), '3');
    await tapSave(tester);
    expect(
      (await savedTransactions(tester, env)).single.category.name,
      'Coffee',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('duplicate category shows an error (case-insensitive)', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.tap(find.byKey(const ValueKey('new-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'food',
    );
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('A category named "food" already exists'), findsOneWidget);
    expect(find.text('New category'), findsOneWidget, reason: 'dialog stays');
    await disposeEnv(tester, env);
  });

  testWidgets('an archived name offers Restore', (tester) async {
    final env = await createEnv(tester);
    final rent = await categoryId(tester, env, 'Rent', TransactionType.expense);
    await tester.runAsync(() => env.cats.archive(rent));
    await openForm(tester, env);

    await tester.tap(find.byKey(const ValueKey('new-category')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'rent',
    );
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('"Rent" is archived'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await settle(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(ValueKey('category-$rent')))
          .selected,
      isTrue,
      reason: 'restored and selected',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('an empty category name is rejected', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);

    await tester.tap(find.byKey(const ValueKey('new-category')));
    await settle(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Enter a name'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('delete from edit mode asks first, then removes it', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final id = await addExpense(tester, env, 999, DateTime(2026, 10, 3));
    await openForm(tester, env, editId: id);

    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(find.text('Delete transaction?'), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await savedTransactions(tester, env), hasLength(1));

    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(await savedTransactions(tester, env), isEmpty);
    expect(find.text('Edit transaction'), findsNothing, reason: 'form closed');
    await disposeEnv(tester, env);
  });

  testWidgets('add mode has no delete action', (tester) async {
    final env = await createEnv(tester);
    await openForm(tester, env);
    expect(find.byTooltip('Delete'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets(
    'editing a transaction with an archived category still shows it',
    (tester) async {
      final env = await createEnv(tester);
      final id = await addExpense(
        tester,
        env,
        500,
        DateTime(2026, 10, 3),
        category: 'Travel',
      );
      final travel = await categoryId(
        tester,
        env,
        'Travel',
        TransactionType.expense,
      );
      await tester.runAsync(() => env.cats.archive(travel));
      await openForm(tester, env, editId: id);

      expect(find.text('Travel (archived)'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(ValueKey('category-$travel')))
            .selected,
        isTrue,
      );
      await disposeEnv(tester, env);
    },
  );

  testWidgets('archived categories are hidden from a new transaction', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final travel = await categoryId(
      tester,
      env,
      'Travel',
      TransactionType.expense,
    );
    await tester.runAsync(() => env.cats.archive(travel));
    await openForm(tester, env);

    expect(find.text('Travel'), findsNothing);
    expect(find.text('Food'), findsOneWidget);
    await disposeEnv(tester, env);
  });
}

Finder _amount() => _amountField;
