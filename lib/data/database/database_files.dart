import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The database file on the phone, and the one safety copy made before an
/// update changes how data is stored (`heisenbudget.before-v3.sqlite`, the
/// number being the schema the copy is at).
///
/// The copy lives beside the database, in the app's private storage: it is
/// financial data too, so it is deleted when everything is erased and after
/// [copyKeepDays] days.
class DatabaseFiles {
  const DatabaseFiles(this.directory);

  /// Where the app keeps its database.
  static Future<DatabaseFiles> locate() async =>
      DatabaseFiles(await getApplicationDocumentsDirectory());

  /// How long the safety copy is kept.
  static const copyKeepDays = 14;

  static const _name = 'heisenbudget';

  /// SQLite side files that can sit beside a database file.
  static const _sideFiles = ['-journal', '-wal', '-shm'];

  static final _copyName = RegExp(r'^heisenbudget\.before-v(\d+)\.sqlite$');

  final Directory directory;

  File _file(String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  /// The live database.
  File get database => _file('$_name.sqlite');

  File _copy(int version) => _file('$_name.before-v$version.sqlite');

  Future<bool> get databaseExists => database.exists();

  /// Copies the database (and any side files) to a new safety copy at
  /// [version], replacing any earlier copy. Call it before the database is
  /// opened, so nothing is mid-write.
  Future<void> copyBeforeUpgrade(int version) async {
    await deleteCopies();
    final target = _copy(version);
    await database.copy(target.path);
    for (final suffix in _sideFiles) {
      final side = File('${database.path}$suffix');
      if (await side.exists()) await side.copy('${target.path}$suffix');
    }
  }

  /// The schema version of the safety copy, or null when there is none.
  Future<int?> copyVersion() async {
    if (!await directory.exists()) return null;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final match = _copyName.firstMatch(entity.uri.pathSegments.last);
      if (match != null) return int.parse(match.group(1)!);
    }
    return null;
  }

  /// When the safety copy was made, or null when there is none.
  Future<DateTime?> copyMadeAt() async {
    final version = await copyVersion();
    return version == null ? null : _copy(version).lastModified();
  }

  /// Puts the safety copy back as the database. The copy is kept. Returns the
  /// schema version it is at.
  Future<int> restoreCopy() async {
    final version = await copyVersion();
    if (version == null) throw StateError('There is no copy to restore.');
    await deleteDatabase();
    final source = _copy(version);
    await source.copy(database.path);
    for (final suffix in _sideFiles) {
      final side = File('${source.path}$suffix');
      if (await side.exists()) await side.copy('${database.path}$suffix');
    }
    return version;
  }

  /// Deletes the database and its side files.
  Future<void> deleteDatabase() async {
    for (final suffix in ['', ..._sideFiles]) {
      final file = File('${database.path}$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// Deletes the safety copy.
  Future<void> deleteCopies() async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('$_name.before-v')) {
        await entity.delete();
      }
    }
  }

  /// Deletes the safety copy once it is older than [copyKeepDays] days.
  Future<void> pruneCopies(DateTime now) async {
    final made = await copyMadeAt();
    if (made != null && now.difference(made).inDays >= copyKeepDays) {
      await deleteCopies();
    }
  }
}
