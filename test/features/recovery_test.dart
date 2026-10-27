import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app_bootstrap.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/database/database_files.dart';
import 'package:heisenbudget/data/database/database_opener.dart';
import 'package:heisenbudget/features/shell/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'test_helpers.dart';

class _Picker extends FileExchange {
  const _Picker(this.bytes);
  final Uint8List? bytes;

  @override
  Future<Uint8List?> pickFile() async => bytes;
}

Uint8List _backup() => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'app': 'heisenbudget',
      'format': 1,
      'exportedAt': '2026-10-25T12:00:00Z',
      'settings': {'currency': 'BDT'},
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

AppDatabase _openFile(File file) => AppDatabase(NativeDatabase(file));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late DatabaseFiles files;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hb_boot');
    files = DatabaseFiles(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> start(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    FileExchange exchange = const FileExchange(),
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'currency_code': 'USD',
      'onboarding_done': true,
      ...prefs,
    });
    final p = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      AppBootstrap(
        prefs: p,
        locate: () async => files,
        openDatabase: _openFile,
        exchange: exchange,
      ),
    );
    for (var i = 0; i < 10; i++) {
      await settle(tester);
    }
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    for (var i = 0; i < 10; i++) {
      await settle(tester);
    }
  }

  final title = find.byKey(const ValueKey('recovery-title'));

  Future<void> garbage() => files.database.writeAsBytes(List.filled(2048, 7));

  testWidgets('a healthy start opens the app', (tester) async {
    await tester.runAsync(() async {});
    await start(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(title, findsNothing);
    await stop(tester);
  });

  testWidgets('data that cannot be opened shows the recovery screen, with '
      'details, and Try again works once it is fixed', (tester) async {
    await tester.runAsync(garbage);
    await start(tester, prefs: {schemaVersionPrefKey: currentSchemaVersion});
    expect(title, findsOneWidget);
    expect(
      find.text('Nothing has been deleted. Choose how to continue.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('recovery-restore-copy')), findsNothing);
    await tap(tester, 'recovery-details');
    expect(
      find.textContaining('not a database', findRichText: true),
      findsOneWidget,
    );

    await tester.runAsync(files.deleteDatabase);
    await tap(tester, 'recovery-retry');
    expect(find.byType(AppShell), findsOneWidget);
    await stop(tester);
  });

  testWidgets('a database from another version is refused with the reason', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = _openFile(files.database);
      await db.customSelect('SELECT 1').get();
      await db.close();
      final raw = sqlite.sqlite3.open(files.database.path);
      raw.execute('PRAGMA user_version = 99');
      raw.close();
    });
    await start(tester, prefs: {schemaVersionPrefKey: currentSchemaVersion});
    expect(title, findsOneWidget);
    await tap(tester, 'recovery-details');
    expect(
      find.textContaining('schema 99', findRichText: true),
      findsOneWidget,
    );
    await stop(tester);
  });

  testWidgets('the copy from before the update can be restored', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final db = _openFile(files.database);
      await db.customSelect('SELECT 1').get();
      await db.close();
      await files.copyBeforeUpgrade(currentSchemaVersion);
      await garbage(); // the update left the live file unusable
    });
    await start(tester, prefs: {schemaVersionPrefKey: currentSchemaVersion});
    expect(find.byKey(const ValueKey('recovery-restore-copy')), findsOneWidget);

    await tap(tester, 'recovery-restore-copy');
    expect(find.text('Go back to the copy?'), findsOneWidget);
    await tap(tester, 'recovery-confirm');
    expect(find.byType(AppShell), findsOneWidget);
    await stop(tester);
  });

  testWidgets('cancelling a confirmation changes nothing', (tester) async {
    await tester.runAsync(garbage);
    await start(tester, prefs: {schemaVersionPrefKey: currentSchemaVersion});
    await tap(tester, 'recovery-erase');
    expect(find.text('Erase everything?'), findsOneWidget);
    await tap(tester, 'recovery-cancel');
    expect(title, findsOneWidget);
    expect(await tester.runAsync(() => files.database.length()), 2048);
    await stop(tester);
  });

  testWidgets('a backup file can be restored from the recovery screen', (
    tester,
  ) async {
    await tester.runAsync(garbage);
    await start(
      tester,
      prefs: {schemaVersionPrefKey: currentSchemaVersion},
      exchange: _Picker(_backup()),
    );
    await tap(tester, 'recovery-restore-backup');
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('1 transaction'), findsOneWidget);
    await tap(tester, 'recovery-confirm');

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Tea'), findsWidgets, reason: 'the restored data');
    await stop(tester);
  });

  testWidgets('a file that is not a backup is refused, data untouched', (
    tester,
  ) async {
    await tester.runAsync(garbage);
    await start(
      tester,
      prefs: {schemaVersionPrefKey: currentSchemaVersion},
      exchange: _Picker(Uint8List.fromList(utf8.encode('hello'))),
    );
    await tap(tester, 'recovery-restore-backup');
    expect(
      find.text('That file is not a Heisenbudget backup.'),
      findsOneWidget,
    );
    expect(title, findsOneWidget);
    expect(await tester.runAsync(() => files.database.length()), 2048);
    await stop(tester);
  });

  testWidgets('erasing starts the app over from nothing', (tester) async {
    await tester.runAsync(() async {
      await garbage();
      await File('${dir.path}/heisenbudget.before-v2.sqlite').writeAsBytes([1]);
    });
    await start(tester, prefs: {schemaVersionPrefKey: currentSchemaVersion});
    await tap(tester, 'recovery-erase');
    await tap(tester, 'recovery-confirm');

    expect(title, findsNothing);
    expect(await tester.runAsync(files.copyVersion), isNull);
    await stop(tester);
  });
}
