import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/csv_export.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository txs;
  late CategoryRepository cats;

  setUp(() {
    db = AppDatabase.memory();
    txs = TransactionRepository(db);
    cats = CategoryRepository(db);
  });
  tearDown(() => db.close());

  Future<CategoryRow> category(String name, TransactionType type) async =>
      (await cats.watchAll().first).firstWhere(
        (c) => c.name == name && c.type == type,
      );

  Future<void> add(int cents, String date, CategoryRow cat, {String? note}) =>
      txs.add(
        TransactionInput(
          amountCents: cents,
          type: cat.type,
          date: DateTime.parse(date),
          categoryId: cat.id,
          note: note,
        ),
      );

  test('no transactions gives just the header', () async {
    expect(
      buildTransactionsCsv(await txs.getAll()),
      '﻿Date,Type,Category,Amount,Note\r\n',
    );
  });

  test('rows are oldest first with plain decimal amounts', () async {
    final food = await category('Food', TransactionType.expense);
    final salary = await category('Salary', TransactionType.income);
    await add(1250, '2026-10-05', food, note: 'Lunch');
    await add(500000, '2026-10-01', salary);
    await add(7, '2026-10-05', food);
    expect(
      buildTransactionsCsv(await txs.getAll()),
      '﻿Date,Type,Category,Amount,Note\r\n'
      '2026-10-01,Income,Salary,5000.00,\r\n'
      '2026-10-05,Expense,Food,12.50,Lunch\r\n'
      '2026-10-05,Expense,Food,0.07,\r\n',
    );
  });

  test('commas, quotes and line breaks are quoted', () async {
    final food = await category('Food', TransactionType.expense);
    await add(100, '2026-10-05', food, note: 'a, "b"\nc');
    final csv = buildTransactionsCsv(await txs.getAll());
    expect(csv, endsWith('2026-10-05,Expense,Food,1.00,"a, ""b""\nc"\r\n'));
  });

  test(
    'a note that would run as a spreadsheet formula is made plain text',
    () async {
      final food = await category('Food', TransactionType.expense);
      for (final lead in ['=', '+', '-', '@']) {
        await add(100, '2026-10-05', food, note: '${lead}SUM(A1)');
      }
      final csv = buildTransactionsCsv(await txs.getAll());
      for (final lead in ['=', '+', '-', '@']) {
        expect(csv, contains(",'${lead}SUM(A1)\r\n"));
      }
      expect(csv, isNot(contains(',=SUM')));
    },
  );

  test(
    'a category name is protected the same way and unicode is kept',
    () async {
      final odd = await cats.add('=Evil', TransactionType.expense);
      await add(100, '2026-10-05', odd, note: 'চা ☕');
      final csv = buildTransactionsCsv(await txs.getAll());
      expect(csv, contains("Expense,'=Evil,1.00,চা ☕"));
    },
  );
}
