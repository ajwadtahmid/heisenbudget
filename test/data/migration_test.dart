import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/domain/transaction_type.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Builds a database exactly as the first release (schema 1, no icon column)
/// created it, so the upgrade path is tested on real old data.
void createSchemaOneDatabase(String path) {
  final raw = sqlite.sqlite3.open(path);
  raw.execute('''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
      is_protected INTEGER NOT NULL DEFAULT 0 CHECK (is_protected IN (0, 1)),
      sort_order INTEGER NOT NULL DEFAULT 0
    );
    CREATE UNIQUE INDEX categories_type_name
      ON categories (type, name COLLATE NOCASE);
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
      type TEXT NOT NULL,
      date TEXT NOT NULL,
      category_id INTEGER NOT NULL REFERENCES categories (id),
      note TEXT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    CREATE INDEX transactions_date ON transactions (date);
    CREATE INDEX transactions_category ON transactions (category_id);
    INSERT INTO categories (name, type, is_default, is_protected, sort_order) VALUES
      ('Food', 'expense', 1, 0, 0),
      ('Other', 'expense', 1, 1, 1),
      ('Salary', 'income', 1, 0, 0),
      ('Other', 'income', 1, 1, 1);
    INSERT INTO categories (name, type, is_default, sort_order)
      VALUES ('Coffee', 'expense', 0, 2);
    INSERT INTO transactions
      (amount_cents, type, date, category_id, note, created_at, updated_at)
      VALUES (1250, 'expense', '2026-10-05', 1, 'lunch', 0, 0);
    PRAGMA user_version = 1;
  ''');
  raw.close();
}

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('heisenbudget_migration');
    file = File('${dir.path}/old.sqlite');
    createSchemaOneDatabase(file.path);
  });

  tearDown(() => dir.delete(recursive: true));

  test('upgrading from schema 1 adds icons and keeps all data', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final rows = await db.select(db.categories).get();
    String icon(String name, TransactionType type) =>
        rows.firstWhere((c) => c.name == name && c.type == type).icon;

    // Default categories get their icons...
    expect(icon('Food', TransactionType.expense), 'restaurant');
    expect(icon('Salary', TransactionType.income), 'salary');
    expect(icon('Other', TransactionType.expense), 'category');
    // ...a custom one keeps the general icon.
    expect(icon('Coffee', TransactionType.expense), 'category');

    // Nothing was lost.
    expect(rows, hasLength(5));
    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.amountCents, 1250);
    expect(txs.single.note, 'lunch');
    expect(txs.single.date, '2026-10-05');
  });

  test('the upgraded database is at schema 2 and fully usable', () async {
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 2);

    // The case-insensitive unique index survived the upgrade.
    expect(
      () => db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'food',
              type: TransactionType.expense,
            ),
          ),
      throwsA(isA<Exception>()),
    );
    // New rows accept an icon.
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: 'Pets',
            type: TransactionType.expense,
            icon: const Value('pets'),
          ),
        );
  });

  test('opening an upgraded database again changes nothing', () async {
    var db = AppDatabase(NativeDatabase(file));
    await db.select(db.categories).get();
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final rows = await db.select(db.categories).get();
    expect(rows, hasLength(5));
    expect(rows.firstWhere((c) => c.name == 'Food').icon, 'restaurant');
  });
}
