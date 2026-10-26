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
    Future<void> set(
      DateTime start, {
      int? cat,
      BudgetUnit unit = BudgetUnit.month,
      bool repeats = true,
      int? cents,
    }) => budgets.setLimit(
      start: start,
      unit: unit,
      repeats: repeats,
      categoryId: cat,
      amountCents: cents,
    );

    test('adds a limit for a category', () async {
      await set(d(2026, 10, 1), cat: food.id, cents: 20000);
      final row = (await all()).single;
      expect(
        (row.categoryId, row.unit, row.repeats, row.start, row.amountCents),
        (food.id, BudgetUnit.month, true, '2026-10-01', 20000),
      );
    });

    test('adds an overall limit with no category', () async {
      await set(d(2026, 10, 1), cents: 90000);
      expect((await all()).single.categoryId, isNull);
    });

    test('stores the period and whether it repeats', () async {
      await set(
        d(2026, 10, 12),
        cat: food.id,
        unit: BudgetUnit.week,
        repeats: false,
        cents: 5000,
      );
      final row = (await all()).single;
      expect((row.unit, row.repeats), (BudgetUnit.week, false));
    });

    test(
      'setting the same start again replaces that row, not adds another',
      () async {
        await set(d(2026, 10, 1), cat: food.id, cents: 20000);
        await set(
          d(2026, 10, 1),
          cat: food.id,
          unit: BudgetUnit.week,
          cents: 25000,
        );
        final rows = await all();
        expect(rows, hasLength(1));
        expect(
          (rows.single.amountCents, rows.single.unit),
          (25000, BudgetUnit.week),
        );
        await set(d(2026, 10, 1), cents: 1000);
        await set(d(2026, 10, 1), cents: 2000);
        expect(
          (await all()).where((r) => r.categoryId == null).single.amountCents,
          2000,
        );
      },
    );

    test(
      'a later start adds a row and leaves earlier periods as they were',
      () async {
        await set(d(2026, 9, 1), cat: food.id, cents: 20000);
        await set(d(2026, 11, 1), cat: food.id, cents: 30000);
        final entries = (await all()).map((r) => r.entry).toList();
        int? at(DateTime date) =>
            resolveBudget(entries, food.id, date, monthStartDay: 1)?.limit;
        expect(at(d(2026, 9, 15)), 20000);
        expect(at(d(2026, 10, 15)), 20000);
        expect(at(d(2026, 11, 15)), 30000);
      },
    );

    test('a null amount means "no budget from here"', () async {
      await set(d(2026, 9, 1), cat: food.id, cents: 20000);
      await set(d(2026, 11, 1), cat: food.id, cents: null);
      final entries = (await all()).map((r) => r.entry).toList();
      expect(
        resolveBudget(
          entries,
          food.id,
          d(2026, 10, 15),
          monthStartDay: 1,
        )!.limit,
        20000,
      );
      expect(
        resolveBudget(entries, food.id, d(2026, 11, 15), monthStartDay: 1),
        isNull,
      );
    });

    test('rejects a zero, negative or huge amount', () async {
      for (final bad in [0, -1, maxAmountCents + 1]) {
        expect(
          () => set(d(2026, 10, 1), cat: food.id, cents: bad),
          throwsA(isA<RangeError>()),
        );
      }
    });

    test('income and unknown categories cannot have a limit', () async {
      expect(
        () => set(d(2026, 10, 1), cat: salary.id, cents: 100),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => set(d(2026, 10, 1), cat: 99999, cents: 100),
        throwsA(isA<ArgumentError>()),
      );
      expect(await all(), isEmpty);
    });

    test(
      'the database refuses duplicates even if the repository is bypassed',
      () async {
        Future<void> raw(int? cat, String start) => db
            .into(db.budgetLimits)
            .insert(
              BudgetLimitsCompanion.insert(
                categoryId: Value(cat),
                unit: BudgetUnit.month,
                start: start,
                amountCents: const Value(100),
                createdAt: DateTime(2026, 10, 1),
              ),
            );
        await raw(food.id, '2026-10-01');
        await expectLater(
          raw(food.id, '2026-10-01'),
          throwsA(isA<Exception>()),
        );
        await raw(null, '2026-10-01');
        await expectLater(
          raw(null, '2026-10-01'),
          throwsA(isA<Exception>()),
          reason: 'two overall limits for one start',
        );
        await raw(transport.id, '2026-10-01');
        await raw(food.id, '2026-11-01');
        await raw(null, '2026-11-01');
      },
    );

    test('limits keep working when their category is archived', () async {
      await set(d(2026, 10, 1), cat: food.id, cents: 20000);
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
          'unit': 'month',
          'repeats': true,
          'start': '2026-10-01',
          'amountCents': 20000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
        {
          'id': 2,
          'categoryId': null,
          'unit': 'week',
          'repeats': false,
          'start': '2026-10-12',
          'amountCents': 90000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
        {
          'id': 3,
          'categoryId': 1,
          'unit': 'month',
          'repeats': true,
          'start': '2026-12-01',
          'amountCents': null,
          'createdAt': '2026-10-01T08:00:00Z',
        },
      ],
    };

    Map<String, Object?> limit(Map<String, Object?> b, [int i = 0]) =>
        (b['budgetLimits']! as List)[i] as Map<String, Object?>;

    test('reads limits with their period and repeat setting', () {
      final data = BackupData.parse(bytesOf(base()));
      expect(data.budgetLimits, hasLength(3));
      expect(
        (data.budgetLimits[1].unit, data.budgetLimits[1].repeats),
        (BudgetUnit.week, false),
      );
      expect(data.budgetLimits[1].categoryId, isNull);
      expect(data.budgetLimits[2].amountCents, isNull);
    });

    test('an older monthly-only limit reads as a repeating monthly one', () {
      final b = base();
      b['budgetLimits'] = <Object?>[
        {
          'id': 1,
          'categoryId': 1,
          'startMonth': '2026-10',
          'amountCents': 20000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
      ];
      final row = BackupData.parse(bytesOf(b)).budgetLimits.single;
      expect(
        (row.unit, row.repeats, row.start),
        (BudgetUnit.month, true, '2026-10-01'),
      );
    });

    test('an older limit uses the backup\'s month start day', () {
      final b = base();
      b['settings'] = {'monthStartDay': 25};
      b['budgetLimits'] = <Object?>[
        {
          'id': 1,
          'categoryId': null,
          'startMonth': '2026-10',
          'amountCents': 1000,
          'createdAt': '2026-10-01T08:00:00Z',
        },
      ];
      expect(
        BackupData.parse(bytesOf(b)).budgetLimits.single.start,
        '2026-10-25',
      );
    });

    test('a missing repeat setting means repeating', () {
      final b = base();
      limit(b).remove('repeats');
      expect(BackupData.parse(bytesOf(b)).budgetLimits.first.repeats, isTrue);
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
    rejects('an unknown period', (b) => limit(b)['unit'] = 'decade');
    rejects(
      'no period at all',
      (b) => limit(b)
        ..remove('unit')
        ..remove('start'),
    );
    rejects(
      'a start that is not a real date',
      (b) => limit(b)['start'] = '2026-02-31',
    );
    rejects('a start in the wrong shape', (b) => limit(b)['start'] = '2026-10');
    rejects(
      'a repeat setting that is not true or false',
      (b) => limit(b)['repeats'] = 'yes',
    );
    rejects('a zero amount', (b) => limit(b)['amountCents'] = 0);
    rejects('a decimal amount', (b) => limit(b)['amountCents'] = 12.5);
    rejects('a bad timestamp', (b) => limit(b)['createdAt'] = 'soon');
    rejects('a bad older month', (b) {
      limit(b)
        ..remove('unit')
        ..remove('start')
        ..['startMonth'] = '2026-13';
    });
    rejects('two limits for one category and start', (b) {
      (b['budgetLimits']! as List).add({...limit(b), 'id': 9});
    });
    rejects('two overall limits for one start', (b) {
      (b['budgetLimits']! as List).add({...limit(b, 1), 'id': 9});
    });

    test(
      'limits survive a backup and restore, and restore replaces old ones',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsRepository(
          await SharedPreferences.getInstance(),
          defaultCurrency: 'USD',
        );
        final service = BackupService(db, settings);
        await budgets.setLimit(
          start: d(2026, 10, 1),
          unit: BudgetUnit.month,
          categoryId: food.id,
          amountCents: 20000,
        );
        await budgets.setLimit(
          start: d(2026, 10, 12),
          unit: BudgetUnit.fortnight,
          repeats: false,
          amountCents: 90000,
        );
        await budgets.setLimit(
          start: d(2026, 12, 1),
          unit: BudgetUnit.month,
          categoryId: food.id,
          amountCents: null,
        );
        final text = (await service.snapshot(now: DateTime.utc(2026, 10, 25)))
            .encode();

        await service.restore(
          BackupData.parse(bytesOf(base()..remove('budgetLimits'))),
        );
        expect(await all(), isEmpty);
        await service.restore(
          BackupData.parse(Uint8List.fromList(utf8.encode(text))),
        );
        final back = await all();
        expect(back, hasLength(3));
        final overall = back.firstWhere((r) => r.categoryId == null);
        expect(
          (overall.unit, overall.repeats, overall.start),
          (BudgetUnit.fortnight, false, '2026-10-12'),
        );
        final entries = back.map((r) => r.entry).toList();
        expect(
          resolveBudget(
            entries,
            food.id,
            d(2026, 11, 15),
            monthStartDay: 1,
          )!.limit,
          20000,
        );
        expect(
          resolveBudget(entries, food.id, d(2026, 12, 15), monthStartDay: 1),
          isNull,
        );
      },
    );

    test('erasing everything removes limits too', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      await budgets.setLimit(
        start: d(2026, 10, 1),
        unit: BudgetUnit.month,
        categoryId: food.id,
        amountCents: 20000,
      );
      await BackupService(db, settings).eraseEverything();
      expect(await all(), isEmpty);
    });
  });
}
