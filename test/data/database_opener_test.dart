import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_service.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/database/database_files.dart';
import 'package:heisenbudget/data/database/database_opener.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart' as sqlite;

AppDatabase openFile(File file) => AppDatabase(NativeDatabase(file));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dir;
  late DatabaseFiles files;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hb_opener');
    files = DatabaseFiles(dir);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<SharedPreferences> prefs([Map<String, Object> values = const {}]) {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  /// A database file as an earlier schema would leave it.
  Future<void> makeDatabaseFile({int userVersion = 3}) async {
    final db = openFile(files.database);
    await db.customSelect('SELECT 1').get();
    await db.close();
    final raw = sqlite.sqlite3.open(files.database.path);
    raw.execute('PRAGMA user_version = $userVersion');
    raw.close();
  }

  int userVersionOf(File file) {
    final raw = sqlite.sqlite3.open(file.path);
    final v = raw.select('PRAGMA user_version').first.values.first as int;
    raw.close();
    return v;
  }

  group('opening the database', () {
    test(
      'a new install creates it, remembers the schema, makes no copy',
      () async {
        final p = await prefs();
        final db = await openAppDatabase(
          prefs: p,
          files: files,
          open: openFile,
        );
        addTearDown(db.close);
        expect(p.getInt(schemaVersionPrefKey), currentSchemaVersion);
        expect(await files.copyVersion(), isNull);
        expect(await db.select(db.categories).get(), isNotEmpty);
      },
    );

    test('the same schema as last time makes no copy', () async {
      await makeDatabaseFile();
      final p = await prefs({schemaVersionPrefKey: currentSchemaVersion});
      final db = await openAppDatabase(prefs: p, files: files, open: openFile);
      addTearDown(db.close);
      expect(await files.copyVersion(), isNull);
    });

    test('an app that was at an older schema copies the file first', () async {
      await makeDatabaseFile();
      final before = await files.database.readAsBytes();
      final p = await prefs({schemaVersionPrefKey: 2});
      final db = await openAppDatabase(prefs: p, files: files, open: openFile);
      addTearDown(db.close);

      expect(await files.copyVersion(), 2);
      final copy = File('${dir.path}/heisenbudget.before-v2.sqlite');
      expect(await copy.readAsBytes(), before);
      expect(p.getInt(schemaVersionPrefKey), currentSchemaVersion);
    });

    test(
      'a database that will not open throws, and nothing is remembered',
      () async {
        await files.database.writeAsBytes(List.filled(2048, 7));
        final p = await prefs({schemaVersionPrefKey: currentSchemaVersion});
        await expectLater(
          openAppDatabase(prefs: p, files: files, open: openFile),
          throwsA(isA<DatabaseOpenException>()),
        );
        expect(p.getInt(schemaVersionPrefKey), currentSchemaVersion);
      },
    );

    test(
      'an upgrade that fails keeps the copy and leaves the file as it was',
      () async {
        await makeDatabaseFile(userVersion: 2);
        final before = await files.database.readAsBytes();
        final p = await prefs({schemaVersionPrefKey: 2});
        await expectLater(
          openAppDatabase(prefs: p, files: files, open: openFile),
          throwsA(isA<DatabaseOpenException>()),
        );
        expect(await files.copyVersion(), 2);
        expect(userVersionOf(files.database), 2);
        expect(await files.database.readAsBytes(), before);
        expect(p.getInt(schemaVersionPrefKey), 2, reason: 'not marked as done');
      },
    );

    test('a copy that cannot be made stops the upgrade', () async {
      await makeDatabaseFile();
      // A directory where the copy's file should go makes the copy fail.
      await Directory('${dir.path}/heisenbudget.before-v2.sqlite').create();
      final p = await prefs({schemaVersionPrefKey: 2});
      var opened = false;
      await expectLater(
        openAppDatabase(
          prefs: p,
          files: files,
          open: (f) {
            opened = true;
            return openFile(f);
          },
        ),
        throwsA(isA<DatabaseOpenException>()),
      );
      expect(opened, isFalse, reason: 'never touched without its copy');
    });
  });

  group('the safety copy', () {
    test('is replaced by the next one, and restored on request', () async {
      await makeDatabaseFile(userVersion: 2);
      await files.copyBeforeUpgrade(2);
      final copyBytes = await files.database.readAsBytes();
      await files.database.writeAsBytes([1, 2, 3]); // the live file changes
      await files.copyBeforeUpgrade(1); // an earlier copy is replaced
      expect(await files.copyVersion(), 1);
      // Put the real copy back for the restore.
      await files.deleteCopies();
      await files.database.writeAsBytes(copyBytes);
      await files.copyBeforeUpgrade(2);
      await files.database.writeAsBytes([9, 9, 9]);

      expect(await files.restoreCopy(), 2);
      expect(await files.database.readAsBytes(), copyBytes);
      expect(await files.copyVersion(), 2, reason: 'the copy is kept');
    });

    test('restoring with no copy says so', () async {
      expect(files.restoreCopy(), throwsA(isA<StateError>()));
    });

    test('is deleted after $kKeep days, kept before', () async {
      await makeDatabaseFile();
      await files.copyBeforeUpgrade(2);
      final copy = File('${dir.path}/heisenbudget.before-v2.sqlite');
      final now = DateTime(2026, 11, 1);

      await copy.setLastModified(now.subtract(const Duration(days: 13)));
      await files.pruneCopies(now);
      expect(await files.copyVersion(), 2);

      await copy.setLastModified(
        now.subtract(const Duration(days: DatabaseFiles.copyKeepDays)),
      );
      await files.pruneCopies(now);
      expect(await files.copyVersion(), isNull);
    });

    test('Erase everything deletes it too', () async {
      await makeDatabaseFile();
      await files.copyBeforeUpgrade(2);
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final service = BackupService(
        db,
        SettingsRepository(
          await SharedPreferences.getInstance(),
          defaultCurrency: 'USD',
        ),
        files: files,
      );
      await service.eraseEverything();
      expect(await files.copyVersion(), isNull);
    });
  });
}

const kKeep = DatabaseFiles.copyKeepDays;
