import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/budget_repository.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/date_range.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
BudgetMonth bm(int y, int m) => BudgetMonth(y, m);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late BudgetRepository budgets;
  late TransactionRepository txs;
  late CategoryRow food;
  late CategoryRow transport;
  late CategoryRow salary;

  setUp(() async {
    db = AppDatabase.memory();
    budgets = BudgetRepository(db);
    txs = TransactionRepository(db);
    final all = await CategoryRepository(db).watchAll().first;
    food = all.firstWhere((c) => c.name == 'Food');
    transport = all.firstWhere((c) => c.name == 'Transport');
    salary = all.firstWhere((c) => c.name == 'Salary');
  });
  tearDown(() => db.close());

  Future<List<BudgetLimitRow>> all() => budgets.watchAll().first;

  group('setLimit', () {
    test('adds a limit for a category', () async {
      await budgets.setLimit(
        month: bm(2026, 10),
        categoryId: food.id,
        amountCents: 20000,
      );
      final row = (await all()).single;
      expect(
        (row.categoryId, row.startMonth, row.amountCents),
        (food.id, '2026-10', 20000),
      );
    });

    test('adds an overall limit with no category', () async {
      await budgets.setLimit(month: bm(2026, 10), amountCents: 90000);
      expect((await all()).single.categoryId, isNull);
    });

    test(
      'setting the same month again replaces that row, not adds another',
      () async {
        await budgets.setLimit(
          month: bm(2026, 10),
          categoryId: food.id,
          amountCents: 20000,
        );
        await budgets.setLimit(
          month: bm(2026, 10),
          categoryId: food.id,
          amountCents: 25000,
        );
        final rows = await all();
        expect(rows, hasLength(1));
        expect(rows.single.amountCents, 25000);
        await budgets.setLimit(month: bm(2026, 10), amountCents: 1000);
        await budgets.setLimit(month: bm(2026, 10), amountCents: 2000);
        expect(
          (await all()).where((r) => r.categoryId == null).single.amountCents,
          2000,
        );
      },
    );

    test(
      'a later month adds a row and leaves earlier months as they were',
      () async {
        await budgets.setLimit(
          month: bm(2026, 9),
          categoryId: food.id,
          amountCents: 20000,
        );
        await budgets.setLimit(
          month: bm(2026, 11),
          categoryId: food.id,
          amountCents: 30000,
        );
        final entries = (await all()).map((r) => r.entry).toList();
        expect(resolveLimit(entries, food.id, bm(2026, 9)), 20000);
        expect(resolveLimit(entries, food.id, bm(2026, 10)), 20000);
        expect(resolveLimit(entries, food.id, bm(2026, 11)), 30000);
      },
    );

    test('a null amount means "no limit from this month on"', () async {
      await budgets.setLimit(
        month: bm(2026, 9),
        categoryId: food.id,
        amountCents: 20000,
      );
      await budgets.setLimit(
        month: bm(2026, 11),
        categoryId: food.id,
        amountCents: null,
      );
      final entries = (await all()).map((r) => r.entry).toList();
      expect(resolveLimit(entries, food.id, bm(2026, 10)), 20000);
      expect(resolveLimit(entries, food.id, bm(2026, 11)), isNull);
    });

    test('rejects a zero, negative or huge amount', () async {
      for (final bad in [0, -1, maxAmountCents + 1]) {
        expect(
          () => budgets.setLimit(
            month: bm(2026, 10),
            categoryId: food.id,
            amountCents: bad,
          ),
          throwsA(isA<RangeError>()),
        );
      }
    });

    test('income and unknown categories cannot have a limit', () async {
      expect(
        () => budgets.setLimit(
          month: bm(2026, 10),
          categoryId: salary.id,
          amountCents: 100,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => budgets.setLimit(
          month: bm(2026, 10),
          categoryId: 99999,
          amountCents: 100,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await all(), isEmpty);
    });

    test(
      'the database refuses duplicates even if the repository is bypassed',
      () async {
        Future<void> raw(int? cat, String month) => db
            .into(db.budgetLimits)
            .insert(
              BudgetLimitsCompanion.insert(
                categoryId: Value(cat),
                startMonth: month,
                amountCents: const Value(100),
                createdAt: DateTime(2026, 10, 1),
              ),
            );
        await raw(food.id, '2026-10');
        await expectLater(raw(food.id, '2026-10'), throwsA(isA<Exception>()));
        await raw(null, '2026-10');
        await expectLater(
          raw(null, '2026-10'),
          throwsA(isA<Exception>()),
          reason: 'two overall limits for one month',
        );
        // Different category or month is fine.
        await raw(transport.id, '2026-10');
        await raw(food.id, '2026-11');
        await raw(null, '2026-11');
      },
    );

    test('limits keep working when their category is archived', () async {
      await budgets.setLimit(
        month: bm(2026, 10),
        categoryId: food.id,
        amountCents: 20000,
      );
      await CategoryRepository(db).archive(food.id);
      expect((await all()).single.categoryId, food.id);
    });
  });

  group('spentInRange', () {
    Future<void> add(int cents, DateTime date, CategoryRow cat) => txs.add(
      TransactionInput(
        amountCents: cents,
        type: cat.type,
        date: date,
        categoryId: cat.id,
      ),
    );

    test('adds up expenses in the range, all categories or one', () async {
      await add(1000, d(2026, 10, 1), food);
      await add(2000, d(2026, 10, 31), transport);
      await add(4000, d(2026, 11, 1), food); // outside
      await add(9000, d(2026, 9, 30), food); // outside
      await add(500000, d(2026, 10, 15), salary); // income never counts
      final october = DateRange(d(2026, 10, 1), d(2026, 10, 31));
      expect(await txs.spentInRange(october), 3000);
      expect(await txs.spentInRange(october, categoryId: food.id), 1000);
      expect(await txs.spentInRange(october, categoryId: transport.id), 2000);
    });

    test('is zero when there is nothing', () async {
      expect(
        await txs.spentInRange(DateRange(d(2026, 10, 1), d(2026, 10, 31))),
        0,
      );
    });

    test('future-dated expenses inside the range count', () async {
      await add(7000, d(2026, 10, 28), food);
      expect(
        await txs.spentInRange(DateRange(d(2026, 10, 1), d(2026, 10, 31))),
        7000,
      );
    });
  });

  group('month start day setting', () {
    late SettingsRepository settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
    });

    test('defaults to 1, saves 1 to 28, and refuses the rest', () async {
      expect(settings.load().monthStartDay, 1);
      await settings.setMonthStartDay(25);
      expect(settings.load().monthStartDay, 25);
      for (final bad in [0, 29, -3]) {
        expect(() => settings.setMonthStartDay(bad), throwsRangeError);
      }
    });

    test('a bad stored value falls back into range', () async {
      SharedPreferences.setMockInitialValues({'month_start_day': 99});
      final s = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      expect(s.load().monthStartDay, 28);
    });

    test('it travels in a backup and is read leniently', () async {
      await settings.setMonthStartDay(25);
      expect(settings.toBackup().monthStartDay, 25);
      expect(BackupSettings.fromJson({'monthStartDay': 25}).monthStartDay, 25);
      for (final bad in [0, 29, 'x', 2.5, null]) {
        expect(
          BackupSettings.fromJson({'monthStartDay': bad}).monthStartDay,
          isNull,
        );
      }
      SharedPreferences.setMockInitialValues({});
      final other = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      await other.applyBackup(const BackupSettings(monthStartDay: 12));
      expect(other.load().monthStartDay, 12);
    });
  });

  group('backup', () {
    Uint8List bytesOf(Object json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    Map<String, Object?> base() => {
      'app': 'heisenbudget',
      'format': 1,
      'exportedAt': '2026-10-25T12:00:00Z',
      'categories': <Object?>[
        {'id': 1, 'name': 'Food', 'type': 'expense'},
        {'id': 2, 'name': 'Salary', 'type': 'income'},
      ],
      'transactions': <Object?>[],
      'budgetLimits': <Object?>[
        {
          'id': 1,
          'categoryId': 1,
          'startMonth': '2026-10',
          'amountCents': 20000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
        {
          'id': 2,
          'categoryId': null,
          'startMonth': '2026-10',
          'amountCents': 90000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
        {
          'id': 3,
          'categoryId': 1,
          'startMonth': '2026-12',
          'amountCents': null,
          'createdAt': '2026-10-01T08:00:00Z',
        },
      ],
    };

    Map<String, Object?> limit(Map<String, Object?> b, [int i = 0]) =>
        (b['budgetLimits']! as List)[i] as Map<String, Object?>;

    test('reads limits, including an overall one and a "no limit" row', () {
      final data = BackupData.parse(bytesOf(base()));
      expect(data.budgetLimits, hasLength(3));
      expect(data.budgetLimits[1].categoryId, isNull);
      expect(data.budgetLimits[2].amountCents, isNull);
    });

    test('a backup from before budgets restores with none', () {
      final b = base()..remove('budgetLimits');
      expect(BackupData.parse(bytesOf(b)).budgetLimits, isEmpty);
    });

    void rejects(String why, void Function(Map<String, Object?> b) change) {
      test('rejects: $why', () {
        final b = base();
        change(b);
        expect(
          () => BackupData.parse(bytesOf(b)),
          throwsA(isA<BackupFormatException>()),
        );
      });
    }

    rejects('limits that are not a list', (b) => b['budgetLimits'] = 5);
    rejects('a repeated id', (b) => limit(b, 1)['id'] = 1);
    rejects('an unknown category', (b) => limit(b)['categoryId'] = 99);
    rejects('an income category', (b) => limit(b)['categoryId'] = 2);
    rejects('a bad month', (b) => limit(b)['startMonth'] = '2026-13');
    rejects(
      'a month in the wrong shape',
      (b) => limit(b)['startMonth'] = 'Oct 2026',
    );
    rejects('a zero amount', (b) => limit(b)['amountCents'] = 0);
    rejects('a decimal amount', (b) => limit(b)['amountCents'] = 12.5);
    rejects('a bad timestamp', (b) => limit(b)['createdAt'] = 'soon');
    rejects('two limits for one category and month', (b) {
      (b['budgetLimits']! as List).add({...limit(b), 'id': 9});
    });
    rejects('two overall limits for one month', (b) {
      (b['budgetLimits']! as List).add({...limit(b, 1), 'id': 9});
    });

    test('limits survive a backup and restore, and restore replaces old ones', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      final service = BackupService(db, settings);
      await budgets.setLimit(
        month: bm(2026, 10),
        categoryId: food.id,
        amountCents: 20000,
      );
      await budgets.setLimit(month: bm(2026, 10), amountCents: 90000);
      await budgets.setLimit(
        month: bm(2026, 12),
        categoryId: food.id,
        amountCents: null,
      );
      final text = (await service.snapshot(now: DateTime.utc(2026, 10, 25)))
          .encode();

      // Replace with a file that has none, then bring them back from the text.
      await service.restore(
        BackupData.parse(bytesOf(base()..remove('budgetLimits'))),
      );
      expect(await all(), isEmpty);
      await service.restore(
        BackupData.parse(Uint8List.fromList(utf8.encode(text))),
      );
      final back = await all();
      expect(back, hasLength(3));
      final entries = back.map((r) => r.entry).toList();
      expect(resolveLimit(entries, food.id, bm(2026, 11)), 20000);
      expect(resolveLimit(entries, food.id, bm(2026, 12)), isNull);
      expect(resolveLimit(entries, null, bm(2027, 1)), 90000);
    });

    test('erasing everything removes limits too', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      await budgets.setLimit(
        month: bm(2026, 10),
        categoryId: food.id,
        amountCents: 20000,
      );
      await BackupService(db, settings).eraseEverything();
      expect(await all(), isEmpty);
    });
  });
}
