import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/domain/budget.dart';
import 'package:heisenbudget/domain/recurrence.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../generated_migrations/schema.dart';

/// Every table, index and column of a database, as text, so two databases can
/// be compared.
Future<List<String>> shapeOf(AppDatabase db) async {
  final out = <String>[];
  final master = await db
      .customSelect(
        'SELECT type, name FROM sqlite_master '
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
      )
      .get();
  for (final row in master) {
    final type = row.read<String>('type');
    final name = row.read<String>('name');
    out.add('$type $name');
    if (type != 'table') continue;
    final columns = await db.customSelect('PRAGMA table_info($name)').get();
    for (final c in columns) {
      out.add(
        '  ${c.read<String>('name')} ${c.read<String>('type')} '
        'notnull=${c.read<int>('notnull')} '
        'default=${c.data['dflt_value']} pk=${c.read<int>('pk')}',
      );
    }
  }
  return out;
}

void main() {
  group('schema 3, the first public schema', () {
    test(
      'a new database has exactly the shape frozen in drift_schemas',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final frozen = AppDatabase(await verifier.startAt(3));
        final fresh = AppDatabase.memory();
        addTearDown(frozen.close);
        addTearDown(fresh.close);
        expect(await shapeOf(fresh), await shapeOf(frozen));
      },
    );

    test('the code agrees with the frozen schema', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final db = AppDatabase(await verifier.startAt(3));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);
    });

    test(
      'the version is 3 and new databases start with default categories',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), currentSchemaVersion);
        expect(currentSchemaVersion, 3);
        expect(await db.select(db.categories).get(), isNotEmpty);
      },
    );

    test('category names are unique per type, ignoring case', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      Future<void> add(String name, TransactionType type) => db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(name: name, type: type));
      await add('Pets', TransactionType.expense);
      expect(
        () => add('PETS', TransactionType.expense),
        throwsA(isA<Exception>()),
      );
      await add('Pets', TransactionType.income); // another type is fine
    });

    test('budget limits are unique per category and first day', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      Future<void> add(int? cat, String start) => db
          .into(db.budgetLimits)
          .insert(
            BudgetLimitsCompanion.insert(
              categoryId: Value(cat),
              lengthDays: 0,
              lengthMonths: const Value(1),
              start: start,
              amountCents: const Value(5000),
              createdAt: DateTime(2026, 10, 25),
            ),
          );
      await add(1, '2026-10-01');
      await add(null, '2026-10-01');
      expect(() => add(1, '2026-10-01'), throwsA(isA<Exception>()));
      expect(() => add(null, '2026-10-01'), throwsA(isA<Exception>()));
      await add(1, '2026-11-01');
      expect(BudgetUnit.month.months, 1);
    });

    test('a repeating rule makes at most one transaction a day', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cats = await db.select(db.categories).get();
      final food = cats.firstWhere((c) => c.type == TransactionType.expense);
      final ruleId = await db
          .into(db.recurringRules)
          .insert(
            RecurringRulesCompanion.insert(
              amountCents: 100,
              type: TransactionType.expense,
              categoryId: food.id,
              unit: RecurrenceUnit.week,
              startDate: '2026-10-05',
              createdAt: DateTime(2026, 10, 5),
            ),
          );
      Future<void> tx() => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              amountCents: 100,
              type: TransactionType.expense,
              date: '2026-10-05',
              categoryId: food.id,
              createdAt: DateTime(2026, 10, 5),
              updatedAt: DateTime(2026, 10, 5),
              recurringRuleId: Value(ruleId),
            ),
          );
      await tx();
      expect(tx, throwsA(isA<Exception>()));
    });

    test('a database at another version is refused, not guessed at', () async {
      final dir = await Directory.systemTemp.createTemp('hb_versions');
      addTearDown(() => dir.delete(recursive: true));
      for (final version in [2, 4]) {
        final file = File('${dir.path}/v$version.sqlite');
        final first = AppDatabase(NativeDatabase(file));
        await first.customSelect('SELECT 1').get();
        await first.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('PRAGMA user_version = $version');
        raw.close();

        final db = AppDatabase(NativeDatabase(file));
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<Object>()),
          reason: 'schema $version',
        );
        await db.close();
      }
    });
  });
}
