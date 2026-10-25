import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/core/category_icons.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

void main() {
  const expenseNames = [
    'Food',
    'Rent',
    'Shopping',
    'Medical',
    'Travel',
    'Transport',
    'Bills',
    'Entertainment',
    'Other',
  ];
  const incomeNames = ['Salary', 'Freelance', 'Gift', 'Other'];

  test('seeding creates exactly the default categories', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    final rows = await db.select(db.categories).get();
    List<String> names(TransactionType type) =>
        rows.where((c) => c.type == type).map((c) => c.name).toList();

    expect(names(TransactionType.expense), expenseNames);
    expect(names(TransactionType.income), incomeNames);
    expect(rows.every((c) => c.isDefault && !c.isArchived), isTrue);
    expect(rows.where((c) => c.isProtected).map((c) => c.name), [
      'Other',
      'Other',
    ]);
  });

  test('default categories come with icons', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final rows = await db.select(db.categories).get();
    String icon(String name, TransactionType type) =>
        rows.firstWhere((c) => c.name == name && c.type == type).icon;

    expect(icon('Food', TransactionType.expense), 'restaurant');
    expect(icon('Rent', TransactionType.expense), 'home');
    expect(icon('Transport', TransactionType.expense), 'bus');
    expect(icon('Salary', TransactionType.income), 'salary');
    expect(icon('Gift', TransactionType.income), 'gift');
    expect(icon('Other', TransactionType.expense), 'category');
    expect(icon('Other', TransactionType.income), 'category');
    // Every seeded key is a real, pickable icon.
    for (final c in rows) {
      expect(categoryIcons.map((o) => o.key), contains(c.icon), reason: c.name);
    }
  });

  test('re-opening an existing database does not duplicate the seed', () async {
    final dir = await Directory.systemTemp.createTemp('heisenbudget_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    final first = AppDatabase(NativeDatabase(file));
    expect((await first.select(first.categories).get()).length, 13);
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    expect((await second.select(second.categories).get()).length, 13);
  });

  test('foreign keys are enforced', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);

    expect(
      () => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              amountCents: 100,
              type: TransactionType.expense,
              date: '2026-10-01',
              categoryId: 9999,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test('amount must be positive (CHECK constraint)', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final food = await (db.select(
      db.categories,
    )..where((c) => c.name.equals('Food'))).getSingle();

    expect(
      () => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              amountCents: 0,
              type: TransactionType.expense,
              date: '2026-10-01',
              categoryId: food.id,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'category names are unique per type, ignoring case (DB index)',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

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
      // Same name under the other type is fine.
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Food',
              type: TransactionType.income,
            ),
          );
    },
  );

  test(
    'indexes exist on transactions(date) and transactions(category_id)',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'transactions'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();
      expect(
        names,
        containsAll(['transactions_date', 'transactions_category']),
      );
    },
  );
}
