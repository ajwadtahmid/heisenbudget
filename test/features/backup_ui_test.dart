import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';
import 'package:heisenbudget/providers/backup_providers.dart';

import 'test_helpers.dart';

/// Stands in for the share sheet and the file picker.
class FakeFileExchange extends FileExchange {
  FakeFileExchange({this.toPick, this.shareFails = false});

  Uint8List? toPick;
  bool shareFails;
  final shared = <({String name, String mime, Uint8List bytes})>[];

  @override
  Future<void> shareFile({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    Rect? origin,
  }) async {
    if (shareFails) throw StateError('no share target');
    shared.add((name: fileName, mime: mimeType, bytes: bytes));
  }

  @override
  Future<Uint8List?> pickFile() async => toPick;
}

Uint8List backupBytes() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'app': 'heisenbudget',
      'format': 1,
      'exportedAt': '2026-10-25T12:00:00Z',
      'settings': {'currency': 'BDT', 'labFlavor': false},
      'categories': [
        {'id': 7, 'name': 'Tea', 'type': 'expense', 'icon': 'restaurant'},
        {'id': 8, 'name': 'Pay', 'type': 'income', 'icon': 'salary'},
      ],
      'transactions': [
        {
          'id': 1,
          'amountCents': 4500,
          'type': 'expense',
          'date': '2026-10-05',
          'categoryId': 7,
          'note': 'From backup',
          'createdAt': '2026-10-05T08:00:00Z',
          'updatedAt': '2026-10-05T08:00:00Z',
        },
      ],
    }),
  ),
);

Future<void> openSettings(
  WidgetTester tester,
  TestEnv env,
  FakeFileExchange exchange,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides,
        fileExchangeProvider.overrideWithValue(exchange),
      ],
      child: const HeisenbudgetApp(),
    ),
  );
  await settle(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Settings'),
    ),
  );
  await settle(tester);
}

Future<void> tapTile(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  testWidgets('Back up shares a dated JSON file that restores cleanly', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Lunch');
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-backup');

    expect(exchange.shared, hasLength(1));
    final file = exchange.shared.single;
    expect(file.name, 'heisenbudget-backup-2026-10-15.json');
    expect(file.mime, 'application/json');
    final data = BackupData.parse(file.bytes);
    expect(data.transactions.single.note, 'Lunch');
    expect(data.settings.currency, 'USD');
    await disposeEnv(tester, env);
  });

  testWidgets('Export to CSV shares the transactions', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Lunch');
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-csv');

    final file = exchange.shared.single;
    expect(file.name, 'heisenbudget-transactions-2026-10-15.csv');
    expect(file.mime, 'text/csv');
    expect(
      utf8.decode(file.bytes),
      contains('2026-10-05,Expense,Food,,12.50,Lunch'),
    );
    await disposeEnv(tester, env);
  });

  testWidgets('Export to CSV with nothing logged says so and shares nothing', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-csv');

    expect(exchange.shared, isEmpty);
    expect(find.text('No transactions to export yet.'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('a failing share sheet shows a calm message, not a crash', (
    tester,
  ) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange(shareFails: true);
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'export-backup');

    expect(
      find.text('Something went wrong. Nothing was changed.'),
      findsOneWidget,
    );
    await disposeEnv(tester, env);
  });

  testWidgets('Restore asks first, then replaces data and settings', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(
      find.textContaining('1 transaction and 2 categories'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    // Nothing changed yet.
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );

    await tester.tap(find.byKey(const ValueKey('restore-confirm')));
    await settle(tester);

    final saved = await savedTransactions(tester, env);
    expect(saved.single.transaction.note, 'From backup');
    expect(saved.single.category.name, 'Tea');
    expect(env.prefs.getString('currency_code'), 'BDT');
    expect(find.text('Backup restored.'), findsOneWidget);
    await disposeEnv(tester, env);
  });

  testWidgets('cancelling the restore dialog changes nothing', (tester) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(toPick: backupBytes());
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');
    await tester.tap(find.byKey(const ValueKey('restore-cancel')));
    await settle(tester);

    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );
    expect(env.prefs.getString('currency_code'), 'USD');
    expect(find.text('Backup restored.'), findsNothing);
    await disposeEnv(tester, env);
  });

  testWidgets('a file that is not a backup is refused with a clear message', (
    tester,
  ) async {
    final env = await createEnv(tester);
    await addExpense(tester, env, 1250, DateTime(2026, 10, 5), note: 'Old');
    final exchange = FakeFileExchange(
      toPick: Uint8List.fromList(utf8.encode('{"hello": "world"}')),
    );
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(
      find.text('That file is not a Heisenbudget backup.'),
      findsOneWidget,
    );
    expect(find.text('Restore this backup?'), findsNothing);
    expect(
      (await savedTransactions(tester, env)).single.transaction.note,
      'Old',
    );
    await disposeEnv(tester, env);
  });

  testWidgets('closing the file picker does nothing', (tester) async {
    final env = await createEnv(tester);
    final exchange = FakeFileExchange();
    await openSettings(tester, env, exchange);

    await tapTile(tester, 'restore-backup');

    expect(find.text('Restore this backup?'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await disposeEnv(tester, env);
  });
}
