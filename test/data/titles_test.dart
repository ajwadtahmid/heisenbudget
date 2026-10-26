import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/backup/csv_export.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/recurring/recurring_service.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/search.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TransactionRepository txs;
  late CategoryRow food;

  setUp(() async {
    db = AppDatabase.memory();
    txs = TransactionRepository(db);
    food = (await CategoryRepository(
      db,
    ).watchAll().first).firstWhere((c) => c.name == 'Food');
  });
  tearDown(() => db.close());

  TransactionInput input({String? title, String? note}) => TransactionInput(
    amountCents: 2500,
    type: TransactionType.expense,
    date: d(2026, 10, 25),
    categoryId: food.id,
    title: title,
    note: note,
  );

  Future<List<TransactionRow>> all() => (db.select(
    db.transactions,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  group('transactions', () {
    test('a title is saved, trimmed, and separate from the note', () async {
      await txs.add(input(title: '  In & Out  ', note: 'Burger'));
      final row = (await all()).single;
      expect((row.title, row.note), ('In & Out', 'Burger'));
    });

    test('no title, or a blank one, is stored as none', () async {
      await txs.add(input());
      await txs.add(input(title: '   '));
      expect((await all()).map((t) => t.title), [null, null]);
    });

    test('a title can be added, changed and removed by editing', () async {
      final id = await txs.add(input(title: 'In & Out'));
      await txs.update(id, input(title: 'Five Guys'));
      expect((await all()).single.title, 'Five Guys');
      await txs.update(id, input());
      expect((await all()).single.title, isNull);
    });

    test('a title over the limit is refused; at the limit is fine', () async {
      expect(
        () => txs.add(input(title: 'x' * (maxTitleLength + 1))),
        throwsA(isA<ArgumentError>()),
      );
      await txs.add(input(title: 'x' * maxTitleLength));
    });

    test('Undo copies keep the title', () async {
      final id = await txs.add(input(title: 'In & Out'));
      final row = (await all()).single;
      expect(TransactionInput.fromRow(row).title, 'In & Out');
      await txs.delete(id);
      await txs.add(TransactionInput.fromRow(row));
      expect((await all()).single.title, 'In & Out');
    });

    test('the title is searchable, and so are the category and note', () {
      bool hit(String q, {String? note}) => SearchQuery.parse(q).matches(
        category: 'Food',
        amountCents: 2500,
        title: 'In & Out',
        note: note,
      );
      expect(hit('out'), isTrue, reason: 'title');
      expect(hit('food'), isTrue, reason: 'category');
      expect(hit('out food'), isTrue, reason: 'both together');
      expect(hit('burger', note: 'Burger'), isTrue, reason: 'note');
      expect(hit('burger'), isFalse);
      expect(hit('shop'), isFalse);
    });
  });

  group('repeating rules and favorites keep the title', () {
    test('a rule hands its title to each transaction it makes', () async {
      final rules = RecurringRepository(db);
      await rules.addWithRule(
        TransactionInput(
          amountCents: 2500,
          type: TransactionType.expense,
          date: d(2026, 8, 25),
          categoryId: food.id,
          title: 'Landlord',
        ),
        RecurringInput(
          amountCents: 2500,
          type: TransactionType.expense,
          categoryId: food.id,
          title: 'Landlord',
          unit: RecurrenceUnit.month,
          interval: 1,
          start: d(2026, 8, 25),
        ),
      );
      await RecurringService(db).catchUp(d(2026, 10, 25));
      final titles = (await all()).map((t) => t.title).toSet();
      expect(titles, {'Landlord'});
      expect(await all(), hasLength(3));
    });

    test('making a transaction repeat copies its title to the rule', () async {
      final id = await txs.add(input(title: 'Gym'));
      await RecurringRepository(db)
          .makeRecurring(id, unit: RecurrenceUnit.month, interval: 1);
      expect((await db.select(db.recurringRules).getSingle()).title, 'Gym');
    });

    test('editing a rule can change its title', () async {
      final rules = RecurringRepository(db);
      await rules.addWithRule(
        input(title: 'Old'),
        RecurringInput(
          amountCents: 2500,
          type: TransactionType.expense,
          categoryId: food.id,
          title: 'Old',
          unit: RecurrenceUnit.month,
          interval: 1,
          start: d(2026, 8, 25),
        ),
      );
      final rule = await db.select(db.recurringRules).getSingle();
      await rules.update(
        rule.id,
        RecurringInput(
          amountCents: 2500,
          type: TransactionType.expense,
          categoryId: food.id,
          title: 'New',
          unit: RecurrenceUnit.month,
          interval: 1,
          start: d(2026, 8, 25),
        ),
        reanchor: false,
      );
      expect((await db.select(db.recurringRules).getSingle()).title, 'New');
    });

    test('a favorite keeps and returns its title', () async {
      final favorites = FavoriteRepository(db);
      final id = await favorites.add(
        FavoriteInput(
          label: 'Burger',
          type: TransactionType.expense,
          categoryId: food.id,
          title: ' In & Out ',
        ),
      );
      expect((await favorites.getById(id))!.title, 'In & Out');
      await favorites.update(
        id,
        FavoriteInput(
          label: 'Burger',
          type: TransactionType.expense,
          categoryId: food.id,
        ),
      );
      expect((await favorites.getById(id))!.title, isNull);
    });

    test('an over-long title is refused on rules and favorites too', () async {
      final tooLong = 'x' * (maxTitleLength + 1);
      expect(
        () => FavoriteRepository(db).add(
          FavoriteInput(
            label: 'A',
            type: TransactionType.expense,
            categoryId: food.id,
            title: tooLong,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RecurringRepository(db).addWithRule(
          input(),
          RecurringInput(
            amountCents: 100,
            type: TransactionType.expense,
            categoryId: food.id,
            title: tooLong,
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 8, 25),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('csv', () {
    test('has a Title column, and guards it like the note', () async {
      await txs.add(input(title: 'In & Out', note: 'Burger'));
      await txs.add(input(title: '=SUM(A1)'));
      final csv = buildTransactionsCsv(await txs.getAll());
      expect(csv, contains('Date,Type,Category,Title,Amount,Note'));
      expect(
        csv,
        contains('2026-10-25,Expense,Food,In & Out,25.00,Burger\r\n'),
      );
      expect(csv, contains("2026-10-25,Expense,Food,'=SUM(A1),25.00,\r\n"));
    });
  });

  group('backup', () {
    Uint8List bytesOf(Object json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    late SettingsRepository settings;
    late BackupService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      service = BackupService(db, settings);
    });

    test(
      'titles on transactions, rules and favorites survive a round trip',
      () async {
        await txs.add(input(title: 'In & Out', note: 'Burger'));
        await RecurringRepository(db).addWithRule(
          input(title: 'Landlord'),
          RecurringInput(
            amountCents: 2500,
            type: TransactionType.expense,
            categoryId: food.id,
            title: 'Landlord',
            unit: RecurrenceUnit.month,
            interval: 1,
            start: d(2026, 9, 25),
          ),
        );
        await FavoriteRepository(db).add(
          FavoriteInput(
            label: 'Burger',
            type: TransactionType.expense,
            categoryId: food.id,
            title: 'In & Out',
          ),
        );
        final text = (await service.snapshot(now: DateTime.utc(2026, 10, 25)))
            .encode();

        await service.restore(
          BackupData(
            exportedAt: DateTime.utc(2026, 10, 25),
            settings: const BackupSettings(),
            categories: (await db.select(db.categories).get()),
            recurringRules: const [],
            favorites: const [],
            budgetLimits: const [],
            transactions: const [],
          ),
        );
        expect(await all(), isEmpty);

        await service.restore(
          BackupData.parse(Uint8List.fromList(utf8.encode(text))),
        );
        expect((await all()).map((t) => t.title), ['In & Out', 'Landlord']);
        expect(
          (await db.select(db.recurringRules).getSingle()).title,
          'Landlord',
        );
        expect((await db.select(db.favorites).getSingle()).title, 'In & Out');
      },
    );

    Map<String, Object?> base() => {
      'app': 'heisenbudget',
      'format': 1,
      'exportedAt': '2026-10-25T12:00:00Z',
      'categories': <Object?>[
        {'id': 1, 'name': 'Food', 'type': 'expense'},
      ],
      'transactions': <Object?>[
        {
          'id': 1,
          'amountCents': 100,
          'type': 'expense',
          'date': '2026-10-05',
          'categoryId': 1,
          'createdAt': '2026-10-05T08:00:00Z',
          'updatedAt': '2026-10-05T08:00:00Z',
        },
      ],
    };

    Map<String, Object?> tx(Map<String, Object?> b) =>
        (b['transactions']! as List).first as Map<String, Object?>;

    test('a backup from before titles still restores, with none', () {
      expect(
        BackupData.parse(bytesOf(base())).transactions.single.title,
        isNull,
      );
    });

    test('a blank title in a file becomes none, and others are trimmed', () {
      final b = base();
      tx(b)['title'] = '  ';
      expect(BackupData.parse(bytesOf(b)).transactions.single.title, isNull);
      tx(b)['title'] = ' Shop ';
      expect(BackupData.parse(bytesOf(b)).transactions.single.title, 'Shop');
    });

    test('a title that is not text, or is too long, is refused', () {
      for (final bad in [5, true, 'x' * (maxTitleLength + 1)]) {
        final b = base();
        tx(b)['title'] = bad;
        expect(
          () => BackupData.parse(bytesOf(b)),
          throwsA(isA<BackupFormatException>()),
          reason: '$bad',
        );
      }
    });
  });
}
