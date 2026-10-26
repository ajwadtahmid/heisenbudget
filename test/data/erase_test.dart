import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/favorite_repository.dart';
import 'package:heisenbudget/data/repositories/recurring_repository.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
