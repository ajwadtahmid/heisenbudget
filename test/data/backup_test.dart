import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/constants.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List bytesOf(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A small valid backup as a map, to be broken one field at a time.
Map<String, Object?> validBackup() => {
  'app': 'heisenbudget',
  'format': 1,
  'exportedAt': '2026-10-25T12:00:00Z',
  'settings': {'currency': 'BDT', 'themeMode': 'dark'},
  'categories': <Object?>[
    {'id': 1, 'name': 'Food', 'type': 'expense', 'icon': 'restaurant'},
    {'id': 2, 'name': 'Salary', 'type': 'income', 'icon': 'salary'},
  ],
  'transactions': <Object?>[
    {
      'id': 1,
      'amountCents': 1250,
      'type': 'expense',
      'date': '2026-10-05',
      'categoryId': 1,
      'note': 'Lunch',
      'createdAt': '2026-10-05T08:00:00Z',
      'updatedAt': '2026-10-05T08:00:00Z',
    },
  ],
};

Map<String, Object?> txOf(Map<String, Object?> b) =>
    (b['transactions']! as List).first as Map<String, Object?>;
Map<String, Object?> catOf(Map<String, Object?> b, [int i = 0]) =>
    (b['categories']! as List)[i] as Map<String, Object?>;

void main() {
  // Each test makes its own in-memory databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('BackupData.parse', () {
    test('reads a valid backup', () {
      final data = BackupData.parse(bytesOf(validBackup()));
      expect(data.categories, hasLength(2));
      expect(data.transactions.single.amountCents, 1250);
      expect(data.transactions.single.note, 'Lunch');
      expect(data.settings.currency, 'BDT');
      expect(data.exportedAt.toUtc(), DateTime.utc(2026, 10, 25, 12));
    });

    test('accepts a leading byte-order mark', () {
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...bytesOf(validBackup()),
      ]);
      expect(BackupData.parse(withBom).transactions, hasLength(1));
    });

    test('a blank note becomes null and a missing icon the general one', () {
      final b = validBackup();
      txOf(b)['note'] = '   ';
      catOf(b).remove('icon');
      final data = BackupData.parse(bytesOf(b));
      expect(data.transactions.single.note, isNull);
      expect(data.categories.first.icon, 'category');
    });

    void rejects(String why, void Function(Map<String, Object?> b) break_) {
      test('rejects: $why', () {
        final b = validBackup();
        break_(b);
        expect(
          () => BackupData.parse(bytesOf(b)),
          throwsA(isA<BackupFormatException>()),
        );
      });
    }

    rejects('another app', (b) => b['app'] = 'something-else');
    rejects('no format number', (b) => b.remove('format'));
    rejects('format 0', (b) => b['format'] = 0);
    rejects('no categories list', (b) => b.remove('categories'));
    rejects('no transactions list', (b) => b.remove('transactions'));
    rejects('repeated category id', (b) => catOf(b, 1)['id'] = 1);
    rejects('category without a name', (b) => catOf(b)['name'] = '  ');
    rejects('unknown category type', (b) => catOf(b)['type'] = 'loan');
    rejects('same name in the same type, any case', (b) {
      (b['categories']! as List).add({
        'id': 3,
        'name': 'FOOD',
        'type': 'expense',
      });
    });
    rejects('zero amount', (b) => txOf(b)['amountCents'] = 0);
    rejects('negative amount', (b) => txOf(b)['amountCents'] = -5);
    rejects('amount above the limit', (b) {
      txOf(b)['amountCents'] = maxAmountCents + 1;
    });
    rejects('amount as text', (b) => txOf(b)['amountCents'] = '12.50');
    rejects('amount as a decimal', (b) => txOf(b)['amountCents'] = 12.5);
    rejects('a day that does not exist', (b) => txOf(b)['date'] = '2026-02-31');
    rejects('a date in the wrong shape', (b) => txOf(b)['date'] = '5/10/2026');
    rejects('a year out of range', (b) => txOf(b)['date'] = '0001-01-01');
    rejects('unknown category id', (b) => txOf(b)['categoryId'] = 99);
    rejects('category of the other type', (b) => txOf(b)['categoryId'] = 2);
    rejects('note over the limit', (b) {
      txOf(b)['note'] = 'x' * (maxNoteLength + 1);
    });
    rejects('note that is not text', (b) => txOf(b)['note'] = 5);
    rejects('bad timestamp', (b) => txOf(b)['createdAt'] = 'yesterday');
    rejects('repeated transaction id', (b) {
      (b['transactions']! as List).add(Map.of(txOf(b)));
    });
    rejects('a transaction that is not an object', (b) {
      (b['transactions']! as List).add(5);
    });

    test(
      'rejects text that is not JSON, JSON that is not an object, and binary',
      () {
        for (final bad in [
          Uint8List.fromList(utf8.encode('not json')),
          Uint8List.fromList(utf8.encode('[1,2,3]')),
          Uint8List.fromList([0xFF, 0xFE, 0x00, 0x80]),
          Uint8List(0),
        ]) {
          expect(
            () => BackupData.parse(bad),
            throwsA(isA<BackupFormatException>()),
          );
        }
      },
    );

    test('rejects a backup from a newer format, saying so', () {
      final b = validBackup()..['format'] = backupFormatVersion + 1;
      expect(
        () => BackupData.parse(bytesOf(b)),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });

    test('rejects a file that is far too large', () {
      expect(
        () => BackupData.parse(Uint8List(maxBackupBytes + 1)),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('ignores settings it does not understand', () {
      final b = validBackup();
      b['settings'] = {
        'currency': 'ZZZ',
        'themeMode': 'neon',
        'accent': 7,
        'textFont': 'comic',
        'labFlavor': 'yes',
        'openingBalanceCents': maxAmountCents + 1,
        'weekMode': 'lunar',
        'weekStartDay': 9,
        'somethingNew': true,
      };
      final s = BackupData.parse(bytesOf(b)).settings;
      expect(s.toJson().values, everyElement(isNull));
    });

    test('a missing settings block is fine', () {
      final b = validBackup()..remove('settings');
      expect(BackupData.parse(bytesOf(b)).settings.currency, isNull);
    });
  });

  group('snapshot and restore', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late BackupService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.memory();
      settings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      service = BackupService(db, settings);
    });

    tearDown(() => db.close());

    Future<void> fillWithData() async {
      final cats = CategoryRepository(db);
      final txs = TransactionRepository(db);
      final pets = await cats.add(
        'Pets',
        TransactionType.expense,
        icon: 'pets',
      );
      final all = await cats.watchAll().first;
      final food = all.firstWhere((c) => c.name == 'Food');
      final salary = all.firstWhere((c) => c.name == 'Salary');
      await cats.archive(food.id);
      Future<void> add(
        int cents,
        TransactionType t,
        int cat,
        String date, [
        String? note,
      ]) {
        return txs.add(
          TransactionInput(
            amountCents: cents,
            type: t,
            date: DateTime.parse(date),
            categoryId: cat,
            note: note,
          ),
        );
      }

      await add(
        1250,
        TransactionType.expense,
        food.id,
        '2026-10-05',
        'Lunch, "fancy"\nsecond line ৳',
      );
      await add(99, TransactionType.expense, pets.id, '2026-10-06');
      await add(500000, TransactionType.income, salary.id, '2026-10-01');
      await settings.setCurrencyCode('BDT');
      await settings.setOpeningBalanceCents(123456);
      await settings.setLabFlavor(false);
      await settings.setWeekStartDay(3);
    }

    test('a backup restores to an empty app exactly, ids included', () async {
      await fillWithData();
      final before = await service.snapshot(now: DateTime.utc(2026, 10, 25));
      final text = before.encode();

      final other = AppDatabase.memory();
      addTearDown(other.close);
      SharedPreferences.setMockInitialValues({});
      final otherSettings = SettingsRepository(
        await SharedPreferences.getInstance(),
        defaultCurrency: 'USD',
      );
      final target = BackupService(other, otherSettings);
      await target.restore(
        BackupData.parse(Uint8List.fromList(utf8.encode(text))),
      );

      final after = await target.snapshot(now: DateTime.utc(2026, 10, 25));
      expect(after.categories, before.categories);
      expect(after.transactions.length, before.transactions.length);
      for (var i = 0; i < before.transactions.length; i++) {
        final a = after.transactions[i];
        final b = before.transactions[i];
        expect(
          (a.id, a.amountCents, a.type, a.date, a.categoryId, a.note),
          (b.id, b.amountCents, b.type, b.date, b.categoryId, b.note),
        );
        expect(a.createdAt.isAtSameMomentAs(b.createdAt), isTrue);
      }
      final s = otherSettings.load();
      expect(s.currency.code, 'BDT');
      expect(s.openingBalanceCents, 123456);
      expect(s.labFlavor, isFalse);
      expect(s.weekStartDay, 3);
      expect(s.onboardingDone, isTrue);
    });

    test('restoring replaces what was there and leaves no old rows', () async {
      await fillWithData();
      final backup = await service.snapshot(now: DateTime.utc(2026, 10, 25));

      // Change things after the backup was taken.
      final txs = TransactionRepository(db);
      final cats = CategoryRepository(db);
      final extra = await cats.add('Gadgets', TransactionType.expense);
      await txs.add(
        TransactionInput(
          amountCents: 777,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 20),
          categoryId: extra.id,
        ),
      );

      await service.restore(backup);
      final now = await service.snapshot(now: DateTime.utc(2026, 10, 25));
      expect(now.categories.map((c) => c.name), isNot(contains('Gadgets')));
      expect(now.transactions.map((t) => t.amountCents), [1250, 99, 500000]);
    });

    test('new rows after a restore get ids above the restored ones', () async {
      await fillWithData();
      final backup = await service.snapshot(now: DateTime.utc(2026, 10, 25));
      await service.restore(backup);
      final cat = backup.categories.last;
      final newId = await TransactionRepository(db).add(
        TransactionInput(
          amountCents: 1,
          type: cat.type,
          date: DateTime(2026, 10, 25),
          categoryId: cat.id,
        ),
      );
      expect(newId, greaterThan(backup.transactions.last.id));
    });

    test(
      'restore forgets last-used categories and marks the tour done',
      () async {
        await settings.setLastCategory(TransactionType.expense, 4);
        await settings.setLastCategory(TransactionType.income, 11);
        await service.restore(BackupData.parse(bytesOf(validBackup())));
        final s = settings.load();
        expect(s.lastExpenseCategoryId, isNull);
        expect(s.lastIncomeCategoryId, isNull);
        expect(s.onboardingDone, isTrue);
      },
    );

    test('settings missing from the file are left as they are', () async {
      await settings.setAccent(settings.load().accent);
      await settings.setOpeningBalanceCents(4200);
      final b = validBackup()..['settings'] = <String, Object?>{};
      await service.restore(BackupData.parse(bytesOf(b)));
      expect(settings.load().openingBalanceCents, 4200);
    });

    test('a restore that fails half-way changes nothing', () async {
      await fillWithData();
      final before = await service.snapshot(now: DateTime.utc(2026, 10, 25));

      // Bypass parsing to force a database error: a transaction that points
      // at a category that is not in the file.
      final broken = BackupData(
        exportedAt: DateTime.utc(2026, 10, 25),
        settings: const BackupSettings(currency: 'EUR'),
        categories: [before.categories.first],
        transactions: [
          TransactionRow(
            id: 1,
            amountCents: 100,
            type: TransactionType.expense,
            date: '2026-10-01',
            categoryId: 9999,
            note: null,
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        ],
      );
      await expectLater(service.restore(broken), throwsA(anything));

      final after = await service.snapshot(now: DateTime.utc(2026, 10, 25));
      expect(after.categories, before.categories);
      expect(after.transactions, before.transactions);
      expect(
        settings.load().currency.code,
        'BDT',
        reason: 'settings untouched',
      );
    });

    test('the file starts with the app id and a format number', () async {
      final text = (await service.snapshot(now: DateTime.utc(2026, 10, 25)))
          .encode();
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['app'], 'heisenbudget');
      expect(json['format'], backupFormatVersion);
      expect(
        json.keys,
        containsAll(['settings', 'categories', 'transactions']),
      );
    });
  });
}
