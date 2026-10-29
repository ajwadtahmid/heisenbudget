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
import '../generated_migrations/schema_v3.dart' show DatabaseAtV3;

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
  group('schema 4, the current schema', () {
    test(
      'a new database has exactly the shape frozen in drift_schemas',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final frozen = AppDatabase(await verifier.startAt(4));
        final fresh = AppDatabase.memory();
        addTearDown(frozen.close);
        addTearDown(fresh.close);
        expect(await shapeOf(fresh), await shapeOf(frozen));
      },
    );

    test('the code agrees with the frozen schema', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final db = AppDatabase(await verifier.startAt(4));
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);
    });

    test(
      'the version is 4 and new databases start with default categories',
      () async {
        final db = AppDatabase.memory();
        addTearDown(db.close);
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), currentSchemaVersion);
        expect(currentSchemaVersion, 4);
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
      for (final version in [2, 5]) {
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

  group('upgrading from schema 3, the first public schema', () {
    test('the upgraded database has exactly the shape of a new one', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final upgraded = AppDatabase(await verifier.startAt(3));
      final fresh = AppDatabase.memory();
      addTearDown(upgraded.close);
      addTearDown(fresh.close);
      await verifier.migrateAndValidate(upgraded, 4);
      expect(await shapeOf(upgraded), await shapeOf(fresh));
    });

    test(
      'everything saved at schema 3 survives, and goals start empty',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final schema = await verifier.schemaAt(3);
        final old = schema.newConnection();
        // One of everything a schema 3 database holds.
        final before = DatabaseAtV3(old);
        await before.customStatement("PRAGMA foreign_keys = ON");
        await before.customStatement(
          "INSERT INTO categories (id, name, type, icon, is_default, is_archived, is_protected, sort_order) "
          "VALUES (1, 'Food', 'expense', 'restaurant', 1, 0, 0, 0), "
          "(2, 'Salary', 'income', 'work', 1, 0, 0, 1)",
        );
        await before.customStatement(
          "INSERT INTO transactions (id, amount_cents, type, date, category_id, note, title, created_at, updated_at) "
          "VALUES (1, 1250, 'expense', '2026-10-05', 1, 'lunch', 'Cafe', 1790000000, 1790000000), "
          "(2, 300000, 'income', '2026-10-01', 2, NULL, NULL, 1790000000, 1790000000)",
        );
        await before.customStatement(
          "INSERT INTO budget_limits (id, category_id, length_days, length_months, repeats, start, amount_cents, created_at) "
          "VALUES (1, 1, 0, 1, 1, '2026-10-01', 50000, 1790000000)",
        );
        await before.customStatement(
          "INSERT INTO favorites (id, label, type, amount_cents, category_id, sort_order, created_at) "
          "VALUES (1, 'Coffee', 'expense', 400, 1, 0, 1790000000)",
        );
        await before.customStatement(
          "INSERT INTO recurring_rules (id, amount_cents, type, category_id, unit, interval, start_date, is_active, next_index, created_at) "
          "VALUES (1, 90000, 'expense', 1, 'month', 1, '2026-10-01', 1, 1, 1790000000)",
        );
        await before.close();

        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 4);

        Future<int> count(String table) async =>
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
        expect(await count('categories'), 2);
        expect(await count('transactions'), 2);
        expect(await count('budget_limits'), 1);
        expect(await count('favorites'), 1);
        expect(await count('recurring_rules'), 1);
        final tx = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals(1))).getSingle();
        expect(tx.amountCents, 1250);
        expect(tx.title, 'Cafe');
        expect(await count('savings_goals'), 0);
        expect(await count('goal_entries'), 0);

        // The new tables work straight away.
        final goal = await db
            .into(db.savingsGoals)
            .insert(
              SavingsGoalsCompanion.insert(
                name: 'Laptop',
                targetCents: 100000,
                createdAt: DateTime(2026, 10, 27),
              ),
            );
        await db
            .into(db.goalEntries)
            .insert(
              GoalEntriesCompanion.insert(
                goalId: goal,
                amountCents: 25000,
                date: '2026-10-27',
                createdAt: DateTime(2026, 10, 27),
              ),
            );
        expect(await count('goal_entries'), 1);
      },
    );

    test('the pre-4 versions are refused: only 3 is upgraded', () async {
      final dir = await Directory.systemTemp.createTemp('hb_versions_old');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/v2.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await first.close();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 2');
      raw.close();
      final db = AppDatabase(NativeDatabase(file));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<Object>()),
      );
      await db.close();
    });
  });

  group('savings goals and their entries', () {
    Future<int> addGoal(AppDatabase db) => db
        .into(db.savingsGoals)
        .insert(
          SavingsGoalsCompanion.insert(
            name: 'Trip',
            targetCents: 60000,
            createdAt: DateTime(2026, 10, 27),
          ),
        );

    test('a target must be above zero, an entry must not be zero', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await expectLater(
        db
            .into(db.savingsGoals)
            .insert(
              SavingsGoalsCompanion.insert(
                name: 'Nothing',
                targetCents: 0,
                createdAt: DateTime(2026, 10, 27),
              ),
            ),
        throwsA(isA<Exception>()),
      );
      final goal = await addGoal(db);
      Future<void> entry(int cents) => db
          .into(db.goalEntries)
          .insert(
            GoalEntriesCompanion.insert(
              goalId: goal,
              amountCents: cents,
              date: '2026-10-27',
              createdAt: DateTime(2026, 10, 27),
            ),
          );
      await expectLater(entry(0), throwsA(isA<Exception>()));
      await entry(-500); // taking money out is an entry too
      await entry(1500);
    });

    test('an entry must belong to a goal', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await expectLater(
        db
            .into(db.goalEntries)
            .insert(
              GoalEntriesCompanion.insert(
                goalId: 99,
                amountCents: 100,
                date: '2026-10-27',
                createdAt: DateTime(2026, 10, 27),
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });

    test('a goal with entries cannot be deleted from under them', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final goal = await addGoal(db);
      await db
          .into(db.goalEntries)
          .insert(
            GoalEntriesCompanion.insert(
              goalId: goal,
              amountCents: 100,
              date: '2026-10-27',
              createdAt: DateTime(2026, 10, 27),
            ),
          );
      await expectLater(
        db.delete(db.savingsGoals).go(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
