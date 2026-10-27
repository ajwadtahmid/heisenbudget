import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'database_files.dart';

/// The schema the database was last opened at, kept on the phone only (not in
/// the backup file). When it is lower than the app's, this launch is about to
/// run an upgrade, so a safety copy is made first.
const schemaVersionPrefKey = 'db_schema_version';

/// The database could not be opened or upgraded. [cause] is the original
/// error, for the details line on the recovery screen.
class DatabaseOpenException implements Exception {
  const DatabaseOpenException(this.cause);

  final Object cause;

  @override
  String toString() => 'The database could not be opened: $cause';
}

/// Builds the database for a file. Tests pass their own.
typedef DatabaseOpener = AppDatabase Function(File file);

/// Opens (and, if needed, upgrades) the app's database.
///
/// 1. When the last launch was at an older schema and a database exists, a
///    copy of it is made before anything touches it.
/// 2. The database is opened and one query forces any upgrade to run now, so a
///    failure shows up here, not later on some screen.
/// 3. The schema is remembered, and an old safety copy is cleaned up.
///
/// Throws [DatabaseOpenException] when it cannot.
Future<AppDatabase> openAppDatabase({
  required SharedPreferences prefs,
  required DatabaseFiles files,
  DatabaseOpener open = AppDatabase.open,
  DateTime Function()? now,
}) async {
  final stored = prefs.getInt(schemaVersionPrefKey);
  try {
    if (stored != null &&
        stored < currentSchemaVersion &&
        await files.databaseExists) {
      await files.copyBeforeUpgrade(stored);
    }
  } catch (e) {
    // Better to stop than to upgrade without the copy that was promised.
    throw DatabaseOpenException(e);
  }

  final db = open(files.database);
  try {
    await db.customSelect('SELECT 1').get();
  } catch (e) {
    try {
      await db.close();
    } catch (_) {}
    throw DatabaseOpenException(e);
  }
  await prefs.setInt(schemaVersionPrefKey, currentSchemaVersion);
  try {
    await files.pruneCopies((now ?? DateTime.now)());
  } catch (_) {
    // An old copy that cannot be deleted now is tried again next launch.
  }
  return db;
}
