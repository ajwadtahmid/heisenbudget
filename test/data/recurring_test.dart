import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/recurring/recurring_service.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late RecurringRepository rules;
  late TransactionRepository txs;
  late RecurringService service;
  late CategoryRow rent;
  late CategoryRow salary;

  setUp(() async {
    db = AppDatabase.memory();
    rules = RecurringRepository(db);
    txs = TransactionRepository(db);
    service = RecurringService(db);
    final all = await CategoryRepository(db).watchAll().first;
    rent = all.firstWhere((c) => c.name == 'Rent');
    salary = all.firstWhere((c) => c.name == 'Salary');
  });
  tearDown(() => db.close());

  RecurringInput monthlyRent(
    DateTime start, {
    DateTime? end,
    int every = 1,
    int cents = 120000,
  }) => RecurringInput(
    amountCents: cents,
    type: TransactionType.expense,
    categoryId: rent.id,
    note: 'Flat',
    unit: RecurrenceUnit.month,
    interval: every,
    start: start,
    end: end,
  );

  TransactionInput firstRent(DateTime date) => TransactionInput(
    amountCents: 120000,
    type: TransactionType.expense,
    date: date,
    categoryId: rent.id,
    note: 'Flat',
  );

  Future<List<TransactionRow>> allTx() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<RecurringRuleRow> onlyRule() async =>
      (await db.select(db.recurringRules).get()).single;

  group('creating a rule with its first transaction', () {
    test(
      'saves the transaction as occurrence 0 and the rule at occurrence 1',
      () async {
        final txId = await rules.addWithRule(
          firstRent(d(2026, 11, 1)),
          monthlyRent(d(2026, 11, 1)),
        );
        final rule = await onlyRule();
        final tx = (await allTx()).single;
        expect(tx.id, txId);
        expect(tx.recurringRuleId, rule.id);
        expect(tx.date, '2026-11-01');
        expect(rule.nextIndex, 1);
        expect(rule.nextDate, d(2026, 12, 1));
        expect(rule.recurrence.scheduleText, 'Monthly on the 1st');
      },
    );

    test('is all or nothing', () async {
      await expectLater(
        rules.addWithRule(
          TransactionInput(
            amountCents: 100,
            type: TransactionType.expense,
            date: d(2026, 11, 1),
            categoryId: 99999, // no such category
          ),
          monthlyRent(d(2026, 11, 1)),
        ),
        throwsA(anything),
      );
      expect(await db.select(db.recurringRules).get(), isEmpty);
      expect(await allTx(), isEmpty);
    });

    test('rejects a bad interval, amount or end date', () async {
      expect(
        () => rules.addWithRule(
          firstRent(d(2026, 11, 1)),
          monthlyRent(d(2026, 11, 1), every: 0),
        ),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => rules.addWithRule(
          firstRent(d(2026, 11, 1)),
          monthlyRent(d(2026, 11, 1), cents: 0),
        ),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => rules.addWithRule(
          firstRent(d(2026, 11, 1)),
          monthlyRent(d(2026, 11, 1), end: d(2026, 10, 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('make an existing transaction recurring', () {
    test('links it and continues from the next occurrence', () async {
      final id = await txs.add(firstRent(d(2026, 10, 15)));
      final ruleId = await rules.makeRecurring(
        id,
        unit: RecurrenceUnit.month,
        interval: 1,
      );
      expect(ruleId, isNotNull);
      final rule = await onlyRule();
      expect(rule.startDate, '2026-10-15');
      expect(rule.nextIndex, 1);
      expect((await allTx()).single.recurringRuleId, rule.id);
    });

    test(
      'does nothing for a transaction that already repeats or is missing',
      () async {
        final id = await rules.addWithRule(
          firstRent(d(2026, 10, 1)),
          monthlyRent(d(2026, 10, 1)),
        );
        expect(
          await rules.makeRecurring(id, unit: RecurrenceUnit.week, interval: 1),
          isNull,
        );
        expect(
          await rules.makeRecurring(
            9999,
            unit: RecurrenceUnit.week,
            interval: 1,
          ),
          isNull,
        );
        expect(await db.select(db.recurringRules).get(), hasLength(1));
      },
    );
  });

  group('catch-up', () {
    test(
      'adds every missed occurrence up to today and no future ones',
      () async {
        await rules.addWithRule(
          firstRent(d(2026, 8, 1)),
          monthlyRent(d(2026, 8, 1)),
        );
        final result = await service.catchUp(d(2026, 10, 15));
        expect(result.count, 2); // Sep 1 and Oct 1
        final dates = (await allTx()).map((t) => t.date).toList();
        expect(dates, ['2026-08-01', '2026-09-01', '2026-10-01']);
        expect((await onlyRule()).nextIndex, 3);
        expect((await onlyRule()).nextDate, d(2026, 11, 1));
      },
    );

    test('adds the occurrence due today but not tomorrow', () async {
      await rules.addWithRule(
        firstRent(d(2026, 9, 1)),
        monthlyRent(d(2026, 9, 1)),
      );
      expect((await service.catchUp(d(2026, 9, 30))).count, 0);
      expect((await service.catchUp(d(2026, 10, 1))).count, 1);
    });

    test('is idempotent: a second run adds nothing', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      await service.catchUp(d(2026, 10, 15));
      final before = await allTx();
      final again = await service.catchUp(d(2026, 10, 15));
      expect(again.isEmpty, isTrue);
      expect((await allTx()).length, before.length);
    });

    test('runs started together share one run and add each row once', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final results = await Future.wait([
        service.catchUp(d(2026, 10, 15)),
        service.catchUp(d(2026, 10, 15)),
        service.catchUp(d(2026, 10, 15)),
      ]);
      expect(results.map((r) => r.count), everyElement(2));
      expect(await allTx(), hasLength(3));
    });

    test('a deleted generated transaction does not come back', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final result = await service.catchUp(d(2026, 10, 15));
      await txs.delete(result.transactionIds.first);
      await service.catchUp(d(2026, 10, 15));
      expect((await allTx()).map((t) => t.date), ['2026-08-01', '2026-10-01']);
    });

    test('a paused rule adds nothing, and resumes where it stopped', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final rule = await onlyRule();
      await rules.setActive(rule.id, false);
      expect((await service.catchUp(d(2026, 10, 15))).count, 0);
      await rules.setActive(rule.id, true);
      expect((await service.catchUp(d(2026, 10, 15))).count, 2);
    });

    test('stops at the end date', () async {
      await rules.addWithRule(
        firstRent(d(2026, 1, 1)),
        monthlyRent(d(2026, 1, 1), end: d(2026, 3, 15)),
      );
      final result = await service.catchUp(d(2026, 12, 1));
      expect(result.count, 2); // Feb 1 and Mar 1
      final rule = await onlyRule();
      expect(rule.hasEnded, isTrue);
      expect((await service.catchUp(d(2027, 12, 1))).isEmpty, isTrue);
    });

    test('the 31st clamps in short months', () async {
      await rules.addWithRule(
        firstRent(d(2026, 1, 31)),
        monthlyRent(d(2026, 1, 31)),
      );
      await service.catchUp(d(2026, 4, 30));
      expect((await allTx()).map((t) => t.date), [
        '2026-01-31',
        '2026-02-28',
        '2026-03-31',
        '2026-04-30',
      ]);
    });

    test('a rule that starts years ago is added in capped batches', () async {
      await rules.addWithRule(
        TransactionInput(
          amountCents: 100,
          type: TransactionType.expense,
          date: d(2020, 1, 1),
          categoryId: rent.id,
        ),
        RecurringInput(
          amountCents: 100,
          type: TransactionType.expense,
          categoryId: rent.id,
          unit: RecurrenceUnit.day,
          interval: 1,
          start: d(2020, 1, 1),
        ),
      );
      final first = await service.catchUp(d(2026, 1, 1));
      expect(first.count, maxCatchUpPerRule);
      final second = await service.catchUp(d(2026, 1, 1));
      expect(second.count, maxCatchUpPerRule);
    });

    test('several rules are handled in one run', () async {
      await rules.addWithRule(
        firstRent(d(2026, 9, 1)),
        monthlyRent(d(2026, 9, 1)),
      );
      await rules.addWithRule(
        TransactionInput(
          amountCents: 500000,
          type: TransactionType.income,
          date: d(2026, 9, 5),
          categoryId: salary.id,
        ),
        RecurringInput(
          amountCents: 500000,
          type: TransactionType.income,
          categoryId: salary.id,
          unit: RecurrenceUnit.month,
          interval: 1,
          start: d(2026, 9, 5),
        ),
      );
      final result = await service.catchUp(d(2026, 10, 20));
      expect(result.count, 2);
      final created = (await allTx()).where(
        (t) => result.transactionIds.contains(t.id),
      );
      expect(created.map((t) => t.type).toSet(), {
        TransactionType.expense,
        TransactionType.income,
      });
    });

    test(
      'keeps the rule\'s amount, category and note on each transaction',
      () async {
        await rules.addWithRule(
          firstRent(d(2026, 9, 1)),
          monthlyRent(d(2026, 9, 1)),
        );
        await service.catchUp(d(2026, 10, 5));
        final made = (await allTx()).last;
        expect(
          (made.amountCents, made.categoryId, made.note, made.type),
          (120000, rent.id, 'Flat', TransactionType.expense),
        );
      },
    );

    test(
      'undo by deleting the created rows leaves the rule advanced',
      () async {
        await rules.addWithRule(
          firstRent(d(2026, 8, 1)),
          monthlyRent(d(2026, 8, 1)),
        );
        final result = await service.catchUp(d(2026, 10, 15));
        await txs.deleteMany(result.transactionIds);
        expect(await allTx(), hasLength(1));
        expect((await service.catchUp(d(2026, 10, 15))).isEmpty, isTrue);
      },
    );
  });

  group('editing and managing rules', () {
    test('editing amount and note only changes future transactions', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      await service.catchUp(d(2026, 9, 15)); // adds Sep 1 at 1200.00
      final rule = await onlyRule();
      await rules.update(
        rule.id,
        monthlyRent(d(2026, 8, 1), cents: 130000),
        reanchor: false,
      );
      await service.catchUp(d(2026, 10, 15)); // adds Oct 1 at 1300.00
      expect((await allTx()).map((t) => t.amountCents), [
        120000,
        120000,
        130000,
      ]);
      expect((await onlyRule()).nextIndex, 3, reason: 'schedule untouched');
    });

    test('changing the schedule re-anchors from the new start date', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final rule = await onlyRule();
      await rules.update(
        rule.id,
        RecurringInput(
          amountCents: 120000,
          type: TransactionType.expense,
          categoryId: rent.id,
          unit: RecurrenceUnit.week,
          interval: 2,
          start: d(2026, 11, 6),
        ),
        reanchor: true,
      );
      final changed = await onlyRule();
      expect(changed.nextIndex, 0);
      expect(changed.nextDate, d(2026, 11, 6));
      expect(changed.recurrence.scheduleText, 'Every 2 weeks on Friday');
    });

    test('the category must match the rule\'s type', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final rule = await onlyRule();
      expect(
        () => rules.update(
          rule.id,
          RecurringInput(
            amountCents: 100,
            type: TransactionType.expense,
            categoryId: salary.id,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 8, 1),
          ),
          reanchor: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('skip next moves past one occurrence without adding it', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final rule = await onlyRule();
      expect(await rules.skipNext(rule.id), isTrue); // skips Sep 1
      await service.catchUp(d(2026, 10, 15));
      expect((await allTx()).map((t) => t.date), ['2026-08-01', '2026-10-01']);
    });

    test('skip next says no when the rule has ended', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1), end: d(2026, 8, 20)),
      );
      expect(await rules.skipNext((await onlyRule()).id), isFalse);
    });

    test('add now records it today and moves the schedule on', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      final rule = await onlyRule();
      final id = await service.addNow(rule.id, d(2026, 8, 20));
      expect(id, isNotNull);
      final added = (await allTx()).last;
      expect(added.date, '2026-08-20');
      expect(added.recurringRuleId, rule.id);
      // Sep 1 is the one that was skipped by paying early.
      final after = await onlyRule();
      expect(after.nextDate, d(2026, 10, 1));
      // Doing it twice on one day is refused.
      expect(await service.addNow(rule.id, d(2026, 8, 20)), isNull);
    });

    test('deleting a rule keeps every transaction it made', () async {
      await rules.addWithRule(
        firstRent(d(2026, 8, 1)),
        monthlyRent(d(2026, 8, 1)),
      );
      await service.catchUp(d(2026, 10, 15));
      await rules.delete((await onlyRule()).id);
      final left = await allTx();
      expect(left, hasLength(3));
      expect(left.every((t) => t.recurringRuleId == null), isTrue);
      expect((await service.catchUp(d(2027, 1, 1))).isEmpty, isTrue);
    });

    test(
      'changing a generated transaction\'s date unlinks it from the rule',
      () async {
        await rules.addWithRule(
          firstRent(d(2026, 8, 1)),
          monthlyRent(d(2026, 8, 1)),
        );
        final result = await service.catchUp(d(2026, 9, 15));
        final id = result.transactionIds.single;
        await txs.update(id, firstRent(d(2026, 9, 3)), unlinkRule: true);
        final row = (await allTx()).firstWhere((t) => t.id == id);
        expect(row.recurringRuleId, isNull);
        expect(row.date, '2026-09-03');
        // The schedule does not refill Sep 1.
        await service.catchUp(d(2026, 9, 20));
        expect((await allTx()).where((t) => t.date == '2026-09-01'), isEmpty);
      },
    );

    test(
      'editing other fields of a generated transaction keeps the link',
      () async {
        await rules.addWithRule(
          firstRent(d(2026, 8, 1)),
          monthlyRent(d(2026, 8, 1)),
        );
        final result = await service.catchUp(d(2026, 9, 15));
        final id = result.transactionIds.single;
        await txs.update(id, firstRent(d(2026, 9, 1)));
        expect(
          (await allTx()).firstWhere((t) => t.id == id).recurringRuleId,
          isNotNull,
        );
      },
    );
  });
}
