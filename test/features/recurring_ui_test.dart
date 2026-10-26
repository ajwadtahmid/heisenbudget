import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:heisenbudget/features/transaction_form/repeat_sheet.dart';

import 'test_helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// Creates "Flat" rent that repeats monthly from [start], plus its first
/// transaction. Returns the rule id.
Future<int> addRentRule(
  WidgetTester tester,
  TestEnv env,
  DateTime start, {
  int cents = 120000,
  DateTime? end,
  bool active = true,
}) async {
  final cat = await categoryId(tester, env, 'Rent', TransactionType.expense);
  final rules = RecurringRepository(env.db);
  await tester.runAsync(
    () => rules.addWithRule(
      TransactionInput(
        amountCents: cents,
        type: TransactionType.expense,
        date: start,
        categoryId: cat,
        note: 'Flat',
      ),
      RecurringInput(
        amountCents: cents,
        type: TransactionType.expense,
        categoryId: cat,
        note: 'Flat',
        unit: RecurrenceUnit.month,
        interval: 1,
        start: start,
        end: end,
      ),
    ),
  );
  final rule = (await tester.runAsync(
    () => env.db.select(env.db.recurringRules).get(),
  ))!.first;
  if (!active) {
    await tester.runAsync(() => rules.setActive(rule.id, false));
  }
  return rule.id;
}

Future<List<TransactionRow>> allTx(WidgetTester tester, TestEnv env) async {
  return (await tester.runAsync(
    () =>
        (env.db.select(env.db.transactions)..orderBy([
              (t) => OrderingTerm.asc(t.date),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get(),
  ))!;
}

Future<List<RecurringRuleRow>> allRules(
  WidgetTester tester,
  TestEnv env,
) async {
  return (await tester.runAsync(
    () => env.db.select(env.db.recurringRules).get(),
  ))!;
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settle(tester);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> openRecurringList(WidgetTester tester) async {
  await goToTab(tester, 'Settings');
  await tapKey(tester, 'manage-recurring');
}

void main() {
  group('the Repeat row in the Add sheet', () {
    testWidgets('starts as "Does not repeat" and saves a plain transaction', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      expect(find.byKey(const ValueKey('repeat-tile')), findsOneWidget);
      expect(find.text('Does not repeat'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('amount-field')), '10');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);

      expect(await allRules(tester, env), isEmpty);
      expect((await allTx(tester, env)).single.recurringRuleId, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('choosing Monthly saves a rule and links the transaction', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      await tester.enterText(
        find.byKey(const ValueKey('amount-field')),
        '1200',
      );
      await tester.enterText(find.byKey(const ValueKey('note-field')), 'Flat');

      await tester.tap(find.byKey(const ValueKey('repeat-tile')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-monthly')));
      await tester.pump();
      expect(find.text('Monthly on the 15th'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(
        find.text('Monthly on the 15th'),
        findsOneWidget,
        reason: 'shown on the row',
      );

      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);

      final rules = await allRules(tester, env);
      expect(rules, hasLength(1));
      expect(
        (rules.single.unit, rules.single.interval),
        (RecurrenceUnit.month, 1),
      );
      expect(rules.single.startDate, '2026-10-15');
      expect(rules.single.nextIndex, 1);
      final tx = (await allTx(tester, env)).single;
      expect(tx.recurringRuleId, rules.single.id);
      expect(tx.amountCents, 120000);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a start date in the past warns how many earlier ones it adds',
      (tester) async {
        final env = await createEnv(tester);
        await tester.pumpWidget(wholeApp(env));
        await settle(tester);
        await tester.tap(find.byTooltip('Add transaction'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('date-tile')));
        await settle(tester);
        await tester.tap(find.text('1').first); // Oct 1
        await tester.tap(find.text('OK'));
        await settle(tester);

        await tester.tap(find.byKey(const ValueKey('repeat-tile')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('repeat-weekly')));
        await tester.tap(find.byKey(const ValueKey('repeat-done')));
        await settle(tester);

        // Oct 1 weekly: the 8th and the 15th are earlier ones up to Oct 15.
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('repeat-note'))).data,
          'Also adds 2 earlier transactions up to today.',
        );

        await tester.enterText(find.byKey(const ValueKey('amount-field')), '5');
        await tester.tap(find.byKey(const ValueKey('save-button')));
        await settle(tester);
        expect((await allTx(tester, env)).map((t) => t.date), [
          '2026-10-01',
          '2026-10-08',
          '2026-10-15',
        ]);
        expect(find.text('Added 2 recurring transactions.'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('refuses a repeat that would add more than 500 earlier ones', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openForm(tester, env);
      await tester.tap(find.byKey(const ValueKey('date-tile')));
      await settle(tester);
      // Go back a few years by typing the year: switch to the year picker.
      await tester.tap(find.text('October 2026'));
      await tester.pump();
      await tester.tap(find.text('2020'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('repeat-tile')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-custom')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('repeat-interval')),
        '1',
      );
      await tester.tap(find.byKey(const ValueKey('repeat-unit-day')));
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('repeat-note'))).data,
        contains('more than 500'),
      );
      await tester.enterText(find.byKey(const ValueKey('amount-field')), '5');
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);
      expect(await allTx(tester, env), isEmpty, reason: 'nothing saved');
      await disposeEnv(tester, env);
    });

    testWidgets('an existing transaction can be made to repeat', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addExpense(tester, env, 4500, d(2026, 10, 10));
      await openForm(tester, env, editId: id);
      await tester.tap(find.byKey(const ValueKey('repeat-tile')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-yearly')));
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('save-button')));
      await settle(tester);

      final rule = (await allRules(tester, env)).single;
      expect(rule.unit, RecurrenceUnit.year);
      expect(rule.startDate, '2026-10-10');
      expect((await allTx(tester, env)).single.recurringRuleId, rule.id);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'a transaction made by a rule shows the rule, not the Repeat row',
      (tester) async {
        final env = await createEnv(tester);
        await addRentRule(tester, env, d(2026, 10, 1));
        final tx = (await allTx(tester, env)).single;
        await openForm(tester, env, editId: tx.id);

        expect(find.byKey(const ValueKey('repeat-tile')), findsNothing);
        expect(find.text('Part of a repeating rule'), findsOneWidget);
        expect(find.text('Monthly on the 1st'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('edit-rule')));
        await settle(tester);
        expect(find.text('Repeating transaction'), findsOneWidget);
        expect(find.byKey(const ValueKey('rule-amount')), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );
  });

  group('the Repeat sheet', () {
    Future<RepeatResult?> openSheet(
      WidgetTester tester,
      TestEnv env, {
      RepeatChoice? current,
      bool allowNone = true,
      void Function(RepeatResult?)? onResult,
    }) async {
      await tester.pumpWidget(
        wrap(
          env,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    final r = await showRepeatSheet(
                      context,
                      start: d(2026, 10, 15),
                      current: current,
                      allowNone: allowNone,
                    );
                    onResult?.call(r);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      return null;
    }

    testWidgets('presets return the matching choice', (tester) async {
      final env = await createEnv(tester);
      RepeatResult? result;
      await openSheet(tester, env, onResult: (r) => result = r);
      await tester.tap(find.byKey(const ValueKey('repeat-weekly')));
      await tester.pump();
      expect(find.text('Weekly on Thursday'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(
        result!.choice,
        const RepeatChoice(unit: RecurrenceUnit.week, interval: 1),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('custom checks the number and takes a unit', (tester) async {
      final env = await createEnv(tester);
      RepeatResult? result;
      await openSheet(tester, env, onResult: (r) => result = r);
      await tester.tap(find.byKey(const ValueKey('repeat-custom')));
      await tester.pump();

      for (final bad in ['', '0', '366']) {
        await tester.enterText(
          find.byKey(const ValueKey('repeat-interval')),
          bad,
        );
        await tester.pump();
        expect(find.text('1 to 365'), findsOneWidget, reason: '"$bad"');
        expect(
          tester
              .widget<FilledButton>(find.byKey(const ValueKey('repeat-done')))
              .onPressed,
          isNull,
        );
      }
      await tester.enterText(
        find.byKey(const ValueKey('repeat-interval')),
        '3',
      );
      await tester.tap(find.byKey(const ValueKey('repeat-unit-week')));
      await tester.pump();
      expect(find.text('Every 3 weeks on Thursday'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(
        result!.choice,
        const RepeatChoice(unit: RecurrenceUnit.week, interval: 3),
      );
      await disposeEnv(tester, env);
    });

    testWidgets('"Does not repeat" returns no choice', (tester) async {
      final env = await createEnv(tester);
      RepeatResult? result;
      await openSheet(
        tester,
        env,
        current: const RepeatChoice(unit: RecurrenceUnit.month, interval: 1),
        onResult: (r) => result = r,
      );
      await tester.tap(find.byKey(const ValueKey('repeat-none')));
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(result, isNotNull);
      expect(result!.choice, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('closing the sheet without Done returns nothing', (
      tester,
    ) async {
      final env = await createEnv(tester);
      var called = false;
      RepeatResult? result;
      await openSheet(
        tester,
        env,
        onResult: (r) {
          called = true;
          result = r;
        },
      );
      await tester.tapAt(const Offset(20, 20)); // the scrim
      await settle(tester);
      expect(called, isTrue);
      expect(result, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('an existing end date shows and can be cleared', (
      tester,
    ) async {
      final env = await createEnv(tester);
      RepeatResult? result;
      await openSheet(
        tester,
        env,
        current: RepeatChoice(
          unit: RecurrenceUnit.month,
          interval: 1,
          end: d(2027, 1, 1),
        ),
        onResult: (r) => result = r,
      );
      expect(find.text('Jan 1, 2027'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-end-clear')));
      await tester.pump();
      expect(find.text('Never'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      expect(result!.choice!.end, isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('without "none" (editing a rule) it is not offered', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await openSheet(tester, env, allowNone: false);
      expect(find.byKey(const ValueKey('repeat-none')), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('catching up when the app opens', () {
    testWidgets('adds what came due and offers Undo', (tester) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 8, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      expect((await allTx(tester, env)).map((t) => t.date), [
        '2026-08-01',
        '2026-09-01',
        '2026-10-01',
      ]);
      expect(find.text('Added 2 recurring transactions.'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect((await allTx(tester, env)).map((t) => t.date), ['2026-08-01']);
      await disposeEnv(tester, env);
    });

    testWidgets('says nothing when nothing is due', (tester) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.byType(SnackBar), findsNothing);
      expect(await allTx(tester, env), hasLength(1));
      await disposeEnv(tester, env);
    });

    testWidgets('a new day brings the next one', (tester) async {
      final env = await createEnv(tester, now: d(2026, 10, 31));
      await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(await allTx(tester, env), hasLength(1));

      env.now = d(2026, 11, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect((await allTx(tester, env)).map((t) => t.date), [
        '2026-10-01',
        '2026-11-01',
      ]);
      await disposeEnv(tester, env);
    });

    testWidgets('a paused rule adds nothing', (tester) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 8, 1), active: false);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(await allTx(tester, env), hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('History shows the repeat mark on made transactions', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 10, 1));
      await addExpense(tester, env, 500, d(2026, 10, 2), note: 'Snack');
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await goToTab(tester, 'History');

      final marks = find.descendant(
        of: find.byKey(ValueKey('tx-${(await allTx(tester, env)).first.id}')),
        matching: find.byIcon(Icons.repeat),
      );
      expect(marks, findsOneWidget);
      expect(
        find.byIcon(Icons.repeat),
        findsOneWidget,
        reason: 'only the rent',
      );
      await disposeEnv(tester, env);
    });
  });

  group('Settings > Repeating transactions', () {
    testWidgets('the Settings row counts the rules', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await goToTab(tester, 'Settings');
      expect(find.text('Rent, salary, subscriptions'), findsOneWidget);
      await addRentRule(tester, env, d(2026, 10, 1));
      await settle(tester);
      expect(find.text('1 repeating transaction'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an empty list explains how to start one', (tester) async {
      final env = await createEnv(tester);
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      expect(find.textContaining('Nothing repeats yet.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets(
      'lists rules with schedule, next date and amount; the switch pauses',
      (tester) async {
        final env = await createEnv(tester);
        final id = await addRentRule(tester, env, d(2026, 10, 1));
        await tester.pumpWidget(wholeApp(env));
        await openRecurringList(tester);

        expect(find.text('Flat'), findsOneWidget);
        expect(find.textContaining('Monthly on the 1st'), findsOneWidget);
        expect(find.textContaining('Next Nov 1, 2026'), findsOneWidget);
        expect(find.textContaining('-\$1,200.00'), findsOneWidget);

        await tester.tap(find.byKey(ValueKey('rule-switch-$id')));
        await settle(tester);
        expect((await allRules(tester, env)).single.isActive, isFalse);
        expect(find.textContaining('Paused'), findsOneWidget);
        await disposeEnv(tester, env);
      },
    );

    testWidgets('a rule past its end date is shown as ended', (tester) async {
      final env = await createEnv(tester, now: d(2026, 12, 20));
      await addRentRule(tester, env, d(2026, 10, 1), end: d(2026, 11, 15));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await openRecurringList(tester);
      expect(find.textContaining('Ended'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('editing the amount only affects what is added next', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);

      await tester.enterText(find.byKey(const ValueKey('rule-amount')), '1300');
      await tapKey(tester, 'rule-save');

      final rule = (await allRules(tester, env)).single;
      expect(rule.amountCents, 130000);
      expect(rule.nextIndex, 1, reason: 'schedule is untouched');
      expect((await allTx(tester, env)).single.amountCents, 120000);
      await disposeEnv(tester, env);
    });

    testWidgets('an empty or invalid amount is not saved', (tester) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('rule-amount')), '');
      await tapKey(tester, 'rule-save');
      expect(find.text('Enter an amount'), findsOneWidget);
      expect((await allRules(tester, env)).single.amountCents, 120000);
      await disposeEnv(tester, env);
    });

    testWidgets('Skip next and Add now move the schedule', (tester) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);

      await tapKey(tester, 'rule-skip'); // skips Nov 1
      expect(find.text('Skipped Nov 1, 2026.'), findsOneWidget);
      expect((await allRules(tester, env)).single.nextIndex, 2);
      expect(find.text('Dec 1, 2026'), findsOneWidget);

      await tapKey(tester, 'rule-add-now');
      final txs = await allTx(tester, env);
      expect(txs.map((t) => t.date), ['2026-10-01', '2026-10-15']);
      expect((await allRules(tester, env)).single.nextIndex, 3);
      await disposeEnv(tester, env);
    });

    testWidgets('delete keeps past transactions and removes the rule', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);

      await tapKey(tester, 'rule-delete');
      expect(
        find.textContaining('already added stay in History'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('rule-delete-confirm')));
      await settle(tester);

      expect(await allRules(tester, env), isEmpty);
      final txs = await allTx(tester, env);
      expect(txs, hasLength(1));
      expect(txs.single.recurringRuleId, isNull);
      expect(find.textContaining('Nothing repeats yet.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('an end date can be set from the editor and is saved', (
      tester,
    ) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 10, 1));
      await tester.pumpWidget(wholeApp(env));
      await openRecurringList(tester);
      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('rule-repeat')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-end')));
      await settle(tester);
      // The picker opens a year ahead; pick the first of the month shown.
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-done')));
      await settle(tester);
      // An end date a year ahead is fine: saving works.
      await tapKey(tester, 'rule-save');
      expect((await allRules(tester, env)).single.endDate, isNotNull);
      await disposeEnv(tester, env);
    });
  });

  group('Home: Coming up', () {
    testWidgets('lists rules due in the next 7 days, soonest first', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 9, 18)); // next: Oct 18, in 3 days
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);

      expect(find.text('COMING UP'), findsOneWidget);
      expect(find.text('Flat'), findsWidgets);
      expect(find.text('Oct 18, 2026 · in 3 days'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('says "tomorrow" for the next day', (tester) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 9, 16));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('Oct 16, 2026 · tomorrow'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('is hidden when nothing is due soon, or the rule is paused', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 10, 1)); // next Nov 1: too far
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(find.text('COMING UP'), findsNothing);
      await disposeEnv(tester, env);

      final env2 = await createEnv(tester);
      await addRentRule(tester, env2, d(2026, 9, 18), active: false);
      await tester.pumpWidget(wholeApp(env2));
      await settle(tester);
      expect(find.text('COMING UP'), findsNothing);
      await disposeEnv(tester, env2);
    });

    testWidgets('does not change the balance or the period totals', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 9, 18));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      // Only the September transaction exists; October has nothing yet.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('balance'))).data,
        '-\$1,200.00',
      );
      await disposeEnv(tester, env);
    });

    testWidgets('tapping a row opens the rule', (tester) async {
      final env = await createEnv(tester);
      await addRentRule(tester, env, d(2026, 9, 18));
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('coming-up-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('rule-amount')), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    Future<void> smallScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the Repeat sheet fits at 200% text', (tester) async {
      final env = await createEnv(tester);
      await smallScreen(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      await tester.tap(find.byTooltip('Add transaction'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('repeat-tile')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('repeat-tile')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('repeat-custom')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });

    testWidgets('the list and the editor fit at 200% text', (tester) async {
      final env = await createEnv(tester);
      final id = await addRentRule(tester, env, d(2026, 9, 18));
      await smallScreen(tester);
      await tester.pumpWidget(wholeApp(env));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'Home with Coming up');

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
      expect(tester.takeException(), isNull, reason: 'the list');

      await tester.tap(find.byKey(ValueKey('rule-$id')));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'the editor');
      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });
}
