import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/csv_export.dart';
import 'package:heisenbudget/data/backup/csv_import.dart';
import 'package:heisenbudget/data/backup/csv_importer.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/repositories/category_repository.dart';
import 'package:heisenbudget/data/repositories/transaction_repository.dart';
import 'package:heisenbudget/domain/transaction_type.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

String say(Object Function() run) {
  try {
    run();
  } on BackupFormatException catch (e) {
    return e.message;
  }
  return 'no error';
}

List<ImportRow> rowsOf(String csv, {void Function(CsvMapping)? tweak}) {
  final table = parseCsv(csv);
  final m = guessMapping(table);
  tweak?.call(m);
  return readRows(table, m);
}

void main() {
  group('decoding a file', () {
    test('an empty file is refused', () {
      expect(say(() => decodeCsvBytes(Uint8List(0))), 'That file is empty.');
      expect(
        say(() => decodeCsvBytes(bytes('  \n \r\n'))),
        'That file is empty.',
      );
    });

    test('a binary file is refused as not text', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 13]);
      expect(
        say(() => decodeCsvBytes(png)),
        'That does not look like a text file. Choose a .csv file.',
      );
    });

    test('a file made mostly of control characters is refused', () {
      final junk = Uint8List.fromList(List.generate(200, (i) => i % 8 + 1));
      expect(say(() => decodeCsvBytes(junk)), contains('text file'));
    });

    test('a JSON file is refused and points at Restore', () {
      expect(
        say(() => decodeCsvBytes(bytes('{"app":"heisenbudget"}'))),
        contains('use Restore from backup'),
      );
    });

    test('a file over the size limit is refused', () {
      final big = Uint8List(maxCsvBytes + 1)..fillRange(0, maxCsvBytes + 1, 65);
      expect(say(() => decodeCsvBytes(big)), contains('too large'));
    });

    test('UTF-8 with a byte-order mark is read without the mark', () {
      final text = decodeCsvBytes(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Date,Amount')]),
      );
      expect(text.text, 'Date,Amount');
      expect(text.guessedEncoding, isFalse);
    });

    test('UTF-16 from Excel is read', () {
      final units = 'Date\tAmount\r\n2026-10-03\t5'.codeUnits;
      final out = <int>[0xFF, 0xFE];
      for (final u in units) {
        out
          ..add(u & 0xFF)
          ..add(u >> 8);
      }
      final text = decodeCsvBytes(Uint8List.fromList(out)).text;
      expect(text, startsWith('Date\tAmount'));
    });

    test('text that is not UTF-8 is read as Latin-1 and flagged', () {
      final text = decodeCsvBytes(
        Uint8List.fromList([
          ...ascii.encode('Caf'),
          0xE9,
          ...ascii.encode(',5'),
        ]),
      );
      expect(text.text, 'Café,5');
      expect(text.guessedEncoding, isTrue);
    });
  });

  group('reading CSV text', () {
    test('quotes, doubled quotes and line breaks inside a cell', () {
      final t = parseCsv('a,b\r\n"x, y","say ""hi""\nthere"\r\n');
      expect(t.rows[1], ['x, y', 'say "hi"\nthere']);
    });

    test('semicolons, tabs and bare returns work', () {
      expect(parseCsv('a;b;c\n1;2;3').rows[1], ['1', '2', '3']);
      expect(parseCsv('a\tb\n1\t2').delimiter, '\t');
      expect(parseCsv('a,b\r1,2\r3,4').rows.length, 3);
    });

    test('blank lines are skipped and rows keep their line number', () {
      final t = parseCsv('a,b\n\n1,2\n\n"x\ny",3\n');
      expect(t.rows.length, 3);
      expect(t.lines, [1, 3, 5]);
    });

    test('a quote that is never closed names the line', () {
      expect(
        say(() => parseCsv('a,b\n1,"oops\n2,3')),
        contains('starts on line 2'),
      );
    });
  });

  group('guessing the columns', () {
    test('the app\'s own export', () {
      final m = guessMapping(
        parseCsv(
          'Date,Type,Category,Title,Amount,Note\r\n'
          '2026-10-03,Expense,Food,Lunch,12.50,\r\n',
        ),
      );
      expect(
        [m.date, m.type, m.category, m.title, m.amount, m.note],
        [0, 1, 2, 3, 4, 5],
      );
      expect(m.hasHeader, isTrue);
      expect(m.order, DateOrder.ymd);
    });

    test('separate money out and money in columns', () {
      final m = guessMapping(
        parseCsv('Date,Description,Debit,Credit\n03/10/2026,Shop,12.50,\n'),
      );
      expect([m.date, m.title, m.moneyOut, m.moneyIn], [0, 1, 2, 3]);
      expect(m.amount, isNull);
    });

    test('no header: columns are found from what the cells look like', () {
      final m = guessMapping(
        parseCsv('2026-10-03,Coffee,-3.20\n2026-10-04,Pay,2000.00\n'),
      );
      expect(m.hasHeader, isFalse);
      expect(m.date, 0);
      expect(m.amount, 2);
    });

    test('day-first is found when a day is above 12', () {
      final m = guessMapping(
        parseCsv('Date,Amount\n25/12/2026,5\n03/10/2026,5\n'),
      );
      expect(m.order, DateOrder.dmy);
    });

    test('month-first is found when the second part is above 12', () {
      final m = guessMapping(parseCsv('Date,Amount\n12/25/2026,5\n'));
      expect(m.order, DateOrder.mdy);
    });
  });

  group('dates', () {
    test('formats and orders', () {
      expect(
        parseImportDate('2026-10-03', DateOrder.ymd),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('03/10/2026', DateOrder.dmy),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('03/10/2026', DateOrder.mdy),
        DateTime(2026, 3, 10),
      );
      expect(parseImportDate('3.10.26', DateOrder.dmy), DateTime(2026, 10, 3));
      expect(
        parseImportDate('Oct 3, 2026', DateOrder.dmy),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('3 October 2026', DateOrder.mdy),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('2026-10-03T14:30:00Z', DateOrder.ymd),
        DateTime(2026, 10, 3),
      );
      expect(
        parseImportDate('03/10/2026 14:30', DateOrder.dmy),
        DateTime(2026, 10, 3),
      );
    });

    test('impossible or out of range dates are refused', () {
      expect(parseImportDate('2026-02-30', DateOrder.ymd), isNull);
      expect(parseImportDate('31/04/2026', DateOrder.dmy), isNull);
      expect(parseImportDate('1850-01-01', DateOrder.ymd), isNull);
      expect(parseImportDate('3500-01-01', DateOrder.ymd), isNull);
      expect(parseImportDate('soon', DateOrder.ymd), isNull);
      expect(parseImportDate('', DateOrder.ymd), isNull);
    });
  });

  group('rows', () {
    test('the sign decides income or expense without a type column', () {
      final rows = rowsOf('Date,Amount\n2026-10-03,-12.50\n2026-10-04,2000\n');
      expect(rows[0].type, TransactionType.expense);
      expect(rows[0].cents, 1250);
      expect(rows[1].type, TransactionType.income);
      expect(rows[1].cents, 200000);
    });

    test('positive can be spending', () {
      final rows = rowsOf(
        'Date,Amount\n2026-10-03,12.50\n',
        tweak: (m) => m.positiveIsExpense = true,
      );
      expect(rows.single.type, TransactionType.expense);
    });

    test('currency symbols, brackets, thousands and trailing minus', () {
      final rows = rowsOf(
        'Date,Amount\n'
        '2026-10-01,"\$1,234.56"\n'
        '2026-10-02,(45.00)\n'
        '2026-10-03,12.50-\n'
        '2026-10-04,"1.234,56 €"\n'
        '2026-10-05,−7\n',
      );
      expect(rows.map((r) => r.cents), [123456, 4500, 1250, 123456, 700]);
      expect(rows.map((r) => r.type), [
        TransactionType.income,
        TransactionType.expense,
        TransactionType.expense,
        TransactionType.income,
        TransactionType.expense,
      ]);
    });

    test('bad rows say why and the rest are still read', () {
      final rows = rowsOf(
        'Date,Amount\n'
        '2026-10-01,5\n'
        ',5\n'
        '2026-13-45,5\n'
        '2026-10-04,abc\n'
        '2026-10-05,0\n'
        '2026-10-06,999999999999\n'
        '2026-10-07,\n',
      );
      expect(rows.where((r) => r.ok).length, 1);
      expect(rows[1].error, 'There is no date');
      expect(rows[2].error, contains('could not be read'));
      expect(rows[3].error, contains('not a number'));
      expect(rows[4].error, 'The amount is zero');
      expect(rows[5].error, 'The amount is too large');
      expect(rows[6].error, 'There is no amount');
      expect(rows.map((r) => r.line), [2, 3, 4, 5, 6, 7, 8]);
    });

    test('a type column, and a type that cannot be told', () {
      final rows = rowsOf(
        'Date,Type,Amount\n'
        '2026-10-01,Income,5\n'
        '2026-10-02,Expense,5\n'
        '2026-10-03,Transfer,5\n'
        '2026-10-04,,5\n'
        '2026-10-05,,-5\n',
      );
      expect(rows[0].type, TransactionType.income);
      expect(rows[1].type, TransactionType.expense);
      expect(rows[2].error, 'The type "Transfer" is not income or expense');
      expect(rows[3].error, 'It is not clear if this is income or expense');
      expect(rows[4].type, TransactionType.expense);
    });

    test('money out and money in', () {
      final rows = rowsOf(
        'Date,Debit,Credit\n'
        '2026-10-01,5.00,\n'
        '2026-10-02,,9.00\n'
        '2026-10-03,1.00,2.00\n'
        '2026-10-04,,\n',
      );
      expect(rows[0].type, TransactionType.expense);
      expect(rows[1].type, TransactionType.income);
      expect(rows[2].error, 'Both money out and money in are filled');
      expect(rows[3].error, isNotNull);
    });

    test('a long title is cut and kept whole in the note', () {
      final title = 'A' * 60;
      final row = rowsOf('Date,Amount,Title\n2026-10-01,5,$title\n').single;
      expect(row.title.length, 40);
      expect(row.note, title);
      expect(row.shortened, isTrue);
    });

    test('too many rows and no rows are refused', () {
      final big = StringBuffer('Date,Amount\n');
      for (var i = 0; i <= maxImportRows; i++) {
        big.writeln('2026-10-01,1');
      }
      expect(say(() => rowsOf(big.toString())), contains('Import up to'));
      expect(say(() => rowsOf('Date,Amount\n')), contains('no transactions'));
    });

    test('short rows do not crash', () {
      final rows = rowsOf('Date,Amount,Note\n2026-10-01\n2026-10-02,5\n');
      expect(rows[0].error, 'There is no amount');
      expect(rows[1].ok, isTrue);
    });
  });

  group('a bank file in another style', () {
    test('semicolons, dotted day-first dates and decimal commas', () {
      final rows = rowsOf(
        'Datum;Betrag;Text\n03.10.2026;-12,50;Shop\n04.10.2026;1.234,56;Pay\n',
      );
      expect(rows.map((r) => r.ok), [true, true]);
      expect(rows[0].date, DateTime(2026, 10, 3));
      expect(rows[0].cents, 1250);
      expect(rows[0].type, TransactionType.expense);
      expect(rows[1].cents, 123456);
      expect(rows[1].type, TransactionType.income);
    });
  });

  group('the app\'s own export comes back in', () {
    test('every field survives, including a formula-looking note', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final cats = CategoryRepository(db);
      final txs = TransactionRepository(db);
      final food = (await cats.watchAll().first).firstWhere(
        (c) => c.name == 'Food',
      );
      await txs.add(
        TransactionInput(
          amountCents: 1250,
          type: TransactionType.expense,
          date: DateTime(2026, 10, 3),
          categoryId: food.id,
          title: 'Lunch, with "friends"',
          note: '=SUM(A1)',
        ),
      );
      final csv = buildTransactionsCsv(await txs.watchFiltered().first);
      final row = rowsOf(csv).single;
      expect(row.date, DateTime(2026, 10, 3));
      expect(row.cents, 1250);
      expect(row.type, TransactionType.expense);
      expect(row.category, 'Food');
      expect(row.title, 'Lunch, with "friends"');
      expect(row.note, '=SUM(A1)');
    });
  });

  group('importing', () {
    late AppDatabase db;
    late CsvImporter importer;
    late TransactionRepository txs;
    late CategoryRepository cats;

    setUp(() {
      db = AppDatabase.memory();
      importer = CsvImporter(db);
      txs = TransactionRepository(db);
      cats = CategoryRepository(db);
    });

    tearDown(() => db.close());

    Future<ImportResult> run(
      String csv, {
      bool create = true,
      bool skip = true,
    }) => importer.import(
      rowsOf(csv),
      createCategories: create,
      skipDuplicates: skip,
    );

    test('adds the rows with the right category, title and note', () async {
      final result = await run(
        'Date,Type,Category,Title,Amount,Note\n'
        '2026-10-03,Expense,food,Lunch,12.50,with Sam\n'
        '2026-10-04,Income,Salary,,2000,\n',
      );
      expect(result.imported, 2);
      final rows = await txs.watchFiltered().first;
      final lunch = rows.firstWhere((r) => r.transaction.title == 'Lunch');
      expect(lunch.category.name, 'Food');
      expect(lunch.transaction.note, 'with Sam');
      expect(lunch.transaction.amountCents, 1250);
      final pay = rows.firstWhere((r) => r.transaction.amountCents == 200000);
      expect(pay.category.name, 'Salary');
      expect(pay.transaction.type, TransactionType.income);
    });

    test('creates the categories that do not exist, once each', () async {
      final result = await run(
        'Date,Category,Amount\n'
        '2026-10-01,Pets,-5\n'
        '2026-10-02,pets,-6\n'
        '2026-10-03,Gifts,7\n',
      );
      expect(result.categoriesCreated, 2);
      final names = (await cats.watchAll().first).map((c) => c.name);
      expect(names.where((n) => n.toLowerCase() == 'pets').length, 1);
      expect(names, contains('Gifts'));
    });

    test(
      'without creating, unknown and blank categories go to Other',
      () async {
        final result = await run(
          'Date,Category,Amount\n'
          '2026-10-01,Pets,-5\n'
          '2026-10-02,,-6\n',
          create: false,
        );
        expect(result.categoriesCreated, 0);
        final rows = await txs.watchFiltered().first;
        expect(rows.every((r) => r.category.isProtected), isTrue);
      },
    );

    test('a file with no category column puts everything in Other', () async {
      await run('Date,Amount\n2026-10-01,-5\n2026-10-02,9\n');
      final rows = await txs.watchFiltered().first;
      expect(rows.length, 2);
      expect(rows.every((r) => r.category.isProtected), isTrue);
    });

    test('a category name is not shared between income and expense', () async {
      await run(
        'Date,Category,Amount\n2026-10-01,Misc,-5\n2026-10-02,Misc,5\n',
      );
      final misc = (await cats.watchAll().first).where((c) => c.name == 'Misc');
      expect(misc.length, 2);
      expect(misc.map((c) => c.type).toSet().length, 2);
    });

    test('skips what is already here, one for one', () async {
      await run('Date,Title,Amount\n2026-10-03,Lunch,-12.50\n');
      final again = await run(
        'Date,Title,Amount\n'
        '2026-10-03,Lunch,-12.50\n'
        '2026-10-03,Lunch,-12.50\n'
        '2026-10-04,Lunch,-12.50\n',
      );
      // One copy existed, so one is skipped and the second is a new purchase.
      expect(again.duplicates, 1);
      expect(again.imported, 2);
      expect((await txs.watchFiltered().first).length, 3);
    });

    test('duplicates are kept when skipping is off', () async {
      await run('Date,Title,Amount\n2026-10-03,Lunch,-12.50\n');
      final again = await run(
        'Date,Title,Amount\n2026-10-03,Lunch,-12.50\n',
        skip: false,
      );
      expect(again.imported, 1);
      expect((await txs.watchFiltered().first).length, 2);
    });

    test('analysis matches what the import then does', () async {
      await run('Date,Amount\n2026-10-03,-5\n');
      final rows = rowsOf(
        'Date,Category,Amount\n2026-10-03,,-5\n2026-10-04,Pets,-6\n'
        '2026-10-05,Pets,-7\n',
      );
      final plan = await importer.analyze(
        rows,
        createCategories: true,
        skipDuplicates: true,
      );
      expect(plan.duplicates, 1);
      expect(plan.toImport.length, 2);
      expect(plan.newCategories, ['Pets']);
      final result = await importer.import(
        rows,
        createCategories: true,
        skipDuplicates: true,
      );
      expect(
        [result.imported, result.duplicates, result.categoriesCreated],
        [2, 1, 1],
      );
    });

    test('unreadable rows are left out and the rest go in', () async {
      final result = await run(
        'Date,Amount\n2026-10-01,5\nnot a date,5\n2026-10-03,abc\n',
      );
      expect(result.imported, 1);
    });

    test(
      'a failure part-way changes nothing, new categories included',
      () async {
        final rows = [
          ...rowsOf('Date,Category,Amount\n2026-10-01,Pets,-5\n'),
          // Zero cents breaks the table's own check when it is written.
          ImportRow(
            line: 9,
            date: DateTime(2026, 10, 2),
            cents: 0,
            type: TransactionType.expense,
            category: 'Gifts',
          ),
        ];
        final before = (await cats.watchAll().first).length;
        await expectLater(
          importer.import(rows, createCategories: true, skipDuplicates: true),
          throwsA(anything),
        );
        expect(await txs.watchFiltered().first, isEmpty);
        expect((await cats.watchAll().first).length, before);
      },
    );

    test('more than 50 new categories: the rest go to Other', () async {
      final csv = StringBuffer('Date,Category,Amount\n');
      for (var i = 0; i < 60; i++) {
        csv.writeln('2026-10-01,Cat$i,-1');
      }
      final plan = await importer.analyze(
        rowsOf(csv.toString()),
        createCategories: true,
        skipDuplicates: false,
      );
      expect(plan.newCategories.length, maxImportedCategories);
      expect(plan.toOther, 10);
    });

    test('a few thousand rows go in', () async {
      final csv = StringBuffer('Date,Amount\n');
      for (var i = 0; i < 3000; i++) {
        csv.writeln('2026-10-01,-${i + 1}');
      }
      final result = await run(csv.toString(), skip: false);
      expect(result.imported, 3000);
    });
  });
}
