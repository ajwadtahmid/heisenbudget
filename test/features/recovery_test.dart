import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show LazyDatabase, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/app_bootstrap.dart';
import 'package:heisenbudget/data/backup/file_exchange.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/database/database_files.dart';
import 'package:heisenbudget/data/database/database_opener.dart';
import 'package:heisenbudget/domain/iso_date.dart';
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

/// A backup with one transaction dated today, so it shows on Home whatever day
/// the test runs (the app is started on the real clock).
Uint8List _backup() {
  final today = toIsoDate(dateOnly(DateTime.now()));
  return Uint8List.fromList(
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
            'date': today,
            'categoryId': 7,
            'note': 'From backup',
            'createdAt': '${today}T08:00:00Z',
            'updatedAt': '${today}T08:00:00Z',
          },
        ],
      }),
    ),
  );
}

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
    DatabaseOpener open = _openFile,
    Future<DatabaseFiles> Function()? locate,
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
        locate: locate ?? () async => files,
        openDatabase: open,
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

  /// Settles until [finder] matches (the data behind a freshly opened screen
  /// arrives from the database a little later, and later still on a slow
  /// machine), for at most about a minute.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await settle(tester);
    }
  }

  final title = find.byKey(const ValueKey('recovery-title'));

  Future<void> garbage() => files.database.writeAsBytes(List.filled(2048, 7));

  testWidgets(
    'storage lookup failure offers retry without destructive actions',
    (tester) async {
      var fail = true;
      await start(
        tester,
        locate: () async {
          if (fail) throw const FileSystemException('Storage unavailable');
          return files;
        },
      );
      expect(title, findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('recovery-restore-backup')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('recovery-erase')))
            .onPressed,
        isNull,
      );
      fail = false;
      await tap(tester, 'recovery-retry');
      await settleUntil(tester, find.byType(AppShell));
      expect(find.byType(AppShell), findsOneWidget);
      await stop(tester);
    },
  );

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

  testWidgets('retry keeps recovery actions disabled until opening finishes', (
    tester,
  ) async {
    await tester.runAsync(garbage);
    final gate = Completer<void>();
    var waiting = false;
    await start(
      tester,
      open: (file) {
        if (!waiting) return _openFile(file);
        return AppDatabase(
          LazyDatabase(() async {
            await gate.future;
            return NativeDatabase(file);
          }),
        );
      },
    );
    waiting = true;
    await tester.tap(find.byKey(const ValueKey('recovery-retry')));
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recovery-retry')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('recovery-restore-backup')),
          )
          .onPressed,
      isNull,
    );
    gate.complete();
    for (var i = 0; i < 10; i++) {
      await settle(tester);
    }
    expect(title, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recovery-retry')))
          .onPressed,
      isNotNull,
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
    await settleUntil(tester, find.byType(AppShell));
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
    await settleUntil(tester, find.text('Tea'));
    expect(find.text('Tea'), findsWidgets, reason: 'the restored data');
    await stop(tester);
  });

  testWidgets('failed recovery restore preserves the original through retry '
      'and restart', (tester) async {
    late List<int> original;
    await tester.runAsync(() async {
      final db = _openFile(files.database);
      await db.customSelect('SELECT 1').get();
      await db.customStatement('''
        INSERT INTO transactions
          (id, amount_cents, type, date, category_id, note, created_at, updated_at)
        VALUES (77, 1234, 'expense', '2026-10-15', 1,
          'Original expense', 0, 0)
      ''');
      await db.close();
      final raw = sqlite.sqlite3.open(files.database.path);
      raw.execute('PRAGMA user_version = 99');
      raw.close();
      original = await files.database.readAsBytes();
    });
    await start(
      tester,
      prefs: {schemaVersionPrefKey: 99},
      exchange: _Picker(_backup()),
      open: (file) {
        if (file.path != files.database.path) {
          throw const FileSystemException('Injected replacement open failure');
        }
        return _openFile(file);
      },
    );
    await tap(tester, 'recovery-restore-backup');
    await tap(tester, 'recovery-confirm');
    expect(title, findsOneWidget);
    expect(find.byKey(const ValueKey('recovery-message')), findsOneWidget);
    expect(await tester.runAsync(files.database.readAsBytes), original);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(schemaVersionPrefKey), 99);
    expect(prefs.getString('currency_code'), 'USD');

    await tap(tester, 'recovery-retry');
    expect(title, findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    await stop(tester);
    // Simulate a process stopping after the original has been saved and
    // the live file removed. Startup must roll back before opening SQLite.
    await tester.runAsync(() async {
      final work = await Directory('${dir.path}/heisenbudget.restore').create();
      await files.database.copy('${work.path}/original.sqlite');
      await File('${work.path}/pending.json').writeAsString(
        jsonEncode({
          'files': [''],
          'preferences': {
            for (final key in prefs.getKeys()) key: prefs.get(key),
          },
        }),
        flush: true,
      );
      await files.deleteDatabase();
    });
    await start(tester, prefs: {schemaVersionPrefKey: 99});
    expect(title, findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    await tester.runAsync(() async {
      final raw = sqlite.sqlite3.open(files.database.path);
      expect(
        raw
            .select('SELECT note FROM transactions WHERE id = 77')
            .single['note'],
        'Original expense',
      );
      raw.close();
    });
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
