import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/features/settings/csv_import_screen.dart';

import 'backup_ui_test.dart' show FakeFileExchange, openSettings, tapTile;
import 'test_helpers.dart';

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

const _good =
    'Date,Type,Category,Title,Amount,Note\n'
    '2026-10-03,Expense,Food,Lunch,12.50,\n'
    '2026-10-04,Income,Salary,,2000,\n';

Future<FakeFileExchange> start(
  WidgetTester tester,
  TestEnv env,
  Uint8List? file,
) async {
  final exchange = FakeFileExchange()..toPickCsv = file;
  await openSettings(tester, env, exchange);
  return exchange;
}

Future<void> pickAndOpen(WidgetTester tester) async {
  // Rows far down the page are built only when scrolled to.
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('import-csv')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tapTile(tester, 'import-csv');
}

bool importEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('csv-import')))
        .onPressed !=
    null;

void main() {
  group('a good file', () {
    testWidgets('shows what will be added, then imports it', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env, text(_good));
      await pickAndOpen(tester);

      expect(find.byType(CsvImportScreen), findsOneWidget);
      expect(find.textContaining('2 rows found'), findsOneWidget);
      expect(find.text('2 transactions will be added.'), findsOneWidget);
      expect(find.byKey(const ValueKey('csv-bad')), findsNothing);

      await tapTile(tester, 'csv-import');

      expect(find.byType(CsvImportScreen), findsNothing);
      expect(find.text('Imported 2 transactions'), findsOneWidget);
      final saved = await savedTransactions(tester, env);
      expect(saved.length, 2);
      await disposeEnv(tester, env);
    });

    testWidgets('going back adds nothing', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env, text(_good));
      await pickAndOpen(tester);
      await tester.pageBack();
      await settle(tester);

      expect(find.byType(CsvImportScreen), findsNothing);
      expect(await savedTransactions(tester, env), isEmpty);
      await disposeEnv(tester, env);
    });

    testWidgets('cancelling the picker does nothing', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env, null);
      await pickAndOpen(tester);

      expect(find.byType(CsvImportScreen), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await disposeEnv(tester, env);
    });
  });

  group('a file that is wrong is refused with the reason', () {
    Future<void> refused(
      WidgetTester tester,
      Uint8List file,
      String message,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env, file);
      await pickAndOpen(tester);

      expect(find.text(message), findsOneWidget);
      expect(find.byType(CsvImportScreen), findsNothing);
      expect(await savedTransactions(tester, env), isEmpty);
      await disposeEnv(tester, env);
    }

    testWidgets('an empty file', (tester) async {
      await refused(tester, Uint8List(0), 'That file is empty.');
    });

    testWidgets('only blank lines', (tester) async {
      await refused(tester, text('\n\r\n  \n'), 'That file is empty.');
    });

    testWidgets('a picture or other binary file', (tester) async {
      await refused(
        tester,
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0]),
        'That does not look like a text file. Choose a .csv file.',
      );
    });

    testWidgets('a backup file', (tester) async {
      await refused(
        tester,
        text('{"app":"heisenbudget","format":1}'),
        'This is a JSON file, not a CSV. If it is a Heisenbudget backup, use '
        'Restore from backup instead.',
      );
    });

    testWidgets('one column of text', (tester) async {
      await refused(
        tester,
        text('hello\nworld\n'),
        'This does not look like a table of transactions: it needs at least '
        'a date column and an amount column.',
      );
    });

    testWidgets('a quoted value that is never closed', (tester) async {
      await refused(
        tester,
        text('Date,Amount\n2026-10-03,"5\n'),
        'The file looks damaged: a quoted value that starts on line 2 is '
        'never closed.',
      );
    });

    testWidgets('a file that is too large', (tester) async {
      final env = await createEnv(tester);
      final exchange = FakeFileExchange()
        ..csvPickError = const BackupFormatException(
          'That file is too large to import. Split it into smaller parts.',
        );
      await openSettings(tester, env, exchange);
      await pickAndOpen(tester);

      expect(
        find.text(
          'That file is too large to import. Split it into smaller parts.',
        ),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('anything unexpected says nothing was changed', (tester) async {
      final env = await createEnv(tester);
      final exchange = FakeFileExchange()..csvPickError = StateError('boom');
      await openSettings(tester, env, exchange);
      await pickAndOpen(tester);

      expect(
        find.text('Something went wrong. Nothing was changed.'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });

    testWidgets('a header and nothing under it', (tester) async {
      final env = await createEnv(tester);
      await start(tester, env, text('Date,Amount\n'));
      await pickAndOpen(tester);

      expect(find.byKey(const ValueKey('csv-why')), findsOneWidget);
      expect(find.textContaining('no transactions'), findsOneWidget);
      expect(importEnabled(tester), isFalse);
      await disposeEnv(tester, env);
    });
  });

  group('a file that is partly wrong', () {
    testWidgets('lists the rows it cannot read and imports the rest', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(
        tester,
        env,
        text(
          'Date,Amount\n'
          '2026-10-03,-12.50\n'
          'sometime,-5\n'
          '2026-10-05,lots\n',
        ),
      );
      await pickAndOpen(tester);

      expect(find.text('1 transaction will be added.'), findsOneWidget);
      expect(
        find.text('2 rows cannot be read and will be left out.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('csv-bad-list')));
      await tester.tap(find.byKey(const ValueKey('csv-bad-list')));
      await settle(tester);
      expect(
        find.text(
          'Line 3: The date "sometime" could not be read with this date order',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Line 4: The amount "lots" is not a number'),
        findsOneWidget,
      );

      await tapTile(tester, 'csv-import');
      expect(find.text('Imported 1 transaction'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('when no row can be read, it says so and cannot import', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env, text('Date,Amount\nsometime,5\nlater,6\n'));
      await pickAndOpen(tester);

      expect(
        find.textContaining('None of the rows could be read'),
        findsOneWidget,
      );
      expect(importEnabled(tester), isFalse);
      await disposeEnv(tester, env);
    });

    testWidgets('columns that cannot be guessed ask for a choice', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await start(tester, env, text('Foo,Bar\nabc,def\nghi,jkl\n'));
      await pickAndOpen(tester);

      expect(
        find.text('Choose the columns that hold the date and the amount.'),
        findsOneWidget,
      );
      expect(importEnabled(tester), isFalse);
      await disposeEnv(tester, env);
    });

    testWidgets('a file in another encoding carries a warning', (tester) async {
      final env = await createEnv(tester);
      await start(
        tester,
        env,
        Uint8List.fromList([
          ...ascii.encode('Date,Title,Amount\n2026-10-03,Caf'),
          0xE9,
          ...ascii.encode(',-4\n'),
        ]),
      );
      await pickAndOpen(tester);

      expect(find.byKey(const ValueKey('csv-encoding-note')), findsOneWidget);
      await disposeEnv(tester, env);
    });
  });

  group('what is already here', () {
    testWidgets('is skipped, and can be kept', (tester) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 1250, DateTime(2026, 10, 3));
      await start(
        tester,
        env,
        text('Date,Amount\n2026-10-03,-12.50\n2026-10-04,-3\n'),
      );
      await pickAndOpen(tester);

      expect(find.text('1 transaction will be added.'), findsOneWidget);
      expect(find.text('1 already here, skipped.'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('csv-skip-duplicates')),
      );
      await tester.tap(find.byKey(const ValueKey('csv-skip-duplicates')));
      await settle(tester);
      expect(find.text('2 transactions will be added.'), findsOneWidget);
      expect(find.byKey(const ValueKey('csv-duplicates')), findsNothing);
      await disposeEnv(tester, env);
    });

    testWidgets('a file that is all duplicates cannot be imported', (
      tester,
    ) async {
      final env = await createEnv(tester);
      await addExpense(tester, env, 1250, DateTime(2026, 10, 3));
      await start(tester, env, text('Date,Amount\n2026-10-03,-12.50\n'));
      await pickAndOpen(tester);

      expect(
        find.text('Everything in this file is already here.'),
        findsOneWidget,
      );
      expect(importEnabled(tester), isFalse);
      await disposeEnv(tester, env);
    });
  });

  group('categories', () {
    testWidgets('new ones are named, and can be turned off', (tester) async {
      final env = await createEnv(tester);
      await start(
        tester,
        env,
        text('Date,Category,Amount\n2026-10-03,Pets,-5\n'),
      );
      await pickAndOpen(tester);

      expect(find.text('New categories: Pets.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('csv-create-categories')),
      );
      await tester.tap(find.byKey(const ValueKey('csv-create-categories')));
      await settle(tester);
      expect(find.byKey(const ValueKey('csv-new-categories')), findsNothing);
      expect(find.text('1 will go to Other.'), findsOneWidget);
      await disposeEnv(tester, env);
    });

    testWidgets('the result says how many were made', (tester) async {
      final env = await createEnv(tester);
      await start(
        tester,
        env,
        text('Date,Category,Amount\n2026-10-03,Pets,-5\n'),
      );
      await pickAndOpen(tester);
      await tapTile(tester, 'csv-import');

      expect(
        find.text('Imported 1 transaction · 1 new category'),
        findsOneWidget,
      );
      await disposeEnv(tester, env);
    });
  });

  group('large text', () {
    testWidgets('the page fits at 200% text on a narrow screen', (
      tester,
    ) async {
      final env = await createEnv(tester);
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await start(
        tester,
        env,
        text(
          'Date,Description,Debit,Credit\n'
          '03/10/2026,A very long description of a purchase,12.50,\n'
          'bad,x,,\n',
        ),
      );
      await pickAndOpen(tester);

      expect(find.byType(CsvImportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeEnv(tester, env);
    });
  });
}
