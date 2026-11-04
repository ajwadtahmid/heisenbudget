import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heisenbudget/data/backup/backup_data.dart';
import 'package:heisenbudget/data/backup/recovery_restore.dart';
import 'package:heisenbudget/data/database/app_database.dart';
import 'package:heisenbudget/data/database/database_files.dart';
import 'package:heisenbudget/data/database/database_opener.dart';
import 'package:heisenbudget/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'backup_test.dart' show bytesOf, validBackup;

class _InterruptedSwap extends DatabaseFiles {
  _InterruptedSwap(super.directory);

  @override
  Future<void> deleteDatabase() async {
    await super.deleteDatabase();
    throw const FileSystemException('Interrupted after deleting live files');
  }
}

class _FailedSettings extends SettingsRepository {
  _FailedSettings(this.prefs) : super(prefs, defaultCurrency: 'USD');
  final SharedPreferences prefs;

  @override
  Future<void> applyBackup(BackupSettings b) async {
    await prefs.setString('currency_code', 'BDT');
    await prefs.setBool('partially_written', true);
    throw StateError('Injected settings failure');
  }
}

AppDatabase _open(File file) => AppDatabase(NativeDatabase(file));

class _RejectedSetting extends InMemorySharedPreferencesStore {
  _RejectedSetting(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == 'flutter.currency_code' && value == 'BDT') {
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late DatabaseFiles files;
  late SharedPreferences prefs;
  late SettingsRepository settings;
  late BackupData data;
  late Map<String, Object> previous;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hb_recovery_restore');
    files = DatabaseFiles(dir);
    previous = {
      schemaVersionPrefKey: 99,
      'currency_code': 'USD',
      'onboarding_done': false,
      'opening_balance_cents': 12345,
      'test_strings': ['a', 'b'],
      'test_double': 1.25,
    };
    SharedPreferences.setMockInitialValues(previous);
    prefs = await SharedPreferences.getInstance();
    settings = SettingsRepository(prefs, defaultCurrency: 'USD');
    data = BackupData.parse(bytesOf(validBackup()));
    // Recovery must also preserve corrupt/newer files and all their sidecars,
    // without trying to interpret their contents during replacement/rollback.
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await File('${files.database.path}$suffix')
          .writeAsString('original$suffix');
    }
    await File('${dir.path}/heisenbudget.before-v3.sqlite')
        .writeAsString('safety');
  });
  tearDown(() => dir.delete(recursive: true));

  RecoveryRestore recovery({
    DatabaseOpener open = _open,
    DatabaseFiles? target,
    SettingsRepository? repository,
  }) => RecoveryRestore(
    target ?? files,
    prefs,
    repository ?? settings,
    open: open,
  );

  Future<void> expectOriginal() async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(
        await File('${files.database.path}$suffix').readAsString(),
        'original$suffix',
      );
    }
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, previous);
    expect(
      await File('${dir.path}/heisenbudget.before-v3.sqlite').readAsString(),
      'safety',
    );
    expect(
      await Directory('${dir.path}/heisenbudget.restore').exists(),
      isFalse,
    );
  }

  test(
    'replacement open failure never touches the original or preferences',
    () async {
      await expectLater(
        recovery(open: (_) => throw const FileSystemException('open'))
            .restore(data),
        throwsA(isA<FileSystemException>()),
      );
      await expectOriginal();
    },
  );

  test(
    'insert failure in the staged database preserves original data',
    () async {
      final invalid = BackupData(
        exportedAt: data.exportedAt,
        settings: data.settings,
        categories: const [],
        transactions: data.transactions,
        recurringRules: const [],
        favorites: const [],
        budgetLimits: const [],
      );
      await expectLater(recovery().restore(invalid), throwsA(isA<Exception>()));
      await expectOriginal();
    },
  );

  test('failure after removing live files rolls back every sidecar', () async {
    await expectLater(
      recovery(target: _InterruptedSwap(dir)).restore(data),
      throwsA(isA<FileSystemException>()),
    );
    await expectOriginal();
  });

  test('failure reopening the installed replacement rolls back', () async {
    await expectLater(
      recovery(
        open: (file) {
          if (file.path == files.database.path) {
            throw const FileSystemException('reopen');
          }
          return _open(file);
        },
      ).restore(data),
      throwsA(isA<FileSystemException>()),
    );
    await expectOriginal();
  });

  test('partially saved settings roll back with the database', () async {
    await expectLater(
      recovery(repository: _FailedSettings(prefs)).restore(data),
      throwsA(isA<StateError>()),
    );
    await expectOriginal();
  });

  test('success installs backup rows/settings, retains safety copy and cleans staging', () async {
    final db = await recovery().restore(data);
    try {
      expect((await db.select(db.transactions).get()).single.note, 'Lunch');
      expect((await db.select(db.categories).get()).map((c) => c.name), [
        'Food',
        'Salary',
      ]);
      expect(prefs.getString('currency_code'), 'BDT');
      expect(prefs.getBool('onboarding_done'), isTrue);
      expect(prefs.getInt(schemaVersionPrefKey), currentSchemaVersion);
      expect(
        await Directory('${dir.path}/heisenbudget.restore').exists(),
        isFalse,
      );
      expect(
        await File('${dir.path}/heisenbudget.before-v3.sqlite').readAsString(),
        'safety',
      );
    } finally {
      await db.close();
    }
    final reopened = _open(files.database);
    try {
      expect(
        (await reopened.select(reopened.transactions).get()).single.amountCents,
        1250,
      );
    } finally {
      await reopened.close();
    }
  });

  Future<Directory> interrupted({bool committed = false}) async {
    final work = await Directory('${dir.path}/heisenbudget.restore').create();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await File('${files.database.path}$suffix')
          .copy('${work.path}/original.sqlite$suffix');
    }
    await File('${work.path}/${committed ? 'committed' : 'pending'}.json')
        .writeAsString(
          jsonEncode({
            'files': ['', '-wal', '-shm', '-journal'],
            'preferences': previous,
          }),
          flush: true,
        );
    await files.deleteDatabase();
    await files.database.writeAsString('replacement');
    await prefs.setString('currency_code', 'BDT');
    return work;
  }

  test('startup rolls back an interrupted swap and settings update', () async {
    await interrupted();
    await recovery().recoverInterrupted();
    await recovery().recoverInterrupted();
    await expectOriginal();
  });

  test(
    'an incomplete rollback can be retried without losing the originals',
    () async {
      await interrupted();
      await files.database.delete();
      await Directory(files.database.path).create();
      await expectLater(
        recovery().recoverInterrupted(),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await File('${dir.path}/heisenbudget.restore/original.sqlite')
            .readAsString(),
        'original',
      );
      await Directory(files.database.path).delete();
      await recovery().recoverInterrupted();
      await expectOriginal();
    },
  );

  test(
    'a rejected preference write rolls back instead of committing',
    () async {
      final store = SharedPreferencesStorePlatform.instance;
      addTearDown(() => SharedPreferencesStorePlatform.instance = store);
      SharedPreferencesStorePlatform.instance = _RejectedSetting({
        for (final entry in previous.entries)
          'flutter.${entry.key}': entry.value,
      });
      await expectLater(recovery().restore(data), throwsA(isA<StateError>()));
      await expectOriginal();
    },
  );

  test(
    'confirmed erase discards pending originals and cannot resurrect them',
    () async {
      await interrupted();
      await recovery().discard();
      await files.deleteDatabase();
      await prefs.clear();
      await recovery().recoverInterrupted();
      expect(await files.database.exists(), isFalse);
      expect(prefs.getKeys(), isEmpty);
      expect(
        await Directory('${dir.path}/heisenbudget.restore').exists(),
        isFalse,
      );
    },
  );

  test('startup never rolls back a committed replacement', () async {
    await interrupted(committed: true);
    await recovery().recoverInterrupted();
    expect(await files.database.readAsString(), 'replacement');
    expect(prefs.getString('currency_code'), 'BDT');
    expect(
      await Directory('${dir.path}/heisenbudget.restore').exists(),
      isFalse,
    );
  });
}
