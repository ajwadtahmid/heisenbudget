import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/database/database_files.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.prefs) : super(defaultCurrency: 'USD');
  bool fail = true;
  @override
  Future<void> clearAll() async {
    if (fail) throw StateError('Settings unavailable');
    await super.clearAll();
  }
}

class _FailingCopies extends DatabaseFiles {
  _FailingCopies(super.directory);
  bool fail = true;
  @override
  Future<void> deleteCopies() async {
    if (fail) throw const FileSystemException('Copies unavailable');
    await super.deleteCopies();
  }
}

void main() {
  test(
    'erase removes plaintext left in free pages by an older connection',
    () async {
      final directory = await Directory.systemTemp.createTemp('hb_erase_bytes');
      final file = File('${directory.path}/ledger.sqlite');
      final marker = List.filled(100, 'PRIVATE_SYNTHETIC_MARKER').join();
      var db = AppDatabase(NativeDatabase(file));
      try {
        await db.customSelect('SELECT 1').get();
        await db.customStatement('PRAGMA secure_delete = OFF');
        await db.customStatement('CREATE TABLE retired_data (note TEXT)');
        await db.customStatement('INSERT INTO retired_data VALUES (?)', [
          marker,
        ]);
        await db.customStatement('DROP TABLE retired_data');
        await db.close();
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          contains('PRIVATE_SYNTHETIC_MARKER'),
        );
        db = AppDatabase(NativeDatabase(file));
        SharedPreferences.setMockInitialValues({});
        final settings = SettingsRepository(
          await SharedPreferences.getInstance(),
          defaultCurrency: 'USD',
        );
        await BackupService(db, settings).eraseEverything();
        await db.close();
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(contains('PRIVATE_SYNTHETIC_MARKER')),
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

  test('last backup is remembered, and is null until then', () async {
    expect(settings.load().lastBackupAt, isNull);
    final when = DateTime.utc(2026, 10, 25, 12, 30);
    await settings.setLastBackupAt(when);
    expect(settings.load().lastBackupAt!.isAtSameMomentAs(when), isTrue);
  });

  test(
    'last backup is not part of a backup file or restored from one',
    () async {
      await settings.setLastBackupAt(DateTime.utc(2026, 10, 25));
      final data = await service.snapshot(now: DateTime.utc(2026, 10, 25));
      expect(data.settings.toJson().keys, isNot(contains('lastBackupAt')));
      expect(data.encode(), isNot(contains('last_backup')));
      expect(data.encode(), isNot(contains('lastBackup')));
    },
  );

  test(
    'eraseEverything removes all data and puts the default categories back',
    () async {
      final cats = CategoryRepository(db);
      final extra = await cats.add('Gadgets', TransactionType.expense);
      final food = (await cats.watchAll().first).firstWhere(
        (c) => c.name == 'Food',
      );
      await TransactionRepository(db).add(
        TransactionInput(
          amountCents: 100,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 25),
          categoryId: extra.id,
          title: 'x',
        ),
      );
      await FavoriteRepository(db).add(
        FavoriteInput(
          label: 'F',
          type: TransactionType.expense,
          categoryId: food.id,
        ),
      );
      await RecurringRepository(db).addWithRule(
        TransactionInput(
          amountCents: 100,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 25),
          categoryId: food.id,
        ),
        RecurringInput(
          amountCents: 100,
          type: TransactionType.expense,
          categoryId: food.id,
          unit: RecurrenceUnit.month,
          interval: 1,
          start: DateTime(2026, 10, 25),
        ),
      );
      await settings.setCurrencyCode('BDT');
      await settings.setOnboardingDone(true);
      await settings.setLastBackupAt(DateTime.utc(2026, 10, 25));

      await service.eraseEverything();

      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.favorites).get(), isEmpty);
      expect(await db.select(db.recurringRules).get(), isEmpty);
      final names = (await db.select(db.categories).get())
          .map((c) => c.name)
          .toList();
      expect(names, hasLength(13));
      expect(names, isNot(contains('Gadgets')));
      expect(names, containsAll(['Food', 'Rent', 'Salary']));
      final s = settings.load();
      expect(s.currency.code, 'USD', reason: 'back to the default');
      expect(s.onboardingDone, isFalse);
      expect(s.lastBackupAt, isNull);
    },
  );

  test('the app can be used again straight after', () async {
    await service.eraseEverything();
    final cats = await CategoryRepository(db).watchAll().first;
    final food = cats.firstWhere((c) => c.name == 'Food');
    await TransactionRepository(db).add(
      TransactionInput(
        amountCents: 500,
        type: TransactionType.expense,
        date: DateTime(2026, 10, 25),
        categoryId: food.id,
      ),
    );
    expect(await db.select(db.transactions).get(), hasLength(1));
    // Protected "Other" categories exist again.
    expect(cats.where((c) => c.isProtected), hasLength(2));
  });

  test(
    'settings failure still deletes safety copies and reports committed erase',
    () async {
      final dir = await Directory.systemTemp.createTemp('hb_erase');
      addTearDown(() => dir.delete(recursive: true));
      final copy = await File('${dir.path}/heisenbudget.before-v3.sqlite')
          .writeAsString('sensitive copy');
      final failing = _FailingSettings(await SharedPreferences.getInstance());
      final service = BackupService(db, failing, files: DatabaseFiles(dir));
      await expectLater(
        service.eraseEverything(),
        throwsA(
          isA<EraseCleanupException>().having((e) => e.remaining, 'remaining', {
            EraseCleanupStep.settings,
          }),
        ),
      );
      expect(await copy.exists(), isFalse);
      expect(await db.select(db.transactions).get(), isEmpty);
      failing.fail = false;
      await service.completeEraseCleanup();
      expect(failing.load().onboardingDone, isFalse);
    },
  );

  test('cleanup retry preserves newly entered transactions', () async {
    final dir = await Directory.systemTemp.createTemp('hb_erase');
    addTearDown(() => dir.delete(recursive: true));
    final files = _FailingCopies(dir);
    final service = BackupService(db, settings, files: files);
    await expectLater(
      service.eraseEverything(),
      throwsA(
        isA<EraseCleanupException>().having((e) => e.remaining, 'remaining', {
          EraseCleanupStep.safetyCopies,
        }),
      ),
    );
    final category = (await db.select(db.categories).get()).firstWhere(
      (c) => c.name == 'Food',
    );
    await TransactionRepository(db).add(
      TransactionInput(
        amountCents: 1234,
        type: TransactionType.expense,
        date: DateTime(2026, 10, 15),
        categoryId: category.id,
      ),
    );
    files.fail = false;
    await service.completeEraseCleanup();
    expect((await db.select(db.transactions).get()).single.amountCents, 1234);
  });
}
